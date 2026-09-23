#!/usr/bin/env bash
# =============================================================
#  日程安排层 · 自检（烟测）—— 不联网、不改数据，只验证「还能跑」
#
#    ./自检.sh          # 全部检查（默认跳过推 Google 那一步）
#    ./自检.sh --联网    # 额外检查 Google 凭据（会访问 Google API）
#
#  检查项：配置可读 → 打卡页生成 → 周文件夹 → today.sh → 两个同步后端
#          → ics 结构合规 → 命令/skill 同步 → 拆书令牌
# =============================================================
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT="$(cd "$DIR/../.." && pwd)"
PLAN="$VAULT/05-日程安排/00-配置/规划配置.json"
RULES="$VAULT/05-日程安排/00-配置/底线规则.json"
SYNC="$VAULT/05-日程安排/00-配置/同步配置.json"
WEEK="$(date '+%G-W%V')"

pass=0; fail=0
ok()   { printf '  ✅ %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  ❌ %s\n' "$1"; fail=$((fail+1)); }
step() { printf '\n==> %s\n' "$1"; }

step "1. 配置文件"
for f in "$PLAN" "$RULES" "$SYNC"; do
    if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
        ok "可解析：${f#$VAULT/}"
    else
        bad "JSON 有问题或缺失：${f#$VAULT/}"
    fi
done
python3 - "$PLAN" <<'PY' && ok "里程碑（唯一真源）能读出来" || bad "里程碑读不出来"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("里程碑"), "没有里程碑"
print("     → " + "、".join(f"{m['名称']} {m['日期']}" for m in d["里程碑"][:4]))
PY

step "2. 打卡页（干跑，不落盘）"
out="$("$DIR/打卡.sh" --print "$WEEK" 2>&1)" && [ -n "$out" ] && ok "打卡页可生成（$WEEK）" || bad "打卡页生成失败"
echo "$out" | grep -qE '^- \[[ x]\] [0-9]{2}-[0-9]{2} · ' && ok "打卡条目格式正确" || bad "打卡条目格式异常"
echo "$out" | grep -qi "traceback" && bad "打卡页里有报错" || true

step "3. 周文件夹与日记"
"$DIR/周文件夹.sh" "$WEEK" >/dev/null 2>&1 && ok "周文件夹脚本可运行（$WEEK）" || bad "周文件夹脚本失败"
[ -d "$VAULT/05-日程安排/06-日志/$WEEK" ] && ok "本周文件夹存在：06-日志/$WEEK/" || bad "本周文件夹不存在"
today="$(date +%F)"
[ -f "$VAULT/05-日程安排/06-日志/$WEEK/$today.md" ] && ok "今天的日记在：06-日志/$WEEK/$today.md" || bad "今天的日记不在周文件夹里"

step "4. today.sh（读 00-配置 里的里程碑）"
t="$("$DIR/today.sh" 2>&1)" && ok "today.sh 可运行" || bad "today.sh 失败"
echo "$t" | grep -qE "连续|还没开始" && ok "含打卡连续天数（新库显示「还没开始」属正常）" || bad "缺少连续天数"
echo "$t" | grep -qE '[0-9]+ 天' && ok "含里程碑倒计时" || bad "缺少里程碑倒计时"

step "5. 同步 · ics 后端"
if python3 "$DIR/导出ics.py" --dry-run >/tmp/.selfcheck_ics.log 2>&1; then
    ok "ics 后端干跑成功：$(grep -o '共 [0-9]* 条事件' /tmp/.selfcheck_ics.log | head -1)"
else
    bad "ics 后端干跑失败"; sed -n '1,5p' /tmp/.selfcheck_ics.log
fi
if python3 "$DIR/导出ics.py" >/tmp/.selfcheck_ics2.log 2>&1; then
    ok "ics 后端真跑成功：$(tail -1 /tmp/.selfcheck_ics2.log)"
    python3 - "$VAULT/05-日程安排/_资源/日程安排.ics" <<'PY' && ok "ics 结构合规（平衡/换行/时间格式）" || bad "ics 结构有问题"
import re, sys, pathlib, collections
raw = pathlib.Path(sys.argv[1]).read_bytes().decode("utf-8")
assert raw.count("\n") == raw.count("\r\n"), "存在裸 LF（应全为 CRLF）"
lines = raw.replace("\r\n ", "").replace("\r\n\t", "").split("\r\n")
bal = collections.Counter()
for l in lines:
    m = re.fullmatch(r"BEGIN:(\w+)|END:(\w+)", l)
    if m:
        k = m.group(1) or m.group(2); bal[k] += 1 if m.group(1) else -1
assert set(bal.values()) == {0}, f"BEGIN/END 不平衡：{dict(bal)}"
assert sum(l == "BEGIN:VEVENT" for l in lines) > 0, "没有事件"
bad_dt = [l for l in lines if l.startswith(("DTSTART", "DTEND"))
          and not re.match(r"DT(?:START|END)(;VALUE=DATE)?:\d{8}(T\d{6}Z)?$", l)]
