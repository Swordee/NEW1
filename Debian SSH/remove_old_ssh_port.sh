#!/usr/bin/env bash
#
# remove_old_ssh_port.sh —— 过渡期结束后，安全移除旧 SSH 端口的收尾脚本 (v2.8)
#
# 使用场景：
#   在 change_ssh_port.sh 中选择「临时保留旧端口」后，确认新端口登录正常，
#   运行本脚本把旧端口彻底关闭。
#
# v2 改进：
#   + 支持 -p 指定要移除的端口、-y 自动确认、-n 预演
#   + 备份 + sshd -t 校验 + 异常自动回滚
#   + 重启后验证剩余端口仍在监听
#
# 用法：
#   sudo bash remove_old_ssh_port.sh            # 交互
#   sudo bash remove_old_ssh_port.sh -p 22      # 指定移除端口
#   sudo bash remove_old_ssh_port.sh -p 22 -y   # 全自动

set -euo pipefail

readonly SCRIPT_VERSION="2.8"
readonly SSHD_CONFIG="/etc/ssh/sshd_config"
readonly BACKUP_DIR="/etc/ssh/sshd_config_backups"
readonly LOG_FILE="/var/log/change_ssh_port.log"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

info() { echo -e "${CYAN}[信息]${NC} $*"; }
ok()   { echo -e "${GREEN}[完成]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
err()  { echo -e "${RED}[错误]${NC} $*"; }

# 交互读取：stdin 不是终端时（如 curl | bash 管道执行）改从 /dev/tty 读取
# 用法：ans="$(prompt "提示文字")" || ans=""
# 用子 shell 探测 /dev/tty 是否真可用，避免 "No such device or address" 噪音
_tty_ok() { { : < /dev/tty; } 2>/dev/null; }

prompt() {
    local __text="$1" __ans=""
    # 提示必须单独写到 stderr。
    # 不能用 { read -p ...; } 2>/dev/null：read -p 的提示本身走 stderr，
    # 会被 2>/dev/null 一起吞掉，表现为"光标停住但没有任何提示"。
    if [[ -t 0 ]]; then
        printf '%s' "$__text" >&2
        read -r __ans
    elif _tty_ok; then
        printf '%s' "$__text" >&2
        read -r __ans < /dev/tty 2>/dev/null || return 1
    else
        return 1
    fi
    printf '%s' "$__ans"
}

log() {
    local ts; ts="$(date '+%F %T')"
    echo "[$ts] [remove v${SCRIPT_VERSION}] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# 重启 SSH 服务：不同发行版服务名可能是 ssh 或 sshd
restart_ssh() {
    systemctl restart ssh  2>/dev/null && return 0
    systemctl restart sshd 2>/dev/null && return 0
    service ssh restart    2>/dev/null && return 0
    service sshd restart   2>/dev/null && return 0
    return 1
}

TARGET=""
ASSUME_YES=0
DRY_RUN=0

usage() {
    cat <<EOF
移除旧 SSH 端口脚本 v${SCRIPT_VERSION}

用法: sudo bash $0 [选项]

选项:
  -p, --port <端口>   指定要移除的端口（省略则交互输入）
  -y, --yes           跳过确认
  -n, --dry-run       预演，不修改文件
  -V, --version       显示版本号
  -h, --help          显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)
            if [[ -z "${2:-}" ]]; then err "选项 $1 需要一个端口参数"; exit 1; fi
            TARGET="$2"; shift 2 ;;
        -y|--yes)    ASSUME_YES=1; shift ;;
        -n|--dry-run) DRY_RUN=1; shift ;;
        -V|--version) echo "remove_old_ssh_port.sh v${SCRIPT_VERSION}"; exit 0 ;;
        -h|--help)   usage; exit 0 ;;
        *)           err "未知参数: $1"; usage; exit 1 ;;
    esac
done

get_ports() {
    # 去重 + 数字排序，避免重复 Port 行导致"端口数量"判断出错
    grep -E '^[[:space:]]*Port[[:space:]]+' "$SSHD_CONFIG" 2>/dev/null \
        | awk '{print $2}' | sort -un || true
}

port_listening() {
    local port="$1"
    # 第 4 列为 Local Address:Port；表头该列不含端口号，故无需跳过首行
    if command -v ss >/dev/null 2>&1; then
        ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$"
    else
        return 1
    fi
}

BACKUP_FILE=""
CHANGED=0

rollback_if_needed() {
    local rc=$?
    if [[ $rc -ne 0 && $CHANGED -eq 1 && -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]]; then
        err "检测到异常，正在回滚 ..."
        cp -p "$BACKUP_FILE" "$SSHD_CONFIG" 2>/dev/null || true
        restart_ssh || true
        err "已回滚。"
        log "ROLLBACK rc=$rc"
    fi
}
trap rollback_if_needed EXIT

