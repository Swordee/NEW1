# Debian 运维工具集

面向 **Debian / Ubuntu** 的一站式运维脚本合集。每个分类独立成目录，自带一键脚本、自解压安装器、中文文档与 ShellCheck CI 检查，复制即用。

> 仓库地址：<https://github.com/Swordee/NEW1>

## 分类

| 分类 | 说明 | 入口 |
| --- | --- | --- |
| **Debian SSH** | 安全更换 SSH 端口：交互式脚本、过渡期保留旧端口、校验失败自动回滚 | [进入分类](https://github.com/Swordee/NEW1/tree/main/Debian%20SSH) |
| **iptables** | iptables 防火墙一键管理，纯 Bash 无 whiptail 依赖，变更前自动备份 | [进入分类](https://github.com/Swordee/NEW1/tree/main/iptables) |
| **fail2ban** | Fail2ban 落地工具集：一键脚本、安装器、中文文档与自定义规则范本 | [进入分类](https://github.com/Swordee/NEW1/tree/main/fail2ban) |

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

> 仓库当前为 **private**，上面的 `raw` 链接匿名访问会返回 404。两种解决方式：
> 1. 在 Settings → General → Danger Zone 把仓库改为 public；
> 2. 或先 `git clone`，再本地执行 `sudo bash "Debian SSH/install.sh"`。

## 国内加速下载

GitHub 直连在国内常不稳定，可用下列镜像。**三条加速线路都只对 public 仓库生效**，私有仓库会一律 404。

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

### 线路状态（2026-11-01 实测）

| 服务 | 状态 | 说明 |
| --- | --- | --- |
| jsDelivr | ✅ 可用 | 公开仓库内容返回 200 |
| raw.githubusercontent.com | ✅ 可用 | 本机实测 200 |
| ghproxy.cc | ⚠️ 不可用 | TLS 证书已过期（`SEC_E_CERT_EXPIRED`） |
| mirror.ghproxy.com | ⚠️ 不可用 | TLS 握手失败，当前网络无法建立连接 |

### jsDelivr 使用注意

- 路径格式：`https://cdn.jsdelivr.net/gh/<用户>/<仓库>@<分支或标签>/<文件路径>`
- 建议用**标签或 commit sha** 代替 `@main`，避免缓存导致内容滞后：`@v2.4`
- 单文件上限 **20 MB**（本项目最大文件 `代码展示.html` 约 240 KB，无压力）
- 内容有缓存，更新后可能延迟数分钟到数小时
- **不支持私有仓库**

## 目录约定

每个分类目录结构基本一致：

```
<分类名>/
├── README.md          分类说明与快速开始
├── <主脚本>.sh        核心工具
├── install.sh         自解压安装器（curl | bash）
├── 文档 / 规则模板
└── scripts/           打包与 CI 辅助脚本
```

- 脚本统一用 `bash -n` + ShellCheck（style 级）校验，CI 在 GitHub Actions 上自动运行
- 修改类脚本默认「先备份 → 再改 → 校验 → 失败自动回滚」
- 所有脚本面向 Debian 10 / 11 / 12，需要 root 权限

## 代码检查

```bash
# SSH 分类自带全仓库检查入口（扫描所有 *.sh）
bash "Debian SSH/check.sh"
```

## 免责声明

脚本会修改系统网络与 SSH 配置。请在**测试环境先行验证**，并保留至少一个活跃 SSH 会话，直到确认新配置可用。使用风险自负。
