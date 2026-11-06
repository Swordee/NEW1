#!/usr/bin/env bash
# ==============================================================================
#  本地端到端模拟：验证 install.sh 在「curl | bash」形态下的完整行为
#  在没有 root 的环境下通过打补丁绕过权限检查，其余逻辑与线上一致
# ==============================================================================
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="/tmp/ipt-e2e"
FAIL=0
PASS_N=0
FAIL_N=0

rm -rf "${TMP}" 2>/dev/null || true
mkdir -p "${TMP}/mockbin"

pass() { PASS_N=$((PASS_N + 1)); printf '  \033[1;32m✔\033[0m %s\n' "$*"; }
fail() { FAIL_N=$((FAIL_N + 1)); FAIL=1; printf '  \033[1;31m✘\033[0m %s\n' "$*"; }
chk()  { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1（期望 [$3]，实际 [$2]）"; fi; }
has()  { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1（输出中找不到 [$3]）"; fi; }
# 界面输出带 ANSI 颜色码，比对前先剥掉
strip_ansi() { printf '%s' "$1" | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g'; }
# 多行输出整体缩进展示
show() { local l; while IFS= read -r l; do printf '    %s\n' "${l}"; done <<<"$1"; }

# 打补丁：去掉 root 检查、去掉 -o root -g root、把 /etc 换成临时目录
# shellcheck disable=SC2016
# 注：sed 模式里的 ${EUID} 是要保留的字面文本
sed -e 's|if \[\[ ${EUID} -ne 0 \]\]; then|if false; then|' \
    -e 's|install -m 0755 -o root -g root|install -m 0755|' \
    -e "s|/etc/iptables-wizard|${TMP}/etc/iptables-wizard|g" \
    "${SRC}/install.sh" > "${TMP}/install-test.sh"

# mock iptables：让被安装的程序能在无 netfilter 的环境下跑起来
cat > "${TMP}/mockbin/iptables" <<'MOCK'
#!/usr/bin/env bash
case " $* " in
  *" --version "*) echo "iptables v1.8.7 (nf_tables_compat)"; exit 0 ;;
  *" -S "*)      printf -- '-P INPUT DROP\n-P FORWARD ACCEPT\n-P OUTPUT ACCEPT\n-A INPUT -i lo -j ACCEPT\n-A INPUT -p tcp --dport 22 -j ACCEPT\n'; exit 0 ;;
  *" -C "*)      exit 0 ;;
  *" -L "*)      printf 'Chain INPUT (policy DROP)\ntarget     prot opt source               destination\nACCEPT     all  --  anywhere             anywhere\n'; exit 0 ;;
esac
exit 0
MOCK
chmod +x "${TMP}/mockbin/iptables"
cat > "${TMP}/mockbin/sshd" <<'MOCK'
#!/usr/bin/env bash
printf 'port 22\n'
MOCK
chmod +x "${TMP}/mockbin/sshd"

export PATH="${TMP}/mockbin:${PATH}"

echo "═══ 1) 模拟 curl | bash：stdin 为管道，参数经 -s -- 传递 ═══"
OUT=$(cat "${TMP}/install-test.sh" | bash -s -- --prefix "${TMP}/usr/local" --force --no-deps 2>&1)
RC=$?
show "${OUT}"
chk "安装退出码为 0" "${RC}" "0"
has "软链失败时给出可读提示" "${OUT}" "不影响使用"

echo
echo "═══ 2) 安装产物 ═══"
if [[ -x "${TMP}/usr/local/sbin/iptables-wizard" ]]; then pass "主程序已安装且可执行"; else fail "主程序缺失或不可执行"; fi
if [[ -d "${TMP}/etc/iptables-wizard/backups" ]]; then pass "备份目录已创建"; else fail "备份目录未创建（软链失败不应阻断后续步骤）"; fi

