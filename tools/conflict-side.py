#!/usr/bin/env python3
"""Resolve every conflict hunk in FILE by taking one side: conflict-side.py ours|theirs|both FILE.

"ours" is the Ubuntu (HEAD) side, "theirs" the incoming Asahi commit. Does not `git add`.
Needs conflict markers in FILE (use `git checkout -m -- FILE` to recreate them).
"""
import re
import sys

PICK = {
    "ours": lambda m: m.group(1),
    "theirs": lambda m: m.group(2),
    "both": lambda m: m.group(1) + m.group(2),
}
HUNK = re.compile(r"<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n", re.S)

if len(sys.argv) != 3 or sys.argv[1] not in PICK:
    sys.exit(__doc__)
side, path = sys.argv[1:]
with open(path) as f:
    text = f.read()
with open(path, "w") as f:
    f.write(HUNK.sub(PICK[side], text))
