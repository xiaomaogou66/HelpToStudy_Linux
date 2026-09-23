#!/usr/bin/env bash
# =============================================================
#  日程同步 · 统一入口（两个地位同等的后端）
#
#    ics   本机 .ics 文件   → 零云依赖，可被 iCal 插件 / 云盘 / 手机订阅
#    gcal  Google 专用日历  → 服务账号 / OAuth，多端原生同步
#
#  用法：
#     ./同步日程.sh                    # 按 00-配置/规划配置.json 的「同步.后端」跑（默认两个都跑）
#     ./同步日程.sh --后端 ics          # 只出 .ics
#     ./同步日程.sh --后端 gcal         # 只推 Google
#     ./同步日程.sh --dry-run          # 只看会同步什么，不写文件、不联网
#
#  其它参数原样透传给对应后端（如 --past-days / --future-days / --ics / --check）。
# =============================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT="$(cd "$DIR/../.." && pwd)"
PLAN="$VAULT/05-日程安排/00-配置/规划配置.json"

BACKENDS=""
PASSTHRU=()
while [ $# -gt 0 ]; do
    case "$1" in
        --后端|--backend)
            BACKENDS="${2:-}"; shift 2 ;;
        --后端=*|--backend=*)
            BACKENDS="${1#*=}"; shift ;;
        *)
            PASSTHRU+=("$1"); shift ;;
    esac
done

# 没指定就用配置里的「同步.后端」；读不到就两个都跑（都失败才算失败）
if [ -z "$BACKENDS" ]; then
    BACKENDS="$(python3 - "$PLAN" <<'PY' 2>/dev/null || true
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
if p.exists():
    b = (json.loads(p.read_text(encoding="utf-8")).get("同步") or {}).get("后端") or []
    print(",".join(b) if isinstance(b, list) else str(b))
PY
)"
fi
[ -z "$BACKENDS" ] && BACKENDS="ics,gcal"

# 中文别名 → 内部名
norm() { case "$1" in 本地|本机|本地ics|"") echo ics ;; 谷歌|google|Google|gcal) echo gcal ;; *) echo "$1" ;; esac; }

RUNNERS=()
for b in ${BACKENDS//,/ }; do
    RUNNERS+=("$(norm "$b")")
done

failed=0
for b in "${RUNNERS[@]}"; do
    case "$b" in
        ics)
            echo "══════════ ① ics 后端：写本机 .ics ══════════"
            python3 "$DIR/导出ics.py" "${PASSTHRU[@]+"${PASSTHRU[@]}"}" || failed=1
            ;;
        gcal)
            echo "══════════ ② gcal 后端：推 Google 日历 ══════════"
            bash   "$DIR/同步日历.sh" "${PASSTHRU[@]+"${PASSTHRU[@]}"}" || failed=1
            ;;
        *)
            echo "[错误] 不认识的后端：$b（可用：ics / gcal）" >&2; failed=1 ;;
    esac
    echo
done

if [ "$failed" = 0 ]; then
    echo "✅ 两个后端都跑完了（后端：${BACKENDS}）"
else
    echo "⚠️  有后端失败（后端：${BACKENDS}）——上面每个后端各自有报错信息" >&2
fi
exit "$failed"