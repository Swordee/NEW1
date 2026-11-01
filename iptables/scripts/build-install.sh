#!/usr/bin/env bash
# ==============================================================================
#  scripts/build-install.sh — 生成自解压安装器 install.sh
# ------------------------------------------------------------------------------
#  把 iptables-wizard.sh 用 gzip+base64 内嵌进 scripts/install.template.sh，
#  产出可直接 curl | bash 的 install.sh。
#
#  用法：
#    bash scripts/build-install.sh            # 生成/更新 install.sh
#    bash scripts/build-install.sh --check    # 仅检查 install.sh 是否是最新的
#                                             # （CI 用：过期则退出码 1）
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${ROOT_DIR}/iptables-wizard.sh"
TPL="${SCRIPT_DIR}/install.template.sh"
OUT="${ROOT_DIR}/install.sh"

die() { printf '\033[1;31m✘\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f ${SRC} ]] || die "找不到 ${SRC}"
[[ -f ${TPL} ]] || die "找不到 ${TPL}"

# 版本号取自主脚本的 readonly VERSION="x.y.z"
VERSION="$(sed -n 's/^readonly VERSION="\([^"]*\)"$/\1/p' "${SRC}" | head -n 1)"
[[ -n ${VERSION} ]] || die "无法从 ${SRC} 解析版本号"

gen() {  # gen <输出文件>
  local out="$1" sha tmp_payload tmp_body
  sha="$(sha256sum "${SRC}" | awk '{print $1}')"

  tmp_payload="$(mktemp)"
  tmp_body="$(mktemp)"
  # -n：不写入文件名与时间戳，保证同样输入产出同样字节（--check 才能比对）
  gzip -9nc "${SRC}" | base64 | tr -d '\n' | fold -w 76 >"${tmp_payload}"

  sed -e "s|@VERSION@|${VERSION}|g" -e "s|@SHA256@|${sha}|g" "${TPL}" >"${tmp_body}"

  # 把 @PAYLOAD@ 这一行替换成 base64 负载
  awk 'NR == FNR { p = p $0 "\n"; next }
       /^@PAYLOAD@$/ { printf "%s", p; next }
       { print }' "${tmp_payload}" "${tmp_body}" >"${out}"

  chmod 0755 "${out}"
  rm -f "${tmp_payload}" "${tmp_body}" 2>/dev/null || true

  printf '\033[1;32m✔\033[0m 已生成 %s\n' "${out}"
  printf '   版本：%s\n' "${VERSION}"
  printf '   sha256：%s\n' "${sha}"
  printf '   大小：%s\n' "$(du -h "${out}" | awk '{print $1}')"
}

case "${1:-}" in
  --check)
    tmp="$(mktemp)"
    gen "${tmp}" >/dev/null
    if [[ ! -f ${OUT} ]]; then
      rm -f "${tmp}" 2>/dev/null || true
      die "install.sh 不存在，请先运行 bash scripts/build-install.sh"
    fi
    if ! diff -q "${OUT}" "${tmp}" >/dev/null 2>&1; then
      rm -f "${tmp}" 2>/dev/null || true
      die "install.sh 已过期：iptables-wizard.sh 或模板有改动，请重新生成（bash scripts/build-install.sh）"
    fi
    rm -f "${tmp}" 2>/dev/null || true
    printf '\033[1;32m✔\033[0m install.sh 与当前源码一致\n'
    ;;
  ""|--force)
    gen "${OUT}"
    ;;
  *)
    die "未知参数：$1（支持 --check）"
    ;;
esac
