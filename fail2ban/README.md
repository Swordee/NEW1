# Fail2ban 一键管理工具（Debian / Ubuntu）

一套面向 Debian / Ubuntu 的 Fail2ban 落地工具：一键脚本、自解压安装器、中文文档与自定义规则范本，附带 ShellCheck CI 检查。

## 目录结构

```
fail2ban/
├── fail2ban-debian.sh          # 主脚本：安装/卸载/重启/状态/目录/日志等
├── install.sh                  # 自解压引导器，支持 curl | bash 远程执行
├── fail2ban-guide.md           # 安装、卸载、SSH 封禁、查看命令完整文档
├── fail2ban-rules-templates.md # 自定义 Filter + Jail 规则范本
├── .shellcheckrc               # ShellCheck 配置（severity=info）
└── scripts/
    ├── build-install.sh        # 由主脚本重新生成 install.sh（内嵌 base64）
    ├── ci-shellcheck.sh        # 本地/CI 通用静态检查
    └── fetch-private.sh        # 私有仓库下载（GitHub API + Token）
```

## 快速开始

### 方式一：本地脚本

```bash
chmod +x fail2ban-debian.sh
sudo ./fail2ban-debian.sh            # 交互菜单
sudo ./fail2ban-debian.sh install    # 安装并启动
sudo ./fail2ban-debian.sh status     # 查看状态与封禁列表
```

### 方式二：自解压引导器

```bash
chmod +x install.sh
sudo ./install.sh                                    # 默认执行 install
sudo ./install.sh install --port 2222 --ignore-ip "1.2.3.4/32" -y
sudo ./install.sh menu                               # 交互菜单
```

### 方式三：私有仓库下载（GitHub API + Token）

本仓库为 **Private**，无法用 jsDelivr / raw 匿名访问，需带 Token 走 GitHub API。

```bash
export GITHUB_TOKEN=ghp_xxxxxxxx          # 需 repo 读权限（fine-grained 选 Contents: Read）

# 1) 取下载脚本
curl -fsSL \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.raw" \
  "https://api.github.com/repos/Swordee/NEW1/contents/fail2ban/scripts/fetch-private.sh?ref=main" \
  -o fetch-private.sh

# 2) 拉取整套工具到 ./src
bash fetch-private.sh --dest ./src

# 3) 安装
sudo ./src/fail2ban/install.sh install --port 2222 -y
```

也可以直接使用仓库内已有的脚本：

```bash
GITHUB_TOKEN=ghp_xxx ./scripts/fetch-private.sh --dest ./src
```

支持参数：`--owner` / `--repo` / `--ref` / `--subdir` / `--dest`。

### 方式四：国内 CDN 加速（jsDelivr，仅公开仓库可用）

> ⚠️ **当前仓库是 Private，下列 jsDelivr 链接会返回 404。** jsDelivr 只能读取公开仓库，
> 如需使用请先把 `NEW1` 设为 Public；私有场景请用「方式三」。

```bash
# 固定版本（推荐，内容不可变）
curl -fsSL https://cdn.jsdelivr.net/gh/Swordee/NEW1@v1.0.0/fail2ban/install.sh \
  | bash -s -- install --port 2222 -y

# 跟随 main（可能被 CDN 缓存，默认数小时）
curl -fsSL https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/fail2ban/install.sh \
  | bash -s -- install --port 2222 -y
```

| 用途 | 地址 |
|------|------|
| 固定版本 | `https://cdn.jsdelivr.net/gh/Swordee/NEW1@v1.0.0/fail2ban/install.sh` |
| 最新 main | `https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/fail2ban/install.sh` |
| 浏览目录 | `https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/fail2ban/` |

说明：`@v1.0.0` 为标签，内容固定；`@main` 会随分支更新，可能被 CDN 缓存。若需刷新缓存，可在 URL 后加 `?t=时间戳`。

## 常用命令

```bash
sudo ./fail2ban-debian.sh install      # 安装并启动
sudo ./fail2ban-debian.sh uninstall    # 卸载
sudo ./fail2ban-debian.sh restart      # 重启
sudo ./fail2ban-debian.sh reload       # 重载配置
sudo ./fail2ban-debian.sh status       # 状态 / 封禁列表
sudo ./fail2ban-debian.sh dir          # 关键目录位置
sudo ./fail2ban-debian.sh logs         # 实时日志
sudo ./fail2ban-debian.sh enable       # 开机自启
sudo ./fail2ban-debian.sh disable      # 取消自启
```

## 文档

- 安装 / 卸载 / 22 端口封禁 / 查看命令：[`fail2ban-guide.md`](fail2ban-guide.md)
- 自定义规则写法与各服务范本：[`fail2ban-rules-templates.md`](fail2ban-rules-templates.md)

## 开发与检查

```bash
./scripts/ci-shellcheck.sh        # 需要 shellcheck
./scripts/build-install.sh        # 修改主脚本后重新生成 install.sh
```

> `install.sh` 由 `scripts/build-install.sh` 自动生成，请勿手动编辑；CI 会校验两者是否同步。

## 安全提示

- 修改配置请写入 `/etc/fail2ban/jail.local`，不要直接改 `jail.conf`。
- 部署前把管理 IP 加入 `ignoreip`，避免误封自己。
