#!/usr/bin/env bash
# 「今天」的条目清单 + 勾选写回（桌面小组件与命令行共用同一个实现）
# 用法：./勾选.sh list [--json] [--date YYYY-MM-DD]
#       ./勾选.sh check|uncheck|toggle <文件> <行号> <uid> [--dry-run] [--json]
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PY="$DIR/../../_工具/.venv/bin/python"; [ -x "$PY" ] || PY="python3"
exec "$PY" "$DIR/勾选.py" "$@"