main() {
    echo -e "${BOLD}==================================================${NC}"
    echo -e "${BOLD}       安全移除旧 SSH 端口  v${SCRIPT_VERSION}${NC}"
    echo -e "${BOLD}==================================================${NC}"
    echo

    if [[ $EUID -ne 0 ]]; then
        err "请使用 root 权限运行（例如：sudo bash $0）"
        exit 1
    fi
    [[ -f "$SSHD_CONFIG" ]] || { err "未找到 $SSHD_CONFIG"; exit 1; }

    local ports=()
    mapfile -t ports < <(get_ports)

    if [[ ${#ports[@]} -eq 0 ]]; then
        err "配置中未找到 Port 行（可能使用默认端口 22），无需移除。"
        exit 1
    fi

    info "当前生效端口：${BOLD}${ports[*]}${NC}"

    if [[ ${#ports[@]} -eq 1 ]]; then
        info "当前只有一个端口（${ports[0]}），没有可移除的旧端口。"
        exit 0
    fi

    # 非交互环境且未指定端口时，直接提示，避免 read 空转
    if [[ -z "$TARGET" && ! -t 0 ]] && ! _tty_ok; then
        err "当前为非交互环境，请用 -p 指定要移除的端口，例如：bash $0 -p 22 -y"
        exit 1
    fi

    # 选择要移除的端口
    if [[ -n "$TARGET" ]]; then
        if ! printf '%s\n' "${ports[@]}" | grep -qx "$TARGET"; then
            err "端口 $TARGET 不在当前生效列表中。"
            exit 1
        fi
    else
        while true; do
            TARGET="$(prompt "$(echo -e "${CYAN}请输入要移除的端口（其余保留）：${NC}")")" || TARGET=""
            if ! [[ "$TARGET" =~ ^[0-9]+$ ]]; then
                err "请输入数字端口。"; continue
            fi
            if ! printf '%s\n' "${ports[@]}" | grep -qx "$TARGET"; then
                err "端口 $TARGET 不在当前生效列表中，请重新输入。"; continue
            fi
            break
        done
    fi

    # 计算剩余端口
    local remain=()
    local p
    for p in "${ports[@]}"; do
        if [[ "$p" != "$TARGET" ]]; then
            remain+=("$p")
        fi
    done
    if [[ ${#remain[@]} -eq 0 ]]; then
        err "不能移除唯一的端口，否则将无法通过 SSH 登录。"
        exit 1
    fi

    echo
    warn "即将移除端口 ${BOLD}${TARGET}${NC}，保留：${BOLD}${remain[*]}${NC}"

    if [[ $DRY_RUN -eq 1 ]]; then
        ok "预演完成，未修改任何文件。"
        exit 0
    fi

    if [[ $ASSUME_YES -ne 1 ]]; then
        c="$(prompt "$(echo -e "${CYAN}确认执行吗？(y/N) ${NC}")")" || c=""
        [[ "$c" == [yY] ]] || { info "已取消操作。"; exit 0; }
    fi

    # 备份
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="${BACKUP_DIR}/sshd_config.$(date +%Y%m%d-%H%M%S).bak"
    cp -p "$SSHD_CONFIG" "$BACKUP_FILE"
    ok "已备份：$BACKUP_FILE"
    log "remove backup: $BACKUP_FILE"

    # 精确删除对应 Port 行
    sed -i -E "/^[[:space:]]*Port[[:space:]]+${TARGET}([[:space:]]+#.*)?[[:space:]]*$/d" "$SSHD_CONFIG"
    CHANGED=1

    # 语法校验
    info "校验配置语法 (sshd -t) ..."
    if ! sshd -t; then
        err "语法校验失败，回滚 ..."
        cp -p "$BACKUP_FILE" "$SSHD_CONFIG"
        CHANGED=0
        err "已回滚，未做任何更改。"
        log "sshd -t failed, rolled back"
        exit 1
    fi
    ok "语法校验通过。"

    # 重启
    info "重启 ssh 服务 ..."
    if restart_ssh; then
        ok "ssh 服务已重启。"
    else
        err "重启失败，请手动检查（当前会话先别断）。"
    fi

    # 验证剩余端口
    sleep 1
    local all_ok=1
    local p
    for p in "${remain[@]}"; do
        local found=0
        for _ in 1 2 3 4 5; do
            if port_listening "$p"; then found=1; break; fi
            sleep 1
        done
        if [[ $found -eq 0 ]]; then
            warn "未检测到端口 $p 监听。"
            all_ok=0
        fi
    done
    if [[ $all_ok -eq 1 ]]; then
        ok "已验证剩余端口处于监听状态。"
    fi

    echo
    ok "完成。当前剩余端口：${BOLD}$(get_ports | tr '\n' ' ')${NC}"
    echo -e "${YELLOW}请保持当前会话，另开窗口用剩余端口登录验证后再断开。${NC}"
    echo -e "${YELLOW}如需回滚：cp ${BACKUP_FILE} ${SSHD_CONFIG} && systemctl restart ssh${NC}"

    log "removed port $TARGET, remain=$(get_ports | tr '\n' ' ')"
}

main "$@"
