#!/usr/bin/env bash
# ==============================================================================
#  iptables-wizard 一键安装器（支持 curl | bash）
# ------------------------------------------------------------------------------
#  用法：
#    curl -fsSL https://example.com/install.sh | sudo bash -s -- --run  # 装完直接进界面
#    curl -fsSL https://example.com/install.sh | sudo bash              # 只安装
#    sudo bash install.sh                                              # 本地执行
#    sudo bash install.sh --prefix /usr                                # 自定义前缀
#    sudo bash install.sh --no-deps                                    # 跳过依赖安装
#    sudo bash install.sh --uninstall                                  # 卸载
#    bash install.sh --check                                           # 只校验内嵌脚本
#    bash install.sh --version | --help
#
#  说明：
#    · 主脚本已 gzip+base64 内嵌在本文件中，无需联网即可安装
#    · 安装阶段全程无交互（不读 stdin），因此可以直接 curl | bash
#    · --run 启动界面时从 /dev/tty 读取输入，不会把管道里的脚本残片当按键
#    · 安装位置：<prefix>/sbin/iptables-wizard，并在 <prefix>/bin 建同名软链
# ==============================================================================
set -euo pipefail

APP="iptables-wizard"
VERSION="1.2.0"
PAYLOAD_SHA256="561b5fe30a8dfd019338892bc68c3081aa029a6fb9edbc811e74547fe985275d"
DEFAULT_PREFIX="/usr/local"

# ------------------------------------------------------------------------------
# 内嵌负载（gzip + base64），由 scripts/build-install.sh 自动生成，请勿手工编辑
# ------------------------------------------------------------------------------
PAYLOAD_B64='
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
43+NVLWnqv4XvLZ5D70nAQA=
'

# ------------------------------------------------------------------ 输出样式 --
if [[ -t 1 ]]; then
  R=$'\e[1;31m'; G=$'\e[1;32m'; Y=$'\e[1;33m'; C=$'\e[1;36m'
  B=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
else
  R=; G=; Y=; C=; B=; D=; N=
fi

info() { printf '  %s %s\n' "${D}·${N}" "$*"; }
ok()   { printf '  %s %s\n' "${G}✔${N}" "$*"; }
warn() { printf '  %s %s\n' "${Y}⚠${N}" "$*"; }
die()  { printf '  %s %s\n' "${R}✘${N}" "$*" >&2; exit 1; }
step() { printf '\n%s\n' "${C}${B}▶ $*${N}"; }

usage() {
  cat <<EOF
${APP} 安装器 v${VERSION}

用法：
  bash install.sh [选项]

选项：
  --prefix DIR     安装前缀，默认 ${DEFAULT_PREFIX}
                   （二进制落在 DIR/sbin，DIR/bin 下建软链）
  --no-deps        跳过依赖安装（默认会装 iptables 与 netfilter-persistent）
  --run            安装完成后立即进入交互式管理界面
  --force          跳过发行版检查（非 Debian 系也能装）
  --uninstall      卸载程序（保留 /etc/iptables-wizard 备份目录）
  --purge          与 --uninstall 一起用，连备份与配置一起删除
  --check          只校验内嵌脚本完整性与版本，不安装
  --version        显示版本
  -h, --help       显示本帮助

示例：
  curl -fsSL https://example.com/install.sh | sudo bash -s -- --run
  sudo bash install.sh --prefix /usr
  sudo bash install.sh --uninstall --purge
EOF
}

need_root() {
  if [[ ${EUID} -ne 0 ]]; then
    die "需要 root 权限：请用 sudo 运行（例如 curl -fsSL ... | sudo bash）"
  fi
}

# ---------------------------------------------------------------- 负载处理 ---
TMP_BIN=""
cleanup() { [[ -n ${TMP_BIN} && -f ${TMP_BIN} ]] && rm -f "${TMP_BIN}" 2>/dev/null || true; }
trap cleanup EXIT

decode_payload() {   # decode_payload 输出文件路径
  local out="$1"
  command -v base64 >/dev/null 2>&1 || die "缺少 base64 命令（apt-get install -y coreutils）"
  command -v gzip   >/dev/null 2>&1 || die "缺少 gzip 命令（apt-get install -y gzip）"
  if ! printf '%s' "${PAYLOAD_B64}" | base64 -d 2>/dev/null | gzip -dc >"${out}" 2>/dev/null; then
    die "内嵌负载解压失败，安装包可能已损坏"
  fi
  [[ -s ${out} ]] || die "内嵌负载为空，安装包可能已损坏"
}

verify_payload() {   # verify_payload 文件路径
  local f="$1" actual=""
  if ! command -v sha256sum >/dev/null 2>&1; then
    warn "缺少 sha256sum，跳过完整性校验"
    return 0
  fi
  actual=$(sha256sum "${f}" | awk '{print $1}')
  if [[ ${actual} != "${PAYLOAD_SHA256}" ]]; then
    die "完整性校验失败：期望 ${PAYLOAD_SHA256:0:16}…，实际 ${actual:0:16}…"
  fi
  ok "完整性校验通过（sha256 ${actual:0:16}…）"
}

