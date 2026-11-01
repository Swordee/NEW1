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
BUILD_DATE="2026-11-01 12:10:24"
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
cec9e1e2b6008d5bc5b3b5ec35de57e71d82ff28453adf1ce7e43bfc10a60399  README.md
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
