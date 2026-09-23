#!/usr/bin/env bash
# 用法： ./today.sh        看今天    ./today.sh done   打卡    ./today.sh 周三   查某天
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA="$DIR/周表.tsv"; LOG="$DIR/.打卡.log"
PLAN="$DIR/../00-配置/规划配置.json"        # 里程碑唯一真源（改 JSON 即可，不用改本脚本）
RULES="$DIR/../00-配置/底线规则.json"        # 底线项文案也从规则生成
names=(周一 周二 周三 周四 周五 周六 周日)
if [[ "${1:-}" == "done" ]]; then
  d=$(date +%F); touch "$LOG"
  if grep -qx "$d" "$LOG"; then echo "今天已打卡（$d）"; else echo "$d" >> "$LOG"; echo "✅ 打卡 $d"; fi
  shift || true
fi
day="${1:-${names[$(( $(date +%u) - 1 ))]}}"
line=$(grep -P "^${day}\t" "$DATA" || true)
[[ -z "$line" ]] && { echo "找不到 $day"; exit 1; }
IFS=$'\t' read -r _ am pm ev night <<< "$line"
echo "════════════════════════════════════════════"
printf "  %s   →   %s\n" "$(date '+%Y-%m-%d %A')" "$day"
echo "════════════════════════════════════════════"
echo
printf "【上午】     %s\n" "$am"
[[ "$pm" != "—" ]] && printf "【下午】     %s\n" "$pm"
printf "【晚上】     %s\n" "$ev"
printf "【放下手机】 %s\n" "$night"
echo
if [[ -f "$LOG" ]]; then
  n=0; d=$(date +%F)
  while grep -qx "$d" "$LOG"; do n=$((n+1)); d=$(date -d "$d -1 day" +%F); done
  printf "🔥 连续 %d 天　累计 %d 天\n" "$n" "$(sort -u "$LOG" | wc -l)"
  [[ $n -eq 0 ]] && echo "   （今天还没打卡——底线项见 00-配置/底线规则.json，勾完就算数）"
else echo "🔥 还没开始。今天把底线项做完，就跑 ./today.sh done"; fi
echo
now=$(date +%s)
python3 - "$PLAN" <<'PY' 2>/dev/null || true
import json, sys, pathlib, datetime
p = pathlib.Path(sys.argv[1])
cfg = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
today = datetime.date.today()
for m in cfg.get("里程碑") or []:
    try:
        d = datetime.date.fromisoformat(m["日期"])
    except Exception:
        continue
    print("  %-16s %5d 天" % (m["名称"], (d - today).days))
PY
echo
python3 - "$RULES" <<'PY' 2>/dev/null || true
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
rules = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
if rules.get("打卡页说明"):
    print(rules["打卡页说明"])
    raise SystemExit
items, seen = [], set()
for rule in (rules.get("触发") or []) + (rules.get("课程底线") or []):
    for it in rule.get("项目") or []:
        if it not in seen:
            seen.add(it); items.append(it)
for rule in rules.get("每周固定") or []:
    it = rule.get("项目")
    if it and it not in seen:
        seen.add(it); items.append(it)
if items:
    print("零意志力底线：" + " ｜ ".join(items))
PY
