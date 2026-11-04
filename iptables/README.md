# iptables-wizard

Debian / Ubuntu 上的一键 iptables 防火墙管理脚本。纯 Bash 实现，**不依赖 whiptail / dialog**，
所有交互都在终端里完成，带彩色语法高亮、中英混排对齐、变更前自动备份。

```
╭──────────────────────────────────────────────────────────────╮
│  iptables-wizard v1.2.0   ·   Debian 防火墙一键管理工具      │
╰──────────────────────────────────────────────────────────────╯
```

- **零依赖**：只用 bash 内建 + coreutils / iptables，装完即用
- **不会把自己关在门外**：改策略、拒绝端口、封 IP 三道关卡都会先校验 SSH
- **规则可持久化**：`netfilter-persistent` 优先，`iptables-save` 兜底
- **随时可回滚**：每次改动自动备份，保留最近 30 份
- **可脚本化**：13 个子命令，方便写进 Ansible / 初始化脚本

---

## 一、快速开始

### 1. 一行安装并进入交互界面（傻瓜式，推荐）

**国内加速（jsDelivr CDN，国内网络优先用这个）**

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/iptables/install.sh | sudo bash -s -- --run
```

**GitHub 直连（海外网络或 CDN 不可达时用）**

```bash
curl -fsSL https://raw.githubusercontent.com/Swordee/NEW1/main/iptables/install.sh | sudo bash -s -- --run
```

这一条命令会依次完成：

1. 下载安装器，校验内嵌脚本的 SHA256 与语法
2. 检查系统是否为 Debian / Ubuntu 系
3. 主程序写入 `/usr/local/sbin/iptables-wizard`，并在 `/usr/local/bin` 建软链
4. **自动安装依赖** `iptables` 与 `netfilter-persistent`（保证规则重启后自动恢复）
5. 创建备份目录 `/etc/iptables-wizard/backups`
6. **直接进入交互式管理界面**

> ⚠️ 精简系统可能没有 `sudo` 命令（root 直接登录的 VPS 常见）。先执行 `apt-get install -y sudo`，
> 或者直接以 root 运行（去掉 `sudo` 即可）：
> `curl -fsSL https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/iptables/install.sh | bash -s -- --run`

安装完成后，日常使用只需要一条命令：

```bash
sudo iptables-wizard
```

只想装程序、不动系统依赖时加 `--no-deps`；只安装、不进界面就去掉 `--run`。

#### CDN 备用节点

主域名不通时，只换主机名即可，路径完全一样：

| 节点 | 地址前缀 |
| --- | --- |
| Cloudflare（默认） | `https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/...` |
| Fastly | `https://fastly.jsdelivr.net/gh/Swordee/NEW1@main/...` |
| Gcore | `https://gcore.jsdelivr.net/gh/Swordee/NEW1@main/...` |
| Cloudflare 备用 | `https://testingcf.jsdelivr.net/gh/Swordee/NEW1@main/...` |

#### 关于 jsDelivr 的三点说明

1. **只能镜像公开仓库**。本仓库已公开，可直接用；若以后转回私有，CDN 地址会立即 404。
2. **`@main` 有缓存**。分支引用在 CDN 侧一般缓存约 12 小时，推了新提交后不会立刻生效。
   想立刻拿到最新版本，把 `@main` 换成具体的 commit SHA：

   ```bash
   # 锁定到某个提交，内容永久不变（推荐写进部署脚本）
   curl -fsSL https://cdn.jsdelivr.net/gh/Swordee/NEW1@ca62320/iptables/install.sh | sudo bash
   ```

3. **手动刷新缓存**（推了新提交、又不想等缓存过期时）：

   ```bash
   curl -s https://purge.jsdelivr.net/gh/Swordee/NEW1@main/iptables/install.sh
   ```

   > 新仓库首次被访问时，jsDelivr 可能返回一次 `Failed to fetch ... from GitHub`，
   > 等几秒重试即可，属于冷缓存回源失败，不是仓库问题。

### 2. 下载后执行（不放心 `| bash` 时用这个）

```bash
# CDN（国内快）
curl -fsSLO https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/iptables/install.sh
# 或 GitHub 直连
# curl -fsSLO https://raw.githubusercontent.com/Swordee/NEW1/main/iptables/install.sh

bash install.sh --check          # 先看看内嵌负载是否完整
sudo bash install.sh             # 确认无误再安装
```

### 3. 直接用源码（不安装）

```bash
git clone https://github.com/Swordee/NEW1.git && cd NEW1/iptables
sudo bash iptables-wizard.sh
```

不想 clone 整个仓库，也可以从 CDN 单独取文件：

```bash
curl -fsSLO https://cdn.jsdelivr.net/gh/Swordee/NEW1@main/iptables/iptables-wizard.sh
sudo bash iptables-wizard.sh
```

### 安装器参数

