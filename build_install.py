# -*- coding: utf-8 -*-
"""把脚本打包进 install.sh（自解压）。

用法：python build_install.py
产出：install.sh（可执行，内嵌 base64(tar.gz) 负载 + sha256 清单）
"""
import base64
import datetime
import hashlib
import io
import os
import tarfile

BASE = r"C:\Users\1\WorkBuddy AI\2026-10-31-22-45-52"
TEMPLATE = os.path.join(BASE, "install.template")
OUTPUT = os.path.join(BASE, "install.sh")
INSTALLER_VERSION = "1.0.0"

# 打进安装包的文件（顺序即清单顺序）
FILES = [
    "change_ssh_port.sh",
    "remove_old_ssh_port.sh",
    "check.sh",
    ".shellcheckrc",
    "README.md",
    "使用文档.md",
    "Debian SSH/README.md",
]


def build_tarball() -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for name in FILES:
            path = os.path.join(BASE, name)
            if not os.path.exists(path):
                raise SystemExit(f"缺少文件: {name}")
            info = tar.gettarinfo(path, arcname=name)
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            with open(path, "rb") as fh:
                tar.addfile(info, fh)
    return buf.getvalue()


def main() -> None:
    raw = build_tarball()
    b64 = base64.b64encode(raw).decode("ascii")
    b64_wrapped = "\n".join(b64[i:i + 76] for i in range(0, len(b64), 76))

    manifest_lines = []
    for name in FILES:
        with open(os.path.join(BASE, name), "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
        manifest_lines.append(f"{digest}  {name}")
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
