#!/usr/bin/env bash
# ==============================================================================
#  iptables-wizard  ·  Debian / Ubuntu 防火墙一键管理脚本   v1.2.0
# ------------------------------------------------------------------------------
#  功能：
#    1. 环境检测与安装（iptables / iptables-persistent / netfilter-persistent）
#    2. 服务控制：启动 / 停止 / 重启 / 重载 / 状态 / 开机自启
#    3. 规则查看：filter / nat / mangle 表，带行号、带流量统计、语法高亮
#    4. 规则设置：放行/拒绝 端口、IP、网段、ICMP、并发限速、SSH 防爆破
#    5. 策略管理：默认策略、五套常用预设（SSH / Web / 数据库 / Docker / 全放行）
#    6. 高级功能：端口转发 DNAT、SNAT 出网、IP 转发、丢包日志、自定义规则
#    7. 规则持久化：保存 / 备份 / 恢复 / 回滚，重启不丢失
#    8. 安全防护：SSH 防锁死检测、每次变更前自动备份、危险操作二次确认
#    9. 环境自检：doctor 子命令，逐项检查依赖与配置一致性
#
#  用法：
#    sudo ./iptables-wizard.sh                # 交互式菜单（默认）
#    sudo ./iptables-wizard.sh status         # 状态概览
#    sudo ./iptables-wizard.sh list [filter]  # 查看规则
#    sudo ./iptables-wizard.sh save           # 保存规则
#    sudo ./iptables-wizard.sh start|stop|restart|reload
#    sudo ./iptables-wizard.sh backup         # 备份当前规则
#    sudo ./iptables-wizard.sh restore <文件> # 从备份恢复
#    sudo ./iptables-wizard.sh doctor         # 环境自检
#    sudo ./iptables-wizard.sh install        # 安装依赖
#
#  说明：
#    · 所有 iptables 命令均带 -w 5（等待 xtables 锁），避免并发报错
#    · 修改类操作前自动备份，备份目录 /etc/iptables-wizard/backups
#    · 规则一律追加（-A），默认拒绝通过 -P DROP 实现，保证追加规则可命中
# ==============================================================================

set -o pipefail

readonly APP="iptables-wizard"
readonly VERSION="1.2.0"
readonly CONF_DIR="/etc/iptables-wizard"
readonly BACKUP_DIR="${CONF_DIR}/backups"
readonly RULES_V4="/etc/iptables/rules.v4"
readonly RULES_V6="/etc/iptables/rules.v6"
readonly LOG_FILE="/var/log/iptables-wizard.log"
readonly MAX_BACKUPS=30

# ------------------------------------------------------------------ 颜色定义 --
if { [[ -t 1 ]] || [[ -n ${FORCE_COLOR:-} ]]; } && [[ -z ${NO_COLOR:-} ]]; then
  C_RESET=$'\e[0m';  C_BOLD=$'\e[1m';   C_DIM=$'\e[2m'
  C_RED=$'\e[1;31m'; C_GREEN=$'\e[1;32m'; C_YELLOW=$'\e[1;33m'
  C_BLUE=$'\e[1;34m'; C_MAGENTA=$'\e[1;35m'; C_CYAN=$'\e[1;36m'
  C_WHITE=$'\e[1;37m'
else
  C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=
  C_BLUE=; C_MAGENTA=; C_CYAN=; C_WHITE=
fi

# Ctrl+C 中断时恢复终端属性，避免颜色残留
trap 'printf "%b\n" "${C_RESET}"; exit 130' INT TERM

# -------------------------------------------------------------- 基础输出函数 --
log() {
  [[ -w ${LOG_FILE} || -w $(dirname "${LOG_FILE}") ]] 2>/dev/null || return 0
  printf '%s [%s] %s\n' "$(date '+%F %T')" "${APP}" "$*" >>"${LOG_FILE}" 2>/dev/null || true
}

hr()   { printf '%b\n' "  ${C_DIM}────────────────────────────────────────────────────────────────${C_RESET}"; }
title(){ printf '\n%b\n' "${C_CYAN}${C_BOLD}▶ $*${C_RESET}"; }
sub()  { printf '%b\n' "${C_BLUE}  ┌─ $*${C_RESET}"; }
ok()   { printf '%b\n' "  ${C_GREEN}✔${C_RESET} $*"; }
warn() { printf '%b\n' "  ${C_YELLOW}⚠${C_RESET} $*"; }
err()  { printf '%b\n' "  ${C_RED}✘${C_RESET} $*"; }
info() { printf '%b\n' "  ${C_DIM}·${C_RESET} $*"; }

# 子菜单统一标题：蓝钻 + 白色标题 + 灰色副标题（替代原先各菜单手写的两行）
menu_header() {  # menu_header "标题" "副标题"
  banner
  printf '%b\n' "  ${C_BLUE}${C_BOLD}◆${C_RESET} ${C_WHITE}${C_BOLD}$1${C_RESET}   ${C_DIM}$2${C_RESET}"
}

# 分组标签行（主菜单分区用）
menu_group() { printf '%b\n' "  ${C_DIM}─ $* ──────────────────────────────────────${C_RESET}"; }
kv() {
  local pad
  dw_calc "$1"
  pad=$(( 14 - DW ))
  (( pad < 0 )) && pad=0
  printf '%b\n' "  ${C_DIM}$1${SPACES:0:pad}${C_RESET}  $2"
}

# 子菜单顶部统一状态栏：策略 / 规则数 / 保存状态
PB=""
badge_of() {   # 结果写入全局 PB，避免 $( ) 起子进程
  case "$1" in
    DROP)   PB="${C_RED}DROP${C_RESET}" ;;
    ACCEPT) PB="${C_GREEN}ACCEPT${C_RESET}" ;;
    *)      PB="${C_DIM}--${C_RESET}" ;;
  esac
}

policy_badge() { badge_of "$1"; printf '%b' "${PB}"; }

statusbar() {
  if ! have_iptables; then
    printf '%b\n' "  ${C_RED}● iptables 未安装${C_RESET} ${C_DIM}（请先执行【2 安装与检测】）${C_RESET}"
    return 0
  fi
  snapshot_state
  if (( ! ST_OK )); then
    printf '%b\n' "  ${C_RED}● 无法读取规则${C_RESET} ${C_DIM}（权限不足 / netfilter 不可用，可用 doctor 排查）${C_RESET}"
    return 0
  fi
  local in_b fw_b out_b saved svc
  badge_of "${ST_IN}";  in_b="${PB}"
  badge_of "${ST_FW}";  fw_b="${PB}"
  badge_of "${ST_OUT}"; out_b="${PB}"
  if has_unsaved; then
    saved="${C_YELLOW}● 未保存${C_RESET}"
  else
    saved="${C_GREEN}● 已保存${C_RESET}"
  fi
  svc=$(svc_state)
  printf '%b\n' "  ${C_DIM}策略${C_RESET} ${in_b} ${C_DIM}/${C_RESET} ${fw_b} ${C_DIM}/${C_RESET} ${out_b} ${C_DIM}│${C_RESET} 规则 ${C_BOLD}${ST_COUNT}${C_RESET} 条 ${C_DIM}│${C_RESET} ${saved} ${C_DIM}│${C_RESET} 服务 ${C_BOLD}${svc}${C_RESET}"
}

pause() {
  printf '\n%b' "${C_DIM}按回车键返回…${C_RESET}"
  IFS= read -r _ || true
}

confirm() {   # confirm "提示" [默认 y/n]
  local prompt="$1" def="${2:-n}" ans
  printf '%b' "  ${C_YELLOW}?${C_RESET} ${C_BOLD}${prompt}${C_RESET} [y/N]: "
  IFS= read -r ans || return 1
  [[ -z ${ans} ]] && ans="${def}"
  [[ ${ans} =~ ^[Yy]([Ee][Ss])?$ ]]
}

read_input() {  # read_input "提示" "默认值" 变量名
  local prompt="$1" def="$2" var="$3" input
  if [[ -n ${def} ]]; then
    printf '%b' "  ${C_BOLD}${prompt}${C_RESET} ${C_DIM}[${def}]${C_RESET}: "
  else
    printf '%b' "  ${C_BOLD}${prompt}${C_RESET}: "
  fi
  IFS= read -r input || { printf '\n'; return 1; }
  [[ -z ${input} ]] && input="${def}"
  printf -v "${var}" '%s' "${input}"
  return 0
}

