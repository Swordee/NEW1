# Fail2ban 使用文档：安装、卸载、封禁规则与排查

> 适用系统：Ubuntu / Debian / Rocky / CentOS / RHEL 等 Linux 发行版
> 目标：保护服务器免受 SSH（22 端口）等服务的暴力破解与端口扫描攻击

---

## 一、Fail2ban 简介

Fail2ban 通过监控服务日志（如 `/var/log/auth.log`），用正则规则识别短时间内大量失败的登录尝试，
然后调用底层防火墙（iptables / nftables / firewalld）自动封禁来源 IP，冷却期结束后自动解封。

三个核心概念：

- **Jail（监狱）**：监控单元，绑定「日志文件 + 过滤规则 + 触发动作」，例如 `sshd` jail 专门盯 SSH。
- **Filter（过滤器）**：正则规则，从日志中匹配失败行并提取攻击 IP。
- **Action（动作）**：命中阈值后执行的操作，默认用防火墙封禁 IP，也可扩展为发邮件、调 API。

---

## 二、安装 Fail2ban

### 1. Debian / Ubuntu

```bash
sudo apt update
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
```

### 2. RHEL / CentOS / Rocky / Alma

```bash
sudo dnf install -y epel-release   # 需要先启用 EPEL 源
sudo dnf install -y fail2ban
sudo systemctl enable --now fail2ban
```

> 旧版 CentOS 7 用 `yum` 代替 `dnf`；若 `firewalld` 在运行，Fail2ban 会自动使用 `firewalld` 后端。

### 3. 验证安装

```bash
sudo fail2ban-client --version
sudo systemctl status fail2ban
```

---

## 三、基础配置（封禁 22 端口被扫）

> ⚠️ 永远不要直接修改 `/etc/fail2ban/jail.conf`（升级时会被覆盖）。
> 请新建 `/etc/fail2ban/jail.local` 或在 `/etc/fail2ban/jail.d/` 下新建 `.conf` 文件。

### 1. 通用默认规则 `jail.local`

```ini
[DEFAULT]
# 封禁时长：1h 表示封 1 小时；-1 表示永久封禁（谨慎使用）
bantime  = 1h
# 统计窗口：在多长时间内的失败计入计数
findtime = 10m
# 窗口内允许的最大失败次数，超过则封禁
maxretry = 5
# 封禁动作（iptables 多端口模式）
banaction = iptables-multiport
# 忽略的 IP（永远不封，务必加上你自己的管理 IP）
ignoreip = 127.0.0.1/8 ::1 你的固定IP/32
# 邮件通知（可选，需配置 sendmail/postfix）
# destemail = admin@example.com
# action = %(action_mwl)s
```

### 2. 针对 SSH（22 端口）的封禁规则

```ini
[sshd]
enabled  = true
port     = ssh                 # 等价于 22；若改了 SSH 端口，写具体端口号如 2222
filter   = sshd
logpath  = /var/log/auth.log   # RHEL 系为 /var/log/secure
maxretry = 3                   # 比默认值更严格：失败 3 次即封
bantime  = 24h                 # 封禁 24 小时
findtime = 10m
backend  = systemd             # 若系统用 journald 且无日志文件，可改用 systemd
```

> 改了 SSH 端口时务必同步修改 `port`，否则规则不会命中。

### 3. 自定义封禁整段扫描（进阶）

如果想对「短时间访问 22 端口但无任何成功登录」的扫描型 IP 更激进地封禁，可缩短 `findtime` 并降低 `maxretry`：

```ini
[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 2
findtime = 1m
bantime  = 7d
```

### 4. 让配置生效

```bash
sudo fail2ban-client reload
# 或重启服务
sudo systemctl restart fail2ban
```

---

## 四、常用查看 / 排查命令

```bash
# 1. 查看所有已启用的 jail
sudo fail2ban-client status

# 2. 查看某个 jail 的详情（封禁数量、被封 IP 列表、总命中数）
sudo fail2ban-client status sshd

# 3. 手动封禁某个 IP
sudo fail2ban-client set sshd banip 1.2.3.4

# 4. 手动解封某个 IP
sudo fail2ban-client set sshd unbanip 1.2.3.4

# 5. 解封 / 停止某个 jail（不停服务）
sudo fail2ban-client unban --all              # 解封所有 jail 的全部 IP
sudo fail2ban-client set sshd unbanip 1.2.3.4 # 解封指定 IP
sudo fail2ban-client stop sshd                # 停止该 jail（保留配置）

# 6. 查看 Fail2ban 自身运行日志（排查为何没生效）
sudo tail -f /var/log/fail2ban.log

# 7. 测试 filter 能否从日志中正确匹配到失败 IP
sudo fail2ban-regex /var/log/auth.log /etc/fail2ban/filter.d/sshd.conf

# 8. 查看防火墙是否真的加了封禁规则（iptables）
sudo iptables -L f2b-sshd -n -v

# 9. 实时观察 SSH 登录失败（辅助定位）
sudo tail -f /var/log/auth.log | grep "Failed password"
```

`fail2ban-regex` 非常关键：如果它显示 `Failregex: 0 total`，说明过滤器正则没匹配上你的日志格式，
需要检查 `logpath` 或自定义 filter。

---

## 五、卸载 Fail2ban

### 1. 先停服务并解封

```bash
sudo fail2ban-client unban --all    # 解除所有封禁，避免残留防火墙规则
sudo systemctl stop fail2ban
sudo systemctl disable fail2ban
```

### 2. 卸载软件包

Debian / Ubuntu：

```bash
sudo apt remove --purge -y fail2ban
sudo apt autoremove -y
```

RHEL / CentOS / Rocky：

```bash
sudo dnf remove -y fail2ban
```

### 3. 清理残留配置（可选）

```bash
sudo rm -rf /etc/fail2ban
sudo rm -f  /var/log/fail2ban.log*
```

> 注意：卸载软件包通常不会自动清除 `/etc/fail2ban` 下的自定义配置，`--purge`（apt）才会删除。
> 若你用 `banaction = firewallcmd-*` 或 `iptables`，卸载后建议确认防火墙规则已清空：
> `sudo iptables -L -n` 查看是否还有 `f2b-*` 链。

---

## 六、常见问题

| 问题 | 排查方向 |
|------|----------|
| Fail2ban 启动但没封 IP | 用 `fail2ban-regex` 验证 filter；确认 `logpath` 正确、日志在写 |
| 误封了自己 | `sudo fail2ban-client set sshd unbanip 你的IP`；并把 IP 加入 `ignoreip` |
| 改了 SSH 端口仍被扫 | 同步修改 jail 里的 `port`，然后 `reload` |
| 重启后规则丢失 | Fail2ban 重启会自动重建封禁，属正常；若需持久需调大 `bantime` |
| systemd 系统日志路径变化 | jail 中用 `backend = systemd`，无需 `logpath` |

---

## 七、最小可用配置速查（直接复制）

```ini
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
banaction = iptables-multiport
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 24h
```
