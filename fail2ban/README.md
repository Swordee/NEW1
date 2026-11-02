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
├── scripts/
│   ├── build-install.sh        # 由主脚本重新生成 install.sh（内嵌 base64）
│   ├── ci-shellcheck.sh        # 本地/CI 通用静态检查
│   └── fetch-private.sh        # 私有仓库下载（GitHub API + Token）
├── ci/
│   └── shellcheck-repo-root.yml # 仓库根目录版工作流（见「启用 GitHub Actions」）
└── .github/workflows/
    └── shellcheck.yml          # 子目录版（GitHub 不会触发，仅作模板保留）
```

## 快速开始

### 最省事：一条命令装好并进面板

在服务器上直接执行（普通用户即可，脚本会自己 `sudo`）：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/Swordee/NEW1@v1.0.5/fail2ban/install.sh | bash
```

它会依次自动完成，**全程只需最后在面板里点数字**：

1. 需要时通过 `sudo` 提权
2. 把自己安装成系统命令 `fail2ban-tool`
3. 自动探测 SSH 端口，并把当前登录 IP 加入白名单（避免把自己封掉）
4. 安装并启动 fail2ban
5. 直接进入交互面板

之后随时可以再次打开面板：

```bash
sudo fail2ban-tool
```

面板长这样（顶部实时显示服务状态，下面是操作项）：

```
============================================================
  Fail2ban 管理面板 · Debian / Ubuntu
------------------------------------------------------------
  服务 运行中    自启 是    封禁 6 个    端口 22
  Jail: sshd
------------------------------------------------------------
   1) 一键安装 / 自动修复
   2) 手动安装（自定义端口与白名单）
   3) 自检并处理问题
   4) 查看状态与封禁列表
   5) 重启服务
   6) 重载配置
   7) 查看实时日志
   8) 显示目录位置
   9) 开启开机自启
  10) 关闭开机自启
  11) 卸载
  12) 重装管理命令到 /usr/local/bin
   0) 退出
------------------------------------------------------------
请选择 [0-12]:
```

> 管理命令默认装到 `/usr/local/bin/fail2ban-tool`，可用 `F2B_BIN_DIR` 改到别处。
> 不想自动提权可加 `--no-elevate`，此时非 root 会直接报错。

### 只想装、不要面板

```bash
./fail2ban-debian.sh auto     # 自动探测 → 安装 → 逐项询问是否修复问题
```

### 方式一：本地脚本

```bash
chmod +x fail2ban-debian.sh
./fail2ban-debian.sh                 # 交互菜单
./fail2ban-debian.sh install         # 安装并启动（会询问端口/白名单）
./fail2ban-debian.sh doctor          # 自检并交互式修复
./fail2ban-debian.sh status          # 查看状态与封禁列表
```

### 方式二：自解压引导器

```bash
chmod +x install.sh
sudo ./install.sh                                    # 默认执行 auto（一键+自检）
sudo ./install.sh install --port 2222 --ignore-ip "1.2.3.4/32" -y
sudo ./install.sh doctor                             # 自检并修复
sudo ./install.sh menu                               # 交互菜单
```

### 方式三：私有/内网下载（GitHub API + Token）

仓库若为 **Private**，或需在受限网络下载，可带 Token 走 GitHub API（不依赖 CDN）。

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

### 方式四：国内 CDN 加速（jsDelivr）

> ✅ 本仓库为公开仓库，jsDelivr 可直接访问（国内通常比 `raw.githubusercontent.com` 更稳定）。
> 若将来把仓库改回 Private，CDN 会失效，请改用「方式三」。

```bash
# 固定版本（推荐，内容不可变，不受 CDN 缓存影响）
curl -fsSL https://cdn.jsdelivr.net/gh/Swordee/NEW1@v1.0.5/fail2ban/install.sh \
  | bash -s -- install --port 2222 -y

# 跟随 main（会被 CDN 缓存，实测可能数天不更新，不建议用于生产）
curl -fsSL https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/fail2ban/install.sh \
  | bash -s -- install --port 2222 -y
```

| 用途 | 地址 |
|------|------|
| 固定版本（推荐） | `https://cdn.jsdelivr.net/gh/Swordee/NEW1@v1.0.5/fail2ban/install.sh` |
| 最新 main | `https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/fail2ban/install.sh` |
| 浏览目录 | `https://cdn.jsdelivr.net/gh/Swordee/NEW1@v1.0.5/fail2ban/` |

说明：`@v1.0.5` 是标签，内容固定、**不受缓存影响**，请优先使用。
`@main` 会随分支更新，但 jsDelivr 对分支有较长缓存（实测主动 purge 后仍可能返回旧内容），
因此不要把它当"最新版"依赖；急用时在 URL 后加 `?t=时间戳` 也未必生效。

