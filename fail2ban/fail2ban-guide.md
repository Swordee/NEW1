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

## 三、配置文件在哪、新规则放哪

### 1. 一张表看清所有位置

| 用途 | 路径 | 要不要改 |
|------|------|----------|
| 主配置目录 | `/etc/fail2ban/` | — |
| 守护进程自身配置 | `/etc/fail2ban/fail2ban.conf` | ❌ 不改 |
| **上游默认 jail 定义** | `/etc/fail2ban/jail.conf` | ❌ 不改（升级会覆盖） |
| **Debian 包默认启用 sshd** | `/etc/fail2ban/jail.d/defaults-debian.conf` | ⚠️ 可读，不建议改 |
| **本机实际生效的覆盖** | `/etc/fail2ban/jail.local` | ✅ 改这里 |
| 分片配置（**推荐放新规则**） | `/etc/fail2ban/jail.d/<服务名>.local` | ✅ 新建 |
| 过滤器（日志正则） | `/etc/fail2ban/filter.d/<名字>.conf` | ✅ 新建 |
| 封禁动作 | `/etc/fail2ban/action.d/*.conf` | 一般不改 |
| 路径变量 | `/etc/fail2ban/paths-common.conf`、`paths-debian.conf` | 一般不改 |
| 运行日志 | `/var/log/fail2ban.log` | — |
| 封禁记录数据库 | `/var/lib/fail2ban/fail2ban.sqlite3` | — |

> 本工具的 `dir` 命令会把上面这些路径连同实际文件列表一起打印出来：
> `sudo fail2ban-tool dir`

### 2. 默认的 22 端口配置到底在哪个文件

**不是一个文件，是四层叠加出来的。** 按加载顺序：

```
① /etc/fail2ban/jail.conf
      [sshd]
      port = ssh              ← ssh 在 /etc/services 中映射为 22
      logpath = %(sshd_log)s
      backend = %(sshd_backend)s

② /etc/fail2ban/paths-common.conf
      sshd_log = %(syslog_authpriv)s   →  /var/log/auth.log
   /etc/fail2ban/paths-debian.conf
      sshd_backend = systemd           ← Debian 覆盖默认 backend
      banaction = nftables             ← Debian 12+ 默认用 nftables

③ /etc/fail2ban/jail.d/defaults-debian.conf
      [sshd]
      enabled = true          ← Debian 包安装时写入，负责"启用"这个 jail

④ /etc/fail2ban/jail.local
      bantime / findtime / maxretry / ignoreip / port
                              ← 本工具写入，覆盖上面所有值
```

对应关系速查：

| 你看到的配置项 | 实际来源 |
|----------------|----------|
| `port = ssh`（即 22） | `jail.conf` 的 `[sshd]` 段 |
| `logpath = /var/log/auth.log` | `paths-common.conf` 的 `sshd_log` |
| `backend = systemd` | `paths-debian.conf`（Debian 12+ 默认） |
| `enabled = true` | `jail.d/defaults-debian.conf` |
| 最终生效的阈值 | `jail.local`（优先级高于以上全部） |

看最终生效值（比翻文件可靠）：

```bash
sudo fail2ban-client get sshd bantime      # 封禁时长（秒）
sudo fail2ban-client get sshd findtime     # 统计窗口（秒）
sudo fail2ban-client get sshd maxretry     # 允许失败次数
sudo fail2ban-client get sshd ignoreip     # 白名单
sudo fail2ban-client get sshd actions      # 封禁动作；端口在参数里，如 port="ssh"
```

> ⚠️ **没有 `get sshd port` 这个命令**（会报 `Invalid command`）。
> 端口要么看 `get sshd actions` 里的 `port="ssh"`，要么直接看配置文件。

### 3. 加载顺序：谁覆盖谁

`man 5 jail.conf` 规定的顺序：

```
jail.conf
jail.d/*.conf        ← 按字母序
jail.local
jail.d/*.local       ← 按字母序，优先级最高
```

**后解析的覆盖先解析的。** 所以：

- `jail.local` 覆盖 `jail.conf` 和 `jail.d/defaults-debian.conf`
- `jail.d/*.local` 又覆盖 `jail.local`

### 4. 新建一条规则，放哪里

