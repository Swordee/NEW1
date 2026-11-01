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
