# Debian SSH

本分类收录 Debian 系统下 SSH 相关工具与文档，核心目标是**安全地更换 SSH 端口**，避免"改完配置连不上、把自己锁在门外"。

## 收录内容

| 文件 | 类型 | 说明 |
| --- | --- | --- |
| [change_ssh_port.sh](./change_ssh_port.sh) | 主脚本 | 交互式/半自动更换 SSH 端口，支持过渡期保留旧端口 |
| [remove_old_ssh_port.sh](./remove_old_ssh_port.sh) | 收尾脚本 | 新端口验证通过后，安全移除旧端口 |
| [install.sh](./install.sh) | 安装器 | 自解压单文件，支持 `curl \| bash` 一键部署 |
| [check.sh](./check.sh) | 质量检查 | 本地 / CI 统一入口（`bash -n` + ShellCheck） |
| [使用文档.md](./使用文档.md) | 文档 | 完整手册：参数、原理、回滚、FAQ |
| [代码展示.html](./代码展示.html) | 展示页 | 带行号与语法高亮的源码 + 修复记录 |

## 快速开始

先进入本目录：

```bash
cd "Debian SSH"
```

```bash
# 1. 更换端口（建议保留旧端口过渡）
sudo bash change_ssh_port.sh

# 2. 另开终端，用新端口验证登录
ssh -p 新端口 用户@服务器IP

# 3. 确认可用后，关闭旧端口
sudo bash remove_old_ssh_port.sh
```

全自动方式：

```bash
sudo bash change_ssh_port.sh -p 2222 -y --firewall   # 改端口 + 保留旧端口 + 放行防火墙
sudo bash change_ssh_port.sh -p 2222 -n              # 预演，不做任何修改
```

## 一键安装（国内加速）

`install.sh` 是自解压单文件，内嵌全部脚本，无需克隆整个仓库。

```bash
# jsDelivr（国内推荐）
curl -fsSL "https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/Debian%20SSH/install.sh" | sudo bash

# ghproxy.cc
curl -fsSL "https://ghproxy.cc/https://raw.githubusercontent.com/Swordee/NEW1/main/Debian%20SSH/install.sh" | sudo bash

# mirror.ghproxy.com
curl -fsSL "https://mirror.ghproxy.com/https://raw.githubusercontent.com/Swordee/NEW1/main/Debian%20SSH/install.sh" | sudo bash

# GitHub 直连
curl -fsSL "https://raw.githubusercontent.com/Swordee/NEW1/main/Debian%20SSH/install.sh" | sudo bash
```

安装后可用命令：`ssh-port-change` / `ssh-port-remove`。完整参数见 [使用文档.md](./使用文档.md) 第 14 节。

想锁定版本可用 jsDelivr 的标签写法：`@v2.4` 代替 `@main`。

> 📌 加速线路只对 public 仓库生效（本仓库已是 public）。
> 2026-11-01 实测：**jsDelivr ✅**、GitHub 直连 ✅；`ghproxy.cc` 证书已过期、`mirror.ghproxy.com` TLS 握手失败，二者暂不可用。

## 安全设计

- **改前必备份**：自动备份到 `/etc/ssh/sshd_config_backups/`
- **校验失败自动回滚**：`sshd -t` 不通过就从备份恢复，本次零改动
- **默认保留旧端口过渡**：新旧端口同时监听，验证通过再清理，极大降低锁死风险
- **重启后验证监听**：真正检查端口是否 `LISTEN`，而不是只看服务状态
- **操作留痕**：日志写入 `/var/log/change_ssh_port.log`

## 适用范围

- Debian 10 / 11 / 12（systemd 系发行版通用，Ubuntu 亦可）
- 需要 root 权限运行
- 防火墙自动识别 `ufw` / `nftables` / `iptables`

> ⚠️ **云服务器还需在云厂商安全组放行新端口**，脚本改不了安全组。这是最常见的"改了端口却连不上"原因。

## 常见坑

| 现象 | 原因 |
| --- | --- |
| 改了端口但旧端口仍在监听 | Debian 12 的 `sshd_config` 顶部有 `Include /etc/ssh/sshd_config.d/*.conf`，子文件里的 `Port` 会生效 |
| `sshd -t` 报错 | 新指令写在 `Match` 块之后会被错误归入匹配块，脚本已改为写入文件顶部规避 |
| 连不上且无法回滚 | 务必保留至少一个活跃 SSH 会话，直到新端口验证通过 |

---

返回 [仓库首页](../README.md)
