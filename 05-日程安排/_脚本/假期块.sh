#!/usr/bin/env bash
# 生成假期学习块（每天 4–6h，法定节假日专用；贴进周决策）
# 用法：./假期块.sh 2026-W40   ｜ ./假期块.sh（本周）
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
VAULT="$(cd ../.. && pwd)"
PY="$VAULT/_工具/.venv/bin/python"; [ -x "$PY" ] || PY="python3"
exec "$PY" "$(pwd)/假期块.py" "$@"
