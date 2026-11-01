#!/usr/bin/env bash
# ==============================================================================
#  tests/smoke.sh — 不依赖 root、不触碰真实 netfilter 的冒烟测试
# ------------------------------------------------------------------------------
#  做法：用「同名 shell 函数」替换 iptables / ip6tables / iptables-save /
#       systemctl / sshd / ss，进程内完成，不 fork、不改系统；
#       然后 source 主脚本，直接调用其内部函数进行断言。
#  覆盖：
#    1. 输入校验（端口 / 地址 / 端口覆盖判断）
#    2. 显示宽度与中英混排对齐
#    3. 命令语法高亮（ANSI 序列、含空格参数加引号）
#    4. 交互流程最终拼出的 iptables 命令
#    5. 命令行入口（--version / --help / 未知命令）
#  用法：bash tests/smoke.sh
#  退出码：0 全部通过；1 有失败
# ==============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WIZARD="${ROOT_DIR}/iptables-wizard.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

green() { printf '\033[1;32m%s\033[0m' "$1"; }
red()   { printf '\033[1;31m%s\033[0m' "$1"; }
dim()   { printf '\033[2m%s\033[0m' "$1"; }

ok_case()   { PASS=$((PASS + 1)); printf '  %s %s\n' "$(green '✔')" "$1"; }
fail_case() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  %s %s\n     %s\n' "$(red '✘')" "$1" "${2:-}"; }

assert_eq() {  # assert_eq 名称 期望 实际
  if [[ "$2" == "$3" ]]; then
    ok_case "$1"
  else
    fail_case "$1" "期望 [${2}]，实际 [${3}]"
  fi
}

assert_contains() {  # assert_contains 名称 内容 子串
  if [[ "$2" == *"$3"* ]]; then
    ok_case "$1"
  else
    fail_case "$1" "未找到子串 [${3}]"
  fi
}

assert_not_contains() {  # assert_not_contains 名称 内容 子串
  if [[ "$2" != *"$3"* ]]; then
    ok_case "$1"
  else
    fail_case "$1" "不应出现子串 [${3}]"
  fi
}

# ------------------------------------------------------------- 进程内 mock ---
# 下面这些「同名函数」由主脚本按命令名间接调用，静态分析看不到调用点，
# 所以每个定义前单独标注 disable=SC2329（函数未被调用）。
TMP_DIR="$(mktemp -d)"
MOCK_LOG="${TMP_DIR}/calls.log"
: >"${MOCK_LOG}"

IPTABLES_RULES="$(printf '%s\n' \
  '-P INPUT DROP' \
  '-A INPUT -i lo -j ACCEPT' \
  '-A INPUT -p tcp --dport 22 -j ACCEPT' \
  '-A INPUT -s 1.2.3.4 -j DROP')"

# shellcheck disable=SC2329
iptables() {
  printf 'iptables %s\n' "$*" >>"${MOCK_LOG}"
  case " $* " in
    *" -S INPUT "*) printf '%s\n' "${IPTABLES_RULES}" ;;
    *" -S "*)       printf '%s\n' '-P INPUT DROP' ;;
    *" -L "*)       printf 'Chain INPUT (policy DROP 0 packets, 0 bytes)\nnum   pkts bytes target     prot opt in     out     source               destination\n' ;;
    *" --version"*) printf 'iptables v1.8.9 (nf_tables)\n' ;;
    *" -C "*)       return 1 ;;
    *) : ;;
  esac
  return 0
}

# shellcheck disable=SC2329
ip6tables() {
  printf 'ip6tables %s\n' "$*" >>"${MOCK_LOG}"
  [[ " $* " == *" -L "* ]] && return 0
  return 0
}

# shellcheck disable=SC2329
iptables_save_mock() {
  printf 'iptables-save %s\n' "$*" >>"${MOCK_LOG}"
  printf '*filter\n:INPUT DROP [0:0]\n-A INPUT -p tcp --dport 22 -j ACCEPT\nCOMMIT\n'
}

# shellcheck disable=SC2329
systemctl() {
  # 模拟「服务未安装」：让 svc_exists 走降级分支，避免依赖 CI 环境
  return 1
}

