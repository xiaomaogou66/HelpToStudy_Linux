#!/usr/bin/env bash
# 薄壳：真正的实现在 today.py（Windows 用 today.bat 调同一个文件）
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$DIR/../../_工具/.venv/bin/python"; [ -x "$PY" ] || PY="python3"
exec "$PY" "$DIR/today.py" "$@"
