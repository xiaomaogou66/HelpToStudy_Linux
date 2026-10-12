#!/usr/bin/env bash
# 刷新法定节假日表（00-配置/节假日.json）
# 用法：./更新节假日.sh            # 今年 + 明年
#       ./更新节假日.sh 2026 2027  # 指定年份
#       ./更新节假日.sh --文件 x.json   # 离线：用本地 json
#       ./更新节假日.sh --dry-run  # 只看不写
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
VAULT="$(cd ../.. && pwd)"
PY="$VAULT/_工具/.venv/bin/python"; [ -x "$PY" ] || PY="python3"
exec "$PY" "$(pwd)/更新节假日.py" "$@"
