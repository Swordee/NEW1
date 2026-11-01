#!/usr/bin/env bash
# ============================================================
#  Fail2ban 一键管理脚本（Debian / Ubuntu 适用）
#
#  用法:
#    sudo ./fail2ban-debian.sh <命令> [选项]
#
#  命令:
#    install     安装并启动（可配 --port / --ignore-ip）
#    uninstall   卸载
#    restart     重启服务
#    reload      重载配置（不中断封禁）
#    status      查看服务状态与封禁列表
#    dir         显示关键目录位置
#    logs        实时跟踪日志
#    enable      设置开机自启
#    disable     取消开机自启
#    menu        交互菜单（默认）
#    help        显示帮助
#
#  选项:
#    --port <端口>          SSH 端口，默认 ssh（即 22）
#    --ignore-ip "<IP列表>" 白名单，空格分隔，默认 "127.0.0.1/8 ::1"
#    -y, --yes              跳过所有确认（适合脚本自动化）
#
#  示例:
#    sudo ./fail2ban-debian.sh install --port 2222 --ignore-ip "1.2.3.4/32"
#    sudo ./fail2ban-debian.sh uninstall --yes
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
SERVICE="fail2ban"

# ---------- 全局状态 ----------
SSH_PORT=""
IGNORE_IPS=""
ASSUME_YES=0
CMD=""

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

# ---------- 通用检查 ----------
need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "需要 root 权限，请用：sudo $0 ${CMD}"
    exit 1
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "缺少必要命令：$1"; exit 1; }
}

confirm() {
  local prompt="$1" ans
  if [ "$ASSUME_YES" -eq 1 ]; then
    info "已指定 --yes，自动确认：$prompt"
    return 0
  fi
  if [ ! -t 0 ]; then
    warn "非交互环境，默认取消（如需自动确认请加 --yes）"
    return 1
  fi
  read -r -p "$(printf '%s%s [y/N]: %s' "$YELLOW" "$prompt" "$NC")" ans
  case "$ans" in
    [yY][eE][sS]|[yY]) return 0 ;;
    *) return 1 ;;
  esac
}

pause() {
  [ -t 0 ] || return 0
  read -r -p "按回车键返回菜单..." _ || true
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
    if [ -t 0 ]; then
      read -r -p "$(printf '%sSSH 端口 [默认 ssh/22]: %s' "$CYAN" "$NC")" p
      SSH_PORT="${p:-ssh}"
    else
      SSH_PORT="ssh"
    fi
  fi
  validate_port "$SSH_PORT" || return 1

  if [ -z "$IGNORE_IPS" ]; then
    if [ -t 0 ]; then
      read -r -p "$(printf '%s白名单 IP（空格分隔）[默认 127.0.0.1/8 ::1]: %s' "$CYAN" "$NC")" ips
      IGNORE_IPS="${ips:-127.0.0.1/8 ::1}"
    else
      IGNORE_IPS="127.0.0.1/8 ::1"
    fi
  fi
  return 0
}

