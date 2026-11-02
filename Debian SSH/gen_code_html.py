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
    ("install.template · 安装完成提示", "引用了未定义的 ${DIM} 颜色变量，set -u 下安装成功最后一刻崩溃", "补上 DIM 定义，安装流程完整走完"),
    ("install.template · 别名入口", "alias ssh 占用系统命令名，与脚本/插件里的 ssh 调用冲突", "改为 alias sshh，系统 ssh 完全不受影响"),
    ("ssh_menu.sh · do_firewall()", "分支条件引用了未定义的 $c，set -u 下会 unbound variable 直接崩溃", "改为只判断 $ans，并补 as_root 提权"),
    ("ssh_menu.sh · list_backups()", "ls -1t | grep 无法处理特殊字符文件名（SC2010/SC2012）", "改用 find -printf 按 mtime 排序，保留 ls 降级分支"),
    ("ssh_menu.sh · 防火墙放行", "A && B || C 陷阱：成功时也可能执行 err 分支（SC2015）", "改为显式 if/elif/else"),
    ("ssh_menu.sh · 卸载", "后台 sleep 删除自身所在目录，脚本可能被提前删掉", "延迟 2 秒 + disown，等脚本退出后再删"),
    ("install.template · alias 注入", "重复安装会写入多份 alias，污染 rc 文件", "按标记先删后写，保证幂等"),
    ("install.template · alias 移除", "卸载后 rc 文件残留别名块", "用 sed 按标记范围精确删除，保留其余配置"),
    ("install.template · 解压自检", "payload 不完整时只报『解压失败』，难以定位", "解压后逐个检查核心脚本是否存在"),
    ("ssh-port.sh · 真实 ssh 定位", "包装器可能找到指向自身的软链，造成无限递归", "逐个校验 readlink 目标，跳过自身目录"),
    ("ssh-port.sh · 参数透传", "无参调用原生 ssh 只会打印用法，无法承载面板", "无参开面板，带参 exec 原生客户端"),
    ("install.template · 平台检查", "非 Linux 上继续安装，后续 systemctl 全部失败", "改为硬性检查，非 Linux 直接拒绝"),
    ("build_install.py · 权限位", "tar 内脚本为 0666，依赖安装后 chmod 兜底", "打包时按扩展名设置 0755 / 0644"),
    ("port_listening()", "用 awk NR>1 跳过表头，若某些 ss 版本无表头会漏掉首行端口", "改为直接取第 4 列，表头该列不含端口号自然不匹配"),
    ("apply_config()", "删除 Port 的正则过宽，会误删『# Port forwarding ...』这类注释", "收紧为仅匹配『Port <数字>』（可带行尾注释）"),
    ("handle_includes()", "『grep && hits+=()』在 set -e 下存在返回非零导致退出的风险", "改为 if 判断，规避 errexit"),
    ("main() 取旧端口", "head -1 配合 pipefail 可能因 SIGPIPE 返回 141 而误退出", "改为 awk 'NR==1{print; exit}'"),
    ("sshd -t 失败分支", "手动回滚后 CHANGED 仍为 1，EXIT trap 会二次回滚并重启服务", "回滚后置 CHANGED=0"),
    ("参数解析 -p", "shift 2 在缺少参数时会报错退出，提示不友好", "增加参数存在性校验并给出明确提示"),
    ("remove: sed 删除", "带行尾注释的 Port 行删不掉", "允许『# 注释』后缀匹配"),
    ("remove: remain 构建", "『[[ ]] && arr+=()』同样的 set -e 风险", "改为 if 判断"),
    ("prompt() 三处", "『[[ -r /dev/tty ]]』在无终端环境仍为真，重定向失败打印噪音", "新增 _tty_ok() 用子 shell 实际探测"),
    ("交互读取", "curl | bash 管道执行时 stdin 被脚本自身占用，read 读到 EOF", "新增 prompt()，非终端时改从 /dev/tty 读取"),
    ("非交互保护", "无 tty 且未传端口时，read 循环空转可能死循环", "检测到非交互环境直接提示改用 -p"),
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
    <p class="sub">代码展示与审计报告 · v2.6</p>
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