# ---------------------------------------------------------------- 命令高亮 ---
# 按 token 着色：命令白色加粗 / 选项洋红 / 链名青色 / ACCEPT 绿 / DROP 红
#              / NAT 类目标黄色 / 协议蓝色 / 数值与地址黄色
render_cmd() {
  local a out="" sep="" c q
  for a in "$@"; do
    c=""
    case "${a}" in
      iptables|ip6tables|iptables-save|iptables-restore|ip6tables-save|ip6tables-restore|\
      systemctl|netfilter-persistent|sysctl|apt-get|modprobe|journalctl|ss|nc|timeout|install)
        c="${C_WHITE}${C_BOLD}" ;;
      --*|-[A-Za-z]*)                  c="${C_MAGENTA}" ;;
      INPUT|OUTPUT|FORWARD|PREROUTING|POSTROUTING|DOCKER-USER|filter|nat|mangle)
        c="${C_CYAN}" ;;
      ACCEPT)                          c="${C_GREEN}" ;;
      DROP|REJECT)                     c="${C_RED}" ;;
      DNAT|SNAT|MASQUERADE|REDIRECT|LOG) c="${C_YELLOW}" ;;
      tcp|udp|icmp|all)                c="${C_BLUE}" ;;
      *[0-9]*.[0-9]*|*[0-9]*/*|[0-9]*) c="${C_YELLOW}" ;;
      *)                               c="" ;;
    esac
    q="${a}"
    [[ -z ${a} || ${a} =~ [[:space:]] ]] && q="\"${a}\""
    if [[ -n ${c} ]]; then
      out+="${sep}${c}${q}${C_RESET}"
    else
      out+="${sep}${q}"
    fi
    sep=" "
  done
  printf '%s' "${out}"
}

# 对一段命令字符串着色（用于 eval 场景，无法拆成数组）
render_str() {
  local s="$1"
  s=$(printf '%s' "${s}" | sed -E \
      -e "s/\b(iptables-restore|iptables-save|ip6tables-restore|ip6tables-save|iptables|ip6tables)\b/${C_WHITE}${C_BOLD}\1${C_RESET}/g" \
      -e "s/\b(PREROUTING|POSTROUTING|DOCKER-USER|INPUT|OUTPUT|FORWARD)\b/${C_CYAN}\1${C_RESET}/g" \
      -e "s/\b(ACCEPT)\b/${C_GREEN}\1${C_RESET}/g" \
      -e "s/\b(DROP|REJECT)\b/${C_RED}\1${C_RESET}/g" \
      -e "s/\b(DNAT|SNAT|MASQUERADE|LOG|REDIRECT)\b/${C_YELLOW}\1${C_RESET}/g" \
      -e "s/(^|[[:space:]])(--?[A-Za-z][A-Za-z-]*)/\1${C_MAGENTA}\2${C_RESET}/g" \
      -e "s/(^|[[:space:]])([0-9]{1,3}(\\.[0-9]{1,3}){3}(\\/[0-9]{1,2})?)/\1${C_YELLOW}\2${C_RESET}/g")
  printf '%s' "${s}"
}

# 高亮显示并执行一条命令
run_cmd() {
  printf '  %b ' "${C_DIM}»${C_RESET}"
  render_cmd "$@"
  printf '\n'
  local out st
  out=$("$@" 2>&1); st=$?
  if (( st == 0 )); then
    [[ -n ${out} ]] && printf '%b\n' "  ${C_GREEN}${out}${C_RESET}"
    log "OK: $*"
    return 0
  fi
  printf '%b\n' "  ${C_RED}${out:-命令执行失败}${C_RESET}"
  log "FAIL(${st}): $* -> ${out}"
  return "${st}"
}

# 高亮显示并 eval 执行（用于含引号/注释的规则串）
run_eval() {
  printf '  %b ' "${C_DIM}»${C_RESET}"
  render_str "$*"
  printf '\n'
  local out st
  out=$(eval "$*" 2>&1); st=$?
  if (( st == 0 )); then
    [[ -n ${out} ]] && printf '%b\n' "  ${C_GREEN}${out}${C_RESET}"
    log "OK: $*"
    return 0
  fi
  printf '%b\n' "  ${C_RED}${out:-命令执行失败}${C_RESET}"
  log "FAIL(${st}): $* -> ${out}"
  return "${st}"
}

# 危险操作警示框（上下边框按显示宽度对齐：顶部前缀 15 列，底部前缀 2 列）
danger_box() {
  local l
  printf '%b\n' "  ${C_RED}${C_BOLD}┌ ⚠ 危险操作 ───────────────────────────${C_RESET}"
  while IFS= read -r l; do
    [[ -n ${l} ]] && printf '%b\n' "  ${C_RED}${C_BOLD}│${C_RESET} ${C_RED}${l}${C_RESET}"
  done <<< "$1"
  printf '%b\n' "  ${C_RED}${C_BOLD}└────────────────────────────────────────${C_RESET}"
}

# ------------------------------------------------------------ 运行环境与依赖 --
require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    printf '%b\n' "${C_RED}✘ 需要 root 权限运行，请使用：sudo $0${C_RESET}"
    exit 1
  fi
}

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# 读取发行版名称（不 source 外部文件，避免执行未知代码，也避免 SC1091）
os_pretty_name() {
  if [[ -r /etc/os-release ]]; then
    local n
    n=$(sed -n 's/^PRETTY_NAME=["]\{0,1\}\([^"]*\)["]\{0,1\}$/\1/p' /etc/os-release 2>/dev/null | head -n 1)
    printf '%s' "${n:-未知}"
  elif [[ -r /etc/issue ]]; then
    head -n 1 /etc/issue 2>/dev/null | sed 's/[[:space:]]*\\[nlr].*$//'
  else
    printf '未知'
  fi
}

# 计算字符串显示宽度（中日韩字符按 2 列计），用于中英混排对齐。
# 实现说明：UTF-8 下 CJK 字符占 3 字节、显示 2 列，ASCII 占 1 字节 1 列，
# 因此 列宽 = 字符数 + (字节数 - 字符数) / 2。
# 全部用内建展开计算，不 fork 子进程（旧实现每字符 fork 一次 printf，是性能瓶颈）。
DW=0                      # dw_calc 的输出（全局，避免用 $(...) 起子进程）
SPACES='                                                                                '

dw_calc() {               # 结果写入全局 DW，不 fork
  local s="$1" chars bytes
  chars=${#s}
  local LC_ALL=C          # 局部切到 C locale，使 ${#s} 返回字节数
  bytes=${#s}
  DW=$(( chars + (bytes - chars) / 2 ))
}

disp_width() { dw_calc "$1"; printf '%s' "${DW}"; }

# 右侧补空格到指定显示宽度
pad_right() {
  local s="$1" target="$2" pad
  dw_calc "${s}"
  pad=$(( target - DW ))
  if (( pad > 0 )); then
    printf '%s%*s' "${s}" "${pad}" ''
  else
    printf '%s' "${s}"
  fi
}

# 两列菜单行，自动对齐
menu_row() {
  local pad
  dw_calc "$2"
  pad=$(( 22 - DW ))
  (( pad < 0 )) && pad=0
  printf '  %b%s%b) %s%s  %b%s%b) %s\n' \
    "${C_CYAN}${C_BOLD}" "$1" "${C_RESET}" "$2" "${SPACES:0:pad}" \
    "${C_CYAN}${C_BOLD}" "$3" "${C_RESET}" "$4"
}

# 修改规则前的统一前置检查
guard_iptables() {
  if have_iptables; then return 0; fi
  err "iptables 不可用，无法执行此操作"
  info "请先进入主菜单【2 安装与检测】安装 iptables"
  return 1
}

init_dirs() {
  local d
  for d in "${CONF_DIR}" "${BACKUP_DIR}"; do
    [[ -d ${d} ]] || mkdir -p "${d}" 2>/dev/null
    chmod 700 "${d}" 2>/dev/null || true
  done
}

IPT=(iptables)
IPT6=(ip6tables)
detect_wait_support() {
  if iptables -w 1 -L -n >/dev/null 2>&1; then
    IPT=(iptables -w 5)
    IPT6=(ip6tables -w 5)
  fi
}

# 探测结果缓存：菜单每次重绘都会调用，避免反复 fork（1=可用 0=不可用 空=未探测）
_IPT_OK=""
_IPV6_OK=""
_SVC_EXISTS=""

reset_probe_cache() { _IPT_OK=""; _IPV6_OK=""; _SVC_EXISTS=""; }

have_iptables() {
  if [[ -z ${_IPT_OK} ]]; then
    if cmd_exists iptables && iptables -L -n >/dev/null 2>&1; then
      _IPT_OK=1
    else
      _IPT_OK=0
    fi
  fi
  [[ ${_IPT_OK} == 1 ]]
}

ipv6_ready() {
  if [[ -z ${_IPV6_OK} ]]; then
    if cmd_exists ip6tables && ip6tables -L -n >/dev/null 2>&1; then
      _IPV6_OK=1
    else
      _IPV6_OK=0
    fi
  fi
  [[ ${_IPV6_OK} == 1 ]]
}

backend_name() {
  local v
  v=$(iptables --version 2>/dev/null)
  if [[ ${v} == *nf_tables* ]]; then
    printf 'nft (iptables-nft 兼容层)'
  elif [[ -n ${v} ]]; then
    printf 'legacy (xtables-legacy)'
  else
    printf '未知'
  fi
}

svc_exists() {
  if [[ -z ${_SVC_EXISTS} ]]; then
    if cmd_exists systemctl && systemctl list-unit-files 2>/dev/null | grep -qE '^netfilter-persistent\.service'; then
      _SVC_EXISTS=1
    else
      _SVC_EXISTS=0
    fi
  fi
  [[ ${_SVC_EXISTS} == 1 ]]
}

svc_state() {
  if svc_exists; then
    local s
    s=$(systemctl is-active netfilter-persistent 2>/dev/null)
    printf '%s' "${s:-unknown}"
  elif have_iptables; then
    printf 'standalone'
  else
    printf 'not-installed'
  fi
}

svc_enabled() {
  svc_exists && systemctl is-enabled netfilter-persistent 2>/dev/null | grep -q '^enabled$'
}

# ------------------------------------------------------------------ 持久化 ---
save_rules() {
  local quiet="${1:-}"
  [[ ${quiet} == quiet ]] || title "保存规则到磁盘"
  mkdir -p /etc/iptables 2>/dev/null

  if svc_exists && cmd_exists netfilter-persistent; then
    # 只调用一次：既展示命令又拿到真实退出码，失败时提示但不阻断（后面还有 iptables-save 兜底）
    if [[ ${quiet} == quiet ]]; then
      netfilter-persistent save >/dev/null 2>&1 || warn "netfilter-persistent save 失败，将仅使用 iptables-save 写入"
    else
      run_cmd netfilter-persistent save || warn "netfilter-persistent save 失败，将仅使用 iptables-save 写入"
    fi
  fi

  local tmp
  tmp=$(mktemp) || return 1
  if ! iptables-save >"${tmp}" 2>/dev/null; then
    err "iptables-save 执行失败"
    rm -f "${tmp}"
    return 1
  fi
  # 防御：输出不像合法的规则文件时拒绝覆盖，避免写出空配置导致重启后无防护
  if ! grep -q '^\*filter' "${tmp}" 2>/dev/null; then
    err "iptables-save 输出异常（缺少 *filter 表），已放弃写入，原配置保持不变"
    rm -f "${tmp}"
    return 1
  fi
  install -m 0640 -o root -g root "${tmp}" "${RULES_V4}" 2>/dev/null || cp -f "${tmp}" "${RULES_V4}"
  rm -f "${tmp}"

  if cmd_exists ip6tables-save && ip6tables-save >/dev/null 2>&1; then
    local t6; t6=$(mktemp)
    ip6tables-save >"${t6}" 2>/dev/null && \
      { install -m 0640 -o root -g root "${t6}" "${RULES_V6}" 2>/dev/null || cp -f "${t6}" "${RULES_V6}"; }
    rm -f "${t6}"
  fi

  [[ ${quiet} == quiet ]] || ok "已写入 ${RULES_V4}（重启后自动生效）"
  log "save rules -> ${RULES_V4}"
  return 0
}

load_rules() {  # 从磁盘恢复
  if [[ ! -s ${RULES_V4} ]]; then
    err "未找到 ${RULES_V4}（或文件为空），请先保存规则"
    return 1
  fi
  run_eval "iptables-restore < '${RULES_V4}'" || return 1
  if [[ -s ${RULES_V6} ]] && cmd_exists ip6tables-restore; then
    run_eval "ip6tables-restore < '${RULES_V6}'" >/dev/null 2>&1 || true
  fi
  return 0
}

# 备份文件名由本脚本生成（rules-YYYYmmdd-HHMMSS.v4），不含空格与换行，
# 因此按修改时间倒序列出是安全的（shellcheck 对 ls 的通用告警在此不适用）。
# shellcheck disable=SC2012
list_backup_files() { ls -1t "${BACKUP_DIR}"/rules-*.v4 2>/dev/null; }

backup_rules() {  # 返回备份文件路径到 stdout
  init_dirs
  local f ts cnt
  ts=$(date +%Y%m%d-%H%M%S)
  f="${BACKUP_DIR}/rules-${ts}.v4"
  if iptables-save >"${f}" 2>/dev/null; then
    chmod 600 "${f}" 2>/dev/null
    cnt=$(list_backup_files | wc -l)
    if (( cnt > MAX_BACKUPS )); then
      list_backup_files | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm -f
    fi
    printf '%s' "${f}"
    return 0
  fi
  return 1
}

auto_backup() {  # 变更前静默备份
  local f
  if f=$(backup_rules); then
    info "已自动备份当前规则 → ${C_DIM}${f}${C_RESET}"
  else
    warn "自动备份失败（继续执行）"
  fi
}

has_unsaved() {  # 0 = 有未保存变更
  have_iptables || return 1
  [[ -f ${RULES_V4} ]] || return 0
  local cur saved
  cur=$(iptables-save 2>/dev/null | grep -v '^#' | md5sum | awk '{print $1}')
  saved=$(grep -v '^#' "${RULES_V4}" 2>/dev/null | md5sum | awk '{print $1}')
  [[ ${cur} != "${saved}" ]]
}

# ------------------------------------------------------------------ 状态信息 --
ssh_ports() {
  local ports=""
  if cmd_exists sshd && sshd -T >/dev/null 2>&1; then
    ports=$(sshd -T 2>/dev/null | awk '/^port /{print $2}' | sort -un | tr '\n' ' ')
  fi
  if [[ -z ${ports} && -f /etc/ssh/sshd_config ]]; then
    ports=$(awk 'tolower($1)=="port"{print $2}' /etc/ssh/sshd_config 2>/dev/null | sort -un | tr '\n' ' ')
  fi
  if [[ -z ${ports} ]]; then
    ports=$(ss -tlnp 2>/dev/null | awk '/sshd/{print $4}' | sed 's/.*://' | sort -un | tr '\n' ' ')
  fi
  [[ -z ${ports} ]] && ports="22"
  printf '%s' "${ports% }"
}

policy_of() {
  "${IPT[@]}" -S "$1" 2>/dev/null | head -1 | awk '{print $3}'
}

# 一次 iptables -S 取回三条链策略与规则总数（菜单重绘热路径，避免 4 次 fork）
# ST_OK=1 表示本次快照成功；失败时 ST_* 保持空值，展示层需显式提示而非显示成 "规则  条"
ST_IN=""; ST_FW=""; ST_OUT=""; ST_COUNT="0"; ST_OK=0
snapshot_state() {
  ST_IN=""; ST_FW=""; ST_OUT=""; ST_COUNT="0"; ST_OK=0
  have_iptables || return 1
  local out line
  out=$("${IPT[@]}" -S 2>/dev/null) || return 1
  [[ -n ${out} ]] || return 1
  ST_COUNT=0
  while IFS= read -r line; do
    case "${line}" in
      "-P INPUT "*)   ST_IN="${line##* }" ;;
      "-P FORWARD "*) ST_FW="${line##* }" ;;
      "-P OUTPUT "*)  ST_OUT="${line##* }" ;;
      "-A "*)         ST_COUNT=$((ST_COUNT + 1)) ;;
      *) : ;;         # 其他行（自定义链等）不影响统计
    esac
  done <<<"${out}"
  ST_OK=1
  return 0
}

rule_count() {
  "${IPT[@]}" -S 2>/dev/null | grep -c '^-A ' || true
}

# SSH 防锁死：确保当前 SSH 端口在 INPUT 中已放行
ensure_ssh_allowed() {
  local p
  for p in $(ssh_ports); do
    if "${IPT[@]}" -C INPUT -p tcp --dport "${p}" -j ACCEPT >/dev/null 2>&1; then
      info "SSH 端口 ${p}/tcp 已放行"
    else
      warn "检测到 SSH 端口 ${p}/tcp 未放行，正在自动添加放行规则（防止把自己锁在门外）"
      "${IPT[@]}" -A INPUT -p tcp --dport "${p}" -j ACCEPT
    fi
  done
}

# ------------------------------------------------------------ 规则着色显示 ---
colorize_rules() {
  awk -v R="${C_RED}" -v G="${C_GREEN}" -v Y="${C_YELLOW}" \
      -v C="${C_CYAN}" -v B="${C_BOLD}" -v M="${C_MAGENTA}" \
      -v D="${C_DIM}" -v N="${C_RESET}" '
    {
      line = $0
      # 1) Chain 行：青色加粗，policy 按放行/拒绝着色
      if (line ~ /^Chain /) {
        if (line ~ /policy (DROP|REJECT)/)  { gsub(/(DROP|REJECT)/, R "&" N, line) }
        else if (line ~ /policy ACCEPT/)    { gsub(/ACCEPT/, G "&" N, line) }
        printf "%s%s%s\n", B C, line, N
        next
      }
      # 2) 列标题
      if (line ~ /^(num|pkts)[ \t]/) { printf "%s%s%s\n", Y, line, N; next }
      # 3) 目标列
      if (line ~ /(^|[ \t])(DROP|REJECT)([ \t]|$)/) { gsub(/(DROP|REJECT)/, R "&" N, line) }
      else if (line ~ /ACCEPT/)                     { gsub(/ACCEPT/, G "&" N, line) }
      # 4) 端口 / 协议细节
      gsub(/dpts?:[0-9,:]+/, Y "&" N, line)
      gsub(/spts?:[0-9,:]+/, Y "&" N, line)
      gsub(/icmp/, M "&" N, line)
      printf "%s\n", line
    }'
}

show_rules() {
  local table="${1:-filter}" desc
  case "${table}" in
    filter) desc="包过滤表：决定每个数据包放行还是丢弃（最常用）" ;;
    nat)    desc="地址转换表：端口转发 DNAT、出网共享 SNAT / MASQUERADE" ;;
    mangle) desc="标记表：修改 TOS / TTL / MARK，特殊场景才用" ;;
    *)      desc="规则表" ;;
  esac

  title "规则表：${table}"
  if ! guard_iptables; then return 1; fi
  printf '%b\n' "  ${C_DIM}${desc}${C_RESET}"
  printf '%b\n' "  ${C_DIM}图例：${C_RESET}${C_GREEN}ACCEPT${C_RESET}${C_DIM}=放行${C_RESET}  ${C_RED}DROP/REJECT${C_RESET}${C_DIM}=丢弃${C_RESET}  ${C_YELLOW}黄色${C_RESET}${C_DIM}=端口${C_RESET}  ${C_DIM}pkts/bytes=命中包数/字节${C_RESET}"
  printf '\n'
  "${IPT[@]}" -t "${table}" -L -n -v --line-numbers 2>&1 | colorize_rules
  printf '\n'
  printf '%b\n' "  ${C_DIM}共 ${C_BOLD}$(rule_count)${C_RESET}${C_DIM} 条规则；修改后需【保存】才能在重启后保留${C_RESET}"
}

# ==============================================================================
#                                  安装 / 检测
# ==============================================================================
do_install() {
  title "环境检测与安装"
  kv "发行版" "$(os_pretty_name)"
  kv "内核"   "$(uname -r)"

  if have_iptables; then
    ok "iptables 已安装：$(iptables --version 2>/dev/null)"
    kv "后端" "$(backend_name)"
  else
    warn "iptables 未安装，准备安装…"
    if ! confirm "是否现在执行 apt-get 安装 iptables？" y; then return 0; fi
    run_cmd apt-get update
    DEBIAN_FRONTEND=noninteractive run_cmd apt-get install -y iptables
  fi

  if ! cmd_exists netfilter-persistent; then
    warn "netfilter-persistent（规则持久化）未安装"
    if confirm "是否安装 iptables-persistent 以实现开机自动加载规则？" y; then
      DEBIAN_FRONTEND=noninteractive run_cmd apt-get install -y iptables-persistent netfilter-persistent
    fi
  else
    ok "netfilter-persistent 已安装：$(command -v netfilter-persistent)"
  fi

  # 内核模块检查
  local m
  for m in ip_tables nf_conntrack iptable_filter iptable_nat; do
    if [[ -d /sys/module/${m} ]] || modprobe -n "${m}" >/dev/null 2>&1; then
      info "内核模块 ${m} 可用"
    else
      warn "内核模块 ${m} 不可用（部分功能可能受限）"
    fi
  done

  init_dirs
  if svc_exists; then
    if ! svc_enabled; then
      if confirm "是否设置 netfilter-persistent 开机自启？" y; then
        run_cmd systemctl enable netfilter-persistent
      fi
    else
      ok "netfilter-persistent 已设置为开机自启"
    fi
  fi

  reset_probe_cache
  printf '\n'
  ok "环境准备完成"
  log "install/env check done"
}

# ==============================================================================
#                                  服务控制
# ==============================================================================
svc_start() {
  title "启动防火墙（加载已保存规则）"
  guard_iptables || return 1
  if [[ ! -s ${RULES_V4} ]]; then
    warn "${RULES_V4} 不存在或为空，没有可加载的规则"
    info "请先添加规则并【保存】，或到【策略与预设】应用一套预设"
    return 1
  fi
  auto_backup
  if svc_exists; then
    run_cmd systemctl start netfilter-persistent && ok "netfilter-persistent 已启动"
  else
    load_rules && ok "已从 ${RULES_V4} 加载规则（无 systemd 服务，使用 iptables-restore）"
  fi
}

svc_stop() {
  title "停止防火墙（清空规则，放行全部流量）"
  guard_iptables || return 1
  danger_box "将清空 filter / nat / mangle 全部规则
并把 INPUT / FORWARD / OUTPUT 策略全部改为 ACCEPT
服务器将处于完全放行状态，公网可直接访问所有端口"
  if ! confirm "确认停止并清空防火墙？" n; then info "已取消"; return 0; fi
  auto_backup
  svc_exists && systemctl stop netfilter-persistent >/dev/null 2>&1

  local c t
  for c in INPUT FORWARD OUTPUT; do "${IPT[@]}" -P "${c}" ACCEPT; done
  for t in filter nat mangle; do
    "${IPT[@]}" -t "${t}" -F 2>/dev/null
    "${IPT[@]}" -t "${t}" -X 2>/dev/null
  done
  # 同步处理 IPv6，避免 v4 放行而 v6 仍拦截
  if ipv6_ready; then
    for c in INPUT FORWARD OUTPUT; do "${IPT6[@]}" -P "${c}" ACCEPT 2>/dev/null; done
    for t in filter nat mangle; do "${IPT6[@]}" -t "${t}" -F 2>/dev/null; done
    info "IPv6 规则已同步清空"
  fi
  ok "防火墙已停止，所有规则已清空（策略：ACCEPT / ACCEPT / ACCEPT）"
  warn "注意：未保存。重启后仍会加载 ${RULES_V4} 中的旧规则"
  log "firewall stopped & flushed"
}

svc_restart() {
  title "重启防火墙"
  guard_iptables || return 1
  auto_backup
  if svc_exists; then
    run_cmd systemctl restart netfilter-persistent && ok "服务已重启"
  else
    load_rules && ok "已重新加载规则"
  fi
}

svc_reload() {
  title "重载配置（不中断现有连接）"
  guard_iptables || return 1
  if svc_exists && cmd_exists netfilter-persistent; then
    run_cmd netfilter-persistent reload && ok "规则已重载"
  else
    load_rules && ok "规则已重载"
  fi
}

svc_status() {
  title "服务状态"
  local state
  state=$(svc_state)
  kv "服务单元" "$(svc_exists && echo 'netfilter-persistent' || echo '未安装（使用 iptables-restore 兜底）')"
  case "${state}" in
    active)        kv "运行状态" "${C_GREEN}active（已加载规则）${C_RESET}" ;;
    standalone)    kv "运行状态" "${C_GREEN}standalone（无 systemd 服务，规则在内存中）${C_RESET}" ;;
    not-installed) kv "运行状态" "${C_RED}iptables 未安装${C_RESET}" ;;
    *)             kv "运行状态" "${C_YELLOW}${state}${C_RESET}" ;;
  esac
  kv "开机自启" "$(svc_enabled && echo -e "${C_GREEN}enabled${C_RESET}" || echo -e "${C_YELLOW}disabled${C_RESET}")"
  kv "持久化文件" "$([[ -s ${RULES_V4} ]] && echo "${RULES_V4}（$(grep -c '^-A ' "${RULES_V4}" 2>/dev/null || true) 条）" || echo '不存在')"
  if svc_exists; then
    printf '\n'
    systemctl status netfilter-persistent --no-pager -l 2>&1 | head -n 15 || true
  fi
}

svc_enable() {
  title "设置开机自启"
  if ! svc_exists; then err "netfilter-persistent 服务未安装"; return 1; fi
  run_cmd systemctl enable netfilter-persistent
}

svc_disable() {
  title "取消开机自启"
  if ! svc_exists; then err "netfilter-persistent 服务未安装"; return 1; fi
  run_cmd systemctl disable netfilter-persistent
}

menu_service() {
  while true; do
    menu_header "服务控制" "启动 / 停止 / 重启 / 重载"
    statusbar
    hr
    printf '%b\n' \
      "  ${C_GREEN}1${C_RESET}) 启动（加载已保存规则）" \
      "  ${C_RED}2${C_RESET}) 停止（清空规则，放行全部）" \
      "  ${C_YELLOW}3${C_RESET}) 重启" \
      "  ${C_CYAN}4${C_RESET}) 重载（reload）" \
      "  ${C_BLUE}5${C_RESET}) 查看服务状态" \
      "  ${C_GREEN}6${C_RESET}) 设置开机自启" \
      "  ${C_RED}7${C_RESET}) 取消开机自启" \
      "  ${C_DIM}0${C_RESET}) 返回主菜单"
    hr
    printf '%b' "  ${C_BOLD}请选择${C_RESET} > "
    local c; IFS= read -r c || return 0
    case "${c}" in
      1) svc_start;   pause ;;
      2) svc_stop;    pause ;;
      3) svc_restart; pause ;;
      4) svc_reload;  pause ;;
      5) svc_status;  pause ;;
      6) svc_enable;  pause ;;
      7) svc_disable; pause ;;
      0|"") return 0 ;;
      *) err "无效选项"; sleep 1 ;;
    esac
  done
}

# ==============================================================================
#                                  查看规则
# ==============================================================================
menu_view() {
  while true; do
    menu_header "查看规则" "按表查看，带行号与命中流量"
    statusbar
    hr
    printf '%b\n' \
      "  ${C_GREEN}1${C_RESET}) filter 表（默认过滤规则，最常用）" \
      "  ${C_GREEN}2${C_RESET}) nat 表（端口转发 / SNAT / DNAT）" \
      "  ${C_GREEN}3${C_RESET}) mangle 表（特殊标记）" \
      "  ${C_GREEN}4${C_RESET}) 全部表一览" \
      "  ${C_GREEN}5${C_RESET}) 规则命令格式（iptables -S，可直接复制）" \
      "  ${C_GREEN}6${C_RESET}) 当前监听端口（ss -tulnp）" \
      "  ${C_GREEN}7${C_RESET}) 防火墙日志（内核丢包记录）" \
      "  ${C_DIM}0${C_RESET}) 返回主菜单"
    hr
    printf '%b' "  ${C_BOLD}请选择${C_RESET} > "
    local c; IFS= read -r c || return 0
    case "${c}" in
      1) show_rules filter; pause ;;
      2) show_rules nat;    pause ;;
      3) show_rules mangle; pause ;;
      4) for t in filter nat mangle; do show_rules "$t"; echo; done; pause ;;
      5)
        title "规则命令格式（可直接复制到其他机器）"
        "${IPT[@]}" -S 2>&1 | colorize_rules
        pause ;;
      6)
        title "当前监听端口"
        ss -tulnp 2>/dev/null | colorize_rules || netstat -tulnp 2>/dev/null
        pause ;;
      7)
        title "防火墙日志（最近 40 条）"
        if cmd_exists journalctl; then
          journalctl -k --no-pager -n 40 2>/dev/null | grep -iE 'iptables|drop|IN=|OUT=' | tail -n 40
        else
          dmesg 2>/dev/null | grep -iE 'iptables|drop' | tail -n 40
        fi
        pause ;;
      0|"") return 0 ;;
      *) err "无效选项"; sleep 1 ;;
    esac
  done
}

# ==============================================================================
#                                  添加规则
# ==============================================================================
valid_port_spec() {
  local spec="${1//-/:}" part n m
  [[ -n ${spec} ]] || return 1
  [[ ${spec} =~ ^[0-9]+([:,][0-9]+)*$ ]] || return 1
  for part in ${spec//,/ }; do
    n="${part%%:*}"
    [[ ${n} =~ ^[0-9]+$ ]] || return 1
    (( 10#${n} >= 1 && 10#${n} <= 65535 )) || return 1
    if [[ ${part} == *:* ]]; then
      m="${part##*:}"
      [[ ${m} =~ ^[0-9]+$ ]] || return 1
      (( 10#${m} >= 10#${n} && 10#${m} <= 65535 )) || return 1
    fi
  done
  return 0
}

valid_ip_spec() {
  local ip="$1" addr prefix o
  [[ -z ${ip} ]] && return 1
  addr="${ip%%/*}"
  prefix=""
  [[ ${ip} == */* ]] && prefix="${ip##*/}"

  [[ ${addr} =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  local IFS='.'
  for o in ${addr}; do
    [[ ${o} =~ ^[0-9]+$ ]] || return 1
    (( 10#${o} >= 0 && 10#${o} <= 255 )) || return 1
  done
  unset IFS

  if [[ -n ${prefix} ]]; then
    [[ ${prefix} =~ ^[0-9]{1,2}$ ]] || return 1
    (( 10#${prefix} >= 0 && 10#${prefix} <= 32 )) || return 1
  fi
  return 0
}

# 判断端口规格（80 / 80,443 / 8000:8100）是否覆盖某个端口
port_spec_covers() {
  local spec="${1//-/:}" target="$2" part lo hi
  for part in ${spec//,/ }; do
    if [[ ${part} == *:* ]]; then
      lo="${part%%:*}"
      hi="${part##*:}"
      (( 10#${target} >= 10#${lo} && 10#${target} <= 10#${hi} )) && return 0
    elif [[ ${part} == "${target}" ]]; then
      return 0
    fi
  done
  return 1
}

# 当前 SSH 客户端 IP（非 SSH 登录时为空）
ssh_client_ip() {
  local conn="${SSH_CONNECTION:-}"
  [[ -n ${conn} ]] && printf '%s' "${conn%% *}"
}

# 带重试的端口输入（自动把 80-90 规范成 80:90）
ask_port() {   # ask_port 变量名 "提示" [默认值]
  local var="$1" prompt="$2" def="${3:-}" v tries=0
  while (( tries < 3 )); do
    read_input "${prompt}" "${def}" v || return 1
    v="${v// /}"
    v="${v//-/:}"
    if valid_port_spec "${v}"; then
      printf -v "${var}" '%s' "${v}"
      return 0
    fi
    err "端口格式不合法：${v:-（空）}　正确示例 → 80 ／ 8000:8100 ／ 80,443"
    tries=$((tries + 1))
  done
  err "连续 3 次输入有误，已返回"
  return 1
}

# 带重试的地址输入
ask_ip() {     # ask_ip 变量名 "提示" [默认值]
  local var="$1" prompt="$2" def="${3:-}" v tries=0
  while (( tries < 3 )); do
    read_input "${prompt}" "${def}" v || return 1
    v="${v// /}"
    if valid_ip_spec "${v}"; then
      printf -v "${var}" '%s' "${v}"
      return 0
    fi
    err "地址格式不合法：${v:-（空）}　正确示例 → 1.2.3.4 ／ 10.0.0.0/8"
    tries=$((tries + 1))
  done
  err "连续 3 次输入有误，已返回"
  return 1
}

# 通用：构建并执行端口规则
apply_port_rule() {
  local proto="$1" ports="$2" src="$3" action="$4" comment="$5"
  local -a base=("${IPT[@]}" -A INPUT -p "${proto}")
  [[ ${src} != "0.0.0.0/0" && -n ${src} ]] && base+=(-s "${src}")
  if [[ ${ports} == *,* ]]; then
    base+=(-m multiport --dports "${ports}")
  else
    base+=(--dport "${ports}")
  fi
  [[ -n ${comment} ]] && base+=(-m comment --comment "${comment}")
  base+=(-j "${action}")
  run_cmd "${base[@]}"
}

menu_add() {
  while true; do
    menu_header "添加规则" "新规则追加到链尾，按添加顺序生效"
    statusbar
    hr
    printf '%b\n' \
      "  ${C_GREEN}1${C_RESET}) 放行端口（ACCEPT）" \
      "  ${C_RED}2${C_RESET}) 拒绝端口（DROP / REJECT）" \
      "  ${C_GREEN}3${C_RESET}) 放行 IP / 网段" \
      "  ${C_RED}4${C_RESET}) 封禁 IP / 网段" \
      "  ${C_GREEN}5${C_RESET}) 放行 ICMP（ping）" \
      "  ${C_RED}6${C_RESET}) 禁止 ICMP（禁 ping）" \
      "  ${C_GREEN}7${C_RESET}) 放行已建立连接（ESTABLISHED,RELATED）" \
      "  ${C_GREEN}8${C_RESET}) 放行回环网卡（lo）" \
      "  ${C_YELLOW}9${C_RESET}) SSH 防爆破（recent 模块限速）" \
      "  ${C_YELLOW}10${C_RESET}) 自定义规则（直接输入 iptables 参数）"
    hr
    printf '%b' "  ${C_BOLD}请选择${C_RESET} > "
    local c; IFS= read -r c || return 0
    case "${c}" in
      1|2) add_port_menu "${c}" ;;
      3|4) add_ip_menu "${c}" ;;
      5)  add_icmp_allow ;;
      6)  add_icmp_deny ;;
      7)  add_established ;;
      8)  add_loopback ;;
      9)  add_ssh_bruteforce ;;
      10) add_custom ;;
      0|"") return 0 ;;
      *) err "无效选项"; sleep 1 ;;
    esac
    pause
  done
}

