#!/usr/bin/env bash
#
# push-to-github.sh — 将本项目一键推送到 GitHub
#
# 设计要点：
#   1. Token 使用 read -s 静默读取，不落盘、不进 .git/config
#   2. 推送时通过一次性 credential.helper 传入 Token（不出现在进程列表）
#   3. 兼容 curl | bash（stdin 被占用时自动从 /dev/tty 读取）
#   4. 支持非交互：GH_TOKEN / GH_USER / GH_REPO 环境变量 + 参数
#
# 用法：
#   bash push-to-github.sh                    # 全交互
#   bash push-to-github.sh -u yourname -r myrepo --private
#
set -Eeuo pipefail

readonly SCRIPT_VERSION="1.0"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info() { printf '%s\n' "${CYAN}[信息]${NC} $*"; }
ok()   { printf '%s\n' "${GREEN}[成功]${NC} $*"; }
warn() { printf '%s\n' "${YELLOW}[警告]${NC} $*"; }
err()  { printf '%s\n' "${RED}[错误]${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------- 交互读取
# stdin 不是终端（curl | bash）时改从 /dev/tty 读，否则 read 会立刻 EOF
# 用子 shell 探测 /dev/tty 是否真的可用，避免 "No such device or address" 噪音
_tty_ok() { { : < /dev/tty; } 2>/dev/null; }

prompt() {
    local text="$1" ans=""
    if [[ -t 0 ]]; then
        read -r -p "$text" ans || ans=""
    elif _tty_ok; then
        { read -r -p "$text" ans < /dev/tty; } 2>/dev/null || ans=""
    else
        return 1
    fi
    printf '%s' "$ans"
}

# 静默读取（Token / 密码），不回显
prompt_secret() {
    local text="$1" ans=""
    if [[ -t 0 ]]; then
        read -r -s -p "$text" ans || ans=""
        printf '\n' >&2
    elif _tty_ok; then
        { read -r -s -p "$text" ans < /dev/tty; } 2>/dev/null || ans=""
        printf '\n' >&2
    else
        return 1
    fi
    printf '%s' "$ans"
}

# ---------------------------------------------------------------- 参数
GH_USER="${GH_USER:-}"
GH_REPO="${GH_REPO:-}"
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
VISIBILITY="private"
MODE="https"          # https | ssh | local
DRY_RUN=0
ASSUME_YES=0

usage() {
    cat <<'EOF'
push-to-github.sh — 将本项目推送到 GitHub

用法:
  bash push-to-github.sh [选项]

选项:
  -u, --user <name>    GitHub 用户名
  -r, --repo <name>    仓库名（默认 debian-ssh-port-tool）
      --public         创建公开仓库（默认 private）
      --private        创建私有仓库（默认）
      --https          使用 HTTPS + 访问令牌推送（默认，推荐）
      --ssh            使用 SSH 推送（需已配置密钥，且 22 端口可达）
      --local          只做本地提交，不推送，由你手动推
  -t, --token <tok>    访问令牌（建议改用 GH_TOKEN 环境变量，避免留在 shell 历史）
  -y, --yes            跳过最终确认
  -n, --dry-run        预演，只显示将执行的命令
  -V, --version        显示版本
  -h, --help           显示本帮助

环境变量:
  GH_TOKEN / GITHUB_TOKEN   访问令牌
  GH_USER                    GitHub 用户名
  GH_REPO                    仓库名

Token 权限: 勾选 repo（私有仓库必需）。创建 Token:
  https://github.com/settings/tokens/new
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--user)
            [[ $# -ge 2 ]] || die "选项 $1 缺少参数"
            GH_USER="$2"; shift 2 ;;
        -r|--repo)
            [[ $# -ge 2 ]] || die "选项 $1 缺少参数"
            GH_REPO="$2"; shift 2 ;;
        -t|--token)
            [[ $# -ge 2 ]] || die "选项 $1 缺少参数"
            GH_TOKEN="$2"; shift 2 ;;
        --public)   VISIBILITY="public"; shift ;;
        --private)  VISIBILITY="private"; shift ;;
        --https)    MODE="https"; shift ;;
        --ssh)      MODE="ssh"; shift ;;
        --local)    MODE="local"; shift ;;
        -y|--yes)   ASSUME_YES=1; shift ;;
        -n|--dry-run) DRY_RUN=1; shift ;;
        -V|--version) printf 'push-to-github.sh v%s\n' "$SCRIPT_VERSION"; exit 0 ;;
        -h|--help)  usage; exit 0 ;;
        *) die "未知选项: $1（用 -h 查看帮助）" ;;
    esac