# ---------- 1. 安装 ----------
do_install() {
  need_root
  require_cmd apt
  require_cmd systemctl

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
    cat > "$F2B_JAIL_LOCAL" <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
banaction = iptables-multiport
ignoreip = ${IGNORE_IPS}

[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 24h
EOF
    ok "已生成基础 jail.local（SSH 防护，端口 ${SSH_PORT}）"
  else
    warn "已存在 $F2B_JAIL_LOCAL，跳过覆盖（如需修改请手动编辑）"
  fi

  info "设置开机自启并启动..."
  systemctl enable "$SERVICE" >/dev/null 2>&1
  systemctl restart "$SERVICE"

  sleep 1
  if systemctl is-active --quiet "$SERVICE"; then
    ok "Fail2ban 安装并启动成功"
    show_status
  else
    err "服务启动失败，请查看：journalctl -u $SERVICE -n 50"
    return 1
  fi
}

# ---------- 2. 卸载 ----------
do_uninstall() {
  need_root
  require_cmd apt
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

# ---------- 3. 重启 / 重载 ----------
do_restart() {
  need_root
  require_cmd systemctl
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
  need_root
  require_cmd fail2ban-client
  info "重载配置（不中断现有封禁）..."
  if fail2ban-client reload; then
    ok "重载完成"
  else
    err "重载失败，请检查配置语法：fail2ban-client -t"
    return 1
  fi
}

# ---------- 4. 状态查看 ----------
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
}

# ---------- 5. 显示目录位置 ----------
do_dir() {
  section "Fail2ban 关键路径"
  kv "主配置目录"      "$F2B_CONF_DIR"
  kv "本地覆盖配置"    "$F2B_JAIL_LOCAL"
  kv "默认 jail 配置"  "$F2B_CONF_DIR/jail.conf"
  kv "过滤器目录"      "$F2B_CONF_DIR/filter.d/"
  kv "动作目录"        "$F2B_CONF_DIR/action.d/"
  kv "jail.d 目录"     "$F2B_CONF_DIR/jail.d/"
  kv "运行日志"        "$F2B_LOG"
  kv "SSH 认证日志"    "$AUTH_LOG"
  kv "systemd 服务"    "/lib/systemd/system/fail2ban.service"

  echo
  if [ -d "$F2B_CONF_DIR" ]; then
    info "配置目录内容："
    ls -lh "$F2B_CONF_DIR" 2>/dev/null
  else
    warn "$F2B_CONF_DIR 不存在（可能尚未安装）"
  fi
}

# ---------- 6. 查看日志 ----------
do_logs() {
  require_cmd tail
  if [ ! -f "$F2B_LOG" ]; then
    warn "$F2B_LOG 不存在，尝试查看 journald..."
    journalctl -u "$SERVICE" -n 50 --no-pager 2>/dev/null || err "无法读取日志"
    return 0
  fi
  info "实时跟踪 $F2B_LOG（Ctrl+C 退出）..."
  tail -f "$F2B_LOG"
}

# ---------- 7. 启用 / 禁用自启 ----------
do_enable() {
  need_root
  require_cmd systemctl
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
  need_root
  require_cmd systemctl
  if systemctl disable "$SERVICE" >/dev/null 2>&1; then
    ok "已取消开机自启"
  else
    warn "取消开机自启失败"
  fi
}

# ---------- 帮助 ----------
show_help() {
  cat <<'EOF'
Fail2ban 一键管理脚本（Debian / Ubuntu）

用法:
  sudo ./fail2ban-debian.sh <命令> [选项]

命令:
  install     安装并启动（可配 --port / --ignore-ip）
  uninstall   卸载
  restart     重启服务
  reload      重载配置（不中断封禁）
  status      查看服务状态与封禁列表
  dir         显示关键目录位置
  logs        实时跟踪日志
  enable      设置开机自启
  disable     取消开机自启
  menu        交互菜单（默认）
  help        显示本帮助

选项:
  --port <端口>           SSH 端口，默认 ssh（即 22）
  --ignore-ip "<IP列表>"  白名单，空格分隔，默认 "127.0.0.1/8 ::1"
  -y, --yes               跳过所有确认（适合自动化）

示例:
  sudo ./fail2ban-debian.sh install --port 2222 --ignore-ip "1.2.3.4/32"
  sudo ./fail2ban-debian.sh status
  sudo ./fail2ban-debian.sh uninstall --yes
EOF
}

# ---------- 交互菜单 ----------
show_menu() {
  printf '\n%s========== Fail2ban 管理菜单 (Debian) ==========%s\n' "$BOLD" "$NC"
  echo "  1) 安装并启动（可设置端口/白名单）"
  echo "  2) 卸载"
  echo "  3) 重启服务"
  echo "  4) 重载配置"
  echo "  5) 查看状态 / 封禁列表"
  echo "  6) 显示目录位置"
  echo "  7) 查看实时日志"
  echo "  8) 启用开机自启"
  echo "  9) 取消开机自启"
  echo "  0) 退出"
  printf '%s================================================%s\n' "$BOLD" "$NC"
}

do_menu() {
  local choice
  while true; do
    show_menu
    read -r -p "请输入选项 [0-9]: " choice || { echo; exit 0; }
    case "$choice" in
      1) SSH_PORT=""; IGNORE_IPS=""; do_install ;;
      2) do_uninstall ;;
      3) do_restart ;;
      4) do_reload ;;
      5) do_status ;;
      6) do_dir ;;
      7) do_logs ;;
      8) do_enable ;;
      9) do_disable ;;
      0) echo "再见"; exit 0 ;;
      *) warn "无效选项：$choice" ;;
    esac
    [ "$choice" != "7" ] && pause
  done
}

# ---------- 入口分发 ----------
CMD="${1:-menu}"
shift || true

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
    *)
      err "未知参数：$1（用 help 查看用法）"
      exit 1 ;;
  esac
done

case "$CMD" in
  install)   do_install ;;
  uninstall) do_uninstall ;;
  restart)   do_restart ;;
  reload)    do_reload ;;
  status)    do_status ;;
  dir)       do_dir ;;
  logs)      do_logs ;;
  enable)    do_enable ;;
  disable)   do_disable ;;
  menu)      do_menu ;;
  -h|--help|help) show_help ;;
  *)
    err "未知命令：$CMD"
    show_help
    exit 1 ;;
esac