add_port_menu() {
  local mode="$1" proto ports src action comment applied
  title "$([[ ${mode} == 1 ]] && echo '放行端口' || echo '拒绝端口')"
  guard_iptables || return 1
  printf '%b\n' "  ${C_DIM}提示：直接回车即使用方括号内的默认值；输错会立即提示并允许重填${C_RESET}\n"

  read_input "协议 [tcp / udp / both]" "tcp" proto || return 0
  proto=${proto,,}
  if [[ ${proto} != tcp && ${proto} != udp && ${proto} != both ]]; then
    err "协议只能是 tcp / udp / both"; return 1
  fi

  ask_port ports "端口（例 80 ／ 8000:8100 ／ 80,443）" || return 1
  ask_ip   src   "来源地址（留空 = 任意）" "0.0.0.0/0" || return 1

  if [[ ${mode} == 1 ]]; then
    read_input "动作 [ACCEPT / REJECT]" "ACCEPT" action || return 0
  else
    read_input "动作 [DROP / REJECT]" "DROP" action || return 0
  fi
  action=${action^^}
  if [[ ${action} != ACCEPT && ${action} != DROP && ${action} != REJECT ]]; then
    err "动作只能是 ACCEPT / DROP / REJECT"; return 1
  fi

  # 安全防护：拒绝所有来源的 SSH 端口会立刻断开当前连接
  if [[ ${action} != ACCEPT && ${src} == "0.0.0.0/0" ]]; then
    local sp
    for sp in $(ssh_ports); do
      if port_spec_covers "${ports}" "${sp}"; then
        danger_box "你正在拒绝【所有来源】对 ${ports} 端口的访问
其中包含当前 SSH 端口 ${sp}/tcp，执行后远程连接会立即断开
如只想限制 SSH 来源，请把「来源地址」改成具体网段"
        if ! confirm "仍然要继续？" n; then info "已取消"; return 0; fi
        break
      fi
    done
  fi

  read_input "备注（可选，便于日后识别）" "" comment || return 0

  echo
  sub "即将执行"
  if [[ ${proto} == both ]]; then
    apply_port_rule tcp "${ports}" "${src}" "${action}" "${comment}"
    apply_port_rule udp "${ports}" "${src}" "${action}" "${comment}"
    applied="tcp + udp"
  else
    apply_port_rule "${proto}" "${ports}" "${src}" "${action}" "${comment}"
    applied="${proto}"
  fi

  echo
  if [[ ${action} == ACCEPT ]]; then
    ok "已放行 ${applied} 端口 ${ports}（来源 ${src}）"
  else
    ok "已拒绝 ${applied} 端口 ${ports}（来源 ${src}）"
  fi
  warn "规则仅在内存中生效，重启前请到【9 保存 / 备份】保存"
}

