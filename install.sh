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
BUILD_DATE="2026-11-01 12:08:34"
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
383bcd5035edb483c207782c0827db510adcaa84389785a305d4ab556ddcb8df  README.md
a2e6269f4c000f2fb3a2e230743e6eb66e1b41587ab095965ba0f9df8bef65fe  使用文档.md
991bf6f69832f0294f09dd4dbced573d2ff8a3217a5f79de30d38f3e15c4b01e  Debian SSH/README.md
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
        # 分类索引（README 里的相对链接依赖这个目录结构）
        if [[ -f "$tmp/Debian SSH/README.md" ]]; then
            mkdir -p "$DIR/Debian SSH"
            cp -f "$tmp/Debian SSH/README.md" "$DIR/Debian SSH/" 2>/dev/null || true
        fi
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
