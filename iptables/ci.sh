#!/usr/bin/env bash
# ==============================================================================
#  ci.sh — 本地 CI 总入口（与 .github/workflows/ci.yml 的检查项保持一致）
# ------------------------------------------------------------------------------
#  在提交前跑一遍，等价于远端 CI 会做的事：
#    1. 语法检查        bash -n 全部 shell 脚本
#    2. 静态分析        shellcheck -S style（--strict 提到 info 级）
#    3. 冒烟测试        tests/smoke.sh（不需要 root，不动真实 netfilter）
#    4. 安装器新鲜度    scripts/build-install.sh --check
#    5. 安装器自检      install.sh --check（sha256 + bash -n + 版本）
#    6. 版本一致性      内嵌版本 == 主脚本 VERSION，且无残留占位符
#
#  用法：
#    bash ci.sh                    # 全量检查
#    bash ci.sh --quick            # 跳过冒烟测试（改文档/注释时用）
#    bash ci.sh --strict           # shellcheck 提升到 info 级别
#    bash ci.sh --fix              # 先重新生成 install.sh，再做全量检查
#    bash ci.sh --only syntax,version   # 只跑指定项
#    bash ci.sh --list             # 列出所有检查项
#    bash ci.sh --no-color         # 关闭颜色（写日志用）
#
#  环境变量：
#    SHELLCHECK_BIN=/path/to/shellcheck   指定 shellcheck（默认自动探测）
#    NO_COLOR=1                           关闭颜色
#    FORCE_COLOR=1                        非终端也输出颜色
#
#  退出码：0 全部通过；1 有检查项失败；2 参数错误
# ==============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}" || { printf '无法进入目录 %s\n' "${ROOT_DIR}" >&2; exit 1; }

WIZARD="${ROOT_DIR}/iptables-wizard.sh"
INSTALLER="${ROOT_DIR}/install.sh"
SMOKE="${ROOT_DIR}/tests/smoke.sh"
BUILD="${ROOT_DIR}/scripts/build-install.sh"
TEMPLATE="${ROOT_DIR}/scripts/install.template.sh"

# ------------------------------------------------------------------ 颜色 -----
C_RESET=''; C_BOLD=''; C_DIM=''
C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''

USE_COLOR=0
if [[ -n ${FORCE_COLOR:-} ]]; then
  USE_COLOR=1
elif [[ -z ${NO_COLOR:-} && -t 1 ]]; then
  USE_COLOR=1
fi

init_color() {
  (( USE_COLOR )) || return 0
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  C_RED=$'\e[1;31m'; C_GREEN=$'\e[1;32m'; C_YELLOW=$'\e[1;33m'; C_CYAN=$'\e[1;36m'
}

MARK_OK='✔'; MARK_NO='✘'; MARK_DOT='·'

# ---------------------------------------------------------------- 参数解析 ---
QUICK=0
STRICT=0
DO_FIX=0
ONLY=""

usage() {
  sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while (( $# )); do
  case "$1" in
    --quick)     QUICK=1 ;;
    --strict)    STRICT=1 ;;
    --fix)       DO_FIX=1 ;;
    --no-color)  USE_COLOR=0; NO_COLOR=1 ;;
    --color)     USE_COLOR=1 ;;
    --only)      shift; ONLY="${1:-}" ;;
    --only=*)    ONLY="${1#*=}" ;;
    --list)      printf '检查项：syntax shellcheck smoke build installer version\n'; exit 0 ;;
    -h|--help)   usage ;;
    *)           printf '未知参数：%s（--help 查看用法）\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

init_color

SC_SEVERITY="style"
(( STRICT )) && SC_SEVERITY="info"

# ------------------------------------------------------------ shellcheck -----
SC_BIN=""

