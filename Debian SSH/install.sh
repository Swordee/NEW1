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
BUILD_DATE="2026-11-01 12:14:49"
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
W8/Ws/VsPVvP1vM6nv8P2ZEXhwDwAAA=
__PAYLOAD_EOF__
)"

MANIFEST="$(cat <<'__MANIFEST_EOF__'
0c718ffc7928c5fc8ba5af7b7671bfad9643e37ef7df1a52812112e95066de63  change_ssh_port.sh
876b8acbd61232233b49367a6de6718498b8336f8ddb6a3928ebb642499def9b  remove_old_ssh_port.sh
7b8b18fca21388df57cb92acf068fc7bd71f79360c6585446301d894b274bc46  check.sh
6a5d5af2db40ae3df8a482fedeb0cdc7040d79c0aecea3a7426c140ebd45efa2  .shellcheckrc
f5683b4ce27063a2c9f13a65f33c03b6ce533e43b41371115c86c2b944a63e9a  README.md
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
