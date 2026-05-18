#!/usr/bin/env bash
# Fetch upstream doc repos, build JSONL chunk index + manifest.
#
# Usage:
#   ./scripts/stack_wiki/refresh_stack_wiki.sh
#
# Requires: git, python3, pip install -r scripts/stack_wiki/requirements.txt

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

./scripts/stack_wiki/fetch_upstream.sh

if ! python3 -c "import docutils" 2>/dev/null; then
  echo "Installing stack_wiki Python deps …"
  pip3 install -q -r scripts/stack_wiki/requirements.txt
fi

python3 scripts/stack_wiki/build_index.py
echo "Stack wiki refresh complete. Search: rg pattern Resources/StackWiki/index/"
