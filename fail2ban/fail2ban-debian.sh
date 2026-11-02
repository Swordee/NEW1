#!/usr/bin/env bash
# ============================================================
#  Fail2ban 一键管理脚本（Debian / Ubuntu 适用）
#
#  用法:
#    ./fail2ban-debian.sh <命令> [选项]
#    （非 root 时会自动通过 sudo 提权重入，无需手动加 sudo）
#
#  命令:
#    auto        一键安装：自动探测 SSH 端口/当前 IP → 安装 → 交互式自检
#    install     安装并启动（可配 --port / --ignore-ip）
#    doctor      自检并交互式处理问题（服务/端口/白名单/日志后端等）
#    uninstall   卸载
#    restart     重启服务
#    reload      重载配置（不中断封禁）
#    status      查看服务状态与封禁列表（含 sshd 生效配置）
#    info        只查看 sshd 的生效配置
#    dir         显示关键目录位置
#    logs        实时跟踪日志
#    enable      设置开机自启
#    disable     取消开机自启
#    bootstrap   一键部署（装成系统命令 + 自动安装 + 进面板）
#    menu        交互面板（默认）
#    help        显示帮助
#
#  选项:
#    --port <端口>          SSH 端口，默认 ssh（即 22）
#    --ignore-ip "<IP列表>" 白名单，空格分隔，默认 "127.0.0.1/8 ::1"
#    -y, --yes              跳过所有确认（适合脚本自动化）
#    --no-elevate           禁止自动 sudo 提权（非 root 时直接报错）
#
#  示例:
#    ./fail2ban-debian.sh auto                       # 一键装好并自检
#    ./fail2ban-debian.sh install --port 2222
#    sudo ./fail2ban-debian.sh doctor
#    ./fail2ban-debian.sh uninstall --yes
# ============================================================

set -u

# ---------- 颜色（仅在终端输出时启用，重定向到文件不污染） ----------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

# ---------- 路径常量 ----------
F2B_CONF_DIR="/etc/fail2ban"
F2B_JAIL_LOCAL="${F2B_CONF_DIR}/jail.local"
F2B_LOG="/var/log/fail2ban.log"
AUTH_LOG="/var/log/auth.log"
SSHD_CONFIG="/etc/ssh/sshd_config"
SERVICE="fail2ban"
# 管理命令安装位置（可用 F2B_BIN_DIR 覆盖，便于测试）
BIN_DIR="${F2B_BIN_DIR:-/usr/local/bin}"
TOOL_NAME="fail2ban-tool"
SCRIPT_VERSION="1.0.6"

# ---------- 全局状态 ----------
SSH_PORT=""
IGNORE_IPS=""
ASSUME_YES=0
NO_ELEVATE=0
CMD=""
SUPPRESS_POST_DOCTOR=0
NONTTY_WARNED=0
# 提示用的程序名：经 install.sh 引导时由引导器注入
PROG_HINT="${F2B_PROG_HINT:-$0}"

# ---------- 输出工具 ----------
info()  { printf '%s[信息]%s %s\n' "$CYAN"   "$NC" "$*"; }
ok()    { printf '%s[成功]%s %s\n' "$GREEN"  "$NC" "$*"; }
warn()  { printf '%s[警告]%s %s\n' "$YELLOW" "$NC" "$*"; }
err()   { printf '%s[错误]%s %s\n' "$RED"    "$NC" "$*" >&2; }

rule()    { printf '%s%s%s\n' "$DIM" "------------------------------------------------------------" "$NC"; }
section() { printf '\n%s%s%s\n' "$BOLD" "$1" "$NC"; rule; }

# 计算字符串显示宽度（UTF-8 中文按 2 列计）
disp_width() {
  local s="$1" bytes ascii mb
  bytes=$(LC_ALL=C printf '%s' "$s" | wc -c)
  ascii=$(LC_ALL=C printf '%s' "$s" | tr -d '\200-\377' | wc -c)
  mb=$(( bytes - ascii ))
  printf '%s' $(( ascii + (mb / 3) * 2 ))
}

# 按显示宽度左对齐填充
pad_disp() {
  local s="$1" target="$2" w n
  w=$(disp_width "$s")
  n=$(( target - w ))
  [ "$n" -lt 0 ] && n=0
  printf '%s%*s' "$s" "$n" ''
}

# 键值对输出（按显示宽度对齐，中英文混排不错位）
kv() {
  local label="$1" value="$2"
  printf '  %s%s%s : %s\n' "$CYAN" "$(pad_disp "$label" 22)" "$NC" "$value"
}

# ---------- 权限：自动提权 ----------
# ---------- 交互输入层 ----------
# 统一决定"从哪里读用户输入"：
#   1) 正常终端：直接读 stdin
#   2) curl | bash 等管道场景：stdin 已到 EOF，改从 /dev/tty 读
#   3) 两者都没有：明确报错，绝不静默退出
# 之前的 bug：管道启动时 read 立即 EOF，面板打印完就无声退出，表现为"输入没反应"。
F2B_TTY_FD=""
REPLY_LINE=""

# /dev/tty 是否真的能打开（比 [ -r /dev/tty ] 可靠）
have_tty() { { : < /dev/tty; } 2>/dev/null; }

# 确定输入来源：成功时 F2B_TTY_FD 为 0（stdin）或 3（/dev/tty）
ensure_tty() {
  [ -n "$F2B_TTY_FD" ] && return 0
  if [ -t 0 ]; then
    F2B_TTY_FD=0
    return 0
  fi
  if { exec 3</dev/tty; } 2>/dev/null; then
    F2B_TTY_FD=3
    return 0
  fi
  return 1
}

# 读一行到全局 REPLY_LINE；返回非 0 表示读不到（EOF 且无终端）
# 优先级：终端 stdin > /dev/tty > 回退 stdin
#   之所以把 /dev/tty 放在"非终端 stdin"之前，是因为 curl | bash 时
#   stdin 是已读完的脚本管道，直接 read 会立刻 EOF（旧版面板"没反应"的根因）。
read_line() {
  local prompt="${1:-}"
  REPLY_LINE=""

  # 1) stdin 本身就是终端
  if [ -t 0 ]; then
    read -r -p "$prompt" REPLY_LINE || return 1
    return 0
  fi

  # 2) stdin 不是终端：优先借用 /dev/tty，面板照样能操作
  if ensure_tty; then
    printf '%s' "$prompt" >&2
    read -r -u "$F2B_TTY_FD" REPLY_LINE || return 1
    return 0
  fi

  # 3) 没有任何终端：回退读 stdin，保留 echo "4" | fail2ban-tool 这类脚本化用法
  read -r REPLY_LINE || return 1
  return 0
}

