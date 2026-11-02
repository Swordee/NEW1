# Debian 运维工具集

面向 **Debian / Ubuntu** 的一站式运维脚本合集。每个分类独立成目录，自带一键脚本、自解压安装器、中文文档与 ShellCheck CI 检查，复制即用。

> 仓库地址：<https://github.com/Swordee/NEW1>

## 分类

| 分类 | 说明 | 入口 |
| --- | --- | --- |
| **Debian SSH** | 安全更换 SSH 端口：交互式面板、过渡期保留旧端口、校验失败自动回滚 | [进入分类](https://github.com/Swordee/NEW1/tree/main/Debian%20SSH) |
| **iptables** | iptables 防火墙一键管理，纯 Bash 无 whiptail 依赖，变更前自动备份 | [进入分类](https://github.com/Swordee/NEW1/tree/main/iptables) |
| **fail2ban** | Fail2ban 落地工具集：一键脚本、安装器、中文文档与自定义规则范本 | [进入分类](https://github.com/Swordee/NEW1/tree/main/fail2ban) |

## 三十秒上手（SSH 工具）

一条命令装好，之后在终端输入 `sshh` 就是图形化面板：

```bash
curl -fsSL "https://cdn.jsdelivr.net/gh/Swordee/NEW1@v2.8/Debian%20SSH/install.sh" | sudo bash
source ~/.bashrc
sshh
```

```text
  当前端口  : 22 2222        端口监听 : 22 ✓ 2222 ✓
  服务状态  : active         配置校验 : 通过
  ────────────────────────────────────────────────
  1) 查看 SSH 状态详情     5) 防火墙规则
  2) 更改 SSH 端口         6) 重启 SSH 服务
  3) 移除旧端口            7) 查看操作日志
  4) 备份与回滚            8) 卸载本工具
```

> `sshh` → 打开面板；`ssh user@host` → 原生 SSH，完全不受影响。
> 刻意不占用 `ssh`，避免与系统命令冲突；卸载时自动清理别名与软链。

## 快速取用

```bash
# 克隆仓库
git clone https://github.com/Swordee/NEW1.git
cd NEW1

# 进入需要的分类，按各自 README 操作
cd "Debian SSH"     # 或 cd iptables / cd fail2ban
```

单文件部署（以 SSH 工具为例，无需克隆）：

```bash
curl -fsSL "https://raw.githubusercontent.com/Swordee/NEW1/main/Debian%20SSH/install.sh" | sudo bash
```

> 仓库已设为 **public**，以上地址均可匿名访问。

## 国内加速下载

GitHub 直连在国内常不稳定，可用下列镜像（三条线路均只对 public 仓库生效）。

### 单文件（SSH 工具安装器）

| 线路 | 地址 |
| --- | --- |
| **jsDelivr** | `https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/Debian%20SSH/install.sh` |
| **ghproxy.cc** | `https://ghproxy.cc/https://raw.githubusercontent.com/Swordee/NEW1/main/Debian%20SSH/install.sh` |
| **mirror.ghproxy.com** | `https://mirror.ghproxy.com/https://raw.githubusercontent.com/Swordee/NEW1/main/Debian%20SSH/install.sh` |
| GitHub 直连 | `https://raw.githubusercontent.com/Swordee/NEW1/main/Debian%20SSH/install.sh` |

```bash
# jsDelivr（国内通常最快，推荐）
curl -fsSL "https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/Debian%20SSH/install.sh" | sudo bash

# ghproxy.cc
curl -fsSL "https://ghproxy.cc/https://raw.githubusercontent.com/Swordee/NEW1/main/Debian%20SSH/install.sh" | sudo bash

# mirror.ghproxy.com
curl -fsSL "https://mirror.ghproxy.com/https://raw.githubusercontent.com/Swordee/NEW1/main/Debian%20SSH/install.sh" | sudo bash
```

### 整包下载

| 方式 | 地址 |
| --- | --- |
| zip 直连 | `https://github.com/Swordee/NEW1/archive/refs/heads/main.zip` |
| zip 经 ghproxy.cc | `https://ghproxy.cc/https://github.com/Swordee/NEW1/archive/refs/heads/main.zip` |
| zip 经 mirror.ghproxy.com | `https://mirror.ghproxy.com/https://github.com/Swordee/NEW1/archive/refs/heads/main.zip` |
| git clone 加速 | `git clone https://ghproxy.cc/https://github.com/Swordee/NEW1.git` |
| jsDelivr 目录浏览 | `https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/` |

> jsDelivr 是文件 CDN，**不支持 `git clone` 和整包 zip**，只能按文件路径取。

### 线路状态（2026-11-01 实测，仓库已 public）

| 服务 | 状态 | 实测 |
| --- | --- | --- |
| **jsDelivr** | ✅ 可用 | `install.sh` 返回 200（29,922 B） |
| **raw.githubusercontent.com** | ✅ 可用 | 200（29,922 B） |
| GitHub zip 直连 | ✅ 可用 | 200（185,566 B） |
| **ghproxy.cc** | ❌ 不可用 | TLS 证书已过期（`SEC_E_CERT_EXPIRED`） |
| **mirror.ghproxy.com** | ❌ 不可用 | TLS 握手失败，无法建立连接 |

> ghproxy 两条线路失效与服务本身有关，不是配置问题。等其证书续期 / 服务恢复后可再试；当前请优先用 **jsDelivr**。

### jsDelivr 使用注意

- 路径格式：`https://cdn.jsdelivr.net/gh/<用户>/<仓库>@<分支或标签>/<文件路径>`
- 建议用**标签**代替 `@main`，避免缓存导致内容滞后：`@v2.8`（本仓库已打此标签）
- 无 tag 时 `data.jsdelivr.com/v1/packages/gh/<用户>/<仓库>` 会返回 404；**即使打了 tag 也可能仍返回 404**，不影响文件访问，可忽略
- 单文件上限 **20 MB**（本项目最大文件 `代码展示.html` 约 240 KB，无压力）
- 内容有缓存，更新后可能延迟数分钟；可访问 `https://purge.jsdelivr.net/gh/Swordee/NEW1@main/<路径>` 强制刷新
- **不支持私有仓库**

### 缓存提示（实测踩坑）

`raw.githubusercontent.com` 同样有 CDN 缓存（约 5 分钟），**刚 push 完立刻访问可能拿到上一版文件**，加查询参数也绕不过去。

排查顺序：

1. 用 GitHub API 确认真实内容：`/repos/<用户>/<仓库>/contents/<路径>?ref=main`
2. 用 jsDelivr + purge 立即取新版
3. 或直接用 commit sha 访问：`https://cdn.jsdelivr.net/gh/Swordee/NEW1@<commit-sha>/Debian%20SSH/install.sh`

## 目录约定

每个分类目录结构基本一致：

```
<分类名>/
├── README.md          分类说明与快速开始
├── <主脚本>.sh        核心工具
├── ssh_menu.sh        交互式面板（Debian SSH 分类）
├── install.sh         自解压安装器（curl | bash）
├── 文档 / 规则模板
└── scripts/           打包与 CI 辅助脚本
```

- 脚本统一用 `bash -n` + ShellCheck（style 级）校验，CI 在 GitHub Actions 上自动运行
- 修改类脚本默认「先备份 → 再改 → 校验 → 失败自动回滚」
- 所有脚本**仅面向 Linux**（Debian 10 / 11 / 12），需要 root 权限

## 代码检查

```bash
# SSH 分类自带全仓库检查入口（扫描所有 *.sh）
bash "Debian SSH/check.sh"
```

## 免责声明

脚本会修改系统网络与 SSH 配置。请在**测试环境先行验证**，并保留至少一个活跃 SSH 会话，直到确认新配置可用。使用风险自负。
