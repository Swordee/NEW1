#!/usr/bin/env bash
# ============================================================
#  生成 install.sh —— 把 fail2ban-debian.sh 以 base64 内嵌，
#  产出单文件、可 `curl | bash` 一键执行的引导器。
#
#  用法: ./scripts/build-install.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
SRC="${ROOT_DIR}/fail2ban-debian.sh"
OUT="${ROOT_DIR}/install.sh"

if [ ! -f "${SRC}" ]; then
  printf '[错误] 找不到源脚本：%s\n' "${SRC}" >&2
  exit 1
fi

# 计算 sha256（Debian 用 sha256sum，macOS 用 shasum）
if command -v sha256sum >/dev/null 2>&1; then
  SHA=$(sha256sum "${SRC}" | grep -oE '[0-9a-f]{64}' | head -n1 || true)
elif command -v shasum >/dev/null 2>&1; then
  SHA=$(shasum -a 256 "${SRC}" | grep -oE '[0-9a-f]{64}' | head -n1 || true)
else
  SHA=""
fi

# base64 编码（保留换行，运行时 base64 -d 会自动忽略）
B64=$(base64 < "${SRC}")

{
  cat <<'HDR'
#!/usr/bin/env bash
# ============================================================
#  install.sh — Fail2ban 一键安装引导器（自解压 / 远程执行）
#
#  本文件由 scripts/build-install.sh 自动生成，请勿手动编辑。
#  修改逻辑请改 fail2ban-debian.sh 后重新运行生成器。
#
#  本地执行:
#    ./install.sh                        # 默认 bootstrap：装好并进交互面板
#    ./install.sh menu                   # 直接进入交互面板
#    ./install.sh doctor                 # 自检并交互式修复
#
#  远程一键执行（curl | bash）:
#    curl -fsSL <url> | bash                        # 装好并进交互面板
#    curl -fsSL <url> | bash -s -- install --port 2222 --ignore-ip "1.2.3.4/32" -y
#
#  权限:
#    非 root 时由内嵌脚本自动调用 sudo 提权（可加 --no-elevate 关闭）。
#
#  引导器选项:
#    --from-file <路径>   改用本地 fail2ban-debian.sh（开发调试）
#    --keep               保留解压出的临时脚本，便于排查
#    -V, --version        显示版本
#    -h, --help           显示帮助
#
#  其余参数原样传给 fail2ban-debian.sh。
# ============================================================
set -euo pipefail

APP_VERSION="1.0.0"
FROM_FILE=""
KEEP=0
PASS_ARGS=()

usage() {
  cat <<'EOF'
install.sh — Fail2ban 一键安装引导器

用法:
  curl -fsSL <url> | bash -s -- [命令] [选项]
  ./install.sh [命令] [选项]

不带命令时默认执行 bootstrap：装成系统命令 fail2ban-tool → 自动安装 fail2ban
→ 直接进入交互面板。非 root 时会自动通过 sudo 提权重入，无需手动加 sudo。

命令（透传给内嵌脚本）:
  bootstrap / auto / install / doctor / status / dir / logs / reload / uninstall / menu / help

引导器选项:
  --from-file <路径>   使用本地 fail2ban-debian.sh（开发调试用）
  --keep               保留解压出的临时脚本
  -V, --version        显示版本
  -h, --help           显示本帮助

透传给 fail2ban-debian.sh 的示例:
  install --port 2222 --ignore-ip "1.2.3.4/32" -y
  status / dir / reload / uninstall --yes / menu
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from-file)
      if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
        printf '[错误] --from-file 需要一个路径\n' >&2
        exit 1
      fi
      FROM_FILE="$2"; shift 2 ;;
    --from-file=*)
      FROM_FILE="${1#*=}"
      [ -n "${FROM_FILE}" ] || { printf '[错误] --from-file= 后不能为空\n' >&2; exit 1; }
      shift ;;
    --keep) KEEP=1; shift ;;
    -V|--version) printf 'install.sh %s\n' "${APP_VERSION}"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do PASS_ARGS+=("$1"); shift; done ;;
    *) PASS_ARGS+=("$1"); shift ;;
  esac