# 完全没有交互终端时的统一提示
no_tty_hint() {
  err "当前没有可用的交互终端（可能是在管道里执行）"
  info "请在新终端直接运行：sudo ${TOOL_NAME}"
  info "或用非交互命令，例如：${PROG_HINT} status"
}

# 带超时执行外部命令：fail2ban-client / systemctl 异常时可能永久阻塞，
# 不设超时会让整个面板卡在"刷新状态"这一步，看起来就是"输入没反应"。
_t() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 3 "$@"
  else
    "$@"
  fi
}

# 清理 fail2ban-client 返回的 Python 列表格式：['a', 'b'] -> a, b
_clean_list() {
  sed 's/^\[//; s/\]$//' | tr -d "'" \
    | sed 's/,[[:space:]]*/, /g' | tr -s ' ' \
    | sed 's/^ //; s/ $//; s/,$//'
}

# 打印 sshd 的运行时生效参数（合并后的真实值，不是某个文件里的值）
_show_sshd_config() {
  command -v fail2ban-client >/dev/null 2>&1 || return 1
  _t fail2ban-client status sshd >/dev/null 2>&1 || return 1

  section "SSH 封禁规则（运行时生效值）"
  kv "封禁时长 bantime"  "$(_t fail2ban-client get sshd bantime 2>/dev/null | _clean_list)"
  kv "统计窗口 findtime" "$(_t fail2ban-client get sshd findtime 2>/dev/null | _clean_list)"
  kv "最大失败 maxretry" "$(_t fail2ban-client get sshd maxretry 2>/dev/null | _clean_list)"
  kv "白名单 ignoreip"   "$(_t fail2ban-client get sshd ignoreip 2>/dev/null | _clean_list)"
  kv "监控日志 logpath"  "$(_t fail2ban-client get sshd logpath 2>/dev/null | _clean_list)"
  kv "封禁动作"          "$(_t fail2ban-client get sshd actions 2>/dev/null | _clean_list | head -1)"

  echo
  info "永久修改：编辑 ${F2B_JAIL_LOCAL} 的 [sshd] bantime，再执行 reload"
  info "临时修改：fail2ban-client set sshd bantime 86400（重启后失效）"
  info "规则正则：${F2B_CONF_DIR}/filter.d/sshd.conf"
  return 0
}

# 非 root 时用 sudo 重新执行自己（保留已解析的参数），避免用户必须记住 sudo。
# 只在真正需要 root 的命令里调用，只读命令（status/dir/help）不提权。
need_root() {
  local want="${1:-$CMD}"
  [ "$(id -u)" -eq 0 ] && return 0

  if [ "$NO_ELEVATE" -eq 1 ]; then
    err "需要 root 权限（已指定 --no-elevate，不自动提权）"
    err "请改用：sudo ${PROG_HINT} $want"
    exit 1
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    err "当前非 root，且系统未安装 sudo，无法自动提权"
    err "请以 root 身份运行：su -c '${PROG_HINT} $want'"
    exit 1
  fi

  # 管道执行时 $0 是 bash/sh，不是脚本文件，无法用 sudo 重新执行自己
  if [ ! -f "$0" ]; then
    err "无法自动提权：当前不是以脚本文件方式运行（例如 curl | bash 直跑脚本）"
    info "请改用引导器：curl -fsSL <install.sh 地址> | bash"
    info "或先下载再执行：curl -fsSL <脚本地址> -o f2b.sh && sudo bash f2b.sh ${want}"
    exit 1
  fi

  local args=("$want")
  [ -n "$SSH_PORT" ]        && args+=(--port "$SSH_PORT")
  [ -n "$IGNORE_IPS" ]      && args+=(--ignore-ip "$IGNORE_IPS")
  [ "$ASSUME_YES" -eq 1 ]   && args+=(-y)

  info "当前非 root，正在通过 sudo 提权执行 '${want}' ..."
  if have_tty; then
    exec sudo bash "$0" "${args[@]}" < /dev/tty
  fi
  # 非交互（如 curl | bash）：先试免密 sudo，失败则给出明确指引
  if sudo -n true 2>/dev/null; then
    exec sudo -n bash "$0" "${args[@]}"
  fi
  err "非交互环境且 sudo 免密不可用，无法自动提权"
  err "请以 root 运行，或先执行 'sudo -v' 缓存凭据后重试"
  exit 1
}

# 缺命令时返回 1 而不是 exit，避免在交互面板里直接退出整个程序
require_cmd() {
  command -v "$1" >/dev/null 2>&1 && return 0
  err "缺少必要命令：$1"
  return 1
}

confirm() {
  local prompt="$1" ans=""
  if [ "$ASSUME_YES" -eq 1 ]; then
    info "已指定 --yes，自动确认：$prompt"
    return 0
  fi
  if ! read_line "$(printf '%s%s [y/N]: %s' "$YELLOW" "$prompt" "$NC")"; then
    if [ "$NONTTY_WARNED" -eq 0 ]; then
      warn "非交互环境：需要确认的操作会被跳过（如需自动执行请加 --yes）"
      NONTTY_WARNED=1
    fi
    info "跳过：$prompt"
    return 1
  fi
  ans="$REPLY_LINE"
  case "$ans" in
    [yY][eE][sS]|[yY]) return 0 ;;
    *) return 1 ;;
  esac
}

pause() {
  # 只在确实有终端时等待；管道/脚本化场景不等待，
  # 否则会把后面本该给菜单的输入（如 "0"）吃掉
  if [ -t 0 ] || [ -n "$F2B_TTY_FD" ]; then
    read_line "按回车键返回菜单..." || return 0
  fi
  return 0
}

# 校验端口：允许数字、字母、逗号（如 2222 / ssh / http,https）
validate_port() {
  local p="$1"
  case "$p" in
    ''|*[!0-9A-Za-z,_-]*)
      err "端口格式不合法：'$p'（示例：22、ssh、http,https）"
      return 1 ;;
  esac
  return 0
}

# 解析安装参数：命令行优先，其次交互输入，最后默认值
resolve_params() {
  if [ -z "$SSH_PORT" ]; then
    if read_line "$(printf '%sSSH 端口 [默认 ssh/22]: %s' "$CYAN" "$NC")"; then
      SSH_PORT="${REPLY_LINE:-ssh}"
    else
      SSH_PORT="ssh"
    fi
  fi
  validate_port "$SSH_PORT" || return 1

  if [ -z "$IGNORE_IPS" ]; then
    if read_line "$(printf '%s白名单 IP（空格分隔）[默认 127.0.0.1/8 ::1]: %s' "$CYAN" "$NC")"; then
      IGNORE_IPS="${REPLY_LINE:-127.0.0.1/8 ::1}"
    else
      IGNORE_IPS="127.0.0.1/8 ::1"
    fi
  fi
  return 0
}

