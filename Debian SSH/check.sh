#!/usr/bin/env bash
#
# check.sh —— 本地 / CI 统一的 Shell 脚本检查入口
#
# 功能：
#   1. 对仓库内所有 *.sh 执行 `bash -n` 语法检查
#   2. 执行 shellcheck（默认 style 级别，最严格）
#   3. 任一失败则返回非 0，可直接用于 CI
#
# 用法：
#   bash check.sh
#   SHELLCHECK_SEVERITY=warning bash check.sh
#   SHELLCHECK_BIN=/path/to/shellcheck bash check.sh
#
# 退出码：0=全部通过  1=存在问题  2=环境缺失（如未安装 shellcheck）

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 在 git 仓库内 → 扫描整个仓库（CI / 本地开发场景）
# 不在仓库内 → 扫描脚本所在目录（install.sh 安装后的独立副本场景）
if ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$ROOT" ]]; then
    :
else
    ROOT="$HERE"
fi
SEVERITY="${SHELLCHECK_SEVERITY:-style}"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
blue()  { printf '\033[36m%s\033[0m\n' "$*"; }

# ---------- 收集脚本文件 ----------
files=()
while IFS= read -r f; do
    files+=("$f")
done < <(find "$ROOT" -type f -name '*.sh' \
            -not -path '*/.git/*' \
            -not -path '*/.workbuddy-ai/*' | sort)

if [[ ${#files[@]} -eq 0 ]]; then
    red "未找到任何 .sh 文件"
    exit 1
fi

blue "发现 ${#files[@]} 个脚本："
for f in "${files[@]}"; do
    printf '  - %s\n' "${f#"$ROOT"/}"
done

fail=0

# ---------- 1) 语法检查 ----------
echo
blue "[1/2] bash -n 语法检查"
for f in "${files[@]}"; do
    rel="${f#"$ROOT"/}"
    if bash -n "$f"; then
        green "  OK   $rel"
    else
        red "  FAIL $rel"
        fail=1
    fi
done

# ---------- 2) shellcheck ----------
echo
blue "[2/2] shellcheck（severity=${SEVERITY}）"

SC="${SHELLCHECK_BIN:-}"
if [[ -z "$SC" ]]; then
    SC="$(command -v shellcheck 2>/dev/null || true)"
fi
if [[ -z "$SC" ]]; then
    red "未找到 shellcheck，请先安装其一："
    echo "  Debian/Ubuntu : sudo apt-get install -y shellcheck"
    echo "  macOS         : brew install shellcheck"
    echo "  pip           : pip install shellcheck-py"
    echo "  或设置环境变量 SHELLCHECK_BIN 指向 shellcheck 可执行文件"
    exit 2
fi

"$SC" --version | head -n 2 || true

if "$SC" -S "$SEVERITY" -f gcc "${files[@]}"; then
    green "  shellcheck 通过"
else
    red "  shellcheck 发现问题"
    fail=1
fi

# ---------- 汇总 ----------
echo
if [[ $fail -eq 0 ]]; then
    green "✅ 全部检查通过"
else
    red "❌ 检查未通过，请修复上述问题"
fi
exit $fail
