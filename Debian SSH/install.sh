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
#       --menu        安装完成后直接打开交互面板（推荐）
#       --no-alias    不向 ~/.bashrc / ~/.zshrc 注入 ssh 别名
#       --no-doc      不安装文档（README / 使用文档）
#       --uninstall   卸载（删除安装目录与命令软链）
#   -V, --version     显示版本
#   -h, --help        显示帮助
#
# 注意：修改 SSH 端口需要 root，请用 sudo 执行。
#
# 远程一键安装（推荐）：
#   curl -fsSL https://cdn.jsdelivr.net/gh/Swordee/NEW1@v2.5/Debian%20SSH/install.sh | sudo bash
#
# 安装完成后，终端里直接输入 ssh 即可打开交互面板。

set -euo pipefail

VERSION="1.1.0"
BUILD_DATE="2026-11-02 20:28:09"
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
      --menu        安装完成后直接打开交互面板（推荐）
      --no-alias    不向 ~/.bashrc / ~/.zshrc 注入 ssh 别名
      --no-doc      不安装文档
      --uninstall   卸载
  -V, --version     显示版本
  -h, --help        显示帮助

安装完成后，在终端里直接输入 ssh 即可打开交互式管理面板；
带参数的用法（ssh user@host）仍由原生 SSH 客户端处理，行为不变。
EOF
}

# ---------- 参数 ----------
DIR="$DEFAULT_DIR"
ASSUME_YES=0
RUN_AFTER=0
NO_DOC=0
DO_UNINSTALL=0
NO_ALIAS=0
MENU_AFTER=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)
            [[ -n "${2:-}" ]] || die "选项 $1 需要一个目录参数"
            DIR="$2"; shift 2 ;;
        -y|--yes)     ASSUME_YES=1; shift ;;
        --run)        RUN_AFTER=1; shift ;;
        --menu)       MENU_AFTER=1; shift ;;
        --no-alias)   NO_ALIAS=1; shift ;;
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
70cc099c66db58e1c983ab15129a934556c9ba8af1d1299c4850d17452ab9da2  ssh_menu.sh
72146cebeb83e6d10bd136a191073313a2527f9c791135c40abf9cb8d93fc5b5  ssh-port.sh
7b8b18fca21388df57cb92acf068fc7bd71f79360c6585446301d894b274bc46  check.sh
6a5d5af2db40ae3df8a482fedeb0cdc7040d79c0aecea3a7426c140ebd45efa2  .shellcheckrc
1e6508145c1c667e1a3e8f36590fd06d8d838f46751eab6235266a12544aa5b6  README.md
56166d47ff4528fcb422f159b7059d7d5aa240b1b6b1a8bb432e40c131c71bba  使用文档.md
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

