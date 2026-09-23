#!/usr/bin/env bash
# 生成本周打卡页（打卡项由当周真实课表决定）
# 用法：./打卡.sh            生成本周 / 补齐缺失项（不动已有勾选）
#       ./打卡.sh 2026-W39   指定周
#       ./打卡.sh --print    只看不上盘
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
VAULT="$(cd ../.. && pwd)"
PY="$VAULT/_工具/.venv/bin/python"; [ -x "$PY" ] || PY="python3"
exec "$PY" "$(pwd)/打卡.py" "$@"