add_ip_menu() {
  local mode="$1" ip action comment
  title "$([[ ${mode} == 3 ]] && echo '放行 IP / 网段' || echo '封禁 IP / 网段')"
  guard_iptables || return 1
  ask_ip ip "IP 或网段（例 1.2.3.4 ／ 10.0.0.0/8）" || return 1
  if [[ ${mode} == 3 ]]; then action="ACCEPT"; else action="DROP"; fi

  # 安全防护：封禁当前 SSH 客户端所在地址会立刻把自己踢下线
  if [[ ${action} != ACCEPT ]]; then
    local cip
    cip=$(ssh_client_ip)
    if [[ -n ${cip} && ( ${ip} == "${cip}" || ${ip} == "0.0.0.0/0" ) ]]; then
      danger_box "你正在封禁 ${ip}
当前 SSH 客户端地址是 ${cip}，执行后你的连接会立即断开
（若是通过跳板机操作，请确认封禁范围）"
      if ! confirm "仍然要继续？" n; then info "已取消"; return 0; fi
    fi
  fi

  read_input "备注（可选）" "" comment || return 0

  echo
  if [[ -n ${comment} ]]; then
    run_cmd "${IPT[@]}" -A INPUT -s "${ip}" -m comment --comment "${comment}" -j "${action}"
  else
    run_cmd "${IPT[@]}" -A INPUT -s "${ip}" -j "${action}"
  fi
  if [[ ${action} == ACCEPT ]]; then
    ok "已放行 ${ip}"
  else
    ok "已封禁 ${ip}"
  fi
  warn "如需重启保留请执行【保存】"
}