# ---------- 探测工具 ----------
# 读取 sshd 实际监听端口（sshd -T 优先，退回 sshd_config）
detect_ssh_port() {
  local p=""
  if command -v sshd >/dev/null 2>&1; then
    p=$(sshd -T 2>/dev/null | awk 'tolower($1)=="port"{print $2; exit}')
  fi
  if [ -z "$p" ] && [ -r "$SSHD_CONFIG" ]; then
    p=$(awk 'tolower($1)=="port"{print $2; exit}' "$SSHD_CONFIG" 2>/dev/null)
  fi
  printf '%s' "${p:-22}"
}

# 当前 SSH 登录的客户端 IP（非 SSH 会话时为空）
detect_client_ip() {
  local ip=""
  if [ -n "${SSH_CONNECTION:-}" ]; then
    ip="${SSH_CONNECTION%% *}"
  fi
  printf '%s' "$ip"
}

# 端口列表归一化：去掉空白、ssh -> 22、统一小写
normalize_ports() {
  local s
  s=$(printf '%s' "$1" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
  s=${s//ssh/22}
  printf '%s' "$s"
}

# 判断端口是否在逗号分隔列表中
port_in_list() {
  local needle="$1" list="$2"
  case ",${list}," in
    *",${needle},"*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------- jail.local 读写 ----------
# 读取某 section 下某个 key 的值
jail_get_key() {
  local sec="$1" key="$2"
  [ -f "$F2B_JAIL_LOCAL" ] || return 0
  awk -v sec="$sec" -v key="$key" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    /^[[:space:]]*\[/ {
      name = $0; gsub(/[][[:space:]]/, "", name)
      insec = (name == sec) ? 1 : 0
      next
    }
    insec == 1 {
      line = $0
      if (line ~ /^[[:space:]]*[#;]/) next
      k = line; sub(/=.*/, "", k); k = trim(k)
      if (tolower(k) == tolower(key)) {
        v = line; sub(/^[^=]*=/, "", v); print trim(v); exit
      }
    }
  ' "$F2B_JAIL_LOCAL"
}

# 写入/覆盖某 section 下的 key=value（section 不存在则追加）
jail_set_key() {
  local sec="$1" key="$2" val="$3" tmp
  [ -f "$F2B_JAIL_LOCAL" ] || : > "$F2B_JAIL_LOCAL"
  tmp=$(mktemp "${TMPDIR:-/tmp}/f2b.jail.XXXXXX" 2>/dev/null) || return 1
  awk -v sec="$sec" -v key="$key" -v val="$val" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    BEGIN { insec = 0; found = 0; seensec = 0 }
    /^[[:space:]]*\[/ {
      if (insec == 1 && found == 0) { print key " = " val; found = 1 }
      name = $0; gsub(/[][[:space:]]/, "", name)
      insec = (name == sec) ? 1 : 0
      if (insec == 1) seensec = 1
      print; next
    }
    insec == 1 {
      line = $0
      if (line ~ /^[[:space:]]*[#;]/) { print; next }
      k = line; sub(/=.*/, "", k); k = trim(k)
      if (tolower(k) == tolower(key)) {
        if (found == 0) { print key " = " val; found = 1 }
        next
      }
      print; next
    }
    { print }
    END {
      if (insec == 1 && found == 0) { print key " = " val; found = 1 }
      if (seensec == 0) { print ""; print "[" sec "]"; print key " = " val }
    }
  ' "$F2B_JAIL_LOCAL" > "$tmp" || { rm -f "$tmp"; return 1; }
  cat "$tmp" > "$F2B_JAIL_LOCAL" || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  rm -f "$tmp" 2>/dev/null || true
  return 0
}

# 注释掉某 section 下的 key（用于 backend 切 systemd 时禁用 logpath）
jail_del_key() {
  local sec="$1" key="$2" tmp
  [ -f "$F2B_JAIL_LOCAL" ] || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/f2b.jail.XXXXXX" 2>/dev/null) || return 1
  awk -v sec="$sec" -v key="$key" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    /^[[:space:]]*\[/ {
      name = $0; gsub(/[][[:space:]]/, "", name)
      insec = (name == sec) ? 1 : 0
      print; next
    }
    insec == 1 {
      line = $0
      if (line ~ /^[[:space:]]*[#;]/) { print; next }
      k = line; sub(/=.*/, "", k); k = trim(k)
      if (tolower(k) == tolower(key)) { print "# " line; next }
      print; next
    }
    { print }
  ' "$F2B_JAIL_LOCAL" > "$tmp" || { rm -f "$tmp"; return 1; }
  cat "$tmp" > "$F2B_JAIL_LOCAL" || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  rm -f "$tmp" 2>/dev/null || true
  return 0
}

# 把 IP 追加进 [DEFAULT] 的 ignoreip（已存在则跳过）
ignoreip_add() {
  local ip="$1" cur
  cur=$(jail_get_key DEFAULT ignoreip)
  case " ${cur} " in
    *" ${ip} "*) return 0 ;;
  esac
  if [ -n "$cur" ]; then
    jail_set_key DEFAULT ignoreip "${cur} ${ip}"
  else
    jail_set_key DEFAULT ignoreip "${ip}"
  fi
}

# 生成基础 jail.local（安装与自检共用）
write_base_jail() {
  mkdir -p "$F2B_CONF_DIR" || return 1
  local banaction_line="" logpath_line="" backend_line=""

  # 封禁后端必须与系统实际可用的工具一致。
  # Debian 12+ 默认 nftables，很多精简镜像没有 iptables 命令；
  # 若写死 iptables-multiport，fail2ban 启动时 action 初始化失败 → status=255。
  if command -v nft >/dev/null 2>&1; then
    banaction_line="banaction = nftables"
  elif command -v iptables >/dev/null 2>&1; then
    banaction_line="banaction = iptables-multiport"
  fi

  # 日志来源：有 auth.log 就按文件读，否则走 systemd journal（Debian 12+ 常态）
  if [ -f "$AUTH_LOG" ]; then
    logpath_line="logpath  = ${AUTH_LOG}"
  else
    backend_line="backend  = systemd"
  fi

  cat > "$F2B_JAIL_LOCAL" <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
${banaction_line}
ignoreip = ${IGNORE_IPS}

[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
${logpath_line}
${backend_line}
maxretry = 3
bantime  = 24h
EOF
}

# ---------- 已存在 jail.local 的坏配置检查与修复 ----------
# install 不会覆盖已有的 jail.local，但如果它是旧模板生成的
# （logpath 指向不存在的文件、banaction 与系统工具不匹配），
# 服务会直接以 status=255 退出。这里就地修掉这两类问题。
# 返回 0 表示改过配置。
repair_existing_jail() {
  local changed=0 lp p missing ba
  [ -f "$F2B_JAIL_LOCAL" ] || return 1

  # 1) logpath 指向的文件不存在 → 改 backend = systemd
  lp=$(jail_get_key sshd logpath)
  if [ -n "$lp" ]; then
    missing=1
    for p in $lp; do
      [ -f "$p" ] && missing=0
    done
    if [ "$missing" -eq 1 ]; then
      warn "sshd jail 的 logpath 指向不存在的文件：${lp}"
      info "这是 Debian 12+ 启动失败（status=255）最常见的原因"
      if confirm "是否改为 backend = systemd 并注释掉 logpath？"; then
        if jail_set_key sshd backend systemd; then
          jail_del_key sshd logpath
          ok "已改为 backend = systemd"
          changed=1
        else
          err "写入 $F2B_JAIL_LOCAL 失败"
        fi
      fi
    fi
  fi

  # 2) banaction 与系统实际可用的工具不匹配 → 改成 nftables
  ba=$(jail_get_key DEFAULT banaction)
  case "$ba" in
    *iptables*)
      if ! command -v iptables >/dev/null 2>&1 && command -v nft >/dev/null 2>&1; then
        warn "banaction = ${ba}，但系统没有 iptables 命令（只有 nft）"
        if confirm "是否改为 banaction = nftables？"; then
          if jail_set_key DEFAULT banaction nftables; then
            ok "已改为 nftables"
            changed=1
          fi
        fi
      fi ;;
    *nftables*)
      if ! command -v nft >/dev/null 2>&1; then
        warn "banaction = ${ba}，但系统没有 nft 命令（请 apt install nftables）"
      fi ;;
  esac

  [ "$changed" -eq 1 ]
}

# 启动失败时把 journal 里最关键的几行直接打出来，省得用户再翻日志
_show_start_error() {
  local out
  out=$(journalctl -u "$SERVICE" -n 30 --no-pager -o cat 2>/dev/null \
        | grep -iE 'error|failed|not found|denied|no such' | tail -n 5)
  if [ -n "$out" ]; then
    printf '\n%s最近的相关日志：%s\n' "$DIM" "$NC"
    printf '%s\n' "$out" | sed 's/^/  /'
  fi
  info "完整日志：journalctl -u ${SERVICE} -n 50 --no-pager -o cat"
  info "配置自检：fail2ban-client -t"
}

# ---------- 1. 安装 ----------
do_install() {
  need_root install
  require_cmd apt || return 1
  require_cmd systemctl || return 1

  resolve_params || return 1
  info "安装参数：SSH 端口 = ${SSH_PORT}，白名单 = ${IGNORE_IPS}"

  if dpkg -s fail2ban >/dev/null 2>&1; then
    info "检测到 fail2ban 已安装，跳过 apt install"
  else
    info "更新软件源..."
    apt update -y || { err "apt update 失败"; return 1; }
    info "安装 fail2ban..."
    DEBIAN_FRONTEND=noninteractive apt install -y fail2ban || { err "安装失败"; return 1; }
  fi

  if [ ! -f "$F2B_JAIL_LOCAL" ]; then
    info "生成基础配置 $F2B_JAIL_LOCAL ..."
    if write_base_jail; then
      ok "已生成基础 jail.local（SSH 防护，端口 ${SSH_PORT}）"
    else
      err "写入 $F2B_JAIL_LOCAL 失败"; return 1
    fi
  else
    warn "已存在 $F2B_JAIL_LOCAL，跳过覆盖"
    if repair_existing_jail; then
      ok "已修复 $F2B_JAIL_LOCAL 中的问题配置"
    fi
  fi

  info "设置开机自启并启动..."
  systemctl enable "$SERVICE" >/dev/null 2>&1
  systemctl restart "$SERVICE"

  sleep 1
  if systemctl is-active --quiet "$SERVICE"; then
    ok "Fail2ban 安装并启动成功"
    show_status
  else
    err "服务启动失败（systemd status=255 表示配置初始化失败）"
    _show_start_error
    return 1
  fi

  # 装完自动衔接交互式自检（doctor 内部调用 install 时不重复）
  if [ "$SUPPRESS_POST_DOCTOR" -eq 0 ] && [ -t 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
    echo
    if confirm "是否立即运行自检，交互式处理潜在问题？"; then
      do_doctor
    fi
  fi
}

# ---------- 2. 一键：自动探测 + 安装 + 自检 ----------
do_auto() {
  need_root auto
  local p cip
  p=$(detect_ssh_port)
  cip=$(detect_client_ip)

  section "一键安装"
  kv "检测到 SSH 端口" "${p}"
  if [ -n "$cip" ]; then
    kv "当前登录 IP" "${cip}（将加入白名单，避免误封自己）"
  else
    kv "当前登录 IP" "（非 SSH 会话，未自动加白）"
  fi

  [ -z "$SSH_PORT" ] && SSH_PORT="$p"
  if [ -z "$IGNORE_IPS" ]; then
    IGNORE_IPS="127.0.0.1/8 ::1"
    [ -n "$cip" ] && IGNORE_IPS="${IGNORE_IPS} ${cip}"
  fi

  if ! confirm "使用以上参数安装 Fail2ban?"; then
    info "已取消"; return 0
  fi

  SUPPRESS_POST_DOCTOR=1
  if ! do_install; then
    SUPPRESS_POST_DOCTOR=0
    echo
    warn "安装未成功，转入自检流程继续排查（菜单项叫「自动修复」，这里兜住）"
    do_doctor
    return 1
  fi
  SUPPRESS_POST_DOCTOR=0

  echo
  info "安装完成，进入自检..."
  do_doctor
}

# ---------- 3. 自检与交互式问题处理 ----------
do_doctor() {
  need_root doctor
  local issues=0 fixed=0 cfg_changed=0 did_reload=0
  local real_port conf_port conf_norm cip cur backend

  section "Fail2ban 自检与问题处理"

  # --- 1. 是否安装 ---
  if command -v fail2ban-client >/dev/null 2>&1; then
    ok "已安装 fail2ban"
  else
    issues=$((issues+1)); warn "未安装 fail2ban"
    if confirm "是否现在安装？"; then
      SUPPRESS_POST_DOCTOR=1
      if do_install; then fixed=$((fixed+1)); fi
      SUPPRESS_POST_DOCTOR=0
    fi
  fi

  # --- 2. 配置文件是否存在 ---
  if [ -f "$F2B_JAIL_LOCAL" ]; then
    ok "配置文件存在：$F2B_JAIL_LOCAL"
  else
    issues=$((issues+1)); warn "缺少 $F2B_JAIL_LOCAL（自定义配置会丢失）"
    if confirm "是否生成基础配置？"; then
      [ -z "$SSH_PORT" ] && SSH_PORT="$(detect_ssh_port)"
      [ -z "$IGNORE_IPS" ] && IGNORE_IPS="127.0.0.1/8 ::1"
      if write_base_jail; then
        ok "已生成 $F2B_JAIL_LOCAL"; fixed=$((fixed+1)); cfg_changed=1
      else
        err "写入失败"
      fi
    fi
  fi

  # --- 3. SSH 端口与 jail 配置是否一致 ---
  if [ -f "$F2B_JAIL_LOCAL" ]; then
    real_port=$(detect_ssh_port)
    conf_port=$(jail_get_key sshd port)
    conf_norm=$(normalize_ports "$conf_port")
    if [ -z "$conf_port" ]; then
      issues=$((issues+1))
      warn "sshd jail 未显式配置 port（实际 SSH 端口 ${real_port}）"
      if confirm "是否写入 port = ${real_port}？"; then
        if jail_set_key sshd port "$real_port"; then ok "已写入 port"; fixed=$((fixed+1)); cfg_changed=1; fi
      fi
    elif ! port_in_list "$real_port" "$conf_norm"; then
      issues=$((issues+1))
      warn "端口不一致：sshd 实际 ${real_port}，jail 配置 ${conf_port}（会导致封禁失效）"
      if confirm "是否把 jail 端口改为 ${real_port}？"; then
        if jail_set_key sshd port "$real_port"; then ok "已更新 port"; fixed=$((fixed+1)); cfg_changed=1; fi
      fi
    else
      ok "SSH 端口一致：${real_port}"
    fi
  fi

  # --- 4. 当前登录 IP 是否在白名单 ---
  cip=$(detect_client_ip)
  if [ -n "$cip" ] && [ -f "$F2B_JAIL_LOCAL" ]; then
    cur=$(jail_get_key DEFAULT ignoreip)
    if printf ' %s ' "$cur" | grep -qF " ${cip} "; then
      ok "当前 IP ${cip} 已在白名单"
    else
      issues=$((issues+1))
      warn "当前登录 IP ${cip} 不在白名单，可能把自己封掉"
      if confirm "是否把 ${cip} 加入 ignoreip？"; then
        if ignoreip_add "$cip"; then ok "已加入白名单"; fixed=$((fixed+1)); cfg_changed=1; fi
      fi
    fi
  fi

  # --- 5. 日志后端：auth.log 缺失（Debian 12+ 常见） ---
  if [ -f "$AUTH_LOG" ]; then
    ok "认证日志存在：$AUTH_LOG"
  else
    backend=$(jail_get_key sshd backend)
    if [ "$backend" = "systemd" ]; then
      ok "未使用 auth.log，sshd jail 已配置 backend = systemd"
    else
      issues=$((issues+1))
      warn "缺少 $AUTH_LOG（Debian 12+ 默认改用 systemd journal）"
      if confirm "是否把 sshd jail 的 backend 改为 systemd？"; then
        if jail_set_key sshd backend systemd; then
          jail_del_key sshd logpath
          ok "已设置 backend = systemd，并注释掉 logpath"; fixed=$((fixed+1)); cfg_changed=1
        fi
      fi
    fi
  fi

  # --- 5.5 封禁后端：banaction 与系统实际工具是否匹配（255 退出的常见原因） ---
  local ba=""
  ba=$(jail_get_key DEFAULT banaction)
  if [ -z "$ba" ] && [ -f "$F2B_CONF_DIR/paths-debian.conf" ]; then
    ba=$(sed -n 's/^[[:space:]]*banaction[[:space:]]*=[[:space:]]*//p' \
         "$F2B_CONF_DIR/paths-debian.conf" 2>/dev/null | head -1)
  fi
  case "$ba" in
    *nftables*)
      if command -v nft >/dev/null 2>&1; then
        ok "封禁后端 nftables（nft 可用）"
      else
        issues=$((issues+1))
        warn "banaction=$ba，但系统没有 nft 命令，封禁会失败"
        if confirm "是否安装 nftables？"; then
          if apt-get install -y nftables >/dev/null 2>&1; then
            ok "已安装 nftables"; fixed=$((fixed+1))
          else
            warn "安装失败，请手动执行：apt install nftables"
          fi
        fi
      fi ;;
    *iptables*)
      if command -v iptables >/dev/null 2>&1; then
        ok "封禁后端 iptables（iptables 可用）"
      else
        issues=$((issues+1))
        warn "banaction=$ba，但系统没有 iptables 命令（Debian 12 默认用 nftables）"
        if confirm "是否把 banaction 改为 nftables？"; then
          if jail_set_key DEFAULT banaction nftables; then
            ok "已改为 nftables"; fixed=$((fixed+1)); cfg_changed=1
          fi
        fi
      fi ;;
    "")
      ok "banaction 使用发行版默认值（Debian 12 为 nftables）" ;;
    *)
      ok "封禁后端：$ba" ;;
  esac

  # --- 6. 服务是否运行 ---
  if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
    ok "服务运行中"
  else
    issues=$((issues+1)); warn "服务未运行"
    if confirm "是否启动服务？"; then
      if systemctl start "$SERVICE" >/dev/null 2>&1; then
        ok "服务已启动"; fixed=$((fixed+1))
      else
        err "启动失败（status=255 表示配置初始化失败）"
        _show_start_error
      fi
    fi
  fi

  # --- 7. 开机自启 ---
  if systemctl is-enabled --quiet "$SERVICE" 2>/dev/null; then
    ok "已设置开机自启"
  else
    issues=$((issues+1)); warn "未设置开机自启"
    if confirm "是否设置开机自启？"; then
      if systemctl enable "$SERVICE" >/dev/null 2>&1; then
        ok "已设置开机自启"; fixed=$((fixed+1))
      else
        err "设置失败"
      fi
    fi
  fi

  # --- 8. sshd jail 是否真的生效 ---
  if fail2ban-client status >/dev/null 2>&1; then
    if fail2ban-client status 2>/dev/null | grep -qw sshd; then
      ok "sshd jail 已启用"
    else
      issues=$((issues+1)); warn "sshd jail 未启用"
      if confirm "是否重载配置使其生效？"; then
        if fail2ban-client reload >/dev/null 2>&1; then
          ok "已重载"; fixed=$((fixed+1)); did_reload=1
        else
          err "重载失败，请检查配置语法：fail2ban-client -t"
        fi
      fi
    fi
  fi

  # --- 9. 配置语法 ---
  if command -v fail2ban-client >/dev/null 2>&1; then
    if fail2ban-client -t >/dev/null 2>&1; then
      ok "配置语法检查通过"
    else
      issues=$((issues+1))
      warn "配置语法有误，执行 'fail2ban-client -t' 查看详情"
      fail2ban-client -t 2>&1 | tail -n 5
    fi
  fi

  # --- 10. 防火墙后端 ---
  if command -v iptables >/dev/null 2>&1 || command -v nft >/dev/null 2>&1; then
    ok "防火墙工具可用（iptables/nft）"
  else
    issues=$((issues+1))
    warn "未找到 iptables/nft，封禁动作可能无法生效"
    info "请安装：apt install -y iptables"
  fi

  # --- 11. 封禁概况 ---
  if fail2ban-client status >/dev/null 2>&1; then
    section "当前封禁概况"
    fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:[[:space:]]*/  已启用 Jail: /p'
    local j banned
    for j in $(fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:[[:space:]]*//p' | tr ',' ' '); do
      banned=$(fail2ban-client status "$j" 2>/dev/null | sed -n 's/.*Currently banned:[[:space:]]*//p')
      printf '  %-16s 已封禁 %s 个 IP\n' "$j" "${banned:-0}"
    done
  fi

  # --- 汇总 ---
  section "自检结果"
  if [ "$issues" -eq 0 ]; then
    ok "未发现问题，配置状态良好"
  else
    printf '  共发现 %s 个问题，已处理 %s 个\n' "$issues" "$fixed"
    if [ "$fixed" -lt "$issues" ]; then
      warn "仍有 $((issues - fixed)) 个问题未处理（可再次运行 doctor）"
    elif [ "$did_reload" -eq 1 ] || [ "$cfg_changed" -eq 0 ]; then
      ok "全部问题已处理"
    else
      ok "全部问题已处理，建议执行一次 reload 或 restart"
    fi
  fi

  if [ "$cfg_changed" -eq 1 ] && [ "$did_reload" -eq 0 ] \
     && fail2ban-client status >/dev/null 2>&1; then
    if confirm "配置已修改，是否重载使其生效？"; then
      if fail2ban-client reload >/dev/null 2>&1; then ok "已重载"; else warn "重载失败"; fi
    fi
  fi
}

# ---------- 4. 卸载 ----------
do_uninstall() {
  need_root uninstall
  require_cmd apt || return 1
  warn "即将卸载 Fail2ban，并可选删除 /etc/fail2ban 配置目录。"
  confirm "确认继续卸载?" || { info "已取消"; return 0; }

  if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
    info "解除所有封禁..."
    fail2ban-client unban --all >/dev/null 2>&1 || true
    info "停止并禁用服务..."
    systemctl stop "$SERVICE" >/dev/null 2>&1 || true
    systemctl disable "$SERVICE" >/dev/null 2>&1 || true
  fi

  info "卸载软件包（purge）..."
  DEBIAN_FRONTEND=noninteractive apt purge -y fail2ban || warn "apt purge 返回非零，可能已卸载"

  if confirm "是否同时删除配置目录 $F2B_CONF_DIR 与日志 $F2B_LOG ?"; then
    rm -rf "$F2B_CONF_DIR"
    rm -f "$F2B_LOG" "$F2B_LOG".* 2>/dev/null || true
    ok "已删除配置目录与日志"
  else
    info "保留配置目录 $F2B_CONF_DIR"
  fi

  ok "卸载完成。"
  info "提示：若曾用 iptables 封禁，可用 'iptables -L -n | grep f2b' 检查残留链。"
}

# ---------- 5. 重启 / 重载 ----------
do_restart() {
  need_root restart
  require_cmd systemctl || return 1
  info "重启 Fail2ban 服务..."
  if systemctl restart "$SERVICE"; then
    ok "重启完成"
    show_status
  else
    err "重启失败，请查看：journalctl -u $SERVICE -n 50"
    return 1
  fi
}

do_reload() {
  need_root reload
  require_cmd fail2ban-client || return 1
  info "重载配置（不中断现有封禁）..."
  if fail2ban-client reload; then
    ok "重载完成"
  else
    err "重载失败，请检查配置语法：fail2ban-client -t"
    return 1
  fi
}

# ---------- 6. 状态查看 ----------
show_status() {
  section "服务状态"
  if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
    ok "服务运行中"
  else
    warn "服务未运行"
  fi
  systemctl status "$SERVICE" --no-pager -l 2>/dev/null | head -n 12

  section "已启用的 Jail"
  if ! fail2ban-client status >/dev/null 2>&1; then
    warn "无法连接 fail2ban 服务（可能未启动或未安装）"
    return 0
  fi
  fail2ban-client status

  local jails j
  jails=$(fail2ban-client status 2>/dev/null \
          | sed -n 's/.*Jail list:[[:space:]]*//p' \
          | tr ',' ' ')
  [ -z "$jails" ] && return 0

  for j in $jails; do
    section "Jail 详情：$j"
    fail2ban-client status "$j" 2>/dev/null
  done
}

do_status() {
  if ! command -v fail2ban-client >/dev/null 2>&1; then
    err "未检测到 fail2ban-client，请先执行 install"
    return 1
  fi
  show_status
  echo
  _show_sshd_config || true
}

# 只显示 sshd 的生效配置（不打印完整状态）
do_info() {
  if ! command -v fail2ban-client >/dev/null 2>&1; then
    err "未检测到 fail2ban-client，请先执行 install"
    return 1
  fi
  if ! _show_sshd_config; then
    warn "sshd jail 未启用或服务未运行，读不到配置"
    info "先执行 doctor 自检，或查看 fail2ban-client status"
    return 1
  fi
}

# ---------- 7. 显示目录位置 ----------
do_dir() {
  section "Fail2ban 关键路径"
  kv "主配置目录"      "$F2B_CONF_DIR"
  kv "本地覆盖配置"    "$F2B_JAIL_LOCAL"
  kv "默认 jail 定义"  "$F2B_CONF_DIR/jail.conf"
  kv "Debian 默认启用" "$F2B_CONF_DIR/jail.d/defaults-debian.conf"
  kv "jail.d 目录"     "$F2B_CONF_DIR/jail.d/"
  kv "过滤器目录"      "$F2B_CONF_DIR/filter.d/"
  kv "动作目录"        "$F2B_CONF_DIR/action.d/"
  kv "路径变量"        "$F2B_CONF_DIR/paths-debian.conf"
  kv "运行日志"        "$F2B_LOG"
  kv "SSH 认证日志"    "$AUTH_LOG"
  kv "封禁数据库"      "/var/lib/fail2ban/fail2ban.sqlite3"
  kv "systemd 服务"    "/lib/systemd/system/fail2ban.service"

  echo
  if [ -d "$F2B_CONF_DIR" ]; then
    info "配置目录内容："
    ls -lh "$F2B_CONF_DIR" 2>/dev/null
    if [ -d "$F2B_CONF_DIR/jail.d" ]; then
      echo
      info "jail.d 目录内容（Debian 默认启用项 + 自定义规则都在这里）："
      find "$F2B_CONF_DIR/jail.d" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null \
        | sort | sed 's/^/  /'
    fi
  else
    warn "$F2B_CONF_DIR 不存在（可能尚未安装）"
  fi

  echo
  section "新建规则该放哪"
  kv "jail（规则本体）"   "${F2B_CONF_DIR}/jail.d/<服务名>.local"
  kv "filter（日志正则）" "${F2B_CONF_DIR}/filter.d/<服务名>.conf"
  info "加载优先级（后者覆盖前者）："
  printf '  %s\n' "jail.conf  →  jail.d/*.conf  →  jail.local  →  jail.d/*.local"
  info "看生效值：fail2ban-client get sshd bantime / maxretry / findtime"
}

# ---------- 8. 查看日志 ----------
do_logs() {
  require_cmd tail || return 1
  if [ ! -f "$F2B_LOG" ]; then
    warn "$F2B_LOG 不存在，尝试查看 journald..."
    journalctl -u "$SERVICE" -n 50 --no-pager 2>/dev/null || err "无法读取日志"
    return 0
  fi
  info "实时跟踪 $F2B_LOG（Ctrl+C 返回面板）..."
  # Ctrl+C 只终止 tail，不要把整个面板进程一起带走
  trap ':' INT
  tail -f "$F2B_LOG" || true
  trap - INT
  return 0
}

# ---------- 9. 启用 / 禁用自启 ----------
do_enable() {
  need_root enable
  require_cmd systemctl || return 1
  if systemctl enable "$SERVICE" >/dev/null 2>&1; then
    ok "已设置开机自启"
  else
    warn "设置开机自启失败"
  fi
  if systemctl start "$SERVICE" >/dev/null 2>&1; then
    ok "服务已启动"
  else
    warn "启动服务失败"
  fi
}

do_disable() {
  need_root disable
  require_cmd systemctl || return 1
  if systemctl disable "$SERVICE" >/dev/null 2>&1; then
    ok "已取消开机自启"
  else
    warn "取消开机自启失败"
  fi
}

# ---------- 帮助 ----------
show_help() {
  printf 'Fail2ban 一键管理脚本 v%s（Debian / Ubuntu）\n\n' "$SCRIPT_VERSION"
  cat <<'EOF'
用法:
  ./fail2ban-debian.sh <命令> [选项]
  非 root 时会自动通过 sudo 提权重入，无需手动加 sudo。

命令:
  bootstrap   一键部署：装成系统命令 + 自动安装 + 进入交互面板（傻瓜式入口）
  auto        一键安装：自动探测 SSH 端口/当前 IP → 安装 → 交互式自检
  selfinstall 仅把本脚本安装为 /usr/local/bin/fail2ban-tool
  install     安装并启动（可配 --port / --ignore-ip）
  doctor      自检并交互式处理问题（服务/端口/白名单/日志后端等）
  uninstall   卸载
  restart     重启服务
  reload      重载配置（不中断封禁）
  status      查看服务状态与封禁列表（含 sshd 生效配置）
  info        只查看 sshd 的生效配置（bantime/findtime/maxretry/白名单/动作）
  dir         显示关键目录位置
  logs        实时跟踪日志
  enable      设置开机自启
  disable     取消开机自启
  menu        交互面板（默认）
  help        显示本帮助

选项:
  --port <端口>           SSH 端口，默认 ssh（即 22）
  --ignore-ip "<IP列表>"  白名单，空格分隔，默认 "127.0.0.1/8 ::1"
  -y, --yes               跳过所有确认（适合自动化）
  --no-elevate            禁止自动 sudo 提权（非 root 时直接报错）

示例:
  curl -fsSL <url> | bash                          # 一条命令装好并进面板
  ./fail2ban-debian.sh bootstrap                   # 同上（本地脚本）
  sudo fail2ban-tool                               # 装完后随时打开面板
  ./fail2ban-debian.sh auto                        # 一键装好并自检
  ./fail2ban-debian.sh install --port 2222
  ./fail2ban-debian.sh doctor                      # 出问题先跑这个
  ./fail2ban-debian.sh uninstall --yes
EOF
}

# ---------- 10. 安装/更新管理命令 ----------
do_selfinstall() {
  need_root selfinstall
  local target="${BIN_DIR}/${TOOL_NAME}"
  # 管道执行时 $0 是 bash/sh，不是脚本文件，绝不能拿去当命令复制
  if [ ! -f "$0" ]; then
    err "当前不是以脚本文件方式运行（如 curl | bash），无法自安装为 ${TOOL_NAME}"
    info "请先下载再执行：curl -fsSL <脚本地址> -o f2b.sh && sudo bash f2b.sh selfinstall"
    return 1
  fi
  if mkdir -p "$BIN_DIR" 2>/dev/null \
     && cp "$0" "$target" 2>/dev/null \
     && chmod 0755 "$target" 2>/dev/null; then
    ok "已安装管理命令：${target}"
    info "以后可直接执行：sudo ${TOOL_NAME}"
    return 0
  fi
  err "安装失败：无法写入 ${target}（权限不足或目录只读）"
  return 1
}

# ---------- 11. 一键部署（傻瓜式入口） ----------
# 把自己装成系统命令 → 未装 fail2ban 则自动装好 → 直接进入交互面板
do_bootstrap() {
  need_root bootstrap
  local target="${BIN_DIR}/${TOOL_NAME}" cip

  section "一键部署"
  kv "管理命令" "${target}"

  if [ -f "$target" ] && [ -f "$0" ] && cmp -s "$0" "$target" 2>/dev/null; then
    ok "管理命令已是最新"
  elif do_selfinstall >/dev/null 2>&1; then
    ok "管理命令已就绪（以后直接执行 sudo ${TOOL_NAME}）"
  else
    warn "无法写入 ${target}，本次仍可继续操作，但下次需重新下载脚本"
    target=""
  fi

  if command -v fail2ban-client >/dev/null 2>&1; then
    ok "fail2ban 已安装，跳过安装步骤"
  else
    info "未检测到 fail2ban，开始自动安装（自动探测端口 + 当前 IP 加白）..."
    if [ -z "$SSH_PORT" ]; then SSH_PORT="$(detect_ssh_port)"; fi
    if [ -z "$IGNORE_IPS" ]; then
      IGNORE_IPS="127.0.0.1/8 ::1"
      cip=$(detect_client_ip)
      if [ -n "$cip" ]; then IGNORE_IPS="${IGNORE_IPS} ${cip}"; fi
    fi
    SUPPRESS_POST_DOCTOR=1
    if do_install; then
      ok "安装完成"
    else
      err "自动安装未完成，进入面板后可选择「自检并处理问题」"
    fi
    SUPPRESS_POST_DOCTOR=0
  fi

  # 优先用已安装的副本进入面板，避免临时解压文件被清理后中断
  if [ -n "$target" ] && [ "$0" != "$target" ]; then
    if have_tty; then
      info "正在进入交互面板..."
      # 关键：把 /dev/tty 接成新进程的 stdin，否则管道场景下 read 立即 EOF
      exec "$target" menu < /dev/tty
    fi
    warn "当前没有交互终端，无法自动进入面板"
    info "请在新终端执行：sudo ${TOOL_NAME}"
    return 0
  fi
  do_menu
}

# ---------- 交互面板 ----------
_panel_rule() { printf '%s%s%s\n' "$DIM" "------------------------------------------------------------" "$NC"; }

_panel_status() {
  local state autostart="-" bans="-" jails="无" port="-" j n total=0
  state="${RED}未安装${NC}"
  if command -v fail2ban-client >/dev/null 2>&1; then
    if _t systemctl is-active --quiet "$SERVICE"; then
      state="${GREEN}运行中${NC}"
    else
      state="${YELLOW}已停止${NC}"
    fi
    if _t systemctl is-enabled --quiet "$SERVICE"; then
      autostart="是"
    else
      autostart="否"
    fi
    port=$(jail_get_key sshd port)
    [ -z "$port" ] && port="未设置"
    jails=$(_t fail2ban-client status \
            | sed -n 's/.*Jail list:[[:space:]]*//p' | tr -d '\t')
    # 注意：必须在遍历之后再把空值换成"无"，
    # 否则会拿"无"当 jail 名去查询（多一次无意义调用，卡顿时更明显）
    if [ -n "$jails" ]; then
      for j in $(printf '%s' "$jails" | tr ',' ' '); do
        n=$(_t fail2ban-client status "$j" \
            | sed -n 's/.*Currently banned:[[:space:]]*//p' | tr -d '[:space:]')
        case "$n" in ''|*[!0-9]*) n=0 ;; esac
        total=$(( total + n ))
      done
    else
      jails="无"
    fi
    bans="$total"
  fi
  printf '  服务 %s    自启 %s    封禁 %s 个    端口 %s\n' "$state" "$autostart" "$bans" "$port"
  printf '  Jail: %s\n' "$jails"
}

show_menu() {
  printf '\n%s%s%s\n' "$BOLD" "============================================================" "$NC"
  printf '%s  Fail2ban 管理面板 · Debian / Ubuntu%s  %sv%s%s\n' \
    "$BOLD" "$NC" "$DIM" "$SCRIPT_VERSION" "$NC"
  _panel_rule
  _panel_status
  _panel_rule
  echo "   1) 一键安装 / 自动修复"
  echo "   2) 手动安装（自定义端口与白名单）"
  echo "   3) 自检并处理问题"
  echo "   4) 查看状态与封禁列表"
  echo "   5) 重启服务"
  echo "   6) 重载配置"
  echo "   7) 查看实时日志"
  echo "   8) 显示目录位置"
  echo "   9) 开启开机自启"
  echo "  10) 关闭开机自启"
  echo "  11) 卸载"
  echo "  12) 重装管理命令到 ${BIN_DIR}"
  echo "   0) 退出"
  _panel_rule
}

do_menu() {
  local choice
  # 面板里绝大多数操作都要 root，进入时一次性提权，
  # 避免点某项时再 exec sudo 把当前面板进程顶掉（表现为"面板闪一下就没了"）
  need_root menu

  while true; do
    show_menu
    if ! read_line "请选择 [0-12]: "; then
      printf '\n'
      # 完全没有交互能力（既无 stdin 数据、也无 /dev/tty）时给出明确说明
      if ! [ -t 0 ] && ! have_tty; then
        no_tty_hint
        return 1
      fi
      warn "输入结束，退出面板"
      return 0
    fi
    choice="$REPLY_LINE"
    case "$choice" in
      1)  do_auto ;;
      2)  SSH_PORT=""; IGNORE_IPS=""; do_install ;;
      3)  do_doctor ;;
      4)  do_status ;;
      5)  do_restart ;;
      6)  do_reload ;;
      7)  do_logs ;;
      8)  do_dir ;;
      9)  do_enable ;;
      10) do_disable ;;
      11) do_uninstall ;;
      12) do_selfinstall ;;
      0)  echo "再见"; return 0 ;;
      "") warn "没有输入内容，请输入 0-12" ;;
      *)  warn "无效选项：$choice" ;;
    esac
    [ "$choice" != "7" ] && pause
  done
}