# shellcheck disable=SC2329
sshd() { printf 'port 22\n'; }
# shellcheck disable=SC2329
ss()   { printf 'LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=1,fd=3))\n'; }

# shellcheck disable=SC2329
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

printf '\n%b\n' "$(dim "iptables-wizard 冒烟测试 · ${WIZARD}")"

# ------------------------------------------------------------------ 载入脚本 --
# shellcheck source=../iptables-wizard.sh
# shellcheck disable=SC1091
if ! source "${WIZARD}"; then
  printf '%s 无法 source 主脚本\n' "$(red '✘')"
  exit 1
fi

# source 之后再用函数覆盖 iptables-save（主脚本内部用命令名调用）
# shellcheck disable=SC2329
iptables-save() { iptables_save_mock "$@"; }

detect_wait_support
reset_probe_cache
IPT=(iptables)
IPT6=(ip6tables)
# IPT / IPT6 由主脚本内部函数使用，这里显式引用一次，避免 SC2034 误报
: "${IPT[0]}" "${IPT6[0]}"

# ------------------------------------------------------------ 1. 输入校验 ----
printf '\n%b\n' "$(dim '1. 输入校验')"
assert_eq "端口 80 合法"           "0" "$(valid_port_spec 80; echo $?)"
assert_eq "端口 80,443 合法"       "0" "$(valid_port_spec '80,443'; echo $?)"
assert_eq "端口 8000-8100 合法"    "0" "$(valid_port_spec '8000-8100'; echo $?)"
assert_eq "端口 70000 非法"        "1" "$(valid_port_spec 70000; echo $?)"
assert_eq "端口 abc 非法"          "1" "$(valid_port_spec abc; echo $?)"
assert_eq "端口 90-80 非法(逆序)"  "1" "$(valid_port_spec '90-80'; echo $?)"
assert_eq "端口空串非法"           "1" "$(valid_port_spec ''; echo $?)"

assert_eq "地址 1.2.3.4 合法"      "0" "$(valid_ip_spec 1.2.3.4; echo $?)"
assert_eq "网段 10.0.0.0/8 合法"   "0" "$(valid_ip_spec 10.0.0.0/8; echo $?)"
assert_eq "地址 999.1.1.1 非法"    "1" "$(valid_ip_spec 999.1.1.1; echo $?)"
assert_eq "掩码 /33 非法"          "1" "$(valid_ip_spec 1.2.3.4/33; echo $?)"

assert_eq "22 被 20:25 覆盖"       "0" "$(port_spec_covers '20:25' 22; echo $?)"
assert_eq "80 被 80,443 覆盖"      "0" "$(port_spec_covers '80,443' 80; echo $?)"
assert_eq "22 不被 8000:8100 覆盖" "1" "$(port_spec_covers '8000:8100' 22; echo $?)"

# ------------------------------------------------------------ 2. 显示对齐 ----
printf '\n%b\n' "$(dim '2. 显示宽度与对齐')"
assert_eq "主机名 显示宽度=6"      "6"  "$(disp_width '主机名')"
assert_eq "iptables 显示宽度=8"    "8"  "$(disp_width 'iptables')"
assert_eq "状态概览 显示宽度=8"    "8"  "$(disp_width '状态概览')"
assert_eq "pad_right 补齐到 10"    "10" "$(disp_width "$(pad_right '中文' 10)")"
assert_eq "超长内容不截断"         "12" "$(disp_width "$(pad_right 'abcdefghijkl' 10)")"

# ------------------------------------------------------------ 3. 命令高亮 ----
printf '\n%b\n' "$(dim '3. 命令语法高亮')"
C_RED=$'\e[1;31m'; C_GREEN=$'\e[1;32m'; C_YELLOW=$'\e[1;33m'
C_MAGENTA=$'\e[1;35m'; C_CYAN=$'\e[1;36m'; C_WHITE=$'\e[1;37m'
C_BLUE=$'\e[1;34m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'; C_RESET=$'\e[0m'
# C_BLUE / C_DIM / C_RESET 由 render_cmd 等主脚本函数消费，此处显式引用避免 SC2034
: "${C_BLUE}${C_DIM}${C_RESET}"