add_icmp_allow() {
  title "放行 ICMP（ping）"
  guard_iptables || return 1
  # 去重：同类规则已存在就不再追加，避免反复执行堆叠多条
  if "${IPT[@]}" -C INPUT -p icmp --icmp-type echo-request -m limit --limit 10/second -j ACCEPT >/dev/null 2>&1; then
    info "放行 ping 的限速规则已存在，跳过"
    return 0
  fi
  run_cmd "${IPT[@]}" -A INPUT -p icmp --icmp-type echo-request -m limit --limit 10/second -j ACCEPT
  ok "已放行 ping（限速 10 次/秒，防 ICMP 洪水）"
}

add_icmp_deny() {
  title "禁止 ICMP（禁 ping）"
  guard_iptables || return 1
  if "${IPT[@]}" -C INPUT -p icmp --icmp-type echo-request -j DROP >/dev/null 2>&1; then
    info "禁 ping 规则已存在，跳过"
    return 0
  fi
  run_cmd "${IPT[@]}" -A INPUT -p icmp --icmp-type echo-request -j DROP
  ok "已禁止 ping 请求"
}

add_established() {
  title "放行已建立 / 相关联的连接"
  guard_iptables || return 1
  if "${IPT[@]}" -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT >/dev/null 2>&1; then
    info "ESTABLISHED,RELATED 放行规则已存在，跳过"
  else
    run_cmd "${IPT[@]}" -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  fi
  if "${IPT[@]}" -C INPUT -m conntrack --ctstate INVALID -j DROP >/dev/null 2>&1; then
    info "INVALID 丢弃规则已存在，跳过"
  else
    run_cmd "${IPT[@]}" -A INPUT -m conntrack --ctstate INVALID -j DROP
  fi
  ok "已放行 ESTABLISHED,RELATED，并丢弃 INVALID 状态包"
}

add_loopback() {
  title "放行回环网卡 lo"
  guard_iptables || return 1
  if "${IPT[@]}" -C INPUT -i lo -j ACCEPT >/dev/null 2>&1; then
    info "回环放行规则已存在，跳过"; return 0
  fi
  run_cmd "${IPT[@]}" -A INPUT -i lo -j ACCEPT
  ok "已放行回环网卡"
}

add_ssh_bruteforce() {
  title "SSH 防爆破（recent 模块）"
  guard_iptables || return 1
  local port maxretry secs
  read_input "SSH 端口" "$(ssh_ports | awk '{print $1}')" port || return 0
  read_input "时间窗口（秒）" "60" secs || return 0
  read_input "窗口内最大尝试次数" "4" maxretry || return 0

  [[ ${port} =~ ^[0-9]+$ ]] || { err "端口不合法"; return 1; }
  [[ ${secs} =~ ^[0-9]+$ ]] || { err "时间窗口必须是数字"; return 1; }
  [[ ${maxretry} =~ ^[0-9]+$ ]] || { err "次数必须是数字"; return 1; }

  # 去重：已存在同类规则就不再插入
  if "${IPT[@]}" -C INPUT -p tcp --dport "${port}" -m recent --name SSHBRUTE --rcheck -j DROP >/dev/null 2>&1; then
    info "SSH 防爆破规则已存在（端口 ${port}），跳过"
    return 0
  fi

  echo
  sub "即将执行（规则插入到 INPUT 链首，优先匹配）"
  run_cmd "${IPT[@]}" -I INPUT 1 -p tcp --dport "${port}" -m conntrack --ctstate NEW \
    -m recent --name SSHBRUTE --rcheck --seconds "${secs}" --hitcount "${maxretry}" -j DROP
  run_cmd "${IPT[@]}" -I INPUT 2 -p tcp --dport "${port}" -m conntrack --ctstate NEW \
    -m recent --name SSHBRUTE --set -j ACCEPT
  echo
  ok "已启用：${secs} 秒内超过 ${maxretry} 次新连接即拉黑该 IP"
  info "黑名单是临时的，可用【删除规则】或清空规则解除"
  info "提示：SSH 端口 ${port} 必须确实在监听，否则此规则无意义"
}

add_custom() {
  title "自定义规则"
  guard_iptables || return 1
  printf '%b\n' "  ${C_DIM}输入 iptables 之后的参数，例如：${C_RESET}"
  printf '%b\n' "    ${C_MAGENTA}-A${C_RESET} ${C_CYAN}INPUT${C_RESET} ${C_MAGENTA}-p${C_RESET} ${C_BLUE}tcp${C_RESET} ${C_MAGENTA}--dport${C_RESET} ${C_YELLOW}8080${C_RESET} ${C_MAGENTA}-j${C_RESET} ${C_GREEN}ACCEPT${C_RESET}"
  printf '%b\n' "    ${C_MAGENTA}-A${C_RESET} ${C_CYAN}INPUT${C_RESET} ${C_MAGENTA}-s${C_RESET} ${C_YELLOW}1.2.3.4${C_RESET} ${C_MAGENTA}-j${C_RESET} ${C_RED}DROP${C_RESET}"
  printf '%b\n' "    ${C_MAGENTA}-t${C_RESET} ${C_CYAN}nat${C_RESET} ${C_MAGENTA}-A${C_RESET} ${C_CYAN}PREROUTING${C_RESET} ${C_MAGENTA}-p${C_RESET} ${C_BLUE}tcp${C_RESET} ${C_MAGENTA}--dport${C_RESET} ${C_YELLOW}80${C_RESET} ${C_MAGENTA}-j${C_RESET} ${C_YELLOW}REDIRECT${C_RESET} ${C_MAGENTA}--to-port${C_RESET} ${C_YELLOW}8080${C_RESET}"
  printf '\n'
  read_input "iptables 参数" "" args || return 0
  [[ -z ${args} ]] && { err "不能为空"; return 1; }

  # 参数会以 root 身份经 eval 执行，含 shell 元字符时额外警告
  # 正则放在变量里，避免在 [[ ]] 中写 $ 触发转义困扰
  local meta_re='[;|&<>]|[$][(]|`'
  if [[ ${args} =~ ${meta_re} ]]; then
    danger_box "参数中包含 shell 元字符（; | & \$( ) \` >）
这些内容会以 root 身份交给 shell 执行，可能运行 iptables 之外的命令
请确认这是你本意输入的内容"
    if ! confirm "确认继续？" n; then info "已取消"; return 0; fi
  fi

  echo
  confirm "确认执行以上命令？" y || { info "已取消"; return 0; }
  run_eval "iptables -w 5 ${args}"
  warn "如需重启保留请执行【保存】"
}

# ==============================================================================
#                                  删除规则
# ==============================================================================
menu_delete() {
  while true; do
    menu_header "删除规则" "建议先到【查看规则】确认行号"
    statusbar
    hr
    printf '%b\n' \
      "  ${C_GREEN}1${C_RESET}) 按行号删除单条规则" \
      "  ${C_GREEN}2${C_RESET}) 按链清空（只清某条链的所有规则）" \
      "  ${C_RED}3${C_RESET}) 清空全部规则（保留默认策略）" \
      "  ${C_DIM}0${C_RESET}) 返回主菜单"
    hr
    printf '%b' "  ${C_BOLD}请选择${C_RESET} > "
    local c; IFS= read -r c || return 0
    case "${c}" in
      1) delete_by_line; pause ;;
      2) flush_chain;    pause ;;
      3) flush_all;      pause ;;
      0|"") return 0 ;;
      *) err "无效选项"; sleep 1 ;;
    esac
  done
}

# 以 -S 格式带编号显示某条链（编号与删除索引完全一致）
show_chain_numbered() {
  "${IPT[@]}" -S "$1" 2>/dev/null | grep -v '^-P ' | nl -ba -w 2 -s ') ' | colorize_rules
}

delete_by_line() {
  local chain num spec total
  guard_iptables || return 1
  read_input "选择链 [INPUT/FORWARD/OUTPUT]" "INPUT" chain || return 0
  chain=${chain^^}
  [[ ${chain} == INPUT || ${chain} == FORWARD || ${chain} == OUTPUT ]] || { err "链名不合法"; return 1; }

  total=$("${IPT[@]}" -S "${chain}" 2>/dev/null | grep -vc '^-P ' || true)
  if [[ ${total:-0} -eq 0 ]]; then
    warn "${chain} 链当前没有任何规则"
    return 0
  fi

  title "${chain} 链规则（共 ${total} 条）"
  show_chain_numbered "${chain}"
  echo
  read_input "要删除的编号（回车取消）" "" num || return 0
  [[ -z ${num} ]] && { info "已取消"; return 0; }
  [[ ${num} =~ ^[0-9]+$ ]] || { err "编号必须是数字"; return 1; }
  (( num >= 1 && num <= total )) || { err "编号超出范围（1 ~ ${total}）"; return 1; }

  spec=$("${IPT[@]}" -S "${chain}" 2>/dev/null | grep -v '^-P ' | sed -n "${num}p")
  [[ -z ${spec} ]] && { err "第 ${num} 条规则不存在"; return 1; }
  spec="${spec/#-A /-D }"

  echo
  confirm "确认删除这条规则？" n || { info "已取消"; return 0; }
  auto_backup
  run_eval "iptables -w 5 ${spec}" && ok "已删除第 ${num} 条规则"
}

flush_chain() {
  local chain
  guard_iptables || return 1
  read_input "选择链 [INPUT/FORWARD/OUTPUT]" "INPUT" chain || return 0
  chain=${chain^^}
  [[ ${chain} == INPUT || ${chain} == FORWARD || ${chain} == OUTPUT ]] || { err "链名不合法"; return 1; }
  confirm "确认清空 ${chain} 链所有规则？（默认策略保持不变）" n || { info "已取消"; return 0; }
  auto_backup
  run_cmd "${IPT[@]}" -F "${chain}"
  ok "${chain} 链已清空（默认策略未变：$(policy_of "${chain}")）"
}

flush_all() {
  guard_iptables || return 1
  danger_box "将清空 filter / nat / mangle 三个表的全部规则
默认策略保持不变，但所有放行/拒绝规则都会消失
若默认策略是 DROP，清空后可能直接失去远程连接"
  confirm "确认清空全部规则？" n || { info "已取消"; return 0; }
  auto_backup
  _flush_tables
  ok "全部规则已清空（策略：$(policy_of INPUT) / $(policy_of FORWARD) / $(policy_of OUTPUT)）"
  warn "如需完全放行，请到【3 服务控制】执行停止"
}

