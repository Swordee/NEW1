# Fail2ban 自定义规则范本（Filter + Jail）

> 本文档讲解如何为任意服务编写 Fail2ban 封禁规则，并给出常见服务的可直接套用范本。
> 环境：Debian / Ubuntu（路径以 `/etc/fail2ban` 为准）

---

## 一、规则由两部分组成

一条完整的 Fail2ban 规则 = **Filter（过滤器）** + **Jail（监狱）**：

| 组成 | 作用 | 存放位置 |
|------|------|----------|
| **Filter** | 用正则从日志里识别「失败」行，并提取攻击 IP（`<HOST>`） | `/etc/fail2ban/filter.d/xxx.conf` |
| **Jail** | 指定监控哪个日志、用哪个 filter、触发阈值与封禁动作 | `/etc/fail2ban/jail.local` 或 `jail.d/xxx.conf` |

> 原则：**不要修改 `jail.conf`**（升级会被覆盖），自定义规则一律写进 `jail.local` 或 `jail.d/`。

---

## 二、Filter 的写法（核心语法）

一个 filter 文件的最小结构：

```ini
[Definition]
failregex = ^<HOST> .* "GET /login" 401
ignoreregex =
```

### 关键字段

| 字段 | 说明 |
|------|------|
| `failregex` | **必填**。匹配「失败/攻击」日志行。必须包含 `<HOST>` 占位符，Fail2ban 会把它替换为 IP 正则并提取出来 |
| `ignoreregex` | 可选。匹配到的行会被**忽略**（即使也命中 failregex），用于排除误报 |
| `prefregex` | 可选。在 failregex 之前先做一次粗筛，提升性能（多行合并日志时用） |
| `datepattern` | 可选。日志时间格式与系统默认不同时指定，如 `%d/%b/%Y:%H:%M:%S` |
| `maxlines` | 可选。日志一条记录跨多行时使用（默认 1） |

### `<HOST>` 的作用

`<HOST>` 是 Fail2ban 内置的 IP 占位符，支持 IPv4/IPv6。写规则时**只需在 IP 出现的位置写 `<HOST>`**，
不用自己写 IP 正则。例如日志：

```
Oct 31 22:00:01 server sshd[1234]: Failed password for root from 1.2.3.4 port 5522 ssh2
```

对应的 failregex：

```ini
failregex = ^.*Failed password for .* from <HOST> port \d+ ssh2$
```

### 常用正则片段

| 目标 | 正则 |
|------|------|
| 行首 | `^` |
| 行尾 | `$` |
| 任意字符（不含换行） | `.*` |
| 数字 | `\d+` |
| 空白 | `\s+` |
| 可选内容 | `(?:...)?` |
| 分组但不捕获 | `(?:...)` |

