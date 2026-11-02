#!/usr/bin/env bash
#
# ssh_menu.sh —— Debian SSH 端口管理 · 交互式面板 (v2.8)
#
# 用途：
#   安装完成后，在命令行输入 `sshh` 即可打开本面板（安装器会注入 alias）。
#   面板提供：状态查看 / 更换端口 / 移除旧端口 / 防火墙 / 备份回滚 / 重启 / 日志 / 卸载。
#
# 用法：
#   sudo bash ssh_menu.sh            # 打开交互面板
#   sudo bash ssh_menu.sh --status   # 仅打印状态（非交互，便于脚本调用）
#   sudo bash ssh_menu.sh --help
#
# 安全设计：
#   * 需要 root 的操作统一走 as_root()，非 root 时自动用 sudo 提权
#   * 面板本身不直接改写 sshd_config，端口变更仍走 change_ssh_port.sh
#     （备份 → sshd -t 校验 → 重启 → 端口监听验证 → 失败自动回滚）
#   * 卸载时会同时清理 alias 注入块与软链，不留残留

set -uo pipefail

readonly SCRIPT_VERSION="2.8"
readonly SSHD_CONFIG="/etc/ssh/sshd_config"
readonly BACKUP_DIR="/etc/ssh/sshd_config_backups"
readonly LOG_FILE="/var/log/change_ssh_port.log"

# ---------- 颜色（NO_COLOR 或非终端时禁用） ----------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
    CYAN=$'\033[0;36m'; BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; BOLD=''; DIM=''; NC=''
fi

info() { printf '%s\n' "${CYAN}[信息]${NC} $*"; }
ok()   { printf '%s\n' "${GREEN}[完成]${NC} $*"; }
warn() { printf '%s\n' "${YELLOW}[警告]${NC} $*"; }
err()  { printf '%s\n' "${RED}[错误]${NC} $*"; }

# ---------- 交互读取（curl | bash / 非终端时改从 /dev/tty 取） ----------
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

# ---------- 路径解析（跟随软链，定位真实安装目录） ----------
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
readonly TOOL_DIR

# ---------- 提权执行 ----------
as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
        return $?
    fi
    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
        return $?
    fi
    err "需要 root 权限，但系统未安装 sudo，请以 root 身份重新运行。"
    return 1
}