# ==============================================================================
#                              策略与预设
# ==============================================================================
menu_policy() {
  while true; do
    menu_header "策略与预设" "一键套用常用防火墙方案"
    statusbar
    hr
    printf '%b\n' \
      "  ${C_GREEN}1${C_RESET}) 设置默认策略（INPUT / FORWARD / OUTPUT）" \
      "  ${C_CYAN}2${C_RESET}) 预设：SSH 基础防护（默认拒绝入站 + 放行 SSH/ICMP/回环）" \
      "  ${C_CYAN}3${C_RESET}) 预设：Web 服务器（SSH + 80 + 443）" \
      "  ${C_CYAN}4${C_RESET}) 预设：数据库服务器（SSH + 内网数据库端口）" \
      "  ${C_CYAN}5${C_RESET}) 预设：Docker 友好（放行 docker 网桥与容器流量）" \
      "  ${C_RED}6${C_RESET}) 预设：全放行（恢复出厂，等价于关闭防火墙）" \
      "  ${C_DIM}0${C_RESET}) 返回主菜单"
    hr
    printf '%b' "  ${C_BOLD}请选择${C_RESET} > "
    local c; IFS= read -r c || return 0
    case "${c}" in
      1) set_policy_menu; pause ;;
      2) preset_ssh;  pause ;;
      3) preset_web;  pause ;;
      4) preset_db;   pause ;;
      5) preset_docker; pause ;;
      6) preset_open; pause ;;
      0|"") return 0 ;;
      *) err "无效选项"; sleep 1 ;;
    esac
  done
}

set_policy_menu() {
  local chain policy
  title "设置默认策略"
  guard_iptables || return 1
  printf '%b\n' "  ${C_DIM}ACCEPT = 未匹配任何规则时放行；DROP = 未匹配时丢弃（入站推荐 DROP）${C_RESET}\n"
  read_input "选择链 [INPUT/FORWARD/OUTPUT]" "INPUT" chain || return 0
  chain=${chain^^}
  [[ ${chain} == INPUT || ${chain} == FORWARD || ${chain} == OUTPUT ]] || { err "链名不合法"; return 1; }
  printf '%b\n' "  ${C_DIM}当前 ${chain} 策略：${C_RESET}$(policy_badge "$(policy_of "${chain}")")"
  read_input "策略 [ACCEPT/DROP]" "DROP" policy || return 0
  policy=${policy^^}
  [[ ${policy} == ACCEPT || ${policy} == DROP ]] || { err "策略只能是 ACCEPT / DROP"; return 1; }

  if [[ ${policy} == DROP ]]; then
    printf '\n'
    if [[ ${chain} == INPUT ]]; then
      warn "设为 DROP 前，正在检查 SSH 端口是否已放行（防止把自己锁在门外）…"
      ensure_ssh_allowed
      if ! "${IPT[@]}" -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT >/dev/null 2>&1; then
        warn "缺少 ESTABLISHED,RELATED 放行规则，正在补充"
        run_cmd "${IPT[@]}" -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      fi
      if ! "${IPT[@]}" -C INPUT -i lo -j ACCEPT >/dev/null 2>&1; then
        run_cmd "${IPT[@]}" -A INPUT -i lo -j ACCEPT
        info "已补充回环网卡放行"
      fi
    elif [[ ${chain} == FORWARD ]]; then
      danger_box "FORWARD 设为 DROP 后：
• 本机做路由/网关时，内网将无法访问外网
• Docker 容器网络会中断
• 端口转发（DNAT）会失效"
    fi
    echo
    if ! confirm "最后确认：将 ${chain} 默认策略设为 DROP？" n; then info "已取消"; return 0; fi
  fi

  auto_backup
  run_cmd "${IPT[@]}" -P "${chain}" "${policy}"
  ok "${chain} 默认策略已设为 ${policy}"
  warn "如需重启保留请执行【保存】"
}

# --- 预设实现 ---------------------------------------------------------------
_flush_tables() {  # 清空全部表（含 IPv6）
  local t
  for t in filter nat mangle; do
    "${IPT[@]}" -t "${t}" -F 2>/dev/null
    "${IPT[@]}" -t "${t}" -X 2>/dev/null
  done
  if ipv6_ready; then
    for t in filter nat mangle; do "${IPT6[@]}" -t "${t}" -F 2>/dev/null; done
    info "IPv6 规则已同步清空"
  fi
}

_preset_begin() {  # 备份 + 清空
  auto_backup
  _flush_tables
}

_base_rules() {  # 通用基础放行
  run_cmd "${IPT[@]}" -A INPUT -i lo -j ACCEPT
  run_cmd "${IPT[@]}" -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  run_cmd "${IPT[@]}" -A INPUT -m conntrack --ctstate INVALID -j DROP
  run_cmd "${IPT[@]}" -A INPUT -p icmp --icmp-type echo-request -m limit --limit 10/second -j ACCEPT
  local p
  for p in $(ssh_ports); do
    run_cmd "${IPT[@]}" -A INPUT -p tcp --dport "${p}" -j ACCEPT
  done
}

preset_ssh() {
  title "预设：SSH 基础防护"
  guard_iptables || return 1
  kv "默认策略" "INPUT=${C_RED}DROP${C_RESET}  FORWARD=${C_RED}DROP${C_RESET}  OUTPUT=${C_GREEN}ACCEPT${C_RESET}"
  kv "放行" "回环 lo · 已建立连接 · ICMP(ping) · SSH ${C_YELLOW}$(ssh_ports)${C_RESET}"
  kv "效果" "除上述端口外，所有入站连接一律丢弃"
  echo
  confirm "确认应用该预设（会先清空现有规则）？" n || { info "已取消"; return 0; }
  _preset_begin
  _base_rules
  run_cmd "${IPT[@]}" -P INPUT DROP
  run_cmd "${IPT[@]}" -P FORWARD DROP
  run_cmd "${IPT[@]}" -P OUTPUT ACCEPT
  echo
  save_rules quiet
  ok "预设已应用并保存"
}

preset_web() {
  title "预设：Web 服务器"
  guard_iptables || return 1
  kv "默认策略" "INPUT=${C_RED}DROP${C_RESET}  FORWARD=${C_RED}DROP${C_RESET}  OUTPUT=${C_GREEN}ACCEPT${C_RESET}"
  kv "放行" "回环 · 已建立连接 · ICMP · SSH ${C_YELLOW}$(ssh_ports)${C_RESET} · HTTP ${C_YELLOW}80${C_RESET} · HTTPS ${C_YELLOW}443${C_RESET}"
  kv "效果" "对外只暴露 80 / 443 与 SSH"
  echo
  confirm "确认应用该预设（会先清空现有规则）？" n || { info "已取消"; return 0; }
  _preset_begin
  _base_rules
  run_cmd "${IPT[@]}" -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT
  run_cmd "${IPT[@]}" -P INPUT DROP
  run_cmd "${IPT[@]}" -P FORWARD DROP
  run_cmd "${IPT[@]}" -P OUTPUT ACCEPT
  echo
  save_rules quiet
  ok "预设已应用并保存"
}

preset_db() {
  title "预设：数据库服务器"
  guard_iptables || return 1
  local net ports
  ask_ip   net   "允许访问数据库的内网网段" "10.0.0.0/8" || return 1
  ask_port ports "数据库端口（逗号分隔）" "3306,5432,6379,27017" || return 1

  kv "默认策略" "INPUT=${C_RED}DROP${C_RESET}  FORWARD=${C_RED}DROP${C_RESET}  OUTPUT=${C_GREEN}ACCEPT${C_RESET}"
  kv "放行" "回环 · 已建立 · ICMP · SSH ${C_YELLOW}$(ssh_ports)${C_RESET}"
  kv "受限放行" "${C_YELLOW}${net}${C_RESET} → 端口 ${C_YELLOW}${ports}${C_RESET}"
  kv "效果" "数据库端口只对内网开放，公网无法直连"
  echo
  confirm "确认应用该预设（会先清空现有规则）？" n || { info "已取消"; return 0; }
  _preset_begin
  _base_rules
  run_cmd "${IPT[@]}" -A INPUT -s "${net}" -p tcp -m multiport --dports "${ports}" -j ACCEPT
  run_cmd "${IPT[@]}" -P INPUT DROP
  run_cmd "${IPT[@]}" -P FORWARD DROP
  run_cmd "${IPT[@]}" -P OUTPUT ACCEPT
  echo
  save_rules quiet
  ok "预设已应用：数据库端口仅对 ${net} 开放，并已保存"
}

preset_docker() {
  title "预设：Docker 友好"
  guard_iptables || return 1
  kv "默认策略" "INPUT=${C_RED}DROP${C_RESET}  FORWARD=${C_GREEN}ACCEPT${C_RESET}  OUTPUT=${C_GREEN}ACCEPT${C_RESET}"
  kv "放行" "回环 · 已建立 · ICMP · SSH ${C_YELLOW}$(ssh_ports)${C_RESET} · docker0 网桥"
  kv "注意" "FORWARD 必须保持 ACCEPT，否则容器网络不通"
  echo
  confirm "确认应用该预设（会先清空现有规则）？" n || { info "已取消"; return 0; }
  _preset_begin
  _base_rules
  run_cmd "${IPT[@]}" -A INPUT -i docker0 -j ACCEPT
  if ip link show 2>/dev/null | grep -qE 'br-[0-9a-f]{12}'; then
    run_cmd "${IPT[@]}" -A INPUT -i br-+ -j ACCEPT
  fi
  run_cmd "${IPT[@]}" -P INPUT DROP
  run_cmd "${IPT[@]}" -P FORWARD ACCEPT
  run_cmd "${IPT[@]}" -P OUTPUT ACCEPT
  echo
  save_rules quiet
  ok "预设已应用并保存（容器出网与端口映射保持可用）"
  info "建议随后执行一次 systemctl restart docker，让 Docker 重建自己的链"
}

preset_open() {
  title "预设：全放行"
  guard_iptables || return 1
  danger_box "将清空全部规则，并把三条链策略都改为 ACCEPT
服务器从此没有任何防护，所有端口对公网开放
仅在调试或排障时临时使用"
  confirm "确认恢复全放行状态？" n || { info "已取消"; return 0; }
  auto_backup
  # 先放开策略再清空规则：避免清空瞬间出现"策略仍为 DROP 且链已空"的黑洞窗口
  run_cmd "${IPT[@]}" -P INPUT ACCEPT
  run_cmd "${IPT[@]}" -P FORWARD ACCEPT
  run_cmd "${IPT[@]}" -P OUTPUT ACCEPT
  _flush_tables
  echo
  save_rules quiet
  ok "已恢复全放行状态"
}

# ==============================================================================
#                                  高级功能
# ==============================================================================
menu_advanced() {
  while true; do
    menu_header "高级功能" "NAT / 转发 / 日志 / 测试"
    statusbar
    hr
    printf '%b\n' \
      "  ${C_CYAN}1${C_RESET}) 端口转发（DNAT：外部端口 → 内网主机）" \
      "  ${C_CYAN}2${C_RESET}) 出网共享（SNAT / MASQUERADE）" \
      "  ${C_CYAN}3${C_RESET}) 开启 / 关闭 IP 转发" \
      "  ${C_YELLOW}4${C_RESET}) 记录被丢弃的包（LOG 规则）" \
      "  ${C_YELLOW}5${C_RESET}) 端口连通性测试" \
      "  ${C_GREEN}6${C_RESET}) 查看 / 清理 nat 表规则" \
      "  ${C_DIM}0${C_RESET}) 返回主菜单"
    hr
    printf '%b' "  ${C_BOLD}请选择${C_RESET} > "
    local c; IFS= read -r c || return 0
    case "${c}" in
      1) adv_dnat;   pause ;;
      2) adv_snat;   pause ;;
      3) adv_ipforward; pause ;;
      4) adv_log;    pause ;;
      5) adv_test;   pause ;;
      6) show_rules nat; pause ;;
      0|"") return 0 ;;
      *) err "无效选项"; sleep 1 ;;
    esac
  done
}