| 参数 | 说明 |
| --- | --- |
| `--run` | 安装完成后立即进入交互界面（`curl \| bash` 场景自动改从 `/dev/tty` 读取按键） |
| `--prefix DIR` | 安装前缀，默认 `/usr/local` |
| `--no-deps` | 跳过依赖安装（默认会装 `iptables` 与 `netfilter-persistent`） |
| `--force` | 跳过发行版检查（在非 Debian 系上强装） |
| `--check` | 只校验内嵌脚本：解码 + SHA256 + 语法 + 版本 |
| `--uninstall` | 卸载程序（保留 `/etc/iptables-wizard` 下的备份） |
| `--purge` | 与 `--uninstall` 一起用，连配置和备份一起删除 |
| `--version` / `-h` | 版本 / 帮助 |

---

## 二、交互菜单

启动 `sudo iptables-wizard` 后进入主菜单，顶部是实时状态栏：

```
策略 INPUT DROP / FORWARD ACCEPT / OUTPUT ACCEPT │ 规则 12 条 │ ● 有未保存变更 │ 服务 active
```

| 编号 | 菜单 | 能做什么 |
| --- | --- | --- |
| 1 | 状态概览 | 策略、规则数、服务状态、持久化文件、最近备份 |
| 2 | 安装与检测 | 装依赖、`doctor` 环境自检 |
| 3 | 服务控制 | 启动 / 停止 / 重启 / 重载 / 开机自启 / 服务状态 |
| 4 | 查看规则 | filter / nat / mangle 分表查看、`iptables -S` 可复制格式、监听端口、内核丢包日志 |
| 5 | 添加规则 | 放行或拒绝端口、IP/网段、ICMP，ESTABLISHED 放行、回环放行、SSH 防爆破、自定义规则 |
| 6 | 删除规则 | 按行号删除、按链清空、清空全部 |
| 7 | 策略与预设 | 改默认策略；SSH 基础防护 / Web 服务器 / 数据库 / Docker 友好 / 全放行 五套预设 |
| 8 | 高级功能 | 端口转发（DNAT）、出网共享（SNAT/MASQUERADE）、IP 转发开关、丢包日志、端口连通性测试 |
| 9 | 保存 / 备份 | 保存到磁盘、手动备份、备份列表、按序号恢复、一键回滚、导出、清空备份 |
| 0 | 退出 | |

> 菜单里输入 `0` 返回上一层，`Ctrl-C` 会恢复终端状态（不会留下花屏）。

---

## 三、命令行子命令

适合写进自动化脚本，全部需要 root：

```bash
sudo iptables-wizard status                    # 状态概览
sudo iptables-wizard list [filter|nat|mangle]  # 按表列出规则
sudo iptables-wizard start | stop | restart | reload
sudo iptables-wizard save                      # 保存规则，重启后仍生效
sudo iptables-wizard backup                    # 备份当前规则
sudo iptables-wizard restore /path/to/backup   # 恢复（会先自动备份当前规则）
sudo iptables-wizard doctor                    # 环境自检：内核模块、服务、持久化、权限
sudo iptables-wizard install                   # 安装依赖
sudo iptables-wizard version | help
```

---

## 四、安全性设计

iptables 最容易出的事故是「把自己锁在外面」，本脚本在三个层面做了拦截：

1. **改默认策略前**：先把已探测到的 SSH 端口、`ESTABLISHED,RELATED`、`lo` 补成 ACCEPT，
   再设 `-P INPUT DROP`，避免出现「策略已 DROP、放行规则还没加」的空窗。
2. **拒绝/封禁时**：如果目标端口覆盖了当前 SSH 端口，或目标 IP 等于当前 SSH 客户端 IP，
   会弹红色警告并要求二次确认，默认选项是「取消」。
3. **SSH 端口识别**：优先读 `SSH_CONNECTION`，其次 `sshd -T` / `sshd_config`，最后 `ss -tlnp` 兜底。

另外：

- 每次改动前自动备份到 `/etc/iptables-wizard/backups/`，滚动保留 30 份
- 写 `/etc/iptables/rules.v4` 前会校验 `iptables-save` 输出里确实有 `*filter`，防止写坏文件
- 所有 `iptables` 调用都带 `-w 5`，避免和 Docker / fail2ban 抢 xtables 锁时报错
- 自定义规则会拦截 `; | & < > $( \`` 等 shell 元字符，防止命令注入
- 操作日志追加写入 `/var/log/iptables-wizard.log`

---

## 五、文件位置

| 路径 | 用途 |
| --- | --- |
| `/etc/iptables/rules.v4`、`rules.v6` | 持久化规则（`netfilter-persistent` 读取） |
| `/etc/iptables-wizard/backups/` | 自动备份，权限 700，保留最近 30 份 |
| `/var/log/iptables-wizard.log` | 操作日志 |
| `/usr/local/sbin/iptables-wizard` | 安装后的程序本体 |
| `/usr/local/bin/iptables-wizard` | 软链，保证在 PATH 里 |

---

## 六、开发与 CI

### 目录结构

```
iptables-wizard.sh           主脚本（唯一源码，约 2000 行）
install.sh                   自解压安装器（由模板 + 主脚本生成，勿手改）
ci.sh                        本地 CI 总入口
scripts/
  install.template.sh        安装器模板（含 @VERSION@ / @SHA256@ / @PAYLOAD@ 占位符）
  build-install.sh           把主脚本打包进模板，生成 install.sh
tests/
  smoke.sh                   冒烟测试，39 项断言，不需要 root
  e2e-install.sh             安装端到端测试（模拟 curl | bash：安装 / --run / 进界面 / 卸载）
.github/workflows/ci.yml     GitHub Actions 流水线
```

