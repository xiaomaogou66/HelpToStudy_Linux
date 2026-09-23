#!/usr/bin/env bash
# =============================================================
#  同步周决策 → Google 日历（秒级推送，不是订阅，无延迟）
#  用法：
#      ./同步日历.sh --dry-run      # 只看会推什么，不联网
#      ./同步日历.sh                # 真正同步
#      ./同步日历.sh --check        # 检查授权
#
#  代理：只有本脚本走代理 —— 固定 127.0.0.1:7897（Clash Verge）。
#        所以不用提前 export，双击 .desktop 也能用。
#        · 换端口：SYNC_PROXY=http://127.0.0.1:7890 ./同步日历.sh
#        · 临时直连：SYNC_PROXY=none ./同步日历.sh
#        以上只在「本脚本 + 它启动的 python」里生效：
#        不动系统代理、不动你的 shell、不影响别的脚本。
#  首次使用先看同目录下的「README-首次配置.md」
# =============================================================
set -euo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
VAULT="$(cd ../.. && pwd)"

VENV="$VAULT/_工具/.venv"
if [ -x "$VENV/bin/python" ]; then
    PY="$VENV/bin/python"
else
    PY="python3"
fi

if ! "$PY" -c "import googleapiclient, google_auth_oauthlib" 2>/dev/null; then
    echo "❌ 缺少依赖，先跑："
    echo "   $VENV/bin/python -m pip install -r '$(pwd)/requirements.txt'"
    exit 1
fi

# ---------------- 代理：本脚本固定走本机 7897 ----------------
PROXY="${SYNC_PROXY:-http://127.0.0.1:7897}"
if [ "$PROXY" = "none" ]; then
    PROXY=""
    echo "🌐 代理：直连（SYNC_PROXY=none）"
else
    case "$PROXY" in
        *://*) ;;                       # 已经是 http:// 或 socks5h://
        *)     PROXY="http://$PROXY" ;; # 只写 127.0.0.1:7897 也认
    esac
fi

if [ -n "$PROXY" ]; then
    export http_proxy="$PROXY"  https_proxy="$PROXY"  all_proxy="$PROXY"
    export HTTP_PROXY="$PROXY"  HTTPS_PROXY="$PROXY"  ALL_PROXY="$PROXY"
    export no_proxy="localhost,127.0.0.1,::1"
    export NO_PROXY="$no_proxy"
    echo "🌐 代理：$PROXY（本脚本固定使用）"

    # 走代理时 httplib2 必须有 PySocks，否则请求会静默超时（直连 Google 是不通的）
    if ! "$PY" -c "import socks" 2>/dev/null; then
        echo "⚠️  要走代理，但 venv 里没有 PySocks → 请求会超时。修："
        echo "   $VENV/bin/python -m pip install PySocks"
        exit 1
    fi
fi

exec "$PY" "$(pwd)/sync_gcal.py" "$@"
