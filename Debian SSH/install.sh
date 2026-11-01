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
BUILD_DATE="2026-11-01 12:22:09"
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
z9bnTX7+P4Zk3dsA8AAA
__PAYLOAD_EOF__
)"

MANIFEST="$(cat <<'__MANIFEST_EOF__'
0c718ffc7928c5fc8ba5af7b7671bfad9643e37ef7df1a52812112e95066de63  change_ssh_port.sh
876b8acbd61232233b49367a6de6718498b8336f8ddb6a3928ebb642499def9b  remove_old_ssh_port.sh
7b8b18fca21388df57cb92acf068fc7bd71f79360c6585446301d894b274bc46  check.sh
6a5d5af2db40ae3df8a482fedeb0cdc7040d79c0aecea3a7426c140ebd45efa2  .shellcheckrc
1f931de20a62a1ab6e7cca30af65c99ce2c4c8498cf08ab76de6b657328f3d29  README.md
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