assert not bad_dt, f"时间格式异常：{bad_dt[:2]}"
print(f"     → {sum(l == 'BEGIN:VEVENT' for l in lines)} 条事件 / "
      f"{sum(l == 'BEGIN:VALARM' for l in lines)} 条提醒")
PY
else
    bad "ics 后端真跑失败"; sed -n '1,5p' /tmp/.selfcheck_ics2.log
fi

step "6. 同步 · Google 后端（不联网）"
"$DIR/同步日历.sh" --dry-run >/tmp/.selfcheck_gcal.log 2>&1
grep -q "缺少依赖" /tmp/.selfcheck_gcal.log \
  && printf '  ⏭ gcal 后端跳过（依赖没装；ics 后端不受影响。装法：_工具/.venv/bin/python -m pip install -r _脚本/requirements.txt）\n' \
  || { grep -q "任务" /tmp/.selfcheck_gcal.log \
        && ok "gcal 后端干跑成功：$(grep -oE '任务 [0-9]+ 条.*课表 [0-9]+ 条' /tmp/.selfcheck_gcal.log | head -1)" \
        || { bad "gcal 后端干跑失败"; sed -n '1,5p' /tmp/.selfcheck_gcal.log; }; }
if [ "${1:-}" = "--联网" ]; then
    "$DIR/同步日历.sh" --check >/tmp/.selfcheck_chk.log 2>&1 \
        && ok "Google 凭据/日历可用：$(tail -1 /tmp/.selfcheck_chk.log)" \
        || { bad "Google 凭据不可用"; tail -3 /tmp/.selfcheck_chk.log; }
else
    printf '  ⏭ 跳过 Google 凭据检查（加 --联网 才查）\n'
fi

step "7. 统一入口"
"$DIR/同步日程.sh" --dry-run >/tmp/.selfcheck_all.log 2>&1
grep -qE "✅ 已写出|任务 [0-9]+ 条" /tmp/.selfcheck_all.log \
    && ok "同步日程.sh 双后端干跑成功" || { bad "同步日程.sh 失败"; tail -5 /tmp/.selfcheck_all.log; }
grep -q "① ics 后端" /tmp/.selfcheck_all.log && grep -q "② gcal 后端" /tmp/.selfcheck_all.log \
    && ok "两个后端都跑到了（地位同等）" || bad "后端调度异常"

step "8. 命令与 skill 一致性"
if python3 "$VAULT/_工具/sync_pi_skills.py" >/tmp/.selfcheck_skills.log 2>&1; then
    ok "命令 → skills 同步成功（$(grep -c '^  ' /tmp/.selfcheck_skills.log) 个）"
else
    bad "skills 同步失败"; tail -3 /tmp/.selfcheck_skills.log
fi
for c in 周决策 课表 学案 拆书 速查表 测试我 新主题-拆解与计划 更新进度; do
    [ -f "$VAULT/.claude/commands/$c.md" ] || bad "命令缺失：/$c"
done
ok "8 条命令齐备"

step "9. 拆书令牌（MinerU）"
TF="$VAULT/_工具/mineru_token.txt"
if [ -s "$TF" ]; then
    days=$(( ( $(date +%s) - $(stat -c %Y "$TF") ) / 86400 ))
    code=$(curl -s -m 15 -o /tmp/.mineru_probe -w '%{http_code}' \
             -H "Authorization: Bearer $(cat "$TF")" \
             https://mineru.net/api/v4/extract/task/0 2>/dev/null || echo 000)
    if [ "$code" = 401 ] && grep -q A0211 /tmp/.mineru_probe 2>/dev/null; then
        bad "MinerU 令牌已过期（已签发 $days 天）→ 重跑 _工具/设置MinerU令牌.sh"
    elif [ "$code" = 000 ]; then
        printf '  ⏭ 令牌检查跳过（离线）\n'
    else
        ok "MinerU 令牌可用（已签发 $days 天）"
    fi
else
    printf '  ⏭ 跳过（还没保存 MinerU 令牌：跑 _工具/设置MinerU令牌.sh）\n'
fi

step "10. 拆书脚本"
PY_BIN="$VAULT/_工具/.venv/bin/python"; [ -x "$PY_BIN" ] || PY_BIN="$(command -v python3 || true)"
if [ -n "$PY_BIN" ] && "$PY_BIN" "$VAULT/_工具/split_textbook.py" --help >/dev/null 2>&1; then
    ok "split_textbook.py 可运行（$PY_BIN）"
else
    printf '  ⏭ 跳过（拆书环境还没装：跑 _工具/.venv 或系统 python3 -m pip install -r _工具/requirements.txt）\n'
fi

printf '\n══════════════════════════════════\n'
printf '  通过 %d 项，失败 %d 项\n' "$pass" "$fail"
printf '══════════════════════════════════\n'
[ "$fail" -eq 0 ] && echo "✅ 自检通过" || echo "⚠️  有项目失败，见上面 ❌"
exit "$fail"