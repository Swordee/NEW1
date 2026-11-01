#!/usr/bin/env bash
#
# install.sh —— Debian SSH 端口更换工具 · 自解压一键安装器
#
# 本文件内嵌全部脚本负载（base64 + tar.gz），可单文件分发，无需额外下载。
#
# 远程一键执行：
#   curl -fsSL https://your.host/install.sh | sudo bash
#   curl -fsSL https://your.host/install.sh | sudo bash -s -- -y --run
#
# 本地执行：
#   sudo bash install.sh
#   sudo bash install.sh -d /usr/local/lib/ssh-port-tools -y
#
# 选项：
#   -d, --dir DIR     安装目录（默认 /opt/ssh-port-tools）
#   -y, --yes         非交互，全部使用默认值
#       --run         安装完成后立即运行「更换端口」脚本
#       --no-doc      不安装文档（README / 使用文档）
#       --uninstall   卸载（删除安装目录与命令软链）
#   -V, --version     显示版本
#   -h, --help        显示帮助
#
# 注意：修改 SSH 端口需要 root，请用 sudo 执行。

set -euo pipefail

VERSION="1.0.0"
BUILD_DATE="2026-11-01 12:20:40"
DEFAULT_DIR="/opt/ssh-port-tools"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info() { echo -e "${CYAN}[信息]${NC} $*"; }
ok()   { echo -e "${GREEN}[完成]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
err()  { echo -e "${RED}[错误]${NC} $*"; }
die()  { err "$*"; exit 1; }

# 交互读取：stdin 不是终端时（curl | bash）改从 /dev/tty 读取
# 用子 shell 探测 /dev/tty 是否真可用，避免 "No such device or address" 噪音
_tty_ok() { { : < /dev/tty; } 2>/dev/null; }

prompt() {
    local __text="$1" __ans=""
    if [[ -t 0 ]]; then
        read -r -p "$__text" __ans
    elif _tty_ok; then
        { read -r -p "$__text" __ans < /dev/tty; } 2>/dev/null
    else
        return 1
    fi
    printf '%s' "$__ans"
}

usage() {
    cat <<EOF
Debian SSH 端口更换工具 · 自解压安装器 v${VERSION}

用法: sudo bash install.sh [选项]

选项:
  -d, --dir DIR     安装目录（默认 ${DEFAULT_DIR}）
  -y, --yes         非交互，全部使用默认值
      --run         安装完成后立即运行「更换端口」脚本
      --no-doc      不安装文档
      --uninstall   卸载
  -V, --version     显示版本
  -h, --help        显示帮助
EOF
}

# ---------- 参数 ----------
DIR="$DEFAULT_DIR"
ASSUME_YES=0
RUN_AFTER=0
NO_DOC=0
DO_UNINSTALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)
            [[ -n "${2:-}" ]] || die "选项 $1 需要一个目录参数"
            DIR="$2"; shift 2 ;;
        -y|--yes)     ASSUME_YES=1; shift ;;
        --run)        RUN_AFTER=1; shift ;;
        --no-doc)     NO_DOC=1; shift ;;
        --uninstall)  DO_UNINSTALL=1; shift ;;
        -V|--version) echo "install.sh v${VERSION} (built ${BUILD_DATE})"; exit 0 ;;
        -h|--help)    usage; exit 0 ;;
        *)            err "未知参数: $1"; echo; usage; exit 1 ;;
    esac
done

# ---------- 内嵌负载（勿手工修改，由 build_install.py 生成）----------
PAYLOAD_B64="$(cat <<'__PAYLOAD_EOF__'
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
__PAYLOAD_EOF__
)"

MANIFEST="$(cat <<'__MANIFEST_EOF__'
0c718ffc7928c5fc8ba5af7b7671bfad9643e37ef7df1a52812112e95066de63  change_ssh_port.sh
876b8acbd61232233b49367a6de6718498b8336f8ddb6a3928ebb642499def9b  remove_old_ssh_port.sh
7b8b18fca21388df57cb92acf068fc7bd71f79360c6585446301d894b274bc46  check.sh
6a5d5af2db40ae3df8a482fedeb0cdc7040d79c0aecea3a7426c140ebd45efa2  .shellcheckrc
aae882ebe9f8ff67c60c010c4ed8c1912ee493232350a3b7bf5e53e9e54fd34e  README.md
a2e6269f4c000f2fb3a2e230743e6eb66e1b41587ab095965ba0f9df8bef65fe  使用文档.md
__MANIFEST_EOF__
)"

# ---------- 工具函数 ----------
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        return 1
    fi
}

