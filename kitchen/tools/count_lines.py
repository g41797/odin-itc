#!/usr/bin/env python3
import sys
from pathlib import Path

def count_file(path):
    total = 0
    in_block = False
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if in_block:
            if "*/" in s:
                in_block = False
            continue
        if not s:
            continue
        if s.startswith("//"):
            continue
        if s.startswith("/*"):
            if "*/" not in s:
                in_block = True
            continue
        total += 1
    return total

root = Path(sys.argv[1])
total = 0
for f in sorted(root.glob("*.odin")):
    if f.name == "doc.odin":
        continue
    total += count_file(f)
print(total)