## 常用命令

```bash
sudo fail2ban-tool                     # 打开交互面板（装好后随时可用）
./fail2ban-debian.sh bootstrap         # 一键部署：装成 fail2ban-tool + 安装 + 进面板
./fail2ban-debian.sh auto              # 一键安装 + 交互自检（自动提权）
./fail2ban-debian.sh install           # 安装并启动
./fail2ban-debian.sh doctor            # 自检并交互式处理问题
./fail2ban-debian.sh uninstall         # 卸载
sudo ./fail2ban-debian.sh restart      # 重启
sudo ./fail2ban-debian.sh reload       # 重载配置
sudo ./fail2ban-debian.sh status       # 状态 / 封禁列表（含 sshd 生效配置）
sudo ./fail2ban-debian.sh info         # 只看 sshd 生效配置与封禁时长
sudo ./fail2ban-debian.sh dir          # 关键目录位置
sudo ./fail2ban-debian.sh logs         # 实时日志
sudo ./fail2ban-debian.sh enable       # 开机自启
sudo ./fail2ban-debian.sh disable      # 取消自启
```

## 自检与问题处理（doctor）

装完之后出问题，先跑这一条：

```bash
./fail2ban-debian.sh doctor
```

它会逐项体检，**每发现一个问题就当场问你要不要修**（`--yes` 则全部自动修）：

| # | 检查项 | 发现时的处理 |
|---|--------|--------------|
| 1 | fail2ban 是否安装 | 询问后直接安装 |
| 2 | `jail.local` 是否存在 | 询问后生成基础配置 |
| 3 | SSH 端口与 `[sshd] port` 是否一致 | 自动读 `sshd -T`，询问后改写配置 |
| 4 | 当前登录 IP 是否在白名单 | 询问后追加到 `ignoreip`（防误封自己） |
| 5 | `auth.log` 缺失（Debian 12+） | 询问后切 `backend = systemd` 并注释 `logpath` |
| 6 | 服务是否运行 | 询问后启动 |
| 7 | 是否开机自启 | 询问后 `systemctl enable` |
| 8 | `sshd` jail 是否真的生效 | 询问后 `reload` |
| 9 | 配置语法 | 执行 `fail2ban-client -t` 并打印错误 |
| 10 | 防火墙工具（iptables/nft） | 给出安装命令 |
| 11 | 当前封禁概况 | 列出每个 jail 的封禁数量 |

结尾会汇总「发现 N 个问题 / 已处理 M 个」，并在配置确实被改写时提示 reload。

在非交互环境（如 `curl | bash` 且无 TTY）中，所有需要确认的修复会自动跳过并只做报告；
加 `--yes` 可让它们全部自动执行。

## 面板没反应 / 输入无响应

如果面板打印出来了，但按数字没反应（或直接闪退），按这个顺序排查。

### 1. 确认是不是在管道里启动的

这是最常见的原因。`curl ... | bash` 时，**stdin 就是那个脚本管道**，脚本读完后立刻 EOF，
面板的 `read` 会瞬间返回失败——表现就是"面板一闪而过"或"敲什么都没反应"。

临时绕过（旧版本也能用）：

```bash
sudo fail2ban-tool < /dev/tty      # 把 stdin 换回终端
```

新版本已内置处理：stdin 不是终端时自动改用 `/dev/tty`，两者都不可用时给出明确提示
（而不是静默退出）。所以升级后直接 `sudo fail2ban-tool` 即可。

### 2. 确认命令装在哪

```bash
command -v fail2ban-tool           # 应输出 /usr/local/bin/fail2ban-tool
ls -l /usr/local/bin/fail2ban-tool
head -n 1 /usr/local/bin/fail2ban-tool   # 应是 #!/usr/bin/env bash
```

若 `command -v` 无输出，说明没装成功；`head -n 1` 显示的是二进制而非 shebang，
说明装错了文件，重新执行：

```bash
sudo ./fail2ban-debian.sh selfinstall
```

### 3. 确认不是被状态查询卡住

面板每轮都会刷新服务状态。如果 `fail2ban-client status` 因 socket 异常挂起，
整个面板会卡在刷新阶段，看起来也像"没反应"。新版本给这类调用加了 3 秒超时。
可以先手动验证：

```bash
timeout 5 fail2ban-client status    # 超过 5 秒没返回 = 服务侧有问题
sudo systemctl restart fail2ban
```

### 4. 输入后要按回车

面板是行缓冲读取，输入 `4` 之后需要按 **回车** 才会执行。

### 5. 还是不行，看非交互输出

绕过面板直接跑命令，确认脚本本身是好的：

