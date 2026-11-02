# -*- coding: utf-8 -*-
"""生成代码展示页：读取两个 .sh，用 pygments 高亮，输出自包含 HTML。"""
import os
from pygments import highlight
from pygments.lexers import BashLexer
from pygments.formatters import HtmlFormatter

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(BASE, "代码展示.html")

FILES = [
    ("ssh_menu.sh", "交互面板 · 输入 sshh 进入", "primary"),
    ("ssh-port.sh", "命令包装器 · 无参开面板 / 带参转发", "primary"),
    ("change_ssh_port.sh", "主脚本 · 更换 SSH 端口", "primary"),
    ("remove_old_ssh_port.sh", "收尾脚本 · 移除旧端口", "secondary"),
    ("install.sh", "自解压安装器 · 含 alias 注入", "secondary"),
    ("push-to-github.sh", "推送脚本 · GitHub 一键推送", "secondary"),
]

# 本次修复清单
FIXES = [
    ("全部脚本 · prompt()", "`{ read -p \"提示\" x; } 2>/dev/null` 把提示（走 stderr）和错误噪音一起丢掉，curl | bash 安装时卡住无提示", "提示改用 printf 单独写 stderr，read 不再带 -p"),
    ("全部脚本 · 颜色变量", "颜色存的是字面量 \\033[0;32m，面板用 printf '%s' 不会解释，终端满屏 \\033[0;36m", "改用 $'\\033[..' 存真实 ESC 字节，printf / echo 都能正确上色"),
    ("install.template · 别名落点", "把 $SUDO_USER 当目录用（它是用户名），sudo 安装时普通用户 rc 被静默跳过，装完 sshh 不生效", "改用 getent passwd 反查真实 home"),
    ("install.template · rc 属主", "sudo 下 sed -i 重建文件，用户 .bashrc 属主变成 root", "写入前后记录并还原属主"),
    ("ssh_menu.sh · 卸载软链", "只删 3 个软链，漏掉 ssh-port-menu", "与安装器对齐，清理 4 个"),
    ("ssh_menu.sh · 卸载别名", "用 $HOME 定位 rc，sudo 下清不到普通用户", "按 SUDO_USER 反查 home"),
    ("ssh_menu.sh · 回滚", "直接覆盖当前配置，备份若损坏会把可用配置也毁掉", "先留存当前配置，校验失败自动恢复"),
    ("ssh_menu.sh · 卸载护栏", "TOOL_DIR 异常时仍执行 rm -rf", "为空或 / 时直接拒绝"),
    ("ssh_menu.sh · 详情页正则", "端口未分组，:22 会匹配到 :2222 行", "改为 :(22|2222) 成组匹配"),
    ("ssh_menu.sh · nftables", "点「放行」后什么都不做，静默失败", "打印需手动执行的 nft 命令"),
    ("install.template · exec 清理", "--menu / --run 用 exec 启动，EXIT trap 不执行，临时目录残留", "exec 前主动清理并解除 trap"),
    ("change/remove · 服务名", "只尝试 systemctl restart ssh，服务名为 sshd 的系统重启失败", "统一 restart_ssh()，依次尝试 ssh / sshd"),
    ("change · Include 回滚", "主配置回滚了，Include 里被注释的 Port 残留", "记录备份路径，异常时一并还原"),
    ("remove · 端口去重", "重复 Port 行让「端口数量」判断出错", "get_ports 加 sort -un"),
    ("install.template · 安装完成提示", "引用了未定义的 ${DIM} 颜色变量，set -u 下安装成功最后一刻崩溃", "补上 DIM 定义"),
    ("install.template · 别名入口", "alias ssh 占用系统命令名，与脚本/插件里的 ssh 调用冲突", "改为 alias sshh，系统 ssh 完全不受影响"),
]

formatter = HtmlFormatter(style="vs", linenos="table", cssclass="hl", linenostart=1)
pyg_css = formatter.get_style_defs(".hl")