# 创建临时目录（仅面向 Linux：mktemp -d 返回标准 POSIX 路径）
make_tmpdir() {
    mktemp -d
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

# ---------- 别名注入 ----------
ALIAS_BEGIN="# >>> ssh-port-tool >>>"
ALIAS_END="# <<< ssh-port-tool <<<"

# alias 块内容：只对交互式 shell 生效，且带参数的 ssh 仍走原生客户端
alias_block() {
    cat <<EOF
${ALIAS_BEGIN}
# Debian SSH 端口管理工具：直接输入 ssh 打开交互面板
# 带参数时（ssh user@host）仍由原生 SSH 客户端处理，行为不变
# 如需完全绕过别名：command ssh user@host
alias ssh='ssh-port'
${ALIAS_END}
EOF
}

# 向指定 rc 文件注入 alias 块（幂等：已存在则先移除旧块）
inject_alias() {
    local rc="$1"
    [[ -n "$rc" ]] || return 0
    # 只处理真实存在的 rc 文件，避免凭空创建 .bashrc
    [[ -f "$rc" ]] || return 0
    # 已存在旧块 → 先删除，保证幂等
    if grep -qF "$ALIAS_BEGIN" "$rc" 2>/dev/null; then
        sed -i "\|^${ALIAS_BEGIN}\$|,\|^${ALIAS_END}\$|d" "$rc" 2>/dev/null || true
    fi
    printf '\n%s\n' "$(alias_block)" >> "$rc"
}

remove_alias() {
    local rc
    for rc in "$@"; do
        [[ -f "$rc" ]] || continue
        if grep -qF "$ALIAS_BEGIN" "$rc" 2>/dev/null; then
            sed -i "\|^${ALIAS_BEGIN}\$|,\|^${ALIAS_END}\$|d" "$rc" 2>/dev/null || true
            ok "已清理别名配置：$rc"
        fi
    done
}

install_alias() {
    local target_home="${SUDO_USER:-$HOME}"
    [[ -n "$target_home" ]] || target_home="$HOME"

    # 当前登录用户 + root，各家 shell 配置都处理
    local homes=() rc
    homes+=("$target_home")
    if [[ "$target_home" != "/root" ]]; then
        homes+=("/root")
    fi

    local home
    for home in "${homes[@]}"; do
        [[ -d "$home" ]] || continue
        for rc in "$home/.bashrc" "$home/.zshrc"; do
            inject_alias "$rc"
        done
    done

    ok "已注入 ssh 别名（重新打开终端或执行 source ~/.bashrc 生效）"
}

# ---------- 安装 / 卸载 ----------
do_install() {
    [[ -n "$DIR" && "$DIR" != "/" ]] || die "安装目录非法: '$DIR'"
    mkdir -p "$DIR" || die "无法创建目录 $DIR"

    local tmp
    tmp="$(make_tmpdir)" || die "无法创建临时目录"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT

    info "解压安装包 ..."
    decode_payload "$tmp" || die "解压失败（base64/tar 不可用？）"

    # 解压结果自检：核心脚本必须到位
    local core
    for core in change_ssh_port.sh remove_old_ssh_port.sh ssh_menu.sh ssh-port.sh; do
        [[ -f "$tmp/$core" ]] || die "解压结果不完整，缺少 $core"
    done

    info "校验文件完整性 ..."
    verify_payload "$tmp" || die "完整性校验失败，已中止"

    info "安装到 $DIR ..."
    cp -f "$tmp/change_ssh_port.sh"     "$DIR/" || die "复制 change_ssh_port.sh 失败"
    cp -f "$tmp/remove_old_ssh_port.sh" "$DIR/" || die "复制 remove_old_ssh_port.sh 失败"
    cp -f "$tmp/ssh_menu.sh"            "$DIR/" || die "复制 ssh_menu.sh 失败"
    cp -f "$tmp/ssh-port.sh"            "$DIR/" || die "复制 ssh-port.sh 失败"
    cp -f "$tmp/check.sh"               "$DIR/" || die "复制 check.sh 失败"
    cp -f "$tmp/.shellcheckrc"          "$DIR/" 2>/dev/null || true
    chmod 755 "$DIR/change_ssh_port.sh" "$DIR/remove_old_ssh_port.sh" \
             "$DIR/ssh_menu.sh" "$DIR/ssh-port.sh" "$DIR/check.sh"

    if [[ $NO_DOC -eq 0 ]]; then
        cp -f "$tmp/README.md"   "$DIR/" 2>/dev/null || true
        cp -f "$tmp/使用文档.md" "$DIR/" 2>/dev/null || true
        chmod 644 "$DIR"/*.md 2>/dev/null || true
    fi

    # 命令软链
    if [[ -d /usr/local/bin && -w /usr/local/bin ]]; then
        ln -sf "$DIR/change_ssh_port.sh"     /usr/local/bin/ssh-port-change
        ln -sf "$DIR/remove_old_ssh_port.sh" /usr/local/bin/ssh-port-remove
        ln -sf "$DIR/ssh-port.sh"            /usr/local/bin/ssh-port
        ln -sf "$DIR/ssh_menu.sh"            /usr/local/bin/ssh-port-menu
        ok "已创建命令：ssh-port / ssh-port-menu / ssh-port-change / ssh-port-remove"
    else
        warn "未创建 /usr/local/bin 软链（目录不可写）"
    fi

    # 别名注入
    if [[ $NO_ALIAS -eq 0 ]]; then
        install_alias
    else
        info "已跳过 ssh 别名注入（--no-alias）"
    fi

    ok "安装完成：$DIR"
    echo
    echo -e "${BOLD}接下来怎么用：${NC}"
    echo -e "  ${GREEN}ssh${NC}                 打开交互式管理面板（推荐）"
    echo -e "  ${GREEN}ssh-port-menu${NC}      同上，直接命令"
    echo -e "  ${GREEN}sudo ssh-port-change${NC}  直接更换端口"
    echo
    echo -e "${DIM}提示：重新打开一个终端，或执行 source ~/.bashrc 让别名生效。${NC}"
    echo -e "${DIM}      带参数用法不受影响：ssh user@host 仍然是原生 SSH 客户端。${NC}"
}

do_uninstall() {
    [[ -n "$DIR" && "$DIR" != "/" ]] || die "安装目录非法: '$DIR'"
    rm -f /usr/local/bin/ssh-port /usr/local/bin/ssh-port-menu \
          /usr/local/bin/ssh-port-change /usr/local/bin/ssh-port-remove

    local target_home="${SUDO_USER:-$HOME}"
    local homes=() rc
    homes+=("${target_home:-/root}")
    if [[ "${target_home:-/root}" != "/root" ]]; then
        homes+=("/root")
    fi
    local home
    for home in "${homes[@]}"; do
        [[ -d "$home" ]] || continue
        for rc in "$home/.bashrc" "$home/.zshrc"; do
            remove_alias "$rc"
        done
    done

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
    [[ "$(uname -s)" == "Linux" ]] || die "本工具仅支持 Linux（Debian/Ubuntu 等）"
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

    if [[ $MENU_AFTER -eq 1 ]]; then
        echo
        info "启动交互式管理面板 ..."
        exec bash "$DIR/ssh_menu.sh" --menu
    fi

    if [[ $RUN_AFTER -eq 1 ]]; then
        echo
        info "启动更换端口脚本 ..."
        exec bash "$DIR/change_ssh_port.sh"
    fi
}

main "$@"