prepare_payload() {
  TMP_BIN="$(mktemp /tmp/${APP}.XXXXXX)" || die "无法创建临时文件"
  decode_payload "${TMP_BIN}"
  verify_payload "${TMP_BIN}"
  if ! bash -n "${TMP_BIN}" 2>/dev/null; then
    die "内嵌脚本语法检查失败，安装包可能已损坏"
  fi
  ok "语法检查通过"
}

# ---------------------------------------------------------------- 环境检查 ---
os_id() {
  [[ -r /etc/os-release ]] || { printf 'unknown'; return 0; }
  sed -n 's/^ID=["]\{0,1\}\([^"]*\)["]\{0,1\}$/\1/p' /etc/os-release | head -n 1
}

check_os() {
  local id
  id=$(os_id)
  case "${id}" in
    debian|ubuntu|linuxmint|kali|raspbian|pop|elementary|zorin|deepin|armbian)
      ok "系统检查：${id}" ;;
    *)
      if [[ ${FORCE} == 1 ]]; then
        warn "未识别的发行版（${id:-unknown}），已按 --force 继续"
      else
        warn "本脚本面向 Debian / Ubuntu 系（当前：${id:-unknown}）"
        warn "如确认可用，请加 --force 重新执行"
        exit 1
      fi ;;
  esac
}

# -------------------------------------------------------------- 依赖安装 ---
install_deps() {
  if ! command -v apt-get >/dev/null 2>&1; then
    warn "未找到 apt-get，跳过依赖安装"
    warn "请手动安装：apt-get install -y iptables netfilter-persistent"
    return 0
  fi

  step "安装依赖（iptables / netfilter-persistent）"
  if ! timeout 180 apt-get update -qq; then
    warn "apt-get update 失败或超时，继续尝试安装已有缓存中的包"
  fi

  # iptables 必装；持久化组件在 Debian 上叫 netfilter-persistent，Ubuntu 上有 iptables-persistent
  local need_persist=0 ver=""
  if ! command -v iptables >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive timeout 300 apt-get install -y iptables || warn "iptables 安装失败"
  fi
  if ! command -v netfilter-persistent >/dev/null 2>&1 && ! command -v iptables-persistent >/dev/null 2>&1; then
    need_persist=1
  fi

  if (( need_persist )); then
    if ! DEBIAN_FRONTEND=noninteractive timeout 300 apt-get install -y netfilter-persistent; then
      warn "netfilter-persistent 安装失败，尝试旧包名 iptables-persistent"
      DEBIAN_FRONTEND=noninteractive timeout 300 apt-get install -y iptables-persistent \
        || warn "持久化组件安装失败：重启后规则不会自动恢复（可在界面【2 安装与检测】里补装）"
    fi
  fi

  if command -v iptables >/dev/null 2>&1; then
    ver=$(iptables --version 2>/dev/null | head -n 1) || true
    ok "iptables：${ver}"
  else
    warn "iptables 仍未可用，界面内【2 安装与检测】可重试"
  fi
  if command -v netfilter-persistent >/dev/null 2>&1 || command -v iptables-persistent >/dev/null 2>&1; then
    ok "规则持久化组件已就绪"
  else
    warn "缺少持久化组件，重启后规则不会自动恢复"
  fi
}

# ------------------------------------------------------------------ 安装 -----
do_install() {
  local prefix="$1"

  need_root
  check_os
  prepare_payload

  step "安装程序到 ${prefix}"
  mkdir -p "${prefix}/sbin" "${prefix}/bin"
  install -m 0755 -o root -g root "${TMP_BIN}" "${prefix}/sbin/${APP}" \
    || die "写入 ${prefix}/sbin 失败"
  ok "已安装 ${prefix}/sbin/${APP}"

  # 软链失败不致命：主程序已在 sbin 下，可直接 "${prefix}/sbin/${APP}" 运行
  if ln -sfn "${prefix}/sbin/${APP}" "${prefix}/bin/${APP}" 2>/dev/null; then
    ok "已创建软链 ${prefix}/bin/${APP}"
  else
    warn "无法创建软链 ${prefix}/bin/${APP}（不影响使用）"
    warn "请直接运行：sudo ${prefix}/sbin/${APP}"
  fi

  step "准备数据目录"
  mkdir -p /etc/iptables-wizard/backups
  chmod 700 /etc/iptables-wizard /etc/iptables-wizard/backups 2>/dev/null || true
  ok "备份目录 /etc/iptables-wizard/backups"

  if (( WITH_DEPS )); then
    install_deps
  else
    info "已按 --no-deps 跳过依赖安装"
  fi

  step "安装完成"
  printf '  %s\n' "${B}常用命令：${N}"
  printf '    %s   %s\n' "${C}sudo ${APP}${N}"         "进入交互式管理界面（推荐）"
  printf '    %s   %s\n' "${C}sudo ${APP} doctor${N}"  "环境自检"
  printf '    %s   %s\n' "${C}sudo ${APP} status${N}"  "查看防火墙状态"
  printf '\n'
  case ":${PATH}:" in
    *":${prefix}/bin:"*) : ;;
    *) warn "${prefix}/bin 不在当前 PATH 中，可用完整路径调用：sudo ${prefix}/sbin/${APP}" ;;
  esac
  info "备份目录：/etc/iptables-wizard/backups"
  info "卸载：sudo bash install.sh --uninstall"
  printf '\n'

  if (( RUN_TUI )); then
    launch_tui "${prefix}/sbin/${APP}"
  fi
}