hl="$(render_cmd iptables -A INPUT -p tcp --dport 80 -j ACCEPT)"
assert_contains "命令名白色加粗"      "${hl}" "${C_WHITE}${C_BOLD}iptables"
assert_contains "选项洋红"            "${hl}" "${C_MAGENTA}-A"
assert_contains "链名青色"            "${hl}" "${C_CYAN}INPUT"
assert_contains "ACCEPT 绿色"         "${hl}" "${C_GREEN}ACCEPT"
assert_contains "端口黄色"            "${hl}" "${C_YELLOW}80"

hl2="$(render_cmd iptables -A INPUT -s 1.2.3.4 -j DROP)"
assert_contains "DROP 红色"           "${hl2}" "${C_RED}DROP"

hl3="$(render_cmd iptables -A INPUT -m comment --comment '封禁 攻击IP' -j DROP)"
assert_contains "含空格参数自动加引号" "${hl3}" '"封禁 攻击IP"'

# ------------------------------------------------------------ 4. 交互流程 ----
printf '\n%b\n' "$(dim '4. 交互流程生成的命令')"

: >"${MOCK_LOG}"
printf '1\ntcp\n8080\n\n\nWeb后端\n\n0\n' | menu_add >/dev/null 2>&1
calls="$(cat "${MOCK_LOG}")"
assert_contains "放行端口 8080"   "${calls}" "-A INPUT -p tcp --dport 8080"
assert_contains "带备注 comment"  "${calls}" "--comment Web后端"
assert_contains "目标为 ACCEPT"   "${calls}" "-j ACCEPT"

: >"${MOCK_LOG}"
printf '1\ntcp\nabc\n99999\n8000-8010\n\n\n\n\n0\n' | menu_add >/dev/null 2>&1
calls="$(cat "${MOCK_LOG}")"
assert_contains "输错重试后端口范围规范化" "${calls}" "--dport 8000:8010"
assert_not_contains "非法输入未被执行"     "${calls}" "--dport abc"

: >"${MOCK_LOG}"
printf '1\nINPUT\n3\ny\n\n' | menu_delete >/dev/null 2>&1
calls="$(cat "${MOCK_LOG}")"
assert_contains "按编号删除第 3 条" "${calls}" "-D INPUT -s 1.2.3.4 -j DROP"

: >"${MOCK_LOG}"
printf 'y\n\n' | preset_ssh >/dev/null 2>&1
calls="$(cat "${MOCK_LOG}")"
assert_contains "预设写入 ESTABLISHED" "${calls}" "--ctstate ESTABLISHED,RELATED"
assert_contains "预设放行 SSH"         "${calls}" "--dport 22 -j ACCEPT"
assert_contains "预设设置 INPUT DROP"  "${calls}" "-P INPUT DROP"

: >"${MOCK_LOG}"
printf '2\ntcp\n22\n\nDROP\nn\n\n0\n' | menu_add >/dev/null 2>&1
calls="$(cat "${MOCK_LOG}")"
assert_not_contains "拒绝 SSH 端口时默认取消" "${calls}" "-j DROP"

# --------------------------------------------------------------- 5. CLI -----
printf '\n%b\n' "$(dim '5. 命令行入口')"
assert_contains "版本输出"     "$(bash "${WIZARD}" --version 2>&1)" "iptables-wizard"
assert_contains "帮助输出"     "$(bash "${WIZARD}" --help 2>&1)"    "用法"
assert_contains "未知命令报错" "$(bash "${WIZARD}" nonsense 2>&1)"  "未知命令"

# ---------------------------------------------------------------- 汇总 -------
printf '\n%b\n' '────────────────────────────────────────────────────────'
if (( FAIL == 0 )); then
  printf '  %s 全部通过：%d 项\n\n' "$(green '✔')" "${PASS}"
  exit 0
fi
printf '  %s 失败 %d 项 / 共 %d 项\n' "$(red '✘')" "${FAIL}" "$((PASS + FAIL))"
for n in "${FAILED_NAMES[@]}"; do printf '     - %s\n' "${n}"; done
printf '\n'
exit 1
