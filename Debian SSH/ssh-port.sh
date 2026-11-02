#!/usr/bin/env bash
#
# ssh-port.sh —— Debian SSH 端口工具 · 命令包装器 (v2.8)
#
# 行为约定：
#
#   ssh-port                    → 打开交互式管理面板（无参数）
#   ssh-port user@host          → 完全等价于原生 ssh，转发所有参数
#   ssh-port -p 2222 root@host  → 同上，带端口/选项也照常转发
#
# 安装器会向 ~/.bashrc、~/.zshrc 注入：
#   alias sshh='ssh-port'
# 于是：
#   sshh                → 打开管理面板
#   sshh root@1.2.3.4   → 转发到原生 SSH 客户端
#
# 设计要点：刻意不占用 ssh 这个名字，避免与系统命令冲突。
# 系统自带的 ssh 始终原封不动，ssh user@host 行为与安装前完全一致。
#
# 如需绕过别名直接运行面板：ssh-port 或 ssh-port-menu

set -uo pipefail

readonly SCRIPT_VERSION="2.8"

# ---------- 定位真实安装目录（跟随软链） ----------
resolve_dir() {
    local src="${BASH_SOURCE[0]}" dir
    while [[ -L "$src" ]]; do
        dir="$(cd -P "$(dirname "$src")" 2>/dev/null && pwd)"
        src="$(readlink "$src")"
        if [[ "$src" != /* ]]; then
            src="$dir/$src"
        fi
    done
    (cd -P "$(dirname "$src")" 2>/dev/null && pwd) || return 1
}

TOOL_DIR="$(resolve_dir)" || TOOL_DIR="$(pwd)"

# ---------- 定位原生 ssh 客户端 ----------
# 依次尝试常见路径；跳过指向本工具自身的软链，避免无限递归
find_real_ssh() {
    local candidate resolved
    for candidate in /usr/bin/ssh /bin/ssh /usr/local/bin/ssh /usr/local/sbin/ssh; do
        [[ -x "$candidate" ]] || continue
        if [[ -L "$candidate" ]]; then
            resolved="$(readlink -f "$candidate" 2>/dev/null || true)"
            # 指向本工具自身的链接 → 跳过
            if [[ "$resolved" == "$TOOL_DIR"/* ]]; then
                continue
            fi
        fi
        printf '%s' "$candidate"
        return 0
    done
    # 兜底：在 PATH 中查找，但排除自身目录
    local IFS=':'
    local p
    for p in $PATH; do
        [[ -z "$p" ]] && continue
        candidate="$p/ssh"
        [[ -x "$candidate" ]] || continue
        resolved="$(readlink -f "$candidate" 2>/dev/null || true)"
        if [[ "$resolved" == "$TOOL_DIR"/* ]]; then
            continue
        fi
        printf '%s' "$candidate"
        return 0
    done
    return 1
}

usage() {
    cat <<EOF
Debian SSH 端口工具包装器 v${SCRIPT_VERSION}

用法:
  ssh-port                 打开交互式管理面板（无参数时）
  ssh-port <ssh参数...>    完全等价于原生 ssh（原样透传）

说明:
  安装器已注入 alias sshh='ssh-port'，因此终端里输入 sshh 即可打开面板；
  系统自带的 ssh 命令完全不受影响，ssh user@host 行为与安装前一致。

  本包装器自有选项（不会与 ssh 参数冲突）:
    --menu           打开管理面板
    --tool-version   显示本工具版本
    --tool-help      显示本帮助

  直接运行面板（不依赖别名）:
    ssh-port
    ssh-port-menu
EOF
}

main() {
    # 无参数 → 打开交互面板
    if [[ $# -eq 0 ]]; then
        local menu="$TOOL_DIR/ssh_menu.sh"
        if [[ ! -f "$menu" ]]; then
            printf '[错误] 未找到面板脚本: %s\n' "$menu" >&2
            return 1
        fi
        exec bash "$menu" --menu
    fi

    # 仅识别本工具自有选项；其余一律原样转发，绝不截获 ssh 的参数
    # （例如 ssh -V 必须显示 OpenSSH 版本，而不是本工具版本）
    case "$1" in
        --menu)
            local menu="$TOOL_DIR/ssh_menu.sh"
            if [[ ! -f "$menu" ]]; then
                printf '[错误] 未找到面板脚本: %s\n' "$menu" >&2
                return 1
            fi
            exec bash "$menu" --menu
            ;;
        --tool-version)
            printf 'ssh-port.sh v%s\n' "$SCRIPT_VERSION"
            return 0 ;;
        --tool-help)
            usage
            return 0 ;;
    esac

    # 带参数 → 转发原生 ssh
    local real
    real="$(find_real_ssh)" || {
        printf '[错误] 未找到原生 ssh 客户端，请确认已安装 openssh-client。\n' >&2
        return 127
    }
    exec "$real" "$@"
}

main "$@"
