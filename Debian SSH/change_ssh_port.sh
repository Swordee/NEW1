#!/usr/bin/env bash
#
# change_ssh_port.sh —— Debian 交互式/半自动 SSH 端口更换脚本 (v2.8)
#
# 相对 v1 的改进：
#   + 支持命令行参数（-p 端口 / -y 自动确认 / --keep-old / --no-firewall / -n 预演）
#   + 检测 sshd_config 中的 Include 指令，避免 sshd_config.d/*.conf 里的 Port 覆盖
#   + 写入日志 /var/log/change_ssh_port.log
#   + Port 指令写入文件顶部，规避 Match 块导致的指令归属错误
#   + 重启后自动验证新端口是否真正在监听
#   + 全程 trap 兜底回滚，异常自动还原备份
#
# 用法：
#   sudo bash change_ssh_port.sh                     # 纯交互
#   sudo bash change_ssh_port.sh -p 2222             # 指定端口，其余交互
#   sudo bash change_ssh_port.sh -p 2222 -y          # 全自动（默认保留旧端口）
#   sudo bash change_ssh_port.sh -p 2222 -y --no-keep-old --firewall
#   sudo bash change_ssh_port.sh -p 2222 -n          # 预演，只显示将要做的改动

set -euo pipefail

readonly SCRIPT_VERSION="2.8"
readonly SSHD_CONFIG="/etc/ssh/sshd_config"
readonly BACKUP_DIR="/etc/ssh/sshd_config_backups"
readonly LOG_FILE="/var/log/change_ssh_port.log"

# ---------- 颜色 ----------
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
    echo "[$ts] [v${SCRIPT_VERSION}] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# 重启 SSH 服务：不同发行版服务名可能是 ssh 或 sshd
restart_ssh() {
    systemctl restart ssh  2>/dev/null && return 0
    systemctl restart sshd 2>/dev/null && return 0
    service ssh restart    2>/dev/null && return 0
    service sshd restart   2>/dev/null && return 0
    return 1
}

# ---------- 参数 ----------
NEW_PORT=""
ASSUME_YES=0
KEEP_OLD=""      # ""=询问 / yes / no
DO_FIREWALL=""   # ""=询问 / yes / no
DRY_RUN=0

usage() {
    cat <<EOF
Debian SSH 端口更换脚本 v${SCRIPT_VERSION}

用法: sudo bash $0 [选项]

选项:
  -p, --port <端口>   指定新端口（省略则交互输入）
  -y, --yes           跳过所有确认（自动化模式）
      --keep-old      过渡期保留旧端口
      --no-keep-old   不保留旧端口（直接只监听新端口）
      --firewall      自动放行防火墙端口
      --no-firewall   不改动防火墙
  -n, --dry-run       预演，仅显示将执行的操作，不修改任何文件
  -V, --version       显示版本号
  -h, --help          显示本帮助
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)
            if [[ -z "${2:-}" ]]; then err "选项 $1 需要一个端口参数"; exit 1; fi
            NEW_PORT="$2"; shift 2 ;;
        -y|--yes)       ASSUME_YES=1; shift ;;
        --keep-old)     KEEP_OLD="yes"; shift ;;
        --no-keep-old)  KEEP_OLD="no"; shift ;;
        --firewall)     DO_FIREWALL="yes"; shift ;;
        --no-firewall)  DO_FIREWALL="no"; shift ;;
        -n|--dry-run)   DRY_RUN=1; shift ;;
        -V|--version)   echo "change_ssh_port.sh v${SCRIPT_VERSION}"; exit 0 ;;
        -h|--help)      usage; exit 0 ;;
        *)              err "未知参数: $1"; echo; usage; exit 1 ;;
    esac
done

# ---------- 基础检查 ----------
require_root() {
    if [[ $EUID -ne 0 ]]; then
        err "请使用 root 权限运行（例如：sudo bash $0）"
        exit 1
    fi
}

# ---------- 端口工具 ----------
get_config_ports() {
    grep -E '^[[:space:]]*Port[[:space:]]+' "$SSHD_CONFIG" 2>/dev/null \
        | awk '{print $2}' | sort -un || true
}

