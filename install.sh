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
BUILD_DATE="2026-11-01 12:03:26"
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
Jp7/D4kXKRYA8AAA
__PAYLOAD_EOF__
)"

MANIFEST="$(cat <<'__MANIFEST_EOF__'
0c718ffc7928c5fc8ba5af7b7671bfad9643e37ef7df1a52812112e95066de63  change_ssh_port.sh
876b8acbd61232233b49367a6de6718498b8336f8ddb6a3928ebb642499def9b  remove_old_ssh_port.sh
8ca43086ff48c1de607c4940ad6d8d21e07684e6c5e6a0b140ed24eb82d51d18  check.sh
6a5d5af2db40ae3df8a482fedeb0cdc7040d79c0aecea3a7426c140ebd45efa2  .shellcheckrc
9ee96e4d7dc284ebe5cebd98678e0cd9a8407760b472ddc8f8f4f5a2ba940b76  README.md
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