done
HDR

  printf 'PAYLOAD_SHA256="%s"\n' "${SHA}"
  printf 'PAYLOAD_B64="\n'
  printf '%s\n' "${B64}"
  printf '"\n\n'

  cat <<'FTR'
# ---------- 解压内嵌脚本 ----------
# 固定用 POSIX 临时目录，避免 Windows 盘符/反斜杠影响 sha256sum 与 rm
TMP_BASE="${TMPDIR:-/tmp}"
TMP_DIR=$(mktemp -d "${TMP_BASE}/f2b.XXXXXX" 2>/dev/null || mktemp -d)
TMP_SCRIPT="${TMP_DIR}/fail2ban-debian.sh"

cleanup() {
  if [ "${KEEP}" -eq 1 ]; then
    printf '[信息] 已保留临时脚本：%s\n' "${TMP_SCRIPT}" >&2
  else
    rm -rf -- "${TMP_DIR}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if [ -n "${FROM_FILE}" ]; then
  if [ ! -f "${FROM_FILE}" ]; then
    printf '[错误] 文件不存在：%s\n' "${FROM_FILE}" >&2
    exit 1
  fi
  cp "${FROM_FILE}" "${TMP_SCRIPT}"
  printf '[信息] 使用本地脚本：%s\n' "${FROM_FILE}"
else
  if ! command -v base64 >/dev/null 2>&1; then
    printf '[错误] 缺少 base64 命令\n' >&2
    exit 1
  fi
  if ! printf '%s' "${PAYLOAD_B64}" | base64 -d > "${TMP_SCRIPT}" 2>/dev/null; then
    if ! printf '%s' "${PAYLOAD_B64}" | base64 --decode > "${TMP_SCRIPT}" 2>/dev/null; then
      printf '[错误] base64 解码失败\n' >&2
      exit 1
    fi
  fi

  # 校验完整性（有 sha256 工具才校验）
  if [ -n "${PAYLOAD_SHA256}" ]; then
    ACTUAL=""
    if command -v sha256sum >/dev/null 2>&1; then
      ACTUAL=$(sha256sum "${TMP_SCRIPT}" 2>/dev/null | grep -oE '[0-9a-f]{64}' | head -n1 || true)
    elif command -v shasum >/dev/null 2>&1; then
      ACTUAL=$(shasum -a 256 "${TMP_SCRIPT}" 2>/dev/null | grep -oE '[0-9a-f]{64}' | head -n1 || true)
    fi
    if [ -n "${ACTUAL}" ] && [ "${ACTUAL}" != "${PAYLOAD_SHA256}" ]; then
      printf '[错误] 校验失败：期望 %s，实际 %s\n' "${PAYLOAD_SHA256}" "${ACTUAL}" >&2
      exit 1
    fi
  fi
  printf '[信息] 已解压内置脚本（sha256 %.12s…）\n' "${PAYLOAD_SHA256}"
fi

if [ ! -s "${TMP_SCRIPT}" ]; then
  printf '[错误] 解压结果为空\n' >&2
  exit 1
fi

chmod +x "${TMP_SCRIPT}" 2>/dev/null || true

# 无参数时默认执行 bootstrap（一条命令装好并进入交互面板）
if [ "${#PASS_ARGS[@]}" -eq 0 ]; then
  PASS_ARGS=(bootstrap)
fi

# 让内嵌脚本的错误提示显示 install.sh，而不是临时解压路径
export F2B_PROG_HINT="install.sh"

# curl | bash 时 stdin 是管道，交互输入改从 /dev/tty 读取
if { : < /dev/tty; } 2>/dev/null; then
  bash "${TMP_SCRIPT}" "${PASS_ARGS[@]}" < /dev/tty
else
  bash "${TMP_SCRIPT}" "${PASS_ARGS[@]}" < /dev/null
fi
FTR
} > "${OUT}"

chmod +x "${OUT}"
printf '[成功] 已生成 %s（%s 字节）\n' "${OUT}" "$(wc -c < "${OUT}" | tr -d ' ')"