get_effective_ports() {
    sshd -T 2>/dev/null | awk '/^port /{print $2}' | sort -un || true
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

validate_port() {
    local port="$1" current_ports="$2"
    [[ "$port" =~ ^[0-9]+$ ]] || { err "端口必须是数字。"; return 1; }
    (( port >= 1 && port <= 65535 )) || { err "端口必须在 1-65535 之间。"; return 1; }
    if (( port < 1024 )); then
        warn "端口 < 1024 属特权端口，建议改用 1024-65535。"
    fi
    if grep -qw "$port" <<< "$current_ports"; then
        err "端口 $port 已是当前 SSH 端口，请换一个。"
        return 1
    fi
    if port_listening "$port"; then
        err "端口 $port 已被本机其他服务占用，请换一个。"
        return 1
    fi
    return 0
}

# ---------- Include 处理 ----------
handle_includes() {
    local include_patterns
    include_patterns="$(grep -E '^[[:space:]]*Include[[:space:]]+' "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}' || true)"
    [[ -z "$include_patterns" ]] && return 0

    local files=() pat f
    while IFS= read -r pat; do
        [[ -z "$pat" ]] && continue
        [[ "$pat" != /* ]] && pat="/etc/ssh/$pat"
        for f in $pat; do
            [[ -f "$f" ]] && files+=("$f")
        done
    done <<< "$include_patterns"

    [[ ${#files[@]} -eq 0 ]] && return 0

    local hits=()
    for f in "${files[@]}"; do
        if grep -qE '^[[:space:]]*Port[[:space:]]+[0-9]+' "$f" 2>/dev/null; then
            hits+=("$f")
        fi
    done

    if [[ ${#hits[@]} -eq 0 ]]; then
        info "已检查 Include 配置，未发现额外 Port 指令。"
        return 0
    fi

    warn "以下被 Include 的配置文件中也定义了 Port，若不处理会继续监听旧端口："
    for f in "${hits[@]}"; do
        echo -e "    ${YELLOW}$f${NC}: $(grep -E '^[[:space:]]*Port[[:space:]]+' "$f" | tr '\n' ' ')"
    done

    local ans
    if [[ $ASSUME_YES -eq 1 ]]; then
        ans="y"
    else
        ans="$(prompt "$(echo -e "${CYAN}是否将这些 Include 文件中的 Port 指令注释掉？(Y/n) ${NC}")")" || ans=""
    fi
    case "$ans" in
        [nN]) warn "保留 Include 中的 Port，旧端口可能仍生效，请知悉。"; return 0 ;;
    esac

    for f in "${hits[@]}"; do
        local bak
        bak="${f}.bak.$(date +%Y%m%d-%H%M%S)"
        cp -p "$f" "$bak"
        INCLUDE_BACKUPS+=("${f}|${bak}")
        sed -i -E 's|^([[:space:]]*)(Port[[:space:]]+)|\1#\2|' "$f"
        ok "已注释 $f 中的 Port 指令（备份：$bak）"
        log "commented Port in include: $f (backup: $bak)"
    done
}

# ---------- 防火墙 ----------
configure_firewall() {
    local port="$1"
    local ans
    if [[ -n "$DO_FIREWALL" ]]; then
        ans="$DO_FIREWALL"
    elif [[ $ASSUME_YES -eq 1 ]]; then
        ans="yes"
    else
        echo
        info "放行新端口 $port 的防火墙规则（否则可能连不上）。"
        ans="$(prompt "$(echo -e "${CYAN}现在配置防火墙放行 $port 吗？(Y/n) ${NC}")")" || ans=""
    fi
    case "$ans" in
        no|[nN]) warn "已跳过防火墙配置，请手动放行端口 $port。"; return ;;
    esac

    if command -v ufw >/dev/null 2>&1; then
        if ufw allow "${port}/tcp" >/dev/null 2>&1; then
            ok "ufw 已放行 $port/tcp"
        else
            err "ufw 放行失败，请手动检查。"
        fi
    elif command -v nft >/dev/null 2>&1; then
        warn "检测到 nftables，请手动确认放行 $port/tcp（nft add rule inet filter input tcp dport $port accept）。"
    elif command -v iptables >/dev/null 2>&1; then
        if iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
            ok "iptables 规则已存在（$port/tcp）"
        elif iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
            ok "iptables 已放行 $port/tcp（重启可能失效，建议持久化）"
        else
            err "iptables 放行失败，请手动检查。"
        fi
    else
        warn "未检测到常见防火墙工具，请自行确认端口可达。"
    fi
}

# ---------- 配置写入 ----------
BACKUP_FILE=""
CHANGED=0
TMP_BODY=""
# 被注释掉 Port 的 Include 文件：每项格式 "源文件|备份文件"
INCLUDE_BACKUPS=()

on_exit() {
    local rc=$?
    # 先兜底回滚
    if [[ $rc -ne 0 && $CHANGED -eq 1 && -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]]; then
        err "检测到异常，正在回滚 sshd_config ..."
        cp -p "$BACKUP_FILE" "$SSHD_CONFIG" 2>/dev/null || true
        # Include 文件同样要还原，否则改动会残留
        local pair src bak
        for pair in "${INCLUDE_BACKUPS[@]}"; do
            src="${pair%%|*}"
            bak="${pair#*|}"
            if [[ -f "$bak" ]]; then
                cp -p "$bak" "$src" 2>/dev/null || true
                log "restored include: $src"
            fi
        done
        restart_ssh || true
        err "已回滚到修改前状态（含 Include 文件）。"
        log "ROLLBACK triggered, rc=$rc"
    fi
    # 再清理临时文件
    [[ -n "${TMP_BODY:-}" && -f "${TMP_BODY:-}" ]] && rm -f "$TMP_BODY"
}
trap on_exit EXIT

apply_config() {
    local new_port="$1" old_port="$2" keep_old="$3"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[预演] 将写入的 Port 指令："
        [[ "$keep_old" == "yes" ]] && echo -e "    ${BOLD}Port $old_port${NC}   (保留旧端口)"
        echo -e "    ${BOLD}Port $new_port${NC}"
        info "[预演] 其余配置保持不变；不写文件、不重启服务。"
        return 0
    fi

    TMP_BODY="$(mktemp)"
    # 删除主配置中所有 Port 指令（含被注释的），避免重复/冲突
    grep -vE '^[[:space:]]*#?[[:space:]]*Port[[:space:]]+[0-9]+[[:space:]]*(#.*)?$' "$SSHD_CONFIG" > "$TMP_BODY" || true

    local new_content; new_content="$(mktemp)"
    {
        echo "# === change_ssh_port.sh v${SCRIPT_VERSION} @ $(date '+%F %T') ==="
        [[ "$keep_old" == "yes" ]] && echo "Port $old_port"
        echo "Port $new_port"
        echo ""
        cat "$TMP_BODY"
    } > "$new_content"

    chmod --reference="$SSHD_CONFIG" "$new_content" 2>/dev/null || chmod 644 "$new_content"
    chown --reference="$SSHD_CONFIG" "$new_content" 2>/dev/null || true

    mv "$new_content" "$SSHD_CONFIG"
    CHANGED=1
}

# ---------- 主流程 ----------
main() {
    echo -e "${BOLD}==================================================${NC}"
    echo -e "${BOLD}     Debian SSH 端口更换脚本  v${SCRIPT_VERSION}${NC}"
    echo -e "${BOLD}==================================================${NC}"
    echo

    require_root

    [[ -f "$SSHD_CONFIG" ]] || { err "未找到 $SSHD_CONFIG"; exit 1; }

    # 非交互环境且未指定端口时，直接提示，避免在 read 循环里空转
    if [[ -z "$NEW_PORT" && ! -t 0 ]] && ! _tty_ok; then
        err "当前为非交互环境，请用 -p 指定端口，例如：bash $0 -p 2222 -y"
        exit 1
    fi

    local old_port current_ports
    old_port="$(get_config_ports | awk 'NR==1{print; exit}')"
    old_port="${old_port:-22}"
    current_ports="$(get_effective_ports)"
    [[ -z "$current_ports" ]] && current_ports="$old_port"

    info "当前生效 SSH 端口：${BOLD}${current_ports//$'\n'/ }${NC}"
    log "start: current ports=$(echo "$current_ports" | tr '\n' ' ')"

    # 新端口：参数优先，否则交互
    if [[ -n "$NEW_PORT" ]]; then
        validate_port "$NEW_PORT" "$current_ports" || { err "参数 -p 指定的端口无效"; exit 1; }
    else
        while true; do
            NEW_PORT="$(prompt "$(echo -e "${CYAN}请输入新的 SSH 端口 (1-65535)：${NC}")")" || NEW_PORT=""
            validate_port "$NEW_PORT" "$current_ports" && break
        done
    fi

    # 保留旧端口策略
    if [[ -z "$KEEP_OLD" ]]; then
        if [[ $ASSUME_YES -eq 1 ]]; then
            KEEP_OLD="yes"
        else
            echo
            warn "建议过渡期保留旧端口（$old_port），验证新端口能登录后再关闭。"
            a="$(prompt "$(echo -e "${CYAN}临时保留旧端口 $old_port 吗？(Y/n) ${NC}")")" || a=""
            case "$a" in [nN]) KEEP_OLD="no" ;; *) KEEP_OLD="yes" ;; esac
        fi
    fi

    # 确认
    echo
    if [[ "$KEEP_OLD" == "yes" ]]; then
        warn "将把 SSH 端口改为 ${BOLD}${NEW_PORT}${NC}，并临时保留旧端口 ${BOLD}${old_port}${NC}。"
    else
        warn "将把 SSH 端口改为 ${BOLD}${NEW_PORT}${NC}（不保留旧端口）。"
    fi
    if [[ $ASSUME_YES -ne 1 && $DRY_RUN -ne 1 ]]; then
        c="$(prompt "$(echo -e "${CYAN}确认执行吗？(y/N) ${NC}")")" || c=""
        [[ "$c" == [yY] ]] || { info "已取消操作。"; exit 0; }
    fi

    # 备份
    if [[ $DRY_RUN -ne 1 ]]; then
        mkdir -p "$BACKUP_DIR"
        BACKUP_FILE="${BACKUP_DIR}/sshd_config.$(date +%Y%m%d-%H%M%S).bak"
        cp -p "$SSHD_CONFIG" "$BACKUP_FILE"
        ok "已备份原配置：$BACKUP_FILE"
        log "backup: $BACKUP_FILE"
    fi

    # Include 检查
    [[ $DRY_RUN -ne 1 ]] && handle_includes

    # 写入配置
    apply_config "$NEW_PORT" "$old_port" "$KEEP_OLD"

    if [[ $DRY_RUN -eq 1 ]]; then
        ok "预演完成，未修改任何文件。"
        exit 0
    fi

    # 语法校验
    info "校验配置语法 (sshd -t) ..."
    if ! sshd -t; then
        err "配置语法校验失败，回滚 ..."
        cp -p "$BACKUP_FILE" "$SSHD_CONFIG"
        CHANGED=0
        restart_ssh || true
        err "已恢复原配置。"
        log "sshd -t failed, rolled back"
        exit 1
    fi
    ok "语法校验通过。"

    # 防火墙
    configure_firewall "$NEW_PORT"

    # 重启
    info "重启 ssh 服务 ..."
    if restart_ssh; then
        ok "ssh 服务已重启。"
    else
        err "重启失败，请手动检查（当前会话先别断）。"
    fi

    # 验证监听
    sleep 1
    local listening=0
    for _ in 1 2 3 4 5; do
        if port_listening "$NEW_PORT"; then listening=1; break; fi
        sleep 1
    done
    if [[ $listening -eq 1 ]]; then
        ok "已验证端口 ${NEW_PORT} 处于监听状态。"
    else
        warn "未检测到端口 ${NEW_PORT} 监听，请执行：ss -tlnp | grep sshd"
    fi

    # 收尾提示
    echo
    echo -e "${BOLD}==================================================${NC}"
    echo -e "${BOLD}               重要安全提示${NC}"
    echo -e "${BOLD}==================================================${NC}"
    echo -e "${YELLOW}1.${NC} 请【新开一个终端】用新端口测试登录："
    echo -e "     ssh -p ${BOLD}${NEW_PORT}${NC} 用户@服务器IP"
    echo -e "${YELLOW}2.${NC} 确认能登录后，再断开当前会话。"
    if [[ "$KEEP_OLD" == "yes" ]]; then
        echo -e "${YELLOW}3.${NC} 验证通过后运行收尾脚本关闭旧端口："
        echo -e "     sudo bash remove_old_ssh_port.sh"
    fi
    echo -e "${YELLOW}4.${NC} 如需回滚："
    echo -e "     cp ${BACKUP_FILE} ${SSHD_CONFIG} && systemctl restart ssh"
    echo -e "${BOLD}==================================================${NC}"

    log "done: new_port=$NEW_PORT keep_old=$KEEP_OLD listening=$listening"
    ok "执行完毕。"
}

main "$@"
