#!/usr/bin/env bash
# 建本周的日志文件夹（06-日志/<周号>/）并预建 7 篇日记
# 用法：./周文件夹.sh          本周
#       ./周文件夹.sh 2026-W39  指定周
#       ./周文件夹.sh --print   只看不写
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
VAULT="$(cd ../.. && pwd)"
PY="$VAULT/_工具/.venv/bin/python"; [ -x "$PY" ] || PY="python3"
exec "$PY" "$(pwd)/周文件夹.py" "$@"