**结论：新建 `/etc/fail2ban/jail.d/<服务名>.local`。**

理由：`*.local` 优先级最高、按字母序加载、一个文件只管一个服务、升级不会覆盖、排查时一眼能定位。

以封禁 Nginx 登录失败为例，一共两个文件：

```bash
# ① jail：规则本体 —— 放 jail.d/，不要动 jail.conf
sudo tee /etc/fail2ban/jail.d/nginx-auth.local >/dev/null <<'EOF'
[nginx-auth]
enabled  = true
port     = http,https
filter   = nginx-auth
logpath  = /var/log/nginx/access.log
maxretry = 5
findtime = 10m
bantime  = 1h
EOF

# ② filter：日志正则 —— 放 filter.d/，文件名要和 jail 里的 filter= 对应
sudo tee /etc/fail2ban/filter.d/nginx-auth.conf >/dev/null <<'EOF'
[Definition]
failregex = ^<HOST> - .* "(GET|POST) [^"]* HTTP/[0-9.]+" (401|403) \d+
ignoreregex =
EOF

# ③ 用真实日志验证正则能命中（最关键的一步）
sudo fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/nginx-auth.conf

# ④ 生效并确认
sudo fail2ban-client reload
sudo fail2ban-client status nginx-auth
```

命名约定：

| 类型 | 路径 | 说明 |
|------|------|------|
| jail | `/etc/fail2ban/jail.d/<服务名>.local` | 定义阈值、端口、日志路径 |
| filter | `/etc/fail2ban/filter.d/<服务名>.conf` | 定义"什么样的日志行算失败" |

`jail` 里的 `filter = nginx-auth` 会自动去找 `filter.d/nginx-auth.conf`。
两个文件名不必相同，但建议一致，方便对应。

> 更详细的规则写法（正则语法、7 个服务范本、验证方法）见
> [`fail2ban-rules-templates.md`](fail2ban-rules-templates.md)。

### 5. Debian 12+ 的两个默认差异（容易踩）

| 项 | Debian 11 及更早 | Debian 12+ |
|----|------------------|------------|
| 封禁动作 | `iptables-multiport` | **`nftables`**（由 `paths-debian.conf` 设定） |
| sshd 日志 | 读 `/var/log/auth.log` | **`backend = systemd`**，直接读 journald |

所以在 Debian 12+ 上：

- 不要盲目照抄网上教程里的 `banaction = iptables-multiport`，先确认实际值：
  `grep -E 'banaction|sshd_backend' /etc/fail2ban/paths-debian.conf`
- `auth.log` 不存在是**正常**的，`logpath` 留空 + `backend = systemd` 即可

---

## 四、基础配置（封禁 22 端口被扫）

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
# 封禁动作：Debian 12+ 默认 nftables；老版本或 RHEL 系常用 iptables-multiport
# 不确定就先看：grep banaction /etc/fail2ban/paths-debian.conf
# banaction = iptables-multiport
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
maxretry = 3                   # 比默认值更严格：失败 3 次即封
bantime  = 24h                 # 封禁 24 小时
findtime = 10m

