#!/usr/bin/env python3
"""
Guardian: patch ArduPilot waf `git_submodule._git_head_hash` so SITL builds succeed when
`git rev-parse` fails (e.g. bundled tree copied without `.git`, or Xcode resource strip).

Idempotent — safe to run after every `fetch_ardupilot_sitl.sh`.
"""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "GUARDIAN_GIT_HEAD_FALLBACK"

OLD = """def _git_head_hash(ctx, path, short=False):
    cmd = [ctx.env.get_flat('GIT'), 'rev-parse']
    if short:
        cmd.append('--short=8')
    cmd.append('HEAD')
    out = ctx.cmd_and_log(cmd, quiet=Context.BOTH, cwd=path)
    return out.strip()"""

NEW = """def _git_head_hash(ctx, path, short=False):
    cmd = [ctx.env.get_flat('GIT'), 'rev-parse']
    if short:
        cmd.append('--short=8')
    cmd.append('HEAD')
    # GUARDIAN_GIT_HEAD_FALLBACK
    try:
        out = ctx.cmd_and_log(cmd, quiet=Context.BOTH, cwd=path)
        return out.strip()
    except Exception:
        return "deadbeef" if short else "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_ardupilot_waf_git_fallback.py <path/to/git_submodule.py>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"patch: missing file {path}", file=sys.stderr)
        return 1
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        print("patch: already applied")
        return 0
    if OLD not in text:
        print("patch: expected _git_head_hash block not found (ArduPilot version mismatch?)", file=sys.stderr)
        return 1
    path.write_text(text.replace(OLD, NEW, 1), encoding="utf-8")
    print(f"patch: applied Guardian git hash fallback to {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