### 本地跑一遍 CI

```bash
bash ci.sh                # 全量：语法 → ShellCheck → 冒烟 → 端到端 → 安装器 → 版本
bash ci.sh --quick        # 跳过冒烟与端到端测试，改注释/文档时用
bash ci.sh --strict       # ShellCheck 提到 info 级
bash ci.sh --only shellcheck,version
bash ci.sh --fix          # 先重新生成 install.sh 再检查
```

输出长这样：

```
 ▶ 1/7 语法检查 (bash -n)
   ✔ iptables-wizard.sh
   ...
 ▶ 2/7 静态分析 (shellcheck)
   ✔ 7 个脚本，0 条告警（级别：style）
 ▶ 3/7 冒烟测试 (tests/smoke.sh)
   ✔ 全部通过：39 项
 ...
 ✔ 全部通过：7 项 · 耗时 5s
```

没装 ShellCheck 时脚本会给出三种安装方式；也可以手动指定：

```bash
SHELLCHECK_BIN=/path/to/shellcheck bash ci.sh
```

### 改了主脚本之后

`install.sh` 里内嵌着主脚本的 gzip+base64 副本，**改了 `iptables-wizard.sh` 必须重新打包**，
否则 CI 的「安装器新鲜度」会失败：

```bash
bash scripts/build-install.sh          # 重新生成 install.sh
bash scripts/build-install.sh --check  # 只检查是否过期（CI 用）
```

打包是确定性的（`gzip -9nc` 不写时间戳），同样输入必然产出同样字节，`--check` 才能靠 `diff` 判断。

### GitHub Actions

`.github/workflows/ci.yml` 四个 job：

| Job | 内容 |
| --- | --- |
| `lint` | `bash -n` + `shellcheck -S style`（要求 0 告警），另跑一遍 `--strict` 作为参考 |
| `smoke` | 在 `debian:11/12`、`ubuntu:22.04/24.04` 四个容器里跑 `tests/smoke.sh` |
| `installer` | `build-install --check`、`install.sh --check`、版本一致性、临时前缀端到端安装 + 卸载 |
| `hygiene` | 检查 LF 换行、行尾空白、bash shebang、`VERSION` 常量格式 |

### 冒烟测试怎么做到不碰真实防火墙的

用「同名 shell 函数」替换 `iptables` / `ip6tables` / `iptables-save` / `systemctl` / `sshd` / `ss`，
全部在进程内完成，不 fork 外部进程，然后 `source` 主脚本直接调用其内部函数做断言：

```bash
iptables() { printf 'iptables %s\n' "$*" >>"${MOCK_LOG}"; ... }
...
printf '1\ntcp\n8080\n\n\nWeb后端\n\n0\n' | menu_add   # 走一遍真实交互流程
assert_contains "放行端口 8080" "$(cat "${MOCK_LOG}")" "--dport 8080"
```

所以既不需要 root，也不会改动任何一台机器的规则，在 CI 容器里跑得很稳。

---

## 七、常见问题

**Q：改完规则忘了保存，重启后没了？**
主菜单和状态栏会显示 `● 有未保存变更`，看到这个提示就去「9 保存 / 备份」里点保存，
或者直接 `sudo iptables-wizard save`。

**Q：把自己锁在外面了怎么办？**
如果还能通过服务商 VNC / 串口登录，执行 `sudo iptables-wizard stop` 先全放行，再慢慢排查；
或者回滚到最近一次备份：

```bash
sudo iptables-wizard restore "$(ls -1t /etc/iptables-wizard/backups | head -n 1 | sed 's|^|/etc/iptables-wizard/backups/|')"
```

也可以进「9 保存 / 备份 → 5 回滚到最近一次备份」，一条命令搞定。云主机建议先确认控制台可用。

**Q：和 Docker 冲突？**
Docker 自己会往 `DOCKER` / `DOCKER-USER` 链写规则，用「策略与预设 → Docker 友好」这套方案，
它只放行 docker 网桥与已建立连接，不会破坏容器网络。

**Q：`iptables` 和 `nftables` 混用？**
Debian 12 默认 `iptables` 已是 `nftables` 前端（`iptables-nft`），本脚本照常工作；
如果系统里还有 `ufw` / `firewalld`，建议先停用，避免两套规则打架。

**Q：IPv6 呢？**
所有清空 / 预设 / 停止操作都会同时处理 `ip6tables`（探测到可用时），避免「IPv4 关了、IPv6 还开着」。

---

## 八、卸载

```bash
sudo bash install.sh --uninstall         # 删程序，保留 /etc/iptables-wizard 备份
sudo bash install.sh --uninstall --purge # 连配置和备份一起删
```

卸载**不会**清空当前防火墙规则。要恢复成「全放行」，先运行 `sudo iptables-wizard stop`。

---

## 九、许可

MIT
