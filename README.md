# Debian SSH 端口更换工具包

带交互提示、可安全回滚的 SSH 端口更换脚本，覆盖「改端口 → 验证 → 收尾清理」全流程，规避"改完连不上、把自己锁在门外"的风险。

> 📖 完整手册见 **[使用文档.md](使用文档.md)**

## 一键安装（自解压）

`install.sh` 内嵌全部脚本，可单文件分发，无需额外下载：

```bash
# 远程一键（需 root）
curl -fsSL https://your.host/install.sh | sudo bash

# 安装并立即运行更换端口脚本
curl -fsSL https://your.host/install.sh | sudo bash -s -- -y --run

# 本地安装到自定义目录
sudo bash install.sh -d /opt/ssh-port-tools
```

安装后可直接使用命令：`ssh-port-change` / `ssh-port-remove`。

## 文件

| 文件 | 作用 |
| --- | --- |
| `change_ssh_port.sh` | 主脚本：更换端口，支持过渡期保留旧端口 |
| `remove_old_ssh_port.sh` | 收尾脚本：验证通过后移除旧端口 |
| `install.sh` | 自解压一键安装器（内嵌全部脚本） |
| `install.template` | 安装器模板（构建源，非 .sh 不参与检查） |
| `build_install.py` | 打包生成 install.sh 的脚本 |
| `push-to-github.sh` | 一键推送到 GitHub（Token 静默输入，不落盘） |
| `check.sh` | 本地 / CI 统一检查入口（bash -n + ShellCheck） |
| `.shellcheckrc` | ShellCheck 项目配置 |
| `.github/workflows/shellcheck.yml` | GitHub Actions 自动检查 |
| `代码展示.html` | 带语法高亮的代码展示页 |
| `使用文档.md` | 完整使用手册 |

## 推送到 GitHub

```bash
# 交互式：提示输入用户名 / 仓库名 / Token
bash push-to-github.sh

# 非交互
GH_TOKEN=ghp_xxx bash push-to-github.sh -u 你的用户名 -r debian-ssh-port-tool --public
```

Token 在 <https://github.com/settings/tokens/new> 生成，勾选 `repo` 权限。脚本会校验 `.gitignore`、创建提交、可选自动建仓，并把 Token 通过一次性 credential helper 传入——**不写入 `.git/config`**。

> 手动推送等价命令：
> ```bash
> git remote add origin https://github.com/<用户名>/<仓库名>.git
> git push -u origin main
> ```

## 快速开始

```bash
# 1. 更换端口（建议保留旧端口过渡）
sudo bash change_ssh_port.sh

# 2. 另开终端，用新端口测试登录
ssh -p 新端口 用户@服务器IP

# 3. 验证成功后，关闭旧端口
sudo bash remove_old_ssh_port.sh
```

## 自动化用法

```bash
# 全自动：改端口 + 保留旧端口 + 放行防火墙
sudo bash change_ssh_port.sh -p 2222 -y --firewall

# 预演，不做任何修改
sudo bash change_ssh_port.sh -p 2222 -n
```

## 安全机制

- 自动备份到 `/etc/ssh/sshd_config_backups/`
- `sshd -t` 校验失败自动回滚
- 默认保留旧端口过渡，验证通过再清理
- 重启后自动验证端口监听
- 操作日志：`/var/log/change_ssh_port.log`

## 代码检查

```bash
# 语法检查 + ShellCheck（style 级）
bash check.sh
```

CI 通过 GitHub Actions 自动运行（`.github/workflows/shellcheck.yml`）。当前 ShellCheck 0.11 全量检查 **0 告警**。

## 注意

- 需 root 运行
- 云服务器还需在**安全组**放行新端口
- 详细参数、原理、FAQ、回滚见 [使用文档.md](使用文档.md)