decode_payload() {
    local dest="$1"
    # 优先 GNU base64 -d，失败则回退 BSD base64 -D
    if printf '%s' "$PAYLOAD_B64" | base64 -d 2>/dev/null | tar -xzf - -C "$dest" 2>/dev/null; then
        return 0
    fi
    printf '%s' "$PAYLOAD_B64" | base64 -D 2>/dev/null | tar -xzf - -C "$dest" 2>/dev/null
}

verify_payload() {
    local dest="$1" line sum name actual fail=0
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi
        sum="${line%%  *}"
        name="${line#*  }"
        if ! actual="$(sha256_of "$dest/$name")"; then
            warn "缺少 sha256sum/shasum，跳过完整性校验"
            return 0
        fi
        if [[ "$sum" != "$actual" ]]; then
            err "校验失败: $name"
            fail=1
        fi
    done <<< "$MANIFEST"
    return "$fail"
}

# ---------- 安装 / 卸载 ----------
do_install() {
    [[ -n "$DIR" && "$DIR" != "/" ]] || die "安装目录非法: '$DIR'"
    mkdir -p "$DIR" || die "无法创建目录 $DIR"

    local tmp
    tmp="$(mktemp -d)" || die "无法创建临时目录"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT

    info "解压安装包 ..."
    decode_payload "$tmp" || die "解压失败（base64/tar 不可用？）"

    info "校验文件完整性 ..."
    verify_payload "$tmp" || die "完整性校验失败，已中止"

    info "安装到 $DIR ..."
    cp -f "$tmp/change_ssh_port.sh"     "$DIR/" || die "复制 change_ssh_port.sh 失败"
    cp -f "$tmp/remove_old_ssh_port.sh" "$DIR/" || die "复制 remove_old_ssh_port.sh 失败"
    cp -f "$tmp/check.sh"               "$DIR/" || die "复制 check.sh 失败"
    cp -f "$tmp/.shellcheckrc"          "$DIR/" 2>/dev/null || true
    chmod 755 "$DIR/change_ssh_port.sh" "$DIR/remove_old_ssh_port.sh" "$DIR/check.sh"

    if [[ $NO_DOC -eq 0 ]]; then
        cp -f "$tmp/README.md"   "$DIR/" 2>/dev/null || true
        cp -f "$tmp/使用文档.md" "$DIR/" 2>/dev/null || true
        chmod 644 "$DIR"/*.md 2>/dev/null || true
    fi

    # 命令软链
    if [[ -d /usr/local/bin && -w /usr/local/bin ]]; then
        ln -sf "$DIR/change_ssh_port.sh"     /usr/local/bin/ssh-port-change
        ln -sf "$DIR/remove_old_ssh_port.sh" /usr/local/bin/ssh-port-remove
        ok "已创建命令：ssh-port-change / ssh-port-remove"
    else
        warn "未创建 /usr/local/bin 软链（目录不可写）"
    fi

    ok "安装完成：$DIR"
    echo
    echo "使用方式："
    echo "  sudo bash $DIR/change_ssh_port.sh"
    echo "  sudo bash $DIR/remove_old_ssh_port.sh"
    echo "  sudo bash $DIR/check.sh"
}

do_uninstall() {
    [[ -n "$DIR" && "$DIR" != "/" ]] || die "安装目录非法: '$DIR'"
    rm -f /usr/local/bin/ssh-port-change /usr/local/bin/ssh-port-remove
    if [[ -d "$DIR" ]]; then
        rm -rf "$DIR"
        ok "已删除 $DIR"
    else
        info "目录不存在：$DIR"
    fi
    ok "卸载完成"
}

# ---------- 主流程 ----------
main() {
    echo -e "${BOLD}==================================================${NC}"
    echo -e "${BOLD}   SSH 端口更换工具 · 安装器 v${VERSION}${NC}"
    echo -e "${BOLD}==================================================${NC}"
    echo

    [[ $EUID -eq 0 ]] || die "请使用 root 运行（sudo bash install.sh）"
    [[ "$(uname -s)" == "Linux" ]] || warn "当前系统非 Linux，可能不适用"
    command -v tar    >/dev/null 2>&1 || die "缺少 tar"
    command -v base64 >/dev/null 2>&1 || die "缺少 base64"

    if [[ $DO_UNINSTALL -eq 1 ]]; then
        do_uninstall
        return 0
    fi

    if [[ $ASSUME_YES -ne 1 ]]; then
        local ans
        ans="$(prompt "将安装到 ${DIR}，继续？(Y/n) ")" || ans=""
        case "$ans" in
            [nN]) info "已取消"; exit 0 ;;
        esac
    fi

    do_install

    if [[ $RUN_AFTER -eq 1 ]]; then
        echo
        info "启动更换端口脚本 ..."
        exec bash "$DIR/change_ssh_port.sh"
    fi
}

main "$@"