echo
echo "═══ 3) --run：stdin 为管道时，界面必须从 /dev/tty 取输入 ═══"
cat > "${TMP}/usr/local/sbin/iptables-wizard" <<'STUB'
#!/usr/bin/env bash
if [[ -t 0 ]]; then echo "TUI_LAUNCHED tty=yes"; else echo "TUI_LAUNCHED tty=no"; fi
STUB
chmod +x "${TMP}/usr/local/sbin/iptables-wizard"
OUT=$(cat "${TMP}/install-test.sh" | bash -s -- --prefix "${TMP}/usr/local" --force --no-deps --run 2>&1)
show "${OUT}"
if [[ "${OUT}" == *"TUI_LAUNCHED tty=yes"* ]]; then
  pass "启动界面时读取的是终端而不是管道"
elif [[ "${OUT}" == *"没有可用的终端"* ]]; then
  pass "无控制终端时给出友好提示而非崩溃"
else
  fail "--run 既没进入界面也没给出提示"
fi
if [[ "${OUT}" == *"No such device or address"* ]]; then
  fail "出现裸的 bash 错误（/dev/tty 打不开时未妥善处理）"
else
  pass "没有裸的 bash 错误"
fi

echo
echo "═══ 4) 装完之后真的能进交互界面 ═══"
# 用真实 payload 还原被测程序，并去掉 root 检查以便在本机验证渲染
# shellcheck disable=SC2016
# 注：sed 模式里的 ${EUID} 是要保留的字面文本
awk "/^PAYLOAD_B64='/,/^'/" "${TMP}/install-test.sh" \
  | sed "1s/^PAYLOAD_B64='//; \$d" | base64 -d 2>/dev/null | gzip -dc 2>/dev/null \
  | sed 's|if \[\[ ${EUID} -ne 0 \]\]; then|if false; then|' \
  > "${TMP}/usr/local/sbin/iptables-wizard"
chmod +x "${TMP}/usr/local/sbin/iptables-wizard"

OUT=$("${TMP}/usr/local/sbin/iptables-wizard" status 2>&1)
show "${OUT}" | head -20
has "状态概览显示默认策略" "${OUT}" "默认策略"
has "状态概览显示规则数量" "${OUT}" "规则数量"
has "状态概览显示 SSH 端口" "${OUT}" "SSH 端口"

echo
echo "═══ 5) 交互菜单渲染（模拟按 4 = 查看规则） ═══"
OUT=$(printf '4\n1\n\n0\n' | "${TMP}/usr/local/sbin/iptables-wizard" 2>&1)
CLEAN=$(strip_ansi "${OUT}")
has "菜单含「查看规则」" "${CLEAN}" "查看规则"
has "规则列表渲染出 Chain INPUT" "${CLEAN}" "Chain INPUT"
has "规则列表渲染出 policy" "${CLEAN}" "policy DROP"
echo "${CLEAN}" | grep -n 'Chain\|ACCEPT\|共 .* 条规则' | head -8 | while IFS= read -r l; do printf '    %s\n' "${l}"; done

echo
echo "═══ 6) 卸载 ═══"
OUT=$(cat "${TMP}/install-test.sh" | bash -s -- --prefix "${TMP}/usr/local" --uninstall --purge 2>&1)
RC=$?
chk "卸载退出码为 0" "${RC}" "0"
if [[ ! -e "${TMP}/usr/local/sbin/iptables-wizard" ]]; then pass "主程序已删除"; else fail "主程序未删除"; fi
if [[ ! -d "${TMP}/etc/iptables-wizard" ]]; then pass "配置目录已按 --purge 删除"; else fail "配置目录未删除"; fi

echo
if (( FAIL )); then
  printf '\033[1;31m✘ e2e 未全部通过（通过 %d 项 / 失败 %d 项）\033[0m\n' "${PASS_N}" "${FAIL_N}"
  exit 1
fi
printf '\033[1;32m✔ e2e 全部通过：%d 项断言\033[0m\n' "${PASS_N}"
