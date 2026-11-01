#!/usr/bin/env bash
# ============================================================
#  从私有 GitHub 仓库下载 fail2ban 工具集
#
#  私有仓库无法使用 jsDelivr / raw.githubusercontent.com 匿名访问，
#  本脚本通过 GitHub Contents API + Token 拉取文件。
#
#  用法:
#    export GITHUB_TOKEN=ghp_xxx
#    ./scripts/fetch-private.sh                 # 下载到当前目录
#    ./scripts/fetch-private.sh --dest ./src    # 下载到指定目录
#
#  选项:
#    --owner <用户>    默认 Swordee
#    --repo  <仓库>    默认 NEW1
#    --ref   <分支>    默认 main
#    --subdir <目录>   默认 fail2ban
#    --dest  <目录>    默认当前目录
#    -h, --help
#
#  Token 权限：私有仓库需要 repo 读权限（fine-grained 需 Contents: Read）
# ============================================================
set -euo pipefail

OWNER="${GH_OWNER:-Swordee}"
REPO="${GH_REPO:-NEW1}"
REF="${GH_REF:-main}"
SUBDIR="${GH_SUBDIR:-fail2ban}"
DEST="${DEST_DIR:-.}"

# 需要下载的文件清单（相对 fail2ban/）
FILES=(
  "README.md"
  "fail2ban-debian.sh"
  "install.sh"
  "fail2ban-guide.md"
  "fail2ban-rules-templates.md"
  ".shellcheckrc"
  ".gitattributes"
  "scripts/build-install.sh"
  "scripts/ci-shellcheck.sh"
  ".github/workflows/shellcheck.yml"
)

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --owner)  OWNER="${2:?--owner 需要值}"; shift 2 ;;
    --repo)   REPO="${2:?--repo 需要值}"; shift 2 ;;
    --ref)    REF="${2:?--ref 需要值}"; shift 2 ;;
    --subdir) SUBDIR="${2:?--subdir 需要值}"; shift 2 ;;
    --dest)   DEST="${2:?--dest 需要值}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[错误] 未知参数：$1" >&2; usage >&2; exit 1 ;;
  esac
done

TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [ -z "${TOKEN}" ]; then
  cat >&2 <<'EOF'
[错误] 未提供 Token。请先设置环境变量：
  export GITHUB_TOKEN=ghp_xxxxxxxx
（私有仓库需 repo 读权限；fine-grained 需 Contents: Read）
EOF
  exit 1
fi

API="https://api.github.com/repos/${OWNER}/${REPO}/contents"

echo "[信息] 仓库：${OWNER}/${REPO}  分支：${REF}  子目录：${SUBDIR}"
echo "[信息] 目标目录：${DEST}"

failed=0
for f in "${FILES[@]}"; do
  out="${DEST}/${SUBDIR}/${f}"
  mkdir -p "$(dirname "${out}")"
  code=$(curl -sS -L -o "${out}" -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/vnd.github.raw" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${API}/${SUBDIR}/${f}?ref=${REF}" || echo "000")
  if [ "${code}" = "200" ]; then
    printf '  [OK]   %s\n' "${f}"
  else
    printf '  [失败] %s（HTTP %s）\n' "${f}" "${code}" >&2
    rm -f "${out}"
    failed=1
  fi
done

if [ "${failed}" -ne 0 ]; then
  echo "[错误] 部分文件下载失败，请检查 Token 权限、仓库名或分支名" >&2
  exit 1
fi

# 恢复脚本执行权限
chmod +x "${DEST}/${SUBDIR}/fail2ban-debian.sh" \
         "${DEST}/${SUBDIR}/install.sh" \
         "${DEST}/${SUBDIR}/scripts/"*.sh 2>/dev/null || true

echo "[成功] 已下载到 ${DEST}/${SUBDIR}"
echo "       下一步：sudo ${DEST}/${SUBDIR}/install.sh install"