# 启动交互界面：curl | bash 之后 stdin 是管道，必须改从 /dev/tty 读取，否则会读到脚本残片
launch_tui() {
  local bin="$1"
  step "启动交互式管理界面"
  if [[ ! -x ${bin} ]]; then
    warn "找不到可执行的 ${bin}，请手动检查安装结果"
    return 1
  fi
  # 情况一：stdin 本来就是终端，直接启动
  if [[ -t 0 ]]; then
    cleanup
    trap - EXIT
    exec "${bin}"
  fi
  # 情况二：stdin 是管道（curl | bash），改从控制终端读取按键。
  # 注意 /dev/tty 可能存在但打不开（无控制终端的 SSH 会话），必须实际打开一次才算可用
  if ! (: </dev/tty) 2>/dev/null; then
    warn "当前没有可用的终端（/dev/tty 不可用），无法自动进入界面"
    warn "请手动执行：sudo ${APP}"
    return 1
  fi
  cleanup
  trap - EXIT
  exec "${bin}" < /dev/tty
}

do_uninstall() {
  local prefix="$1" target
  need_root
  step "卸载 ${APP}"
  target="${prefix}/sbin/${APP}"
  if [[ -f ${target} ]]; then
    rm -f "${target}"
    ok "已删除 ${target}"
  else
    warn "未找到 ${target}，可能安装在其他前缀（用 --prefix 指定）"
  fi
  if [[ -L ${prefix}/bin/${APP} ]]; then
    rm -f "${prefix}/bin/${APP}"
    ok "已删除软链 ${prefix}/bin/${APP}"
  fi

  if [[ ${PURGE} == 1 ]]; then
    if [[ -d /etc/iptables-wizard ]]; then
      rm -rf /etc/iptables-wizard || warn "删除 /etc/iptables-wizard 失败，请手动清理"
      [[ -d /etc/iptables-wizard ]] || ok "已删除配置与备份 /etc/iptables-wizard"
    fi
    info "系统防火墙规则（/etc/iptables/rules.v4）未删除，如需清理请手动处理"
  else
    info "已保留备份目录 /etc/iptables-wizard（如需一并删除加 --purge）"
  fi
  printf '\n'
}

do_check() {
  step "校验内嵌脚本"
  prepare_payload
  local v
  v=$(bash "${TMP_BIN}" --version 2>/dev/null || printf '未知')
  ok "内嵌脚本版本：${v}"
  info "安装器版本：${VERSION}"
  printf '\n'
}

# ------------------------------------------------------------------ 主流程 ---
PREFIX="${DEFAULT_PREFIX}"
ACTION="install"
FORCE=0
WITH_DEPS=1
RUN_TUI=0
PURGE=0

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --prefix)
        [[ -n ${2:-} ]] || die "--prefix 需要一个目录参数"
        PREFIX="${2%/}"
        shift 2 ;;
      --prefix=*) PREFIX="${1#*=}"; PREFIX="${PREFIX%/}"; shift ;;
      --no-deps)    WITH_DEPS=0; shift ;;
      --with-deps)  WITH_DEPS=1; shift ;;   # 兼容旧写法（已是默认行为）
      --run)        RUN_TUI=1; shift ;;
      --force)      FORCE=1; shift ;;
      --uninstall)  ACTION="uninstall"; shift ;;
      --purge)      PURGE=1; shift ;;
      --check)      ACTION="check"; shift ;;
      --version)    printf '%s %s\n' "${APP}-installer" "${VERSION}"; exit 0 ;;
      -h|--help)    usage; exit 0 ;;
      *)            die "未知参数：$1（用 --help 查看用法）" ;;
    esac
  done
  [[ -n ${PREFIX} ]] || die "--prefix 不能为空"
}

main() {
  parse_args "$@"
  printf '\n%s\n' "${C}${B}╭────────────────────────────────────────────────────╮${N}"
  printf '%s\n'   "${C}${B}│${N}  ${B}${APP}${N} ${D}安装器 v${VERSION}${N}"
  printf '%s\n'   "${C}${B}╰────────────────────────────────────────────────────╯${N}"

  case "${ACTION}" in
    install)   do_install "${PREFIX}" ;;
    uninstall) do_uninstall "${PREFIX}" ;;
    check)     do_check ;;
    *)         die "未知操作：${ACTION}" ;;
  esac
}

main "$@"
