# -*- coding: utf-8 -*-
"""把脚本打包进 install.sh（自解压）。

用法：python "Debian SSH/build_install.py"
产出：与脚本同目录的 install.sh（内嵌 base64(tar.gz) 负载 + sha256 清单）

路径说明：本脚本位于分类目录内（如 "Debian SSH/"），
         HERE 为分类目录，ROOT 为仓库根，.shellcheckrc 等仓库级文件从 ROOT 取。
"""
import base64
import datetime
import hashlib
import io
import os
import tarfile

HERE = os.path.dirname(os.path.abspath(__file__))
CATEGORY = os.path.basename(HERE)
ROOT = os.path.dirname(HERE)

TEMPLATE = os.path.join(HERE, "install.template")
OUTPUT = os.path.join(HERE, "install.sh")
INSTALLER_VERSION = "1.1.0"

# (源文件相对仓库根的路径, 包内名称)
FILES = [
    (f"{CATEGORY}/change_ssh_port.sh", "change_ssh_port.sh"),
    (f"{CATEGORY}/remove_old_ssh_port.sh", "remove_old_ssh_port.sh"),
    (f"{CATEGORY}/ssh_menu.sh", "ssh_menu.sh"),
    (f"{CATEGORY}/ssh-port.sh", "ssh-port.sh"),
    (f"{CATEGORY}/check.sh", "check.sh"),
    (".shellcheckrc", ".shellcheckrc"),
    (f"{CATEGORY}/README.md", "README.md"),
    (f"{CATEGORY}/使用文档.md", "使用文档.md"),
]


def build_tarball() -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for src, arc in FILES:
            path = os.path.join(ROOT, src)
            if not os.path.exists(path):
                raise SystemExit(f"缺少文件: {src}")
            info = tar.gettarinfo(path, arcname=arc)
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            # .sh 统一带可执行位，避免解压后依赖后续 chmod
            info.mode = 0o755 if arc.endswith(".sh") else 0o644
            with open(path, "rb") as fh:
                tar.addfile(info, fh)
    return buf.getvalue()


def main() -> None:
    raw = build_tarball()
    b64 = base64.b64encode(raw).decode("ascii")
    b64_wrapped = "\n".join(b64[i:i + 76] for i in range(0, len(b64), 76))

    manifest_lines = []
    for src, arc in FILES:
        with open(os.path.join(ROOT, src), "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
        manifest_lines.append(f"{digest}  {arc}")
    manifest = "\n".join(manifest_lines)

    with open(TEMPLATE, encoding="utf-8") as fh:
        tpl = fh.read()

    build_date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    out = (
        tpl.replace("__VERSION__", INSTALLER_VERSION)
           .replace("__BUILD_DATE__", build_date)
           .replace("__PAYLOAD_B64__", b64_wrapped)
           .replace("__MANIFEST__", manifest)
    )

    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(out)
    os.chmod(OUTPUT, 0o755)

    print(f"generated: {OUTPUT}")
    print(f"  files   : {len(FILES)}")
    print(f"  tar.gz  : {len(raw)} bytes")
    print(f"  base64  : {len(b64)} chars")
    print(f"  install : {len(out)} chars")


if __name__ == "__main__":
    main()
