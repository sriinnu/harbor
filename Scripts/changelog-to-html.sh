#!/usr/bin/env bash
set -euo pipefail

VERSION=${1:?"Usage: $0 <version> [changelog]"}
CHANGELOG=${2:-CHANGELOG.md}

python3 - "$VERSION" "$CHANGELOG" <<'PY'
import html
import pathlib
import re
import sys

version = sys.argv[1]
changelog = pathlib.Path(sys.argv[2])
text = changelog.read_text()

pattern = re.compile(rf"^##\s+\[?{re.escape(version)}\]?.*$", re.M)
m = pattern.search(text)
if not m:
    sys.exit(f"changelog section not found for {version}")
start = m.end()
next_header = text.find("\n## ", start)
section = text[start: next_header if next_header != -1 else len(text)].strip()

lines = [ln.rstrip() for ln in section.splitlines()]
out = []
para = []
items = []

def inline(text):
    """Escape text, then turn Markdown `code` and **bold** into HTML. Sparkle shows the
    notes as HTML, so Markdown left in them shows up literally."""
    parts = re.split(r"`([^`]+)`", text)
    for i, part in enumerate(parts):
        if i % 2:
            parts[i] = "<code>{}</code>".format(html.escape(part))
        else:
            parts[i] = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", html.escape(part))
    return "".join(parts)

def flush_para():
    global para
    if para:
        out.append("<p>{}</p>".format(inline(" ".join(para))))
        para = []

def flush_list():
    global items
    if items:
        out.append("<ul>{}</ul>".format("".join(f"<li>{inline(i)}</li>" for i in items)))
        items = []

for line in lines:
    if not line.strip():
        flush_para()
        flush_list()
        continue
    if line.startswith("### "):
        flush_para()
        flush_list()
        out.append(f"<h3>{inline(line[4:])}</h3>")
        continue
    if line.startswith("#### "):
        flush_para()
        flush_list()
        out.append(f"<h4>{inline(line[5:])}</h4>")
        continue
    bullet = re.match(r"^[-*]\s+(.*)$", line)
    if bullet:
        flush_para()
        items.append(bullet.group(1))
        continue
    # An indented line right after a bullet continues that bullet (wrapped text).
    if items and line.startswith((" ", "\t")):
        items[-1] += " " + line.strip()
        continue
    flush_list()
    para.append(line.strip())

flush_para()
flush_list()

print("".join(out))
PY