done

# ---------------------------------------------------------------- 工具函数
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '%s\n' "${YELLOW}[预演]${NC} $*"
    else
        "$@"
    fi
}

# 用一次性 credential.helper 把 Token 传给 git，不写入 .git/config
git_push_with_token() {
    local url="$1" branch="$2"
    # 单引号是故意的：$GH_USER / $GH_TOKEN 需由 git 调用 helper 时才展开
    # shellcheck disable=SC2016
    GH_USER="$GH_USER" GH_TOKEN="$GH_TOKEN" \
        git -c credential.helper='!f() { echo username="$GH_USER"; echo password="$GH_TOKEN"; }; f' \
        push -u "$url" "$branch"
}

# 拉取远程 main；远程为空仓库时返回非零（调用方容忍即可）
git_fetch_remote() {
    local url="$1"
    if [[ "$MODE" == "https" ]]; then
        # shellcheck disable=SC2016
        GH_USER="$GH_USER" GH_TOKEN="$GH_TOKEN" GIT_TERMINAL_PROMPT=0 \
            git -c credential.helper='!f() { echo username="$GH_USER"; echo password="$GH_TOKEN"; }; f' \
            fetch -q "$url" main >/dev/null 2>&1
    else
        GIT_TERMINAL_PROMPT=0 git fetch -q "$url" main >/dev/null 2>&1
    fi
}

# 调 GitHub API 创建仓库（Token 通过 curl 配置文件传入，不进 argv）
create_repo_api() {
    local name="$1" vis="$2" cfg rc=0
    cfg="$(mktemp)"
    chmod 600 "$cfg"
    {
        printf 'header = "Authorization: Bearer %s"\n' "$GH_TOKEN"
        printf 'header = "Accept: application/vnd.github+json"\n'
        printf 'header = "X-GitHub-Api-Version: 2022-11-28"\n'
    } > "$cfg"

    local payload
    payload="$(printf '{"name":"%s","private":%s,"description":"Debian SSH 端口更换工具（交互式 / 自解压安装）"}' \
        "$name" "$([[ "$vis" == "private" ]] && echo true || echo false)")"

    local out
    out="$(curl -sS -m 30 -w '\n%{http_code}' -X POST -K "$cfg" \
        https://api.github.com/user/repos -d "$payload" 2>&1)" || rc=$?
    rm -f "$cfg"

    if [[ $rc -ne 0 ]]; then
        err "调用 GitHub API 失败（网络问题？）"
        printf '%s\n' "$out"
        return 1
    fi

    local code
    code="$(printf '%s' "$out" | tail -n1)"
    case "$code" in
        201)
            ok "已在 GitHub 创建仓库: $GH_USER/$name（$vis）"
            return 0 ;;
        422)
            warn "仓库 $GH_USER/$name 已存在，继续推送。"
            return 0 ;;
        401)
            err "Token 无效或已过期（HTTP 401）。请重新生成 Token。"
            return 1 ;;
        403)
            err "Token 权限不足（HTTP 403）。请确认已勾选 repo 权限。"
            return 1 ;;
        *)
            err "创建仓库失败，HTTP $code"
            printf '%s\n' "$out" | head -n -1
            return 1 ;;
    esac
}