find_shellcheck() {
  local c py d
  if [[ -n ${SHELLCHECK_BIN:-} ]]; then
    if [[ -x ${SHELLCHECK_BIN} ]]; then SC_BIN=${SHELLCHECK_BIN}; return 0; fi
    printf 'SHELLCHECK_BIN 指向的文件不可执行：%s\n' "${SHELLCHECK_BIN}" >&2
    return 1
  fi
  if c=$(command -v shellcheck 2>/dev/null) && [[ -n ${c} ]]; then
    SC_BIN=${c}; return 0
  fi
  # 常见安装目录（brew / 手工 make install / pip --user / 激活的 venv）
  for d in "${VIRTUAL_ENV:-}/bin" "${VIRTUAL_ENV:-}/Scripts" \
           "${HOME}/.local/bin" /usr/local/bin /opt/homebrew/bin /usr/bin; do
    [[ -n ${d} ]] || continue
    if [[ -x ${d}/shellcheck ]]; then SC_BIN="${d}/shellcheck"; return 0; fi
    if [[ -x ${d}/shellcheck.exe ]]; then SC_BIN="${d}/shellcheck.exe"; return 0; fi
  done
  # pip 安装的 shellcheck-py 落在 Python 的 scripts 目录，未必在 PATH 里
  for py in python3 python py; do
    command -v "${py}" >/dev/null 2>&1 || continue
    c=$("${py}" - <<'PYEOF' 2>/dev/null
import os, sysconfig
scripts = sysconfig.get_path("scripts") or ""
for name in ("shellcheck.exe", "shellcheck"):
    path = os.path.join(scripts, name)
    if os.path.isfile(path):
        print(path)
        break
PYEOF
)
    if [[ -n ${c} && -x ${c} ]]; then SC_BIN=${c}; return 0; fi
  done
  return 1
}

# ------------------------------------------------------------ 脚本清单 ------
SHELL_FILES=()
collect_files() {
  local f
  for f in "${WIZARD}" "${INSTALLER}" "${BUILD}" "${TEMPLATE}" "${SMOKE}" \
           "${ROOT_DIR}/ci.sh"; do
    [[ -f ${f} ]] && SHELL_FILES+=("${f}")
  done
}

rel() { printf '%s' "${1#"${ROOT_DIR}/"}"; }

# ================================================================ 检查项 =====

# 1) 语法检查 ---------------------------------------------------------------
step_syntax() {
  local f out rc bad=0
  for f in "${SHELL_FILES[@]}"; do
    out=$(bash -n "${f}" 2>&1)
    rc=$?
    if (( rc == 0 )); then
      printf '   %b %s\n' "${C_GREEN}${MARK_OK}${C_RESET}" "$(rel "${f}")"
    else
      bad=1
      printf '   %b %s\n' "${C_RED}${MARK_NO}${C_RESET}" "$(rel "${f}")"
      printf '%s\n' "${out}" | sed 's/^/       /'
    fi
  done
  (( bad == 0 )) || return 1
  return 0
}

# 2) 静态分析 ---------------------------------------------------------------
step_shellcheck() {
  local out rc
  if ! find_shellcheck; then
    printf '   %b 未找到 shellcheck\n' "${C_RED}${MARK_NO}${C_RESET}"
    printf '       安装方式任选其一：\n'
    printf '         Debian/Ubuntu : sudo apt-get install -y shellcheck\n'
    printf '         macOS         : brew install shellcheck\n'
    printf '         通用（pip）   : pip install shellcheck-py\n'
    printf '       或指定路径：SHELLCHECK_BIN=/path/to/shellcheck bash ci.sh\n'
    return 1
  fi

  out=$("${SC_BIN}" -S "${SC_SEVERITY}" -f gcc "${SHELL_FILES[@]}" 2>&1)
  rc=$?
  if [[ -n ${out} ]]; then
    printf '%s\n' "${out}" | sed 's/^/       /'
  fi
  if (( rc != 0 )); then
    printf '   %b 存在待修复的告警（级别：%s）\n' "${C_RED}${MARK_NO}${C_RESET}" "${SC_SEVERITY}"
    return 1
  fi
  printf '   %b %d 个脚本，0 条告警（级别：%s）\n' \
    "${C_GREEN}${MARK_OK}${C_RESET}" "${#SHELL_FILES[@]}" "${SC_SEVERITY}"
  return 0
}

# 3) 冒烟测试 ---------------------------------------------------------------
step_smoke() {
  local out rc summary
  if [[ ! -f ${SMOKE} ]]; then
    printf '   %b 找不到 %s\n' "${C_RED}${MARK_NO}${C_RESET}" "$(rel "${SMOKE}")"
    return 1
  fi
  out=$(bash "${SMOKE}" 2>&1)
  rc=$?
  if (( rc != 0 )); then
    printf '%s\n' "${out}" | sed 's/^/       /'
    return 1
  fi
  # 只取「全部通过：N 项」这一段，避免和本脚本自己的 ✔ 重复
  summary=$(printf '%s\n' "${out}" | grep -o '全部通过.*' | tail -n 1)
  printf '   %b %s\n' "${C_GREEN}${MARK_OK}${C_RESET}" "${summary:-全部通过}"
  return 0
}

