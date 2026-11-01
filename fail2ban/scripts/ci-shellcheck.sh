#!/usr/bin/env bash
# ============================================================
#  静态检查脚本（ShellCheck，本地 / CI 通用）
#
#  用法:
#    ./scripts/ci-shellcheck.sh              # 检查仓库内所有 .sh / .bash
#    ./scripts/ci-shellcheck.sh a.sh b.sh    # 只检查指定文件（相对/绝对均可）
#
#  环境变量:
#    SHELLCHECK_SEVERITY  最低严重级别（默认 info，可捕获 SC2086 等）
#    SHELLCHECK_OPTS      追加给 shellcheck 的额外参数
#
#  退出码:
#    0   全部通过
#    1   shellcheck 发现问题
#    127 未安装 shellcheck
# ============================================================
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
CALLER_DIR=$(pwd)

SEVERITY="${SHELLCHECK_SEVERITY:-info}"

# ---------- 1. 确认 shellcheck 可用 ----------
if ! command -v shellcheck >/dev/null 2>&1; then
  cat >&2 <<'EOF'
[错误] 未安装 shellcheck，请先安装：
  Debian / Ubuntu : sudo apt-get install -y shellcheck
  RHEL / CentOS   : sudo dnf install -y ShellCheck
  macOS           : brew install shellcheck
  临时用 Docker   : docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable -x ./*.sh
EOF
  exit 127
fi

# 把相对路径转为绝对路径（基于调用者当前目录，而非脚本所在目录）
abspath() {
  local p="$1"
  case "${p}" in
    /*) printf '%s' "${p}" ;;              # 已是绝对路径
    *)  printf '%s/%s' "${CALLER_DIR}" "${p}" ;;
  esac
}

# ---------- 2. 收集待检查文件 ----------
files=()
missing=0

if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    abs=$(abspath "${arg}")
    if [ -f "${abs}" ]; then
      files+=("${abs}")
    else
      printf '[警告] 文件不存在，已跳过：%s\n' "${arg}" >&2
      missing=1
    fi
  done
elif command -v git >/dev/null 2>&1 \
     && git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r f; do
    [ -n "${f}" ] && files+=("${ROOT_DIR}/${f}")
  done < <(git -C "${ROOT_DIR}" ls-files -- '*.sh' '*.bash' 2>/dev/null || true)
else
  while IFS= read -r f; do
    [ -n "${f}" ] && files+=("${f}")
  done < <(find "${ROOT_DIR}" -type f \( -name '*.sh' -o -name '*.bash' \) \
             -not -path '*/.git/*' 2>/dev/null || true)
fi

# 去重（保持顺序）
unique=()
declare -A seen=()
for f in "${files[@]:-}"; do
  if [ -n "${f}" ] && [ -z "${seen[${f}]:-}" ]; then
    seen["${f}"]=1
    unique+=("${f}")
  fi
done

if [ "${#unique[@]}" -eq 0 ]; then
  if [ "${missing}" -eq 1 ]; then
    echo "[错误] 指定的文件均不存在" >&2
    exit 1
  fi
  echo "[信息] 未找到需要检查的 shell 脚本"
  exit 0
fi

# ---------- 3. 执行检查 ----------
echo "[信息] shellcheck 检查 ${#unique[@]} 个文件（severity=${SEVERITY}）"
printf '  - %s\n' "${unique[@]}"
echo "------------------------------------------------------------"

rc=0
# shellcheck disable=SC2086  # SHELLCHECK_OPTS 需按空格拆分
shellcheck -x --severity="${SEVERITY}" ${SHELLCHECK_OPTS:-} "${unique[@]}" || rc=$?

echo "------------------------------------------------------------"
if [ "${rc}" -eq 0 ]; then
  echo "[成功] shellcheck 全部通过"
else
  echo "[失败] shellcheck 发现问题（退出码 ${rc}），请按提示修复"
fi
exit "${rc}"