# ---------------------------------------------------------------- 主流程
main() {
    printf '%s\n' "${BOLD}================================================${NC}"
    printf '%s\n' "${BOLD}  Debian SSH 端口更换工具 — 推送到 GitHub${NC}"
    printf '%s\n' "${BOLD}================================================${NC}"
    printf '\n'

    command -v git >/dev/null 2>&1 || die "未找到 git，请先安装：https://git-scm.com/downloads"

    local here root
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || die "无法进入脚本所在目录"
    # 脚本可能位于分类子目录（如 Debian SSH/），需定位到仓库根再操作，
    # 否则 git add -A 只会暂存当前子目录
    root="$(git -C "$here" rev-parse --show-toplevel 2>/dev/null || true)"
    cd "${root:-$here}" || die "无法进入项目目录"
    root="$(pwd)"
    info "项目目录: $root"

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        info "初始化 git 仓库 ..."
        run git init -b main >/dev/null
    fi

    # ---------- 提交身份 ----------
    local cname cemail
    cname="$(git config --get user.name 2>/dev/null || true)"
    cemail="$(git config --get user.email 2>/dev/null || true)"
    if [[ -z "$cname" || -z "$cemail" ]]; then
        warn "git 提交身份未配置，需要设置 user.name / user.email"
        [[ -n "$cname" ]] || cname="$(prompt "  Git 用户名: ")" || cname=""
        [[ -n "$cemail" ]] || cemail="$(prompt "  Git 邮箱（建议与 GitHub 一致）: ")" || cemail=""
        if [[ -z "$cname" || -z "$cemail" ]]; then
            die "无法读取提交身份（当前环境无终端）。请先手动设置：
  git config --local user.name \"你的名字\"
  git config --local user.email \"你的邮箱\""
        fi
        run git config --local user.name "$cname"
        run git config --local user.email "$cemail"
        ok "已设置本仓库提交身份: $cname <$cemail>"
    else
        info "提交身份: $cname <$cemail>"
    fi

    # ---------- 远程信息 ----------
    if [[ "$MODE" != "local" ]]; then
        if [[ -z "$GH_USER" ]]; then
            GH_USER="$(prompt "GitHub 用户名: ")" || GH_USER=""
            [[ -n "$GH_USER" ]] || die "未提供用户名（当前环境无终端，可用 -u 参数指定）"
        fi
        if [[ -z "$GH_REPO" ]]; then
            local def="debian-ssh-port-tool"
            local input
            input="$(prompt "仓库名（默认 $def）: ")" || input=""
            GH_REPO="${input:-$def}"
        fi
        printf '\n'
        info "目标仓库: https://github.com/${GH_USER}/${GH_REPO}  （${VISIBILITY}）"
        info "推送方式: ${MODE}"

        # ---------- 认证准备 ----------
        if [[ "$MODE" == "https" && -z "$GH_TOKEN" ]]; then
            warn "需要一个 GitHub 访问令牌（Personal Access Token）"
            info "生成地址: https://github.com/settings/tokens/new  → 勾选 repo 权限"
            GH_TOKEN="$(prompt_secret "  粘贴 Token（输入不回显）: ")" || GH_TOKEN=""
            [[ -n "$GH_TOKEN" ]] || die "未提供 Token，已中止（可用 GH_TOKEN 环境变量或 -t 参数传入）"
        fi
        if [[ "$MODE" == "ssh" ]]; then
            warn "SSH 方式需要已配置密钥且 github.com:22 可达"
            info "检测到本机 SSH 22 端口常被网络阻断，若失败请改用 HTTPS"
        fi
        printf '\n'
    fi

    # ---------- 建仓与 remote（放在提交之前，便于对齐远程已有历史）----------
    local url=""
    if [[ "$MODE" != "local" ]]; then
        if [[ "$MODE" == "https" && $DRY_RUN -eq 0 ]]; then
            info "检查 / 创建远程仓库 ..."
            create_repo_api "$GH_REPO" "$VISIBILITY" || warn "跳过自动建仓，将直接尝试推送（仓库需已存在）"
        fi

        if [[ "$MODE" == "ssh" ]]; then
            url="git@github.com:${GH_USER}/${GH_REPO}.git"
        else
            url="https://github.com/${GH_USER}/${GH_REPO}.git"
        fi

        if git remote get-url origin >/dev/null 2>&1; then
            info "更新 origin → $url"
            run git remote set-url origin "$url"
        else
            info "添加 origin → $url"
            run git remote add origin "$url"
        fi

        # 远程若已有初始提交（建仓时勾了 README 就会这样），把本地接到它上面，
        # 避免 unrelated histories / non-fast-forward 报错。
        # 仅在本地还没有任何提交时执行，绝不会覆盖已有历史。
        if [[ $DRY_RUN -eq 0 ]] && ! git rev-parse --verify HEAD >/dev/null 2>&1; then
            if git_fetch_remote "$url"; then
                if git rev-parse --verify origin/main >/dev/null 2>&1; then
                    git reset --soft origin/main
                    ok "已对齐远程 main 历史（本次提交将作为它的后继）"
                fi
            fi
        fi
    fi

    # ---------- 提交 ----------
    run git add -A

    if git diff --cached --quiet 2>/dev/null; then
        info "没有需要提交的改动"
    else
        local msg="feat: Debian SSH 端口更换工具 v2.4

- change_ssh_port.sh: 交互式更换端口，保留旧端口过渡
- remove_old_ssh_port.sh: 验证通过后移除旧端口
- install.sh: 自解压一键安装（curl | bash）
- push-to-github.sh: 一键推送到 GitHub
- check.sh + GitHub Actions: ShellCheck CI
- 完整使用文档与高亮展示页"
        info "创建提交 ..."
        run git commit -m "$msg"
        ok "提交完成"
    fi

    run git branch -M main

    if [[ "$MODE" == "local" ]]; then
        printf '\n'
        ok "本地仓库已就绪（未推送）"
        printf '\n后续手动推送：\n'
        printf '  git remote add origin https://github.com/<你的用户名>/<仓库名>.git\n'
        printf '  git push -u origin main\n'
        return 0
    fi

    # ---------- 最终确认 ----------
    if [[ $ASSUME_YES -eq 0 && $DRY_RUN -eq 0 ]]; then
        printf '\n'
        local c
        c="$(prompt "确认推送到 https://github.com/${GH_USER}/${GH_REPO} ？(y/N) ")" || c=""
        case "$c" in
            y|Y|yes|YES) ;;
            *) warn "已取消。"; exit 0 ;;
        esac
    fi

    # ---------- 推送 ----------
    printf '\n'
    info "推送中 ..."
    local rc=0
    if [[ $DRY_RUN -eq 1 ]]; then
        run git push -u origin main
    elif [[ "$MODE" == "https" ]]; then
        git_push_with_token "$url" main || rc=$?
    else
        git push -u origin main || rc=$?
    fi

    printf '\n'
    if [[ $rc -ne 0 ]]; then
        err "推送失败（退出码 $rc）"
        printf '\n排查建议：\n'
        printf '  1. Token 是否勾选了 repo 权限、是否过期\n'
        printf '  2. 仓库名是否与 GitHub 上一致（大小写敏感）\n'
        printf '  3. 若报 non-fast-forward / unrelated histories，说明远程已有提交：\n'
        printf '     git fetch origin main && git log --oneline origin/main   # 先看清远程内容\n'
        printf '     git pull --rebase --allow-unrelated-histories origin main # 再合并\n'
        printf '  4. 网络受限可配置代理: git config --global http.proxy http://127.0.0.1:7890\n'
        exit "$rc"
    fi

    ok "推送成功！"
    printf '\n仓库地址: %s\n' "${GREEN}https://github.com/${GH_USER}/${GH_REPO}${NC}"
    printf '\n后续提交只需：\n'
    printf '  git add -A && git commit -m "说明" && git push\n'
}

main "$@"