> ⚠️ 正则中 `[` `]` `.` `*` `+` `?` `(` `)` `{` `}` `|` `^` `$` `\` 都是特殊字符，
> 匹配字面量要转义，如 `\[error\]`、`\.php`。

---

## 三、Jail 的写法

在 `/etc/fail2ban/jail.local` 中新增一段（或放进 `jail.d/myapp.conf`）：

```ini
[myapp]
enabled  = true
filter   = myapp                 # 对应 filter.d/myapp.conf
logpath  = /var/log/myapp/auth.log
port     = 8080                  # 被封禁的端口（http/https 可写 http,https）
maxretry = 5
findtime = 10m
bantime  = 1h
```

### Jail 常用参数

| 参数 | 说明 |
|------|------|
| `enabled` | `true` 启用该 jail |
| `filter` | 使用的过滤器名（不含 `.conf`） |
| `logpath` | 要监控的日志文件路径（可多个，空格分隔） |
| `port` | 封禁的端口；`http,https` 表示同时封这两个端口 |
| `maxretry` | 窗口内最大失败次数 |
| `findtime` | 统计时间窗口 |
| `bantime` | 封禁时长（`-1` 永久） |
| `backend` | 日志读取方式：`auto` / `systemd` / `polling` |
| `action` | 封禁动作，默认继承 `[DEFAULT]` |

---

## 四、常见服务规则范本（可直接复制）

### 1. Nginx 登录失败（401/403 暴力破解）

**filter.d/nginx-auth.conf**

```ini
[Definition]
failregex = ^<HOST> - .* "(GET|POST) .* HTTP/1\.[01]" (401|403)\s+\d+
ignoreregex =
```

> 说明：`(401|403)` 后接 `\s+\d+` 匹配响应体大小，避免把状态码 4010 之类的数字误判。
> 末尾不必加 `$`，因为日志后面还有 referer/UA 字段。

**jail.local**

```ini
[nginx-auth]
enabled  = true
filter   = nginx-auth
logpath  = /var/log/nginx/access.log
port     = http,https
maxretry = 5
findtime = 10m
bantime  = 1h
```

> 注意：Nginx 默认访问日志的 IP 在行首，故 `failregex` 以 `<HOST>` 开头。

### 2. WordPress `wp-login.php` 爆破

**filter.d/wordpress.conf**

```ini
[Definition]
# WordPress 登录失败返回 200；登录成功返回 302。
# 因此只匹配 200（失败），并用 ignoreregex 排除 302（成功），避免误封正常用户。
failregex = ^<HOST> .* "POST /wp-login\.php.*" 200\s
ignoreregex = ^<HOST> .* "POST /wp-login\.php.*" 302\s
```

> ⚠️ 常见错误：把 `(200|302)` 一起匹配，会把**登录成功**的请求也算作失败，导致误封正常用户。

**jail.local**

```ini
[wordpress]
enabled  = true
filter   = wordpress
logpath  = /var/log/nginx/access.log
port     = http,https
maxretry = 5
findtime = 10m
bantime  = 24h
```

> 更稳妥的做法：只在登录失败时记录日志，再用失败日志匹配，避免误封正常登录。

### 3. Apache 认证失败

```ini
[apache-auth]
enabled  = true
filter   = apache-auth
logpath  = /var/log/apache2/error.log
port     = http,https
maxretry = 5
bantime  = 1h
```

### 4. FTP（vsftpd）登录失败

```ini
[vsftpd]
enabled  = true
filter   = vsftpd
logpath  = /var/log/vsftpd.log
maxretry = 5
bantime  = 1h
```

### 5. 邮件服务（Postfix SASL 认证失败）

```ini
[postfix-sasl]
enabled  = true
filter   = postfix-sasl
logpath  = /var/log/mail.log
port     = smtp,ssmtp,submission
maxretry = 5
bantime  = 1h
```

### 6. MySQL / MariaDB 认证失败

```ini
[mysqld-auth]
enabled  = true
filter   = mysqld-auth
logpath  = /var/log/mysql/error.log
port     = 3306
maxretry = 5
bantime  = 1h
```

### 7. 完全自定义应用（通用模板）

假设你的应用日志格式为：

```
2026-10-31 22:00:01 WARN  login failed for user=admin from 1.2.3.4
```

**filter.d/myapp.conf**

```ini
[Definition]
failregex = ^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} WARN\s+login failed for user=\S+ from <HOST>
ignoreregex =
```

**jail.local**

```ini
[myapp]
enabled  = true
filter   = myapp
logpath  = /var/log/myapp/app.log
maxretry = 3
findtime = 5m
bantime  = 1h
```

---

## 五、写完规则后必须验证

### 1. 用 `fail2ban-regex` 测试 filter 能否命中日志

```bash
sudo fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/nginx-auth.conf
```

关注输出：

```
Failregex: 12 total
|- #) [# of hits] regular expression
|  1) [12] ^<HOST> - .* "(GET|POST) .* HTTP/1\.[01]" (401|403)
```

- `Failregex: 0 total` → 正则没匹配上，检查日志格式与正则。
- 想看具体匹配到哪几行：

```bash
sudo fail2ban-regex --print-all-matched /var/log/nginx/access.log /etc/fail2ban/filter.d/nginx-auth.conf
```

### 2. 验证 IP 提取是否正确

```bash
sudo fail2ban-regex --print-all-ignored /path/to/log /path/to/filter.conf
```

### 3. 重载生效

```bash
sudo fail2ban-client reload
sudo fail2ban-client status myapp
```

---

## 六、进阶技巧

### 1. 一个 jail 同时封多个端口

```ini
[myapp]
port = http,https,8080
```

### 2. 累犯加重封禁（recidive）

`recidive` 会监控 `fail2ban.log`，对「反复被多次封禁」的 IP 进行长期封禁：

```ini
[recidive]
enabled  = true
filter   = recidive
logpath  = /var/log/fail2ban.log
maxretry = 3
findtime = 1d
bantime  = 7d
```

### 3. 自定义封禁动作（发邮件 / 通知）

在 `[DEFAULT]` 或单个 jail 中指定：

```ini
[DEFAULT]
destemail = admin@example.com
sender    = fail2ban@example.com
action    = %(action_mwl)s   # 封禁 + whois + 发送邮件
```

### 4. 多行日志（如 Java 异常堆栈）

```ini
[myapp]
maxlines = 2
```

### 5. 日志时间格式非标准

```ini
[Definition]
datepattern = ^%%Y-%%m-%%d %%H:%%M:%%S
```

> 在 filter 文件中 `%` 需写成 `%%`。

---

## 七、常见内置 Filter 速查

| Filter 名 | 对应服务 | 典型日志 |
|-----------|----------|----------|
| `sshd` | SSH | `/var/log/auth.log` |
| `nginx-http-auth` | Nginx 基础认证 | `/var/log/nginx/error.log` |
| `nginx-botsearch` | Nginx 恶意扫描 | `/var/log/nginx/access.log` |
| `apache-auth` | Apache 认证 | `/var/log/apache2/error.log` |
| `wordpress` | WordPress 登录 | access.log |
| `vsftpd` | FTP | `/var/log/vsftpd.log` |
| `postfix-sasl` | Postfix 邮件认证 | `/var/log/mail.log` |
| `mysqld-auth` | MySQL | `/var/log/mysql/error.log` |
| `recidive` | 累犯 | `/var/log/fail2ban.log` |

查看系统自带全部 filter：

```bash
ls /etc/fail2ban/filter.d/
```

---

## 八、排错清单

| 现象 | 原因 | 解决 |
|------|------|------|
| `Failregex: 0 total` | 正则不匹配日志 | 用 `--print-all-matched` 对照日志实际格式修正正则 |
| 匹配到但 IP 为空 | 没写 `<HOST>` 或位置错 | 在 IP 出现处放 `<HOST>` |
| jail 显示但无封禁 | `logpath` 错 / 日志无写入 | 确认路径与权限；`systemd` 系统用 `backend = systemd` |
| 封禁后仍能登录 | 端口 `port` 写错 | 改成实际端口或 `http,https` |
| 误封正常用户 | 正则过宽 | 收窄 failregex，或用 `ignoreregex` 排除 |

---

## 九、一句话总结

> **写规则 = 找到日志里「失败」那一行 → 把 IP 位置换成 `<HOST>` 写成 failregex → 在 jail.local 里声明 filter + logpath + 阈值 → 用 `fail2ban-regex` 验证 → `reload` 生效。**
