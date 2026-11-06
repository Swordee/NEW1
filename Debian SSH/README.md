# Debian SSH

本分类收录 Debian 系统下 SSH 相关工具与文档，核心目标是**安全地更换 SSH 端口**，避免"改完配置连不上、把自己锁在门外"。

> 一条命令安装，之后在终端输入 `sshh` 就能打开交互式管理面板。
> 刻意**不占用 `ssh`**，避免与系统命令冲突——原生 `ssh user@host` 行为完全不变。

## 最快上手（三步）

```bash
# 1. 一条命令安装（国内推荐 jsDelivr 线路）
curl -fsSL "https://cdn.jsdelivr.net/gh/Swordee/NEW1@v2.9/Debian%20SSH/install.sh" | sudo bash

# 2. 让别名生效（或直接新开一个终端）
source ~/.bashrc

# 3. 输入 sshh，进入交互面板
sshh
```

面板长这样，用数字键选择即可：

```text
╔══════════════════════════════════════════════════════════════╗
║   Debian SSH · 端口管理面板                v2.9              ║
╚══════════════════════════════════════════════════════════════╝
  主机        : root@server · Debian GNU/Linux 12
  当前端口    : 22 2222
  端口监听    : 22 ✓ 2222 ✓
  服务状态    : active running
  防火墙      : ufw active
  配置校验    : 通过
  最近备份    : sshd_config.20261102-201500.bak
  ────────────────────────────────────────────────────────────
  1) 查看 SSH 状态详情
  2) 更改 SSH 端口
  3) 移除旧端口（过渡期收尾）
  4) 备份与回滚
  5) 防火墙规则
  6) 重启 SSH 服务
  7) 查看操作日志
  8) 卸载本工具
  0) 退出
```

> 输入 `sshh` 会打开面板；输入 `ssh user@host` 仍然是**原生 SSH 客户端**，行为与安装前完全一致。

## 收录内容

| 文件 | 类型 | 说明 |
| --- | --- | --- |
| [ssh_menu.sh](./ssh_menu.sh) | 交互面板 | `ssh` 进入的图形化菜单：状态/换端口/防火墙/回滚/日志/卸载 |
| [ssh-port.sh](./ssh-port.sh) | 命令包装器 | 无参数开面板，带参数透传给原生 ssh |
| [change_ssh_port.sh](./change_ssh_port.sh) | 主脚本 | 交互式/半自动更换 SSH 端口，支持过渡期保留旧端口 |
| [remove_old_ssh_port.sh](./remove_old_ssh_port.sh) | 收尾脚本 | 新端口验证通过后，安全移除旧端口 |
| [install.sh](./install.sh) | 安装器 | 自解压单文件，支持 `curl \| bash` 一键部署 |
| [check.sh](./check.sh) | 质量检查 | 本地 / CI 统一入口（`bash -n` + ShellCheck） |
| [使用文档.md](./使用文档.md) | 文档 | 完整手册：参数、原理、回滚、FAQ |
| [代码展示.html](./代码展示.html) | 展示页 | 带行号与语法高亮的源码 + 修复记录 |

## 不使用安装器（直接跑脚本）

```bash
cd "Debian SSH"

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

## 一键安装（多线路）

`install.sh` 是自解压单文件，内嵌全部脚本，无需克隆整个仓库。

```bash
# jsDelivr（国内推荐，按标签锁版本）
curl -fsSL "https://cdn.jsdelivr.net/gh/Swordee/NEW1@v2.9/Debian%20SSH/install.sh" | sudo bash

# GitHub 直连
curl -fsSL "https://raw.githubusercontent.com/Swordee/NEW1/main/Debian%20SSH/install.sh" | sudo bash

# ghproxy.cc
curl -fsSL "https://ghproxy.cc/https://raw.githubusercontent.com/Swordee/NEW1/main/Debian%20SSH/install.sh" | sudo bash