cards_html = []
nav_items = []
for idx, (fn, subtitle, kind) in enumerate(FILES):
    path = os.path.join(BASE, fn)
    with open(path, encoding="utf-8") as f:
        code = f.read()
    nlines = code.count("\n") + (0 if code.endswith("\n") else 1)
    nbytes = len(code.encode("utf-8"))
    hl = highlight(code, BashLexer(), formatter)
    anchor = f"file{idx+1}"
    nav_items.append(f'<a href="#{anchor}">{fn}</a>')
    cards_html.append(f'''
<section class="card" id="{anchor}">
  <div class="card-head">
    <span class="dot dot-{kind}"></span>
    <h2>{fn}</h2>
    <span class="badge">{subtitle}</span>
    <span class="meta">{nlines} 行 · {nbytes/1024:.1f} KB</span>
  </div>
  <div class="code-wrap">
    {hl}
  </div>
</section>''')

fix_rows = "\n".join(
    f"<tr><td class='num'>{i+1}</td><td><code>{loc}</code></td><td>{bug}</td><td class='fix'>{fix}</td></tr>"
    for i, (loc, bug, fix) in enumerate(FIXES)
)

html_doc = f'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Debian SSH 端口更换工具 · 代码展示</title>
<style>
  :root {{
    --bg: #f7f8fa;
    --panel: #ffffff;
    --border: #e3e6ea;
    --text: #1f2328;
    --muted: #6b7280;
    --accent: #0969da;
    --green: #1a7f37;
    --amber: #9a6700;
    --red: #cf222e;
    --mono: "JetBrains Mono", "Cascadia Code", "Fira Code", Consolas, "Courier New", monospace;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0;
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
    line-height: 1.6;
    padding: 0 0 60px;
  }}
  header.hero {{
    background: linear-gradient(135deg, #0969da 0%, #1f6feb 55%, #388bfd 100%);
    color: #fff;
    padding: 34px 28px 26px;
  }}
  header.hero h1 {{ margin: 0 0 6px; font-size: 26px; letter-spacing: .3px; }}
  header.hero .sub {{ margin: 0; opacity: .92; font-size: 14px; }}
  header.hero .chips {{ margin-top: 14px; display: flex; flex-wrap: wrap; gap: 8px; }}
  .chip {{
    background: rgba(255,255,255,.18);
    border: 1px solid rgba(255,255,255,.3);
    padding: 3px 10px; border-radius: 999px; font-size: 12.5px;
  }}
  .wrap {{ max-width: 1180px; margin: 0 auto; padding: 0 20px; }}
  nav.toc {{
    position: sticky; top: 0; z-index: 10;
    background: rgba(247,248,250,.92);
    backdrop-filter: blur(6px);
    border-bottom: 1px solid var(--border);
    padding: 10px 0;
  }}
  nav.toc .wrap {{ display: flex; gap: 16px; align-items: center; flex-wrap: wrap; }}
  nav.toc a {{
    color: var(--accent); text-decoration: none; font-size: 13.5px; font-weight: 600;
    padding: 4px 10px; border-radius: 6px;
  }}
  nav.toc a:hover {{ background: #e7f0fe; }}
  nav.toc .toc-title {{ font-size: 12px; color: var(--muted); text-transform: uppercase; letter-spacing: .08em; }}
  h2.section-title {{ font-size: 19px; margin: 34px 0 14px; }}
  .card {{
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 12px;
    margin: 22px 0;
    overflow: hidden;
    box-shadow: 0 1px 2px rgba(16,24,40,.04), 0 4px 14px rgba(16,24,40,.04);
  }}
  .card-head {{
    display: flex; align-items: center; gap: 10px;
    padding: 13px 18px;
    background: #fbfcfd;
    border-bottom: 1px solid var(--border);
  }}
  .card-head h2 {{ margin: 0; font-size: 15.5px; font-family: var(--mono); }}
  .dot {{ width: 10px; height: 10px; border-radius: 50%; display: inline-block; }}
  .dot-primary {{ background: #2da44e; }}
  .dot-secondary {{ background: #bf8700; }}
  .badge {{
    font-size: 12px; color: var(--muted);
    background: #eef1f4; padding: 2px 9px; border-radius: 999px;
  }}
  .meta {{ margin-left: auto; font-size: 12.5px; color: var(--muted); font-family: var(--mono); }}
  .code-wrap {{ overflow-x: auto; }}
  /* ---- pygments 表格行号样式 ---- */
  .code-wrap .hl {{ margin: 0; }}
  .code-wrap table {{ border-collapse: collapse; width: 100%; }}
  .code-wrap td {{ vertical-align: top; padding: 0; }}
  .code-wrap td.linenos {{
    user-select: none;
    background: #f6f8fa;
    border-right: 1px solid var(--border);
    padding: 12px 0;
  }}
  .code-wrap td.linenos .linenodiv pre {{
    margin: 0; padding: 0 12px 0 14px;
    font-family: var(--mono); font-size: 13px; line-height: 1.55;
    color: #9aa4b2; text-align: right;
  }}
  .code-wrap td.code {{ background: #ffffff; }}
  .code-wrap td.code pre {{
    margin: 0; padding: 12px 18px;
    font-family: var(--mono); font-size: 13px; line-height: 1.55;
    white-space: pre; tab-size: 4;
  }}
  /* ---- 审计表 ---- */
  .audit {{
    background: var(--panel); border: 1px solid var(--border); border-radius: 12px;
    overflow: hidden; margin: 22px 0;
  }}
  table.audit-t {{ width: 100%; border-collapse: collapse; font-size: 13.5px; }}
  table.audit-t th {{
    text-align: left; background: #fbfcfd; color: var(--muted);
    font-weight: 600; padding: 11px 14px; border-bottom: 1px solid var(--border);
    font-size: 12.5px; letter-spacing: .03em;
  }}
  table.audit-t td {{ padding: 11px 14px; border-bottom: 1px solid #f0f2f4; vertical-align: top; }}
  table.audit-t tr:last-child td {{ border-bottom: none; }}
  table.audit-t td.num {{ color: var(--muted); width: 36px; font-family: var(--mono); }}
  table.audit-t code {{
    font-family: var(--mono); font-size: 12.5px;
    background: #eef1f4; padding: 1px 6px; border-radius: 5px;
  }}
  table.audit-t td.fix {{ color: var(--green); }}
  footer {{ text-align: center; color: var(--muted); font-size: 12.5px; margin-top: 40px; }}
  @media (max-width: 720px) {{
    .meta {{ display: none; }}
    header.hero {{ padding: 26px 18px 20px; }}
  }}
</style>
</head>
<body>
<header class="hero">
  <div class="wrap">
    <h1>Debian SSH 端口更换工具</h1>
    <p class="sub">代码展示与审计报告 · v2.8</p>
    <div class="chips">
      <span class="chip">输入 sshh 进交互面板</span>
      <span class="chip">自动备份 / 校验 / 回滚</span>
      <span class="chip">Include 检测</span>
      <span class="chip">端口监听验证</span>
      <span class="chip">ShellCheck 0 告警</span>
      <span class="chip">curl | bash 一键安装</span>
      <span class="chip">仅限 Linux</span>
    </div>
  </div>
</header>

<nav class="toc">
  <div class="wrap">
    <span class="toc-title">导航</span>
    <a href="#audit">修复清单</a>
    {''.join(nav_items)}
  </div>
</nav>

<div class="wrap">
  <h2 class="section-title" id="audit">本次修复的 Bug</h2>
  <div class="audit">
    <table class="audit-t">
      <thead>
        <tr><th>#</th><th>位置</th><th>问题</th><th>修复</th></tr>
      </thead>
      <tbody>
        {fix_rows}
      </tbody>
    </table>
  </div>

  <h2 class="section-title">脚本源码</h2>
  {''.join(cards_html)}

  <footer>
    由 pygments 生成 · 浅色主题 · 支持离线打开 · 最后更新 2026-11-02
  </footer>
</div>
</body>
</html>
'''

# 注入 pygments 样式
html_doc = html_doc.replace("</style>", pyg_css + "\n</style>")

with open(OUT, "w", encoding="utf-8") as f:
    f.write(html_doc)

print("generated:", OUT, len(html_doc), "bytes")