adv_dnat() {
  title "端口转发 DNAT（外部端口 → 内网主机）"
  guard_iptables || return 1
  local eport dip dport proto
  read_input "协议 [tcp / udp]" "tcp" proto || return 0
  proto=${proto,,}
  [[ ${proto} == tcp || ${proto} == udp ]] || { err "协议只能是 tcp / udp"; return 1; }

  ask_port eport "外部端口（本机对外端口）" || return 1
  [[ ${eport} == *,* || ${eport} == *:* ]] && { err "端口转发只支持单个端口，不支持范围或列表"; return 1; }
  ask_ip   dip   "目标内网 IP" || return 1
  ask_port dport "目标端口" "${eport}" || return 1
  [[ ${dport} == *,* || ${dport} == *:* ]] && { err "目标端口只支持单个端口"; return 1; }

  echo
  if ! sysctl -n net.ipv4.ip_forward 2>/dev/null | grep -q '^1$'; then
    warn "IP 转发未开启，将自动开启"
    run_cmd sysctl -w net.ipv4.ip_forward=1
    # 判重需容忍 "net.ipv4.ip_forward = 1"（等号两侧带空格）的写法，避免重复追加
    grep -qE '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=' /etc/sysctl.conf 2>/dev/null || \
      echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
  fi
  sub "即将执行"
  run_cmd "${IPT[@]}" -t nat -A PREROUTING -p "${proto}" --dport "${eport}" -j DNAT --to-destination "${dip}:${dport}"
  run_cmd "${IPT[@]}" -A FORWARD -p "${proto}" -d "${dip}" --dport "${dport}" -j ACCEPT
  run_cmd "${IPT[@]}" -t nat -A POSTROUTING -d "${dip}" -p "${proto}" --dport "${dport}" -j MASQUERADE
  echo
  ok "已配置：本机 ${eport}/${proto} → ${dip}:${dport}"
  warn "如需重启保留请执行【保存】"
  info "验证：在外部机器执行 nc -vz <本机公网IP> ${eport}"
}

adv_snat() {
  title "出网共享 SNAT / MASQUERADE"
  guard_iptables || return 1
  local net iface
  ask_ip net "内网网段" "192.168.1.0/24" || return 1
  read_input "出口网卡（留空 = 自动检测）" "" iface || return 0
  if [[ -z ${iface} ]]; then
    iface=$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')
  fi
  [[ -z ${iface} ]] && { err "无法检测出口网卡，请手动填写（用 ip route 查看）"; return 1; }
  kv "出口网卡" "${C_YELLOW}${iface}${C_RESET}"

  sysctl -n net.ipv4.ip_forward 2>/dev/null | grep -q '^1$' || {
    run_cmd sysctl -w net.ipv4.ip_forward=1
    grep -qE '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=' /etc/sysctl.conf 2>/dev/null \
      || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
  }
  echo
  run_cmd "${IPT[@]}" -t nat -A POSTROUTING -s "${net}" -o "${iface}" -j MASQUERADE
  run_cmd "${IPT[@]}" -A FORWARD -s "${net}" -o "${iface}" -j ACCEPT
  run_cmd "${IPT[@]}" -A FORWARD -d "${net}" -i "${iface}" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  echo
  ok "已配置：${net} 通过 ${iface} 共享上网"
  info "客户端需把网关指向本机内网 IP，并把 DNS 指向可用服务器"
}

adv_ipforward() {
  title "IP 转发"
  local cur
  cur=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
  kv "当前状态" "${cur}"
  printf '%b\n' "  ${C_GREEN}1${C_RESET}) 开启   ${C_RED}2${C_RESET}) 关闭   ${C_DIM}0${C_RESET}) 返回"
  printf '%b' "  ${C_BOLD}请选择${C_RESET} > "
  local c; IFS= read -r c || return 0
  case "${c}" in
    1)
      run_cmd sysctl -w net.ipv4.ip_forward=1
      grep -qE '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=' /etc/sysctl.conf 2>/dev/null \
        || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
      ok "已开启 IP 转发（并写入 /etc/sysctl.conf 永久生效）" ;;
    2)
      run_cmd sysctl -w net.ipv4.ip_forward=0
      # 兼容 "=1" 与 "= 1" 两种历史写法
      sed -i 's/^\([[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=[[:space:]]*\)1/\10/' /etc/sysctl.conf 2>/dev/null
      ok "已关闭 IP 转发" ;;
    *) return 0 ;;
  esac
}

adv_log() {
  title "记录被丢弃的包"
  guard_iptables || return 1
  printf '%b\n' "  ${C_DIM}在 INPUT 链末尾加一条 LOG 规则：被默认策略 DROP 的包会写入内核日志${C_RESET}\n"
  if "${IPT[@]}" -C INPUT -j LOG --log-prefix "IPT-DROP: " >/dev/null 2>&1; then
    info "LOG 规则已存在"
    if confirm "是否移除该 LOG 规则？" n; then
      run_cmd "${IPT[@]}" -D INPUT -j LOG --log-prefix "IPT-DROP: " && ok "已移除"
    fi
    return 0
  fi
  if ! confirm "确认添加日志规则？（流量大时会产生大量日志）" n; then
    info "已取消"; return 0
  fi
  run_cmd "${IPT[@]}" -A INPUT -m limit --limit 5/min -j LOG --log-prefix "IPT-DROP: " --log-level 4
  echo
  ok "已添加（限速 5 条/分钟，避免刷爆磁盘）"
  info "实时查看：journalctl -k -f | grep IPT-DROP"
}

adv_test() {
  title "端口连通性测试"
  local host port
  read_input "目标主机" "127.0.0.1" host || return 0
  read_input "目标端口" "22" port || return 0
  # host 会进入 /dev/tcp 重定向串，限制字符集防止意外执行其他内容
  [[ ${host} =~ ^[A-Za-z0-9._-]+$ ]] || { err "主机名格式不合法（仅允许字母数字与 . _ -）"; return 1; }
  [[ ${port} =~ ^[0-9]+$ ]] || { err "端口不合法"; return 1; }

  printf '  %b %s:%s … ' "${C_DIM}测试${C_RESET}" "${host}" "${port}"
  if cmd_exists nc; then
    if nc -z -w 3 "${host}" "${port}" 2>/dev/null; then
      printf '%b\n' "${C_GREEN}✔ 端口开放${C_RESET}"
    else
      printf '%b\n' "${C_RED}✘ 不通 / 被拒绝${C_RESET}"
    fi
  elif timeout 3 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
    printf '%b\n' "${C_GREEN}✔ 端口开放${C_RESET}"
  else
    printf '%b\n' "${C_RED}✘ 不通 / 被拒绝${C_RESET}"
  fi
  info "本机测试通过不代表外部可达，外部访问还受云厂商安全组影响"
}

# ==============================================================================
#                              保存 / 备份 / 恢复
# ==============================================================================
menu_persist() {
  while true; do
    menu_header "保存 / 备份 / 恢复" "让规则在重启后依然生效"
    statusbar
    if has_unsaved; then
      printf '%b\n' "  ${C_YELLOW}⚠ 运行中的规则与磁盘 ${RULES_V4} 不一致，重启后这些改动会丢失${C_RESET}"
    else
      printf '%b\n' "  ${C_GREEN}✔ 运行规则与磁盘配置一致${C_RESET}"
    fi
    hr
    printf '%b\n' \
      "  ${C_GREEN}1${C_RESET}) 保存当前规则（重启后仍然生效）" \
      "  ${C_GREEN}2${C_RESET}) 手动备份当前规则" \
      "  ${C_GREEN}3${C_RESET}) 查看备份列表" \
      "  ${C_YELLOW}4${C_RESET}) 从备份恢复规则（选择序号）" \
      "  ${C_YELLOW}5${C_RESET}) 回滚到最近一次备份（最快恢复）" \
      "  ${C_GREEN}6${C_RESET}) 导出规则为文件（可下载留存）" \
      "  ${C_RED}7${C_RESET}) 删除全部备份" \
      "  ${C_DIM}0${C_RESET}) 返回主菜单"
    hr
    printf '%b' "  ${C_BOLD}请选择${C_RESET} > "
    local c; IFS= read -r c || return 0
    case "${c}" in
      1) save_rules; pause ;;
      2) do_backup; pause ;;
      3) list_backups; pause ;;
      4) restore_backup; pause ;;
      5) rollback_latest; pause ;;
      6) export_rules; pause ;;
      7) clean_backups; pause ;;
      0|"") return 0 ;;
      *) err "无效选项"; sleep 1 ;;
    esac
  done
}

do_backup() {
  local f
  if f=$(backup_rules); then
    ok "备份完成 → ${f}"
  else
    err "备份失败（请检查磁盘空间与权限）"
    return 1
  fi
}

rollback_latest() {
  title "回滚到最近一次备份"
  local f
  f=$(list_backup_files | head -n 1)
  if [[ -z ${f} ]]; then
    err "没有任何备份，无法回滚"
    return 1
  fi
  printf '%b\n' "  ${C_DIM}最近备份：${C_RESET}${C_BOLD}$(basename "${f}")${C_RESET}"
  printf '%b\n' "  ${C_DIM}包含 $(grep -c '^-A ' "${f}" 2>/dev/null || true) 条规则${C_RESET}"
  confirm "确认用该备份覆盖当前运行规则？" n || { info "已取消"; return 0; }
  run_eval "iptables-restore < '${f}'" && ok "已回滚"
  if confirm "是否同时保存为开机生效配置？" y; then save_rules; fi
}

count_rules_in() { grep -c '^-A ' "$1" 2>/dev/null || true; }

fmt_backup_time() {
  local b; b=$(basename "$1")
  if [[ ${b} =~ ^rules-([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2})\.v4$ ]]; then
    printf '%s-%s-%s %s:%s:%s' \
      "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" \
      "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}"
  else
    printf '%s' "${b}"
  fi
}

list_backups() {
  title "备份列表（${BACKUP_DIR}）"
  if [[ -z $(list_backup_files) ]]; then
    info "暂无备份"; return 0
  fi
  printf '%b\n' "  ${C_DIM}序号  备份时间             规则数   大小   文件名${C_RESET}"
  local i=1 f n sz
  while IFS= read -r f; do
    n=$(count_rules_in "${f}")
    sz=$(du -h "${f}" 2>/dev/null | awk '{print $1}')
    printf '  %b%2d%b)  %s   %b%3s 条%b  %b%5s%b  %b%s%b\n' \
      "${C_CYAN}" "${i}" "${C_RESET}" \
      "$(fmt_backup_time "${f}")" \
      "${C_DIM}" "${n:-0}" "${C_RESET}" \
      "${C_DIM}" "${sz:-?}" "${C_RESET}" \
      "${C_DIM}" "$(basename "${f}")" "${C_RESET}"
    ((i++))
  done < <(list_backup_files)
  printf '%b\n' "  ${C_DIM}最多保留 ${MAX_BACKUPS} 份，超出自动清理最旧的${C_RESET}"
}