# mirror.ghproxy.com
curl -fsSL "https://mirror.ghproxy.com/https://raw.githubusercontent.com/Swordee/NEW1/main/Debian%20SSH/install.sh" | sudo bash
```

安装后可用命令：

| 命令 | 作用 |
| --- | --- |
| `sshh` | 打开交互式管理面板（安装器注入了 alias） |
| `ssh-port-menu` | 同上，不依赖别名的直接入口 |
| `ssh-port-change` | 直接更换端口 |
| `ssh-port-remove` | 直接移除旧端口 |

想锁定版本可用 jsDelivr 的标签写法：`@v2.9` 代替 `@main`。

> 📌 加速线路只对 public 仓库生效（本仓库已是 public）。
> 2026-11-01 实测：**jsDelivr ✅**、GitHub 直连 ✅；`ghproxy.cc` 证书已过期、`mirror.ghproxy.com` TLS 握手失败，二者暂不可用。

### 安装器参数

```text
-d, --dir DIR     安装目录（默认 /opt/ssh-port-tools）
-y, --yes         非交互，全部使用默认值
    --menu        安装完成后直接打开交互面板
    --run         安装完成后直接运行更换端口
    --no-alias    不注入 sshh 别名（只装命令，不动 shell 配置）
    --no-doc      不安装文档
    --uninstall   卸载（同时清理别名与软链）
```

## 关于 `sshh` 命令

安装器会在 `~/.bashrc`（及 `~/.zshrc`，若存在）写入一段带标记的配置：

```bash
# >>> ssh-port-tool >>>
alias sshh='ssh-port'
# <<< ssh-port-tool <<<
```

| 你输入 | 实际执行 |
| --- | --- |
| `sshh` | 打开交互式管理面板 |
| `sshh user@host` | 转发给原生 SSH 客户端 |
| `ssh user@host` | 原生 SSH，**完全不受本工具影响** |
| `ssh-port` / `ssh-port-menu` | 不依赖别名，直接开面板 |

- **不占用 `ssh`**：从 v2.6 起改用 `sshh`，避免与系统命令冲突
- **幂等**：重复安装不会产生多份配置
- **可逆**：`--uninstall` 或面板里选「卸载」会精确删除这一段，不动你的其他配置
- 不想改 shell 配置：安装时加 `--no-alias`，之后用 `ssh-port-menu` 打开面板
- 装过旧版（占用过 `ssh`）的话，新装会自动替换旧配置块；当前终端执行 `unalias ssh` 即可清除残留

> 本工具**绝不替换 `/usr/bin/ssh`**，原生客户端始终原封不动。

## 安全设计

- **改前必备份**：自动备份到 `/etc/ssh/sshd_config_backups/`
- **校验失败自动回滚**：`sshd -t` 不通过就从备份恢复，本次零改动
- **默认保留旧端口过渡**：新旧端口同时监听，验证通过再清理，极大降低锁死风险
- **重启后验证监听**：真正检查端口是否 `LISTEN`，而不是只看服务状态
- **操作留痕**：日志写入 `/var/log/change_ssh_port.log`
- **回滚前先自保**：回滚时先留存当前配置，若备份本身是坏的会自动恢复，不会把可用配置覆盖掉
- **Include 一并回滚**：`sshd_config.d/*.conf` 里被注释的 `Port` 也会随异常一起还原
- **卸载有护栏**：安装目录异常（为空或 `/`）时拒绝 `rm -rf`，4 个软链与别名块一并清理

## 适用范围

- Debian 10 / 11 / 12（systemd 系发行版通用，Ubuntu 亦可）
- **仅支持 Linux**，安装器会在非 Linux 系统上直接拒绝运行
- 需要 root 权限运行
- 防火墙自动识别 `ufw` / `nftables` / `iptables`

> ⚠️ **云服务器还需在云厂商安全组放行新端口**，脚本改不了安全组。这是最常见的"改了端口却连不上"原因。

> ⚠️ **云服务器还需在云厂商安全组放行新端口**，脚本改不了安全组。这是最常见的"改了端口却连不上"原因。

## 常见坑

| 现象 | 原因 |
| --- | --- |
| 改了端口但旧端口仍在监听 | Debian 12 的 `sshd_config` 顶部有 `Include /etc/ssh/sshd_config.d/*.conf`，子文件里的 `Port` 会生效 |
| `sshd -t` 报错 | 新指令写在 `Match` 块之后会被错误归入匹配块，脚本已改为写入文件顶部规避 |
| 连不上且无法回滚 | 务必保留至少一个活跃 SSH 会话，直到新端口验证通过 |

---

返回 [仓库首页](../README.md)
