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
BUILD_DATE="2026-11-01 11:10:02"
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
8ca43086ff48c1de607c4940ad6d8d21e07684e6c5e6a0b140ed24eb82d51d18  check.sh
6a5d5af2db40ae3df8a482fedeb0cdc7040d79c0aecea3a7426c140ebd45efa2  .shellcheckrc
9ee96e4d7dc284ebe5cebd98678e0cd9a8407760b472ddc8f8f4f5a2ba940b76  README.md
22700292ffa4db9ccdeea73cb087cccf98681daa8037b0781412fa6fa418c0e9  使用文档.md
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