# ---------- 状态采集 ----------
config_ports() {
    # 主配置 + Include 的子配置里的所有 Port 指令
    local pat f out=""
    {
        if [[ -f "$SSHD_CONFIG" ]]; then
            grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' "$SSHD_CONFIG" 2>/dev/null || true
        fi
        while IFS= read -r pat; do
            [[ -z "$pat" ]] && continue
            [[ "$pat" != /* ]] && pat="/etc/ssh/$pat"
            for f in $pat; do
                if [[ -f "$f" ]]; then
                    grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' "$f" 2>/dev/null || true
                fi
            done
        done < <(grep -E '^[[:space:]]*Include[[:space:]]+' "$SSHD_CONFIG" 2>/dev/null || true)
    } | awk '{print $2}' | sort -un
}

effective_ports() {
    # sshd -T 需要 root；失败时回退到解析配置文件
    local out=""
    if [[ $EUID -eq 0 ]] && command -v sshd >/dev/null 2>&1; then
        out="$(sshd -T 2>/dev/null | awk '/^port /{print $2}' | sort -un || true)"
    fi
    if [[ -z "$out" ]]; then
        out="$(config_ports)"
    fi
    if [[ -z "$out" ]]; then
        out="22"
    fi
    printf '%s' "$out"
}

port_listening() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$"
    else
        return 1
    fi
}

svc_status() {
    local state="unknown" detail=""
    if command -v systemctl >/dev/null 2>&1; then
        state="$(systemctl is-active ssh 2>/dev/null || true)"
        if [[ -z "$state" || "$state" == "inactive" || "$state" == "failed" ]]; then
            state="$(systemctl is-active sshd 2>/dev/null || true)"
        fi
        detail="$(systemctl show ssh -p SubState --value 2>/dev/null || true)"
        if [[ -z "$detail" ]]; then
            detail="$(systemctl show sshd -p SubState --value 2>/dev/null || true)"
        fi
    elif command -v service >/dev/null 2>&1; then
        if service ssh status >/dev/null 2>&1; then
            state="active"
        fi
    fi
    [[ -z "$state" ]] && state="unknown"
    if [[ -n "$detail" ]]; then
        printf '%s %s' "$state" "$detail"
    else
        printf '%s' "$state"
    fi
}

firewall_info() {
    local kind="none" extra=""
    if command -v ufw >/dev/null 2>&1; then
        kind="ufw"
        if [[ $EUID -eq 0 ]]; then
            extra="$(ufw status 2>/dev/null | awk '/^Status:/{print $2}' || true)"
        fi
    elif command -v nft >/dev/null 2>&1; then
        kind="nftables"
    elif command -v iptables >/dev/null 2>&1; then
        kind="iptables"
    fi
    printf '%s %s' "$kind" "$extra"
}

config_valid() {
    if [[ $EUID -ne 0 ]] || ! command -v sshd >/dev/null 2>&1; then
        printf 'unknown'
        return
    fi
    if sshd -t >/dev/null 2>&1; then
        printf '通过'
    else
        printf '失败'
    fi
}

# 列出备份文件（按修改时间倒序，只输出文件名）
list_backups() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    if find "$dir" -maxdepth 1 -type f -name '*.bak' -printf '%T@ %f\n' >/dev/null 2>&1; then
        find "$dir" -maxdepth 1 -type f -name '*.bak' -printf '%T@ %f\n' 2>/dev/null \
            | sort -rn | cut -d' ' -f2-
    else
        # 降级路径：GNU find 不支持 -printf 时退回 ls
        # shellcheck disable=SC2010,SC2012
        ls -1t "$dir" 2>/dev/null | grep -E '\.bak$' || true
    fi
}

last_backup() {
    local f
    f="$(list_backups "$BACKUP_DIR" | awk 'NR==1{print; exit}')"
    if [[ -n "$f" ]]; then
        printf '%s' "$f"
    else
        printf '无'
    fi
}

host_summary() {
    local os="Linux"
    if [[ -r /etc/os-release ]]; then
        os="$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release 2>/dev/null || true)"
    fi
    [[ -z "$os" ]] && os="Linux"
    printf '%s@%s · %s' "${USER:-root}" "$(hostname 2>/dev/null || echo localhost)" "$os"
}

# ---------- 面板渲染 ----------
draw_header() {
    local ports listen svc fw valid backup
    ports="$(effective_ports)"
    listen=""
    local p
    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        if port_listening "$p"; then
            listen+=" ${GREEN}${p} ✓${NC}"
        else
            listen+=" ${YELLOW}${p} ✗${NC}"
        fi
    done <<< "$ports"

    svc="$(svc_status)"
    fw="$(firewall_info)"
    valid="$(config_valid)"
    backup="$(last_backup)"

    printf '%s\n' "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    printf '%s\n' "${CYAN}║${NC}   ${BOLD}Debian SSH · 端口管理面板${NC}                ${BLUE}v${SCRIPT_VERSION}${NC}          ${CYAN}║${NC}"
    printf '%s\n' "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    printf '  %s%-9s%s: %s\n' "$DIM" "主机" "$NC" "$(host_summary)"
    printf '  %s%-9s%s: %s\n' "$DIM" "当前端口" "$NC" "$(printf '%s' "$ports" | tr '\n' ' ')"
    printf '  %s%-9s%s:%s\n' "$DIM" "端口监听" "$NC" "$listen"
    printf '  %s%-9s%s: %s\n' "$DIM" "服务状态" "$NC" "$svc"
    printf '  %s%-9s%s: %s\n' "$DIM" "防火墙" "$NC" "$fw"
    printf '  %s%-9s%s: %s\n' "$DIM" "配置校验" "$NC" "$valid"
    printf '  %s%-9s%s: %s\n' "$DIM" "最近备份" "$NC" "$backup"
    printf '%s\n' "${DIM}  ────────────────────────────────────────────────────────────${NC}"
}

draw_menu() {
    printf '  %s1)%s 查看 SSH 状态详情\n' "$BOLD" "$NC"
    printf '  %s2)%s 更改 SSH 端口\n' "$BOLD" "$NC"
    printf '  %s3)%s 移除旧端口（过渡期收尾）\n' "$BOLD" "$NC"
    printf '  %s4)%s 备份与回滚\n' "$BOLD" "$NC"
    printf '  %s5)%s 防火墙规则\n' "$BOLD" "$NC"
    printf '  %s6)%s 重启 SSH 服务\n' "$BOLD" "$NC"
    printf '  %s7)%s 查看操作日志\n' "$BOLD" "$NC"
    printf '  %s8)%s 卸载本工具\n' "$BOLD" "$NC"
    printf '  %s0)%s 退出\n' "$BOLD" "$NC"
    printf '%s\n' "${DIM}  ────────────────────────────────────────────────────────────${NC}"
}

clear_screen() {
    printf '\033[H\033[2J\033[3J'
}

pause_enter() {
    local _
    if [[ -t 0 ]]; then
        read -r -p "  按 Enter 返回菜单..." _ || true
    else
        sleep 1
    fi
}

# ---------- 具体功能 ----------
show_detail() {
    printf '\n%s\n' "${BOLD}── SSH 状态详情 ──${NC}"
    printf '  配置文件    : %s\n' "$SSHD_CONFIG"
    printf '  备份目录    : %s\n' "$BACKUP_DIR"
    printf '  日志文件    : %s\n' "$LOG_FILE"

    local ports
    ports="$(effective_ports)"
    printf '  生效端口    : %s\n' "$(printf '%s' "$ports" | tr '\n' ' ')"

    printf '  监听明细    :\n'
    if command -v ss >/dev/null 2>&1; then
        # 端口需整体成组匹配，否则 22 会匹配到 2222 这类行
        local port_pat
        port_pat="$(printf '%s' "$ports" | tr '\n' '|')"
        port_pat="${port_pat%|}"
        ss -tlnp 2>/dev/null | grep -E "sshd|:(${port_pat})[[:space:]]" \
            || printf '    （未找到 sshd 监听记录）\n'
    else
        printf '    （ss 不可用）\n'
    fi

    printf '  配置中的 Port 指令:\n'
    if [[ -f "$SSHD_CONFIG" ]]; then
        grep -nE '^[[:space:]]*Port[[:space:]]+[0-9]+' "$SSHD_CONFIG" 2>/dev/null \
            | while IFS= read -r line; do printf '    %s\n' "$line"; done
    else
        printf '    （配置文件不存在）\n'
    fi

    printf '  防火墙:\n'
    if command -v ufw >/dev/null 2>&1; then
        as_root ufw status 2>/dev/null | while IFS= read -r line; do printf '    %s\n' "$line"; done
    elif command -v iptables >/dev/null 2>&1; then
        as_root iptables -S 2>/dev/null | grep -E "dport|ACCEPT" | while IFS= read -r line; do printf '    %s\n' "$line"; done
    else
        printf '    （未检测到常见防火墙工具）\n'
    fi
    printf '\n'
}

do_change_port() {
    printf '\n'
    if [[ ! -f "$TOOL_DIR/change_ssh_port.sh" ]]; then
        err "未找到 change_ssh_port.sh（安装目录：$TOOL_DIR）"
        return 1
    fi
    as_root bash "$TOOL_DIR/change_ssh_port.sh"
}

do_remove_old_port() {
    printf '\n'
    if [[ ! -f "$TOOL_DIR/remove_old_ssh_port.sh" ]]; then
        err "未找到 remove_old_ssh_port.sh（安装目录：$TOOL_DIR）"
        return 1
    fi
    as_root bash "$TOOL_DIR/remove_old_ssh_port.sh"
}

do_backup() {
    printf '\n%s\n' "${BOLD}── 备份与回滚 ──${NC}"
    local files=()
    mapfile -t files < <(list_backups "$BACKUP_DIR")
    if [[ ${#files[@]} -eq 0 ]]; then
        warn "备份目录为空：$BACKUP_DIR"
        return 0
    fi

    local i=1
    local f
    for f in "${files[@]}"; do
        printf '  %s%2d)%s %s  (%s)\n' "$BOLD" "$i" "$NC" "$f" "$(date -r "$BACKUP_DIR/$f" '+%F %T' 2>/dev/null || echo '-')"
        i=$((i + 1))
    done

    local ans
    ans="$(prompt "$(echo -e "${CYAN}输入要回滚的编号（直接回车返回）：${NC}")")" || ans=""
    if [[ -z "$ans" ]]; then
        return 0
    fi
    if ! [[ "$ans" =~ ^[0-9]+$ ]] || (( ans < 1 || ans > ${#files[@]} )); then
        err "编号无效。"
        return 1
    fi

    local target="${files[$((ans - 1))]}"
    warn "将用备份回滚当前配置：$target"
    local c
    c="$(prompt "$(echo -e "${CYAN}确认回滚？(y/N) ${NC}")")" || c=""
    if [[ "$c" != [yY] ]]; then
        info "已取消。"
        return 0
    fi

    # 覆盖前先留存当前配置：若备份本身是坏的，可立即恢复，避免把可用配置覆盖掉
    local pre="$SSHD_CONFIG.pre-rollback.$$"
    as_root cp -p "$SSHD_CONFIG" "$pre" 2>/dev/null || true
    if ! as_root cp -p "$BACKUP_DIR/$target" "$SSHD_CONFIG"; then
        err "回滚失败：无法写入 $SSHD_CONFIG"
        as_root rm -f "$pre" 2>/dev/null || true
        return 1
    fi
    if as_root sshd -t >/dev/null 2>&1; then
        as_root rm -f "$pre" 2>/dev/null || true
        if as_root systemctl restart ssh 2>/dev/null \
            || as_root service ssh restart 2>/dev/null; then
            ok "已回滚并重启 SSH 服务。"
        else
            warn "已回滚，但服务重启失败，请手动检查：systemctl status ssh"
        fi
    else
        # 备份本身是坏的：必须恢复回滚前的配置，否则会把可用配置覆盖成坏的
        as_root cp -p "$pre" "$SSHD_CONFIG" 2>/dev/null || true
        as_root rm -f "$pre" 2>/dev/null || true
        err "该备份的配置语法校验失败，已恢复回滚前的配置。"
        err "请手动检查备份文件：$BACKUP_DIR/$target"
        return 1
    fi
}

do_firewall() {
    printf '\n%s\n' "${BOLD}── 防火墙规则 ──${NC}"
    local ports
    ports="$(effective_ports)"

    if command -v ufw >/dev/null 2>&1; then
        printf '  ufw 状态:\n'
        as_root ufw status 2>/dev/null | while IFS= read -r line; do printf '    %s\n' "$line"; done
    elif command -v nft >/dev/null 2>&1; then
        printf '  nftables 规则:\n'
        as_root nft list ruleset 2>/dev/null | head -n 30 | while IFS= read -r line; do printf '    %s\n' "$line"; done
    elif command -v iptables >/dev/null 2>&1; then
        printf '  iptables 规则:\n'
        as_root iptables -S 2>/dev/null | while IFS= read -r line; do printf '    %s\n' "$line"; done
    else
        warn "未检测到 ufw / nftables / iptables。"
        return 0
    fi

    local ans
    ans="$(prompt "$(echo -e "${CYAN}是否为当前端口 ${BOLD}${ports//$'\n'/ }${NC} 补充放行规则？(y/N) ${NC}")")" || ans=""
    if [[ "$ans" == [yY] ]]; then
        local p
        while IFS= read -r p; do
            [[ -z "$p" ]] && continue
            if command -v ufw >/dev/null 2>&1; then
                if as_root ufw allow "${p}/tcp" >/dev/null 2>&1; then
                    ok "ufw 已放行 ${p}/tcp"
                else
                    warn "ufw 放行 ${p}/tcp 失败"
                fi
            elif command -v iptables >/dev/null 2>&1; then
                if as_root iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null; then
                    ok "iptables 规则已存在（${p}/tcp）"
                elif as_root iptables -A INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null; then
                    ok "iptables 已放行 ${p}/tcp（重启可能失效，建议持久化）"
                else
                    warn "iptables 放行 ${p}/tcp 失败"
                fi
            elif command -v nft >/dev/null 2>&1; then
                # nft 的规则位置因发行版而异，不自动改，避免把规则插错表/链
                warn "nftables 需手动放行 ${p}/tcp："
                printf '      nft add rule inet filter input tcp dport %s accept\n' "$p"
            fi
        done <<< "$ports"
    fi
}

do_restart() {
    printf '\n'
    warn "重启 SSH 服务会短暂中断连接（当前会话不受影响）。"
    local c
    c="$(prompt "$(echo -e "${CYAN}确认重启？(y/N) ${NC}")")" || c=""
    if [[ "$c" != [yY] ]]; then
        info "已取消。"
        return 0
    fi
    if as_root systemctl restart ssh 2>/dev/null; then
        ok "ssh 已重启。"
    elif as_root systemctl restart sshd 2>/dev/null; then
        ok "sshd 已重启。"
    elif as_root service ssh restart 2>/dev/null; then
        ok "ssh 已重启（service）。"
    else
        err "重启失败，请手动检查：systemctl status ssh"
        return 1
    fi
    sleep 1
    local ports p
    ports="$(effective_ports)"
    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        if port_listening "$p"; then
            ok "端口 $p 正在监听。"
        else
            warn "端口 $p 未检测到监听，请检查：ss -tlnp | grep sshd"
        fi
    done <<< "$ports"
}

do_logs() {
    printf '\n%s\n' "${BOLD}── 最近操作日志 ──${NC}"
    if [[ -f "$LOG_FILE" ]]; then
        tail -n 30 "$LOG_FILE" | while IFS= read -r line; do printf '  %s\n' "$line"; done
    else
        warn "日志文件不存在：$LOG_FILE"
    fi
    printf '\n'
}

do_uninstall() {
    printf '\n%s\n' "${BOLD}── 卸载 ──${NC}"

    # 安全检查：TOOL_DIR 异常时绝不执行 rm -rf
    if [[ -z "$TOOL_DIR" || "$TOOL_DIR" == "/" || "$TOOL_DIR" == "$HOME" ]]; then
        err "安装目录异常（${TOOL_DIR:-空}），已中止卸载以防误删。"
        err "请手动清理，或重新运行 install.sh --uninstall"
        return 1
    fi

    warn "将删除安装目录、软链，并从 shell 配置中移除 sshh 别名。"
    printf '  安装目录: %s\n' "$TOOL_DIR"
    local c
    c="$(prompt "$(echo -e "${CYAN}确认卸载？(y/N) ${NC}")")" || c=""
    if [[ "$c" != [yY] ]]; then
        info "已取消。"
        return 0
    fi

    # 清理 alias 注入块
    # sudo 下 $HOME 是 /root，需反查 SUDO_USER 的真实 home，否则普通用户的配置清不掉
    local target_home="$HOME" h
    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
        if command -v getent >/dev/null 2>&1; then
            h="$(getent passwd "$SUDO_USER" 2>/dev/null | awk -F: '{print $6; exit}')" || h=""
        else
            h="$(awk -F: -v u="$SUDO_USER" '$1==u{print $6; exit}' /etc/passwd 2>/dev/null)" || h=""
        fi
        if [[ -n "$h" && -d "$h" ]]; then
            target_home="$h"
        fi
    fi

    local homes=("$target_home") rc home
    if [[ "$target_home" != "/root" && -d /root ]]; then
        homes+=("/root")
    fi
    for home in "${homes[@]}"; do
        for rc in "$home/.bashrc" "$home/.zshrc"; do
            [[ -f "$rc" ]] || continue
            if grep -q 'ssh-port-tool' "$rc" 2>/dev/null; then
                if sed -i '/^# >>> ssh-port-tool >>>$/,/^# <<< ssh-port-tool <<<$/d' "$rc" 2>/dev/null; then
                    ok "已清理别名配置：$rc"
                else
                    warn "清理别名失败，请手动编辑：$rc"
                fi
            fi
        done
    done

    # 清理软链（与安装器创建的 4 个保持一致）
    local link
    for link in /usr/local/bin/ssh-port /usr/local/bin/ssh-port-menu \
                /usr/local/bin/ssh-port-change /usr/local/bin/ssh-port-remove; do
        if [[ -L "$link" ]]; then
            rm -f "$link" && ok "已删除软链：$link"
        fi
    done

    # 删除安装目录（脚本自身位于其中，需等脚本退出后再删）
    printf '  安装目录将在本脚本退出后删除：%s\n' "$TOOL_DIR"
    ( sleep 2; rm -rf "$TOOL_DIR" ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
    ok "卸载完成。请重新打开终端使别名生效。"
}

# ---------- 非交互状态输出 ----------
print_status() {
    local ports p listen=""
    ports="$(effective_ports)"
    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        if port_listening "$p"; then
            listen+="$p(监听) "
        else
            listen+="$p(未监听) "
        fi
    done <<< "$ports"

    printf '主机      : %s\n' "$(host_summary)"
    printf '生效端口  : %s\n' "$(printf '%s' "$ports" | tr '\n' ' ')"
    printf '监听状态  : %s\n' "$listen"
    printf '服务状态  : %s\n' "$(svc_status)"
    printf '防火墙    : %s\n' "$(firewall_info)"
    printf '配置校验  : %s\n' "$(config_valid)"
    printf '最近备份  : %s\n' "$(last_backup)"
    printf '安装目录  : %s\n' "$TOOL_DIR"
    printf '脚本版本  : v%s\n' "$SCRIPT_VERSION"
}

usage() {
    cat <<EOF
Debian SSH 端口管理面板 v${SCRIPT_VERSION}

用法: sudo bash $0 [选项]

选项:
  --status     仅打印当前状态（非交互）
  --version    显示版本号
  -h, --help   显示本帮助
EOF
}

# ---------- 主流程 ----------
main() {
    local mode="${1:-menu}"
    case "$mode" in
        --status)  print_status; return 0 ;;
        --version) echo "ssh_menu.sh v${SCRIPT_VERSION}"; return 0 ;;
        -h|--help) usage; return 0 ;;
        --menu)    ;;
        *)         err "未知参数: $mode"; usage; return 1 ;;
    esac

    if [[ $EUID -ne 0 ]]; then
        warn "当前非 root，需要修改的操作将自动使用 sudo 提权。"
    fi

    while true; do
        clear_screen
        draw_header
        draw_menu
        local ans
        ans="$(prompt "$(echo -e "${CYAN}请选择 [0-8]：${NC}")")" || ans=""
        case "$ans" in
            1) show_detail; pause_enter ;;
            2) do_change_port; pause_enter ;;
            3) do_remove_old_port; pause_enter ;;
            4) do_backup; pause_enter ;;
            5) do_firewall; pause_enter ;;
            6) do_restart; pause_enter ;;
            7) do_logs; pause_enter ;;
            8) do_uninstall; return 0 ;;
            0|q|Q) clear_screen; printf '%s\n' "${DIM}再见。${NC}"; return 0 ;;
            "") ;;
            *) err "无效选项: $ans"; sleep 1 ;;
        esac
    done
}

main "$@"