# 4) 安装器新鲜度 -----------------------------------------------------------
step_build() {
  local out rc
  if [[ ! -f ${BUILD} ]]; then
    printf '   %b 找不到 %s\n' "${C_RED}${MARK_NO}${C_RESET}" "$(rel "${BUILD}")"
    return 1
  fi
  if (( DO_FIX )); then
    out=$(bash "${BUILD}" 2>&1)
    printf '%s\n' "${out}" | sed 's/^/       /'
  fi
  out=$(bash "${BUILD}" --check 2>&1)
  rc=$?
  if (( rc != 0 )); then
    printf '   %b %s\n' "${C_RED}${MARK_NO}${C_RESET}" "install.sh 与源码不同步"
    printf '%s\n' "${out}" | sed 's/^/       /'
    printf '       修复：bash scripts/build-install.sh\n'
    return 1
  fi
  printf '   %b install.sh 与当前源码一致\n' "${C_GREEN}${MARK_OK}${C_RESET}"
  return 0
}

# 5) 安装器自检 -------------------------------------------------------------
step_installer() {
  local out rc
  if [[ ! -f ${INSTALLER} ]]; then
    printf '   %b 找不到 install.sh，请先运行 bash scripts/build-install.sh\n' \
      "${C_RED}${MARK_NO}${C_RESET}"
    return 1
  fi
  out=$(bash "${INSTALLER}" --check 2>&1)
  rc=$?
  if (( rc != 0 )); then
    printf '%s\n' "${out}" | sed 's/^/       /'
    return 1
  fi
  # 只回显关键几行，避免日志过长
  printf '%s\n' "${out}" | grep -E '完整性|语法|内嵌脚本版本' | sed 's/^[[:space:]]*/       /'
  printf '   %b 内嵌负载可解码、校验通过、语法正确\n' "${C_GREEN}${MARK_OK}${C_RESET}"
  return 0
}

# 6) 版本一致性 -------------------------------------------------------------
step_version() {
  local v_main v_inst v_tpl leftover bad=0
  v_main=$(sed -n 's/^readonly VERSION="\([^"]*\)"$/\1/p' "${WIZARD}" 2>/dev/null | head -n 1)
  if [[ -z ${v_main} ]]; then
    printf '   %b 无法从主脚本解析 VERSION\n' "${C_RED}${MARK_NO}${C_RESET}"
    return 1
  fi
  printf '   %b 主脚本版本 %s\n' "${C_GREEN}${MARK_OK}${C_RESET}" "${v_main}"

  if [[ -f ${INSTALLER} ]]; then
    v_inst=$(bash "${INSTALLER}" --version 2>/dev/null | awk '{print $NF}')
    if [[ ${v_inst} == "${v_main}" ]]; then
      printf '   %b 安装器版本 %s\n' "${C_GREEN}${MARK_OK}${C_RESET}" "${v_inst}"
    else
      bad=1
      printf '   %b 安装器版本 [%s] != 主脚本 [%s]\n' \
        "${C_RED}${MARK_NO}${C_RESET}" "${v_inst:-空}" "${v_main}"
    fi

    leftover=$(grep -c '@VERSION@\|@SHA256@\|@PAYLOAD@' "${INSTALLER}" 2>/dev/null || true)
    if [[ ${leftover} != "0" ]]; then
      bad=1
      printf '   %b install.sh 残留 %s 处未替换的占位符\n' \
        "${C_RED}${MARK_NO}${C_RESET}" "${leftover}"
    else
      printf '   %b 无残留占位符\n' "${C_GREEN}${MARK_OK}${C_RESET}"
    fi
  fi

  if [[ -f ${TEMPLATE} ]]; then
    v_tpl=$(grep -c '@VERSION@\|@SHA256@\|@PAYLOAD@' "${TEMPLATE}" 2>/dev/null || true)
    if [[ ${v_tpl} == "0" ]]; then
      bad=1
      printf '   %b 模板缺少占位符，构建脚本将无法替换\n' "${C_RED}${MARK_NO}${C_RESET}"
    fi
  fi

  (( bad == 0 )) || return 1
  return 0
}

# ================================================================ 调度器 =====

STEP_KEYS=(   syntax  shellcheck  smoke  build  installer  version )
STEP_LABELS=( "语法检查 (bash -n)" \
              "静态分析 (shellcheck)" \
              "冒烟测试 (tests/smoke.sh)" \
              "安装器新鲜度 (build-install --check)" \
              "安装器自检 (install.sh --check)" \
              "版本一致性" )
STEP_FUNCS=(  step_syntax step_shellcheck step_smoke step_build step_installer step_version )