# ↓ 日志来源：二选一，只能留一个
backend  = systemd             # 方式 A（Debian 12+ / Ubuntu 22.04+ 默认）：读 systemd journal
# logpath = /var/log/auth.log  # 方式 B：有该文件时才用（RHEL 系为 /var/log/secure）
```

> ⚠️ **`logpath` 与 `backend = systemd` 只能留一个。**
> `logpath` 指向的文件如果不存在，fail2ban 会在启动阶段直接报
> `ERROR Failed during configuration: Have not found any log file for sshd jail`
> 然后以 `status=255` 退出 —— 这是 Debian 12+ 上最常见的启动失败原因。
> 判断方法：`ls -l /var/log/auth.log`，没有这个文件就用方式 A。

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

### 5. 查看 SSH 封禁规则、修改封禁时间

#### ① 看当前生效的值（不是配置文件里的值）

```bash
sudo fail2ban-client status sshd            # 当前封禁列表 + 失败计数
sudo fail2ban-client get sshd bantime       # 封禁时长（秒）
sudo fail2ban-client get sshd findtime      # 统计窗口（秒）
sudo fail2ban-client get sshd maxretry      # 允许失败次数
sudo fail2ban-client get sshd ignoreip      # 白名单
sudo fail2ban-client get sshd logpath       # 监控哪些日志
sudo fail2ban-client get sshd failregex     # 判定"失败"的正则
sudo fail2ban-client get sshd actions       # 封禁动作（端口也在这里，如 port="ssh"）
```

被封 IP 及封禁时间：

```bash
sudo fail2ban-client get sshd banip --with-time
sudo fail2ban-client banned                 # 所有 jail 的封禁字典
```

> 为什么要用 `get` 而不是翻文件：同一个参数可能在 `jail.conf`、`jail.d/*.conf`、
> `jail.local` 里各写了一份，`get` 返回的是**最终合并后真正在跑的值**。

#### ② 规则定义在哪看

| 想看什么 | 去哪看 |
|----------|--------|
| 判定"失败"的正则 | `/etc/fail2ban/filter.d/sshd.conf` 的 `failregex` |
| 阈值、端口、白名单 | `/etc/fail2ban/jail.local` 的 `[sshd]` 段 |
| Debian 包默认启用项 | `/etc/fail2ban/jail.d/defaults-debian.conf` |
| 上游默认模板 | `/etc/fail2ban/jail.conf` 的 `[sshd]` |

#### ③ 改封禁时间（bantime）

**永久生效** —— 改配置文件，这是唯一能持久的方式：

```ini
# /etc/fail2ban/jail.local
[sshd]
bantime  = 1d        # 封 1 天
findtime = 10m       # 10 分钟内的失败才计数
maxretry = 3         # 失败 3 次就封
```

```bash
sudo fail2ban-client reload sshd    # 只重载 sshd，不影响其他 jail
```

时间写法：

| 写法 | 含义 |
|------|------|
| `30m` | 30 分钟 |
| `1h` | 1 小时 |
| `1d` | 1 天 |
| `7d` | 7 天 |
| `-1` | 永久封禁（谨慎，容易误封自己） |

> `bantime` 写在 `[DEFAULT]` 段对**所有 jail** 生效；写在 `[sshd]` 段只覆盖 sshd。
> `[sshd]` 的优先级更高。

**临时生效**（只影响本次运行，重启服务后回到配置文件的值）：

```bash
sudo fail2ban-client set sshd bantime 86400     # 86400 秒 = 1 天
sudo fail2ban-client set sshd maxretry 5
```

> ⚠️ 改 `bantime` **不会改变已经封禁的 IP 的剩余时长**——它们仍按封禁时的旧值到期。
> 想让新值立刻作用于某个 IP，先解封、再让它重新触发：

```bash
sudo fail2ban-client set sshd unbanip 203.0.113.5
sudo fail2ban-client unban --all        # 或一次解封全部
```

#### ④ 一条命令看全（本工具）

```bash
sudo fail2ban-tool info     # 打印 sshd 的 bantime/findtime/maxretry/白名单/动作
```

---

## 五、常用查看 / 排查命令

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

## 六、卸载 Fail2ban

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

## 七、常见问题

| 问题 | 排查方向 |
|------|----------|
| Fail2ban 启动但没封 IP | 用 `fail2ban-regex` 验证 filter；确认 `logpath` 正确、日志在写 |
| 误封了自己 | `sudo fail2ban-client set sshd unbanip 你的IP`；并把 IP 加入 `ignoreip` |
| 改了 SSH 端口仍被扫 | 同步修改 jail 里的 `port`，然后 `reload` |
| 重启后规则丢失 | Fail2ban 重启会自动重建封禁，属正常；若需持久需调大 `bantime` |
| systemd 系统日志路径变化 | jail 中用 `backend = systemd`，无需 `logpath` |
| 启动失败 `status=255` | 见下方「`status=255` 启动失败专项排查」 |

### 专项：`status=255` 启动失败

**现象**

```text
# systemctl status fail2ban
Active: failed (Result: exit-code)
Process: ... ExecStart=/usr/bin/fail2ban-server ... (code=exited, status=255/FAILURE)

# journalctl -u fail2ban -n 20
ERROR  Failed during configuration: Have not found any log file for sshd jail
ERROR  Async configuration of server failed
ERROR  ERROR: test configuration failed
```

`255` 是 fail2ban-server 配置初始化失败后主动退出的退出码。**它只是结果，不是原因**，
真正原因永远写在 `journalctl` 的上一条 `ERROR` 里。按出现频率排序：

| 报错关键字 | 原因 | 修复 |
|-----------|------|------|
| `Have not found any log file for sshd jail` | `logpath` 指向的文件不存在（Debian 12+ 默认无 `/var/log/auth.log`） | 删掉 `logpath`，改 `backend = systemd` |
| `Failed to execute ban jail 'sshd' action ...` / `iptables: not found` | `banaction` 与系统工具不匹配（Debian 12 默认 nftables，可能没有 iptables 命令） | `banaction = nftables` 或 `apt install iptables` |
| `Unable to read the filter` / `No such file ... filter.d/xxx.conf` | `filter` 名字写错或自定义 filter 未创建 | 检查 `/etc/fail2ban/filter.d/<名字>.conf` |
| `Invalid port` | `port` 写法错误（空值、多余空格、错误分隔符） | 用逗号分隔，如 `port = 22,2222` |

**修复步骤（日志缺失型，最常见）**

```bash
# 1. 确认确实没有这个文件
ls -l /var/log/auth.log

# 2. 备份
sudo cp -a /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak

# 3. 注释掉所有 logpath 行（不用写正则括号，粘贴不会出错）
sudo sed -i '/logpath/s/^/# /' /etc/fail2ban/jail.local

# 4. 用 drop-in 覆盖 backend（jail.d/*.local 优先级最高，比改 jail.local 更干净）
sudo tee /etc/fail2ban/jail.d/zz-sshd-systemd.local >/dev/null <<'EOF'
[sshd]
backend = systemd
EOF

# 5. 确认改动生效
grep -n "logpath" /etc/fail2ban/jail.local
cat /etc/fail2ban/jail.d/zz-sshd-systemd.local

# 6. 先做配置语法检查（这一步过了再启动，不要盲目 restart）
sudo fail2ban-client -t

# 7. 启动
sudo systemctl restart fail2ban
sudo systemctl status fail2ban --no-pager
```

**改完的正确形态**

```ini
[sshd]
enabled  = true
port     = 22
filter   = sshd
backend  = systemd
# logpath  = /var/log/auth.log   ← 被注释掉
maxretry = 3
bantime  = 24h
```

**验证真的在监控日志**

```bash
sudo fail2ban-client status sshd    # 期望 Log file(s) 为 journal 或 -，"Total failed" 会增长
sudo journalctl -u fail2ban -f      # 另开一个窗口观察
```

> 用本仓库一键脚本安装的话，v1.0.5 起已自动判断 `auth.log` 是否存在来选择日志后端，
> 不会再写出这个错误配置。v1.0.6 起 `install` 遇到**已存在**的 `jail.local` 也会先检查
> `logpath` / `banaction` 是否会导致 255，并询问是否就地修复。
> 老版本可执行 `sudo fail2ban-tool doctor`，它会检测并交互式修复。

**两个容易踩的坑**

1. **`fail2ban-client -t` 别敲成 `-`**
   只敲 `-` 会去连正在运行的服务，报 `Failed to access socket path: /var/run/fail2ban/fail2ban.sock. Is fail2ban running?`，
   看起来像"服务没起来"，其实是命令敲错了。`-t`（test）只读配置、不连 socket，服务死了也能用。

2. **日志里出现 `Server ready` 之后仍然 255**
   说明配置这关过了，是启动之后才失败的（action 初始化、socket 目录、残留进程）。
   用前台模式跑一次，错误会直接打在屏幕上：

   ```bash
   sudo systemctl stop fail2ban
   sudo fail2ban-server -f -vv start 2>&1 | tail -n 40
   # 看完按 Ctrl+C 退出，再 systemctl start fail2ban
   ```

---

## 八、最小可用配置速查（直接复制）

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
maxretry = 3
bantime  = 24h
backend  = systemd
# logpath = /var/log/auth.log   # 二选一：该文件不存在时不要写这行
```

> 若 `ls /var/log/auth.log` 有输出，把上面两行互换（保留 `logpath`、注释掉 `backend`）也可以。
