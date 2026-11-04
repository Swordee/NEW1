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
VERSION="@VERSION@"
PAYLOAD_SHA256="@SHA256@"
DEFAULT_PREFIX="/usr/local"

# ------------------------------------------------------------------------------
# 内嵌负载（gzip + base64），由 scripts/build-install.sh 自动生成，请勿手工编辑
# ------------------------------------------------------------------------------
PAYLOAD_B64='
@PAYLOAD@
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