SEL_KEYS=(); SEL_LABELS=(); SEL_FUNCS=()

select_steps() {
  local i key wanted
  for i in "${!STEP_KEYS[@]}"; do
    key=${STEP_KEYS[$i]}
    if [[ -n ${ONLY} ]]; then
      case ",${ONLY}," in
        *",${key},"*) : ;;
        *) continue ;;
      esac
    fi
    if (( QUICK )) && [[ ${key} == smoke ]]; then continue; fi
    SEL_KEYS+=("${key}")
    SEL_LABELS+=("${STEP_LABELS[$i]}")
    SEL_FUNCS+=("${STEP_FUNCS[$i]}")
  done

  if [[ -n ${ONLY} && ${#SEL_KEYS[@]} -eq 0 ]]; then
    printf '%s\n' "--only 未匹配到任何检查项：${ONLY}" >&2
    printf '可用项：%s\n' "${STEP_KEYS[*]}" >&2
    exit 2
  fi
  # 校验 --only 里是否写了不存在的名字
  for wanted in ${ONLY//,/ }; do
    local found=0 k
    for k in "${STEP_KEYS[@]}"; do [[ ${k} == "${wanted}" ]] && found=1; done
    if (( found == 0 )); then
      printf '未知检查项：%s（可用：%s）\n' "${wanted}" "${STEP_KEYS[*]}" >&2
      exit 2
    fi
  done
}

HR_LINE='──────────────────────────────────────────────────────────────'
hr() { printf '%s\n' "${HR_LINE}"; }

sc_version() {
  [[ -n ${SC_BIN} ]] || return 0
  local v
  v=$("${SC_BIN}" --version 2>/dev/null | sed -n 's/^version: *//p' | head -n 1)
  printf '%s' "${v:-unknown}"
}

main() {
  collect_files

  local total=${#SEL_FUNCS[@]} n=0 fails=0 start=${SECONDS}
  local i label fn t0 dt status scv
  local -a FAILED_LABELS=()

  # 提前探测一次 shellcheck，方便在表头显示版本
  find_shellcheck >/dev/null 2>&1 || true
  scv=$(sc_version)

  printf '\n'
  hr
  printf ' %s iptables-wizard CI\n' "${C_BOLD}${C_CYAN}${MARK_DOT}${C_RESET}"
  printf ' %s %s\n' "${C_DIM}${MARK_DOT}${C_RESET}" "${C_DIM}${ROOT_DIR}${C_RESET}"
  printf ' %s bash %s · shellcheck %s · 级别 %s\n' "${C_DIM}${MARK_DOT}${C_RESET}" \
    "${BASH_VERSION%%(*}" "${scv:-未安装}" "${SC_SEVERITY}"
  (( QUICK )) && printf ' %s 已跳过冒烟测试（--quick）\n' "${C_YELLOW}${MARK_DOT}${C_RESET}"
  hr

  for i in "${!SEL_FUNCS[@]}"; do
    n=$((n + 1))
    label=${SEL_LABELS[$i]}
    fn=${SEL_FUNCS[$i]}
    printf '\n %s%s %d/%d %s%s\n' "${C_BOLD}" '▶' "${n}" "${total}" "${label}" "${C_RESET}"
    t0=${SECONDS}
    if "${fn}"; then status=0; else status=$?; fi
    dt=$(( SECONDS - t0 ))
    if (( status == 0 )); then
      printf '   %s通过%s %s\n' "${C_GREEN}" "${C_RESET}" "${C_DIM}(${dt}s)${C_RESET}"
    else
      fails=$((fails + 1))
      FAILED_LABELS+=("${label}")
      printf '   %s失败%s %s\n' "${C_RED}" "${C_RESET}" "${C_DIM}(${dt}s)${C_RESET}"
    fi
  done

  printf '\n'
  hr
  if (( fails == 0 )); then
    printf ' %s 全部通过：%d 项 · 耗时 %ds\n' "${C_GREEN}${C_BOLD}${MARK_OK}${C_RESET}" \
      "${total}" "$(( SECONDS - start ))"
    hr
    printf '\n'
    return 0
  fi

  printf ' %s 失败 %d 项 / 共 %d 项 · 耗时 %ds\n' "${C_RED}${C_BOLD}${MARK_NO}${C_RESET}" \
    "${fails}" "${total}" "$(( SECONDS - start ))"
  for label in "${FAILED_LABELS[@]}"; do
    printf '    - %s\n' "${label}"
  done
  hr
  printf '\n'
  return 1
}

select_steps
main