# ---------- 入口分发 ----------
# 参数顺序无关：命令与选项可任意前后，例如
#   install --port 2222   /   --port 2222 install   /   -y doctor
main() {
  CMD=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --port)
        if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
          err "--port 需要一个值，例如：--port 2222"
          exit 1
        fi
        SSH_PORT="$2"; shift 2 ;;
      --port=*)
        SSH_PORT="${1#*=}"
        [ -n "$SSH_PORT" ] || { err "--port= 后不能为空"; exit 1; }
        shift ;;
      --ignore-ip)
        if [ $# -lt 2 ]; then
          err "--ignore-ip 需要一个值，例如：--ignore-ip \"1.2.3.4/32\""
          exit 1
        fi
        IGNORE_IPS="$2"; shift 2 ;;
      --ignore-ip=*)
        IGNORE_IPS="${1#*=}"
        [ -n "$IGNORE_IPS" ] || { err "--ignore-ip= 后不能为空"; exit 1; }
        shift ;;
      -y|--yes)
        ASSUME_YES=1; shift ;;
      --no-elevate)
        NO_ELEVATE=1; shift ;;
      -h|--help)
        show_help; exit 0 ;;
      -*)
        err "未知参数：$1（用 help 查看用法）"
        exit 1 ;;
      *)
        if [ -n "$CMD" ]; then
          err "多余的参数：$1（命令只能是第一个非选项参数）"
          exit 1
        fi
        CMD="$1"; shift ;;
    esac
  done

  [ -z "$CMD" ] && CMD=menu

  case "$CMD" in
    bootstrap|start|ui) do_bootstrap ;;
    selfinstall) do_selfinstall ;;
    auto|onekey) do_auto ;;
    install)     do_install ;;
    doctor|check|fix) do_doctor ;;
    uninstall)   do_uninstall ;;
    restart)     do_restart ;;
    reload)      do_reload ;;
    status)      do_status ;;
    info|config) do_info ;;
    dir)         do_dir ;;
    logs)        do_logs ;;
    enable)      do_enable ;;
    disable)     do_disable ;;
    menu)        do_menu ;;
    help)        show_help ;;
    *)
      err "未知命令：$CMD"
      show_help
      exit 1 ;;
  esac
}

# F2B_LIB_ONLY=1 时只加载函数，不执行入口（便于测试与复用）
if [ "${F2B_LIB_ONLY:-0}" != "1" ]; then
  main "$@"
fi
