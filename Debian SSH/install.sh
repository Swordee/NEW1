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
#   curl -fsSL https://cdn.jsdelivr.net/gh/Swordee/NEW1@v2.6/Debian%20SSH/install.sh | sudo bash
#
# 安装完成后，终端里输入 sshh 即可打开交互面板（不占用系统 ssh 命令）。

set -euo pipefail

VERSION="1.1.0"
BUILD_DATE="2026-11-02 21:39:30"
DEFAULT_DIR="/opt/ssh-port-tools"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

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
      --no-alias    不向 ~/.bashrc / ~/.zshrc 注入 sshh 别名
      --no-doc      不安装文档
      --uninstall   卸载
  -V, --version     显示版本
  -h, --help        显示帮助

安装完成后，在终端里输入 sshh 即可打开交互式管理面板；
系统自带的 ssh 命令完全不受影响（ssh user@host 行为不变）。
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
0a85ea1d4961ab3755c58cf74008f277505864187ca00d002f9c91cb3c5d81db  ssh_menu.sh
81ba01ba36d5befaaa4a8699034758f6727cd8e13ae85cfef01bd9004d5efaa1  ssh-port.sh
7b8b18fca21388df57cb92acf068fc7bd71f79360c6585446301d894b274bc46  check.sh
6a5d5af2db40ae3df8a482fedeb0cdc7040d79c0aecea3a7426c140ebd45efa2  .shellcheckrc
4c189f3dc960faf00251119a94bdb19e50a4fc1c7e10331d08b649c61a1c017d  README.md
b86516ab8e11571aef6f702d018f37aec948ca28c286e1719be26044b6271ae2  使用文档.md
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

# alias 块内容：使用 sshh 作为入口，不覆盖系统自带的 ssh 命令
alias_block() {
    cat <<EOF
${ALIAS_BEGIN}
# Debian SSH 端口管理工具：输入 sshh 打开交互面板
# 刻意不占用 ssh，避免与系统命令冲突；ssh 仍为原生客户端，行为不变
# 如需直接运行面板而不依赖别名：ssh-port
alias sshh='ssh-port'
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

    ok "已注入 sshh 别名（重新打开终端或执行 source ~/.bashrc 生效）"
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
        info "已跳过 sshh 别名注入（--no-alias）"
    fi

    ok "安装完成：$DIR"
    echo
    echo -e "${BOLD}接下来怎么用：${NC}"
    echo -e "  ${GREEN}sshh${NC}                  打开交互式管理面板（推荐）"
    echo -e "  ${GREEN}ssh-port-menu${NC}         同上，直接命令"
    echo -e "  ${GREEN}sudo ssh-port-change${NC}  直接更换端口"
    echo
    echo -e "${DIM}提示：重新打开一个终端，或执行 source ~/.bashrc 让 sshh 生效。${NC}"
    echo -e "${DIM}      系统自带的 ssh 命令不受影响：ssh user@host 仍是原生客户端。${NC}"
    echo -e "${DIM}      若之前装过旧版（占用过 ssh），当前终端可执行 unalias ssh 清除残留。${NC}"
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