restore_backup() {
  title "从备份恢复"
  list_backups
  local n f
  read_input "输入备份序号（回车取消）" "" n || return 0
  [[ -z ${n} ]] && { info "已取消"; return 0; }
  [[ ${n} =~ ^[0-9]+$ ]] || { err "序号必须是数字"; return 1; }
  (( n >= 1 )) || { err "序号从 1 开始"; return 1; }
  f=$(list_backup_files | sed -n "${n}p")
  [[ -z ${f} ]] && { err "第 ${n} 个备份不存在"; return 1; }

  confirm "确认用 $(fmt_backup_time "${f}") 的备份覆盖当前规则？" n || { info "已取消"; return 0; }
  auto_backup
  run_eval "iptables-restore < '${f}'" && ok "已恢复"
  if confirm "是否同时保存为开机生效配置？" y; then save_rules; fi
}

export_rules() {
  title "导出规则"
  local out ts
  ts=$(date +%Y%m%d-%H%M%S)
  out="/root/iptables-rules-${ts}.v4"
  if iptables-save >"${out}" 2>/dev/null; then
    ok "已导出 → ${out}"
  else
    err "导出失败（请检查 /root 写入权限）"
    return 1
  fi
}

clean_backups() {
  title "删除全部备份"
  confirm "确认删除 ${BACKUP_DIR} 下所有备份文件？" n || { info "已取消"; return 0; }
  rm -f "${BACKUP_DIR}"/rules-*.v4
  ok "已清理"
}

# ==============================================================================
#                                  环境自检
# ==============================================================================
doctor() {
  banner
  printf '%b\n' "  ${C_CYAN}${C_BOLD}环境自检（doctor）${C_RESET}"
  hr
  local fail=0 m s

  if [[ ${EUID} -eq 0 ]]; then ok "root 权限"; else err "非 root 运行"; fail=1; fi

  if cmd_exists iptables; then
    ok "iptables：$(iptables --version 2>/dev/null)"
  else
    err "iptables 未安装"; fail=1
  fi

  if iptables -L -n >/dev/null 2>&1; then
    ok "内核 netfilter 可访问"
  else
    err "无法访问 netfilter（LXC/容器内可能缺少 NET_ADMIN 权限）"; fail=1
  fi

  for m in ip_tables nf_conntrack iptable_filter iptable_nat; do
    if [[ -d /sys/module/${m} ]] || modprobe -n "${m}" >/dev/null 2>&1; then
      ok "内核模块 ${m}"
    else
      warn "内核模块 ${m} 不可用（相关功能受限）"
    fi
  done

  if cmd_exists netfilter-persistent; then
    ok "netfilter-persistent 已安装"
  else
    warn "netfilter-persistent 未安装：重启后规则不会自动恢复"
  fi

  if [[ -s ${RULES_V4} ]]; then
    ok "持久化文件：${RULES_V4}（$(count_rules_in "${RULES_V4}") 条）"
  else
    warn "持久化文件缺失：${RULES_V4}（执行一次保存即可生成）"
  fi

  if has_unsaved; then
    warn "运行中的规则与磁盘配置不一致（有未保存变更）"
  else
    ok "运行规则与磁盘配置一致"
  fi

  if have_iptables; then
    s=$(ssh_ports)
    local p miss=0
    for p in ${s}; do
      "${IPT[@]}" -C INPUT -p tcp --dport "${p}" -j ACCEPT >/dev/null 2>&1 || miss=1
    done
    if (( miss )); then
      warn "SSH 端口 ${s} 未全部放行，当前策略为 $(policy_of INPUT) 时可能失联"
    else
      ok "SSH 端口 ${s} 已放行"
    fi
  fi

  hr
  if (( fail )); then
    err "自检未通过，请先修复上面的红色项"
    return 1
  fi
  ok "自检通过"
}

# ==============================================================================
#                                  状态概览
# ==============================================================================
dashboard() {
  banner
  printf '%b\n' "  ${C_CYAN}${C_BOLD}防火墙状态概览${C_RESET}"
  hr

  kv "主机名"   "$(hostname 2>/dev/null)"
  kv "系统"     "$(os_pretty_name)"
  kv "内核"     "$(uname -r)"
  if have_iptables; then
    kv "iptables" "$(iptables --version 2>/dev/null)"
    kv "后端"     "$(backend_name)"
  else
    kv "iptables" "${C_RED}未安装${C_RESET}"
    kv "后端"     "${C_DIM}--${C_RESET}"
  fi

  hr
  local state
  state=$(svc_state)
  case "${state}" in
    active|standalone) kv "防火墙" "${C_GREEN}● 运行中${C_RESET}  ${C_DIM}(${state})${C_RESET}" ;;
    not-installed)     kv "防火墙" "${C_RED}● 未安装${C_RESET}" ;;
    *)                 kv "防火墙" "${C_RED}● 未运行${C_RESET}  ${C_DIM}(${state})${C_RESET}" ;;
  esac
  if svc_enabled; then
    kv "开机自启" "${C_GREEN}● 已启用${C_RESET}"
  else
    kv "开机自启" "${C_YELLOW}○ 未启用${C_RESET}"
  fi

  if have_iptables; then
    hr
    snapshot_state
    if (( ! ST_OK )); then
      kv "默认策略" "${C_YELLOW}无法读取${C_RESET} ${C_DIM}(权限不足或 netfilter 不可用)${C_RESET}"
      kv "规则数量" "${C_YELLOW}无法读取${C_RESET}"
    else
      local b_in b_fw b_out
      badge_of "${ST_IN}";  b_in="${PB}"
      badge_of "${ST_FW}";  b_fw="${PB}"
      badge_of "${ST_OUT}"; b_out="${PB}"
      kv "默认策略" "IN=${b_in}  FW=${b_fw}  OUT=${b_out}"
      kv "规则数量" "${C_BOLD}${ST_COUNT}${C_RESET} 条"

      local ports p blocked="" all_ok=1
      ports=$(ssh_ports)
      for p in ${ports}; do
        if ! "${IPT[@]}" -C INPUT -p tcp --dport "${p}" -j ACCEPT >/dev/null 2>&1; then
          all_ok=0
          blocked+="${p} "
        fi
      done
      if (( all_ok )); then
        kv "SSH 端口" "${C_YELLOW}${ports}${C_RESET}  ${C_GREEN}✔ 已放行${C_RESET}"
      else
        kv "SSH 端口" "${C_YELLOW}${ports}${C_RESET}  ${C_RED}✘ 未放行：${blocked% }${C_RESET}"
      fi
    fi
  fi

  hr
  if [[ -s ${RULES_V4} ]]; then
    kv "持久化" "${C_GREEN}✔${C_RESET} ${RULES_V4}  ${C_DIM}($(count_rules_in "${RULES_V4}") 条)${C_RESET}"
  else
    kv "持久化" "${C_YELLOW}⚠ 尚未生成${C_RESET} ${RULES_V4}"
  fi
  if has_unsaved; then
    kv "配置同步" "${C_YELLOW}● 有未保存的变更（重启会丢失）${C_RESET}"
  else
    kv "配置同步" "${C_GREEN}● 已保存${C_RESET}"
  fi
  local lb
  lb=$(list_backup_files | head -n 1)
  if [[ -n ${lb} ]]; then
    kv "最近备份" "${C_DIM}$(fmt_backup_time "${lb}")${C_RESET}"
  else
    kv "最近备份" "${C_DIM}暂无${C_RESET}"
  fi
}

banner() {
  [[ -t 1 ]] && { clear 2>/dev/null || printf '\e[H\e[2J'; }
  local line="──────────────────────────────────────────────────────────────"
  printf '\n'
  printf '%b\n' "  ${C_CYAN}${C_BOLD}╭${line}╮${C_RESET}"
  printf '%b\n' "  ${C_CYAN}${C_BOLD}│${C_RESET}  ${C_WHITE}${C_BOLD}iptables-wizard${C_RESET} ${C_DIM}v${VERSION}${C_RESET}   ${C_DIM}·${C_RESET}   ${C_BOLD}Debian 防火墙一键管理工具${C_RESET}"
  printf '%b\n' "  ${C_CYAN}${C_BOLD}╰${line}╯${C_RESET}"
  printf '%b\n' "  ${C_DIM}$(hostname 2>/dev/null)${C_RESET}  ${C_DIM}·${C_RESET}  ${C_DIM}$(os_pretty_name)${C_RESET}"
  printf '%b\n' "  ${C_DIM}需要 root 权限 · 变更前自动备份 · 规则持久化到 ${RULES_V4}${C_RESET}"
}

# ==============================================================================
#                                  主菜单
# ==============================================================================
main_menu() {
  while true; do
    dashboard
    hr
    printf '%b\n' "  ${C_BOLD}功能菜单${C_RESET}   ${C_DIM}输入编号回车 · 0 或 q 退出${C_RESET}"
    menu_group 状态
    menu_row 1 "状态概览"   2 "安装与检测"
    menu_group 服务与规则
    menu_row 3 "服务控制"   4 "查看规则"
    menu_row 5 "添加规则"   6 "删除规则"
    menu_group 策略与维护
    menu_row 7 "策略与预设" 8 "高级功能"
    menu_row 9 "保存 / 备份" 0 "退出"
    hr
    printf '%b' "  ${C_BOLD}请选择${C_RESET} > "
    local c; IFS= read -r c || exit 0
    case "${c}" in
      1) dashboard; pause ;;
      2) do_install; pause ;;
      3) menu_service ;;
      4) menu_view ;;
      5) menu_add ;;
      6) menu_delete ;;
      7) menu_policy ;;
      8) menu_advanced ;;
      9) menu_persist ;;
      0|q|Q) printf '\n%b\n' "  ${C_DIM}再见${C_RESET}"; exit 0 ;;
      *) err "无效选项：${c}"; sleep 1 ;;
    esac
  done
}

usage() {
  cat <<EOF
${APP} v${VERSION} — Debian iptables 一键管理脚本

用法：
  $0                     交互式菜单
  $0 status              状态概览
  $0 list [filter|nat|mangle]
  $0 save                保存规则（重启生效）
  $0 start               启动（加载已保存规则）
  $0 stop                停止（清空规则，放行全部）
  $0 restart             重启服务
  $0 reload              重载规则
  $0 backup              备份当前规则
  $0 restore <文件>      从备份文件恢复（会先自动备份当前规则）
  $0 doctor              环境自检
  $0 install             安装依赖
  $0 version             显示版本
  $0 help                显示本帮助

文件位置：
  持久化配置：${RULES_V4} / ${RULES_V6}
  备份目录：  ${BACKUP_DIR}
  操作日志：  ${LOG_FILE}
EOF
}

main() {
  local action="${1:-menu}"
  case "${action}" in
    help|-h|--help) usage; exit 0 ;;
    version|-v|--version) echo "${APP} ${VERSION}"; exit 0 ;;
    menu|status|list|save|start|stop|restart|reload|doctor|check|backup|restore|install) ;;
    *) err "未知命令：${action}（用 help 查看用法）"; exit 1 ;;
  esac

  require_root
  detect_wait_support
  init_dirs

  case "${action}" in
    menu)    main_menu ;;
    status)  dashboard; echo ;;
    list)    show_rules "${2:-filter}" ;;
    save)    save_rules ;;
    start)   svc_start ;;
    stop)    svc_stop ;;
    restart) svc_restart ;;
    reload)  svc_reload ;;
    doctor|check) doctor ;;
    backup)
      if f=$(backup_rules); then
        echo "备份完成：${f}"
      else
        err "备份失败（请检查磁盘空间与权限）"
        exit 1
      fi ;;
    restore)
      [[ -z ${2:-} ]] && { err "请指定备份文件路径"; exit 1; }
      [[ -f $2 ]] || { err "文件不存在：$2"; exit 1; }
      auto_backup
      iptables-restore <"$2" && echo "已从 $2 恢复" ;;
    install) do_install ;;
    *) err "未知命令：${action}（用 help 查看用法）"; exit 1 ;;
  esac
}

# 仅在被直接执行时启动主流程；被 source 时只加载函数（供 tests/smoke.sh 使用）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