```bash
sudo fail2ban-tool status
sudo fail2ban-tool doctor
```

## 服务起不来（`status=255`）

```text
Active: failed (Result: exit-code)
Process: ... ExecStart=/usr/bin/fail2ban-server ... (code=exited, status=255/FAILURE)
```

`255` 只是 fail2ban-server 配置初始化失败后的退出码，**真正原因在 `journalctl` 上一行**：

```bash
sudo journalctl -u fail2ban -n 30 --no-pager
```

最常见的两种：

| 报错 | 原因 | 一行修复 |
|------|------|----------|
| `Have not found any log file for sshd jail` | `jail.local` 里写了 `logpath = /var/log/auth.log`，但 Debian 12+ 没有这个文件 | 注释掉 `logpath`，加 `backend = systemd` |
| `iptables: not found` / `Failed to execute ban action` | `banaction` 写死 iptables，而系统只有 nftables | 改成 `banaction = nftables` |

改完先做语法检查，别直接 restart：

```bash
sudo fail2ban-client -t && sudo systemctl restart fail2ban
```

或者直接交给自检（会自动识别并修复这两类问题）：

```bash
sudo fail2ban-tool doctor
```

> v1.0.5 起 `install` 生成配置时会自动判断系统有无 `auth.log`、有无 `nft`，
> 不再产生这两类错误配置。老版本请先更新。

详细排查表（含 filter 缺失、port 写错等）见
[fail2ban-guide.md](fail2ban-guide.md) 第七节「`status=255` 启动失败专项排查」。

## 配置文件位置速查

| 用途 | 路径 |
|------|------|
| 主配置目录 | `/etc/fail2ban/` |
| 默认 jail 定义（含 22 端口的 `[sshd]`） | `/etc/fail2ban/jail.conf` |
| Debian 包默认启用 sshd | `/etc/fail2ban/jail.d/defaults-debian.conf` |
| 本工具写入的本地覆盖 | `/etc/fail2ban/jail.local` |
| **新建规则放这里** | `/etc/fail2ban/jail.d/<服务名>.local` |
| 自定义过滤器（日志正则） | `/etc/fail2ban/filter.d/<服务名>.conf` |
| 运行日志 | `/var/log/fail2ban.log` |
| 封禁数据库 | `/var/lib/fail2ban/fail2ban.sqlite3` |

**加载优先级（后者覆盖前者）：**

```
jail.conf  →  jail.d/*.conf  →  jail.local  →  jail.d/*.local
```

所以默认的 22 端口配置不是一个文件，而是：
`jail.conf` 里的 `[sshd] port = ssh` + `paths-common.conf` 的日志路径
+ `paths-debian.conf` 的 `backend = systemd` + `jail.d/defaults-debian.conf` 的 `enabled = true`
+ `jail.local` 里的实际阈值，四层叠加。

```bash
sudo fail2ban-tool dir          # 打印全部路径与实际文件列表
sudo fail2ban-client get sshd bantime   # 看封禁时长等生效值
```

完整说明（含新建规则的完整示例、Debian 12 的 nftables/systemd 差异）见
[fail2ban-guide.md](fail2ban-guide.md) 第三节。

## 文档

- 安装 / 卸载 / 22 端口封禁 / 查看命令：[`fail2ban-guide.md`](fail2ban-guide.md)
- 自定义规则写法与各服务范本：[`fail2ban-rules-templates.md`](fail2ban-rules-templates.md)

## 开发与检查

```bash
./scripts/ci-shellcheck.sh        # 需要 shellcheck
./scripts/build-install.sh        # 修改主脚本后重新生成 install.sh
```

> `install.sh` 由 `scripts/build-install.sh` 自动生成，请勿手动编辑；CI 会校验两者是否同步。

### 启用 GitHub Actions

GitHub 只识别**仓库根目录**的 `.github/workflows/`，而本工具集在 `fail2ban/` 子目录下，
所以 `fail2ban/.github/workflows/shellcheck.yml` **不会自动触发**。在仓库根目录执行一次即可启用：

```bash
mkdir -p .github/workflows
cp fail2ban/ci/shellcheck-repo-root.yml .github/workflows/shellcheck.yml
git add .github/workflows/shellcheck.yml
git commit -m "ci: enable shellcheck workflow at repo root"
git push
```

`ci/shellcheck-repo-root.yml` 与子目录版本逻辑一致，额外做了两处适配：
步骤统一 `working-directory: fail2ban`，并用 `paths` 过滤（仅当 `fail2ban/` 有改动时触发）。

## 安全提示

- 修改配置请写入 `/etc/fail2ban/jail.local`，不要直接改 `jail.conf`。
- 部署前把管理 IP 加入 `ignoreip`，避免误封自己。
