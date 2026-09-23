#!/usr/bin/env bash
# =============================================================
#  从本地 Obsidian 库「单向」同步框架文件到本仓库（发布用）
#
#  只拷白名单里的工作流文件；个人笔记 / 日记 / 密钥 / 课表 / 词库
#  一律不拷，拷完做「通用化 + 隐私扫描」，扫到个人信息就中止。
#
#  用法：
#     ./scripts/sync-from-vault.sh                 # 库默认在 ~/obsidian_vault
#     VAULT=~/某处/obsidian_vault ./scripts/sync-from-vault.sh
#     ./scripts/sync-from-vault.sh --dry-run       # 只列会拷/会改的文件
# =============================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
VAULT="${VAULT:-$HOME/obsidian_vault}"
DRY=false
[ "${1:-}" = "--dry-run" ] && DRY=true

[ -d "$VAULT" ] || { echo "[错误] 找不到库：$VAULT" >&2; exit 1; }

copied=0; skipped=0
copy() {
    for rel in "$@"; do
        src="$VAULT/$rel"
        if [ ! -e "$src" ]; then printf '  [缺失] %s\n' "$rel"; skipped=$((skipped+1)); continue; fi
        dst="$REPO_ROOT/$rel"
        if $DRY; then printf '  [将拷] %s\n' "$rel"; copied=$((copied+1)); continue; fi
        mkdir -p "$(dirname "$dst")"
        if [ -d "$src" ]; then
            rsync -a --delete \
              --exclude='🔒*' --exclude='*.local.md' --exclude='__pycache__/' --exclude='*.pyc' --exclude='.打卡.log' \
              --exclude='calender-*.json' --exclude='service-account*.json' --exclude='token.json' \
              --exclude='credentials.json' --exclude='*.tmp' \
              "$src/" "$dst/"
        else
            cp -a "$src" "$dst"
        fi
        copied=$((copied+1))
    done
}

echo "==> 1. 拷贝框架文件（白名单）"
copy \
  00-使用指南 01-提示词库 02-模板 \
  "03-学习主题/📌 从这里开始.md" "04-教材分块/📖 教材分块说明.md" \
  AGENTS.md CLAUDE.md \
  copilot/copilot-custom-prompts \
  .claude/commands \
  .pi/skills
copy .obsidian/app.json .obsidian/appearance.json .obsidian/community-plugins.json \
     .obsidian/core-plugins.json .obsidian/graph.json .obsidian/hotkeys.json \
     .obsidian/templates.json .obsidian/daily-notes.json \
     .obsidian/dataview .obsidian/quickadd .obsidian/templater-obsidian \
     .obsidian/themes .obsidian/snippets
for d in "$VAULT"/.obsidian/plugins/*/; do
    name="$(basename "$d")"
    copy ".obsidian/plugins/$name/manifest.json" \
         ".obsidian/plugins/$name/main.js" \
         ".obsidian/plugins/$name/styles.css"
done
copy _工具/split_textbook.py _工具/拆书.sh _工具/设置MinerU令牌.sh \
     _工具/sync_pi_skills.py _工具/requirements.txt _工具/拆书.desktop
copy 05-日程安排/_脚本 05-日程安排/06-日志/说明-怎么打卡.md 05-日程安排/00-配置/多端同步.md
echo "    拷入 $copied 项（缺失 $skipped 项）"

echo "==> 2. 生成通用版配置（个人值一律不出现）"
write_if() {  # write_if <相对路径>  —— 从 stdin 写入
    if $DRY; then echo "  [将生成] $1"; else
        mkdir -p "$(dirname "$REPO_ROOT/$1")"
        cat > "$REPO_ROOT/$1"
        echo "  [已生成] $1"
    fi
}

write_if 05-日程安排/00-配置/规划配置.json <<'JSON'
{
  "_说明": "日程安排层的总配置（人改这个文件）。引擎在 _脚本/，打卡规则在 00-配置/底线规则.json，日历/课表在 00-配置/同步配置.json。",
  "本人称呼": "",

  "终局目标": {
    "描述": "（例）某个学位 / 某类资格 / 某国的长期身份",
    "截止年": 2035,
    "_说明": "只用于主页文案；真正的日期看下面的里程碑。"
  },

  "里程碑": [
    { "名称": "（例）语言考试", "日期": "2027-11-14" },
    { "名称": "（例）升学考试初试", "日期": "2028-12-23" },
    { "名称": "（例）申请截止", "日期": "2029-01-15" }
  ],
  "_里程碑说明": "**唯一真源**：主页倒计时、首页「今天」、today.sh 都读这里，改一处三处同步，不用再改脚本。",

  "检查点来源": ["05-日程安排/04-检查点与待核实.md"],
  "_检查点来源说明": "带 📅 的未完成任务会被当作检查点/待办；也是同步日历扫描的来源之一（另一个是 06-日志/<周号>/<周号>.md）。",

  "同步": {
    "后端": ["ics", "gcal"],
    "_后端说明": "两个后端地位同等，各自独立可用，也可以同时开。ics = 只写本机 .ics 文件（零云依赖，可被 iCal 插件 / 云盘 / 手机订阅）；gcal = 推到 Google 专用日历（多端原生同步）。",
    "ics输出": "05-日程安排/_资源/日程安排.ics",
    "ics日历名": "日程安排",
    "ics刷新间隔": "PT1H",
    "gcal": { "脚本": "_脚本/同步日历.sh" },
    "_gcal说明": "Google 后端的日历 ID / 凭据 / 课表源都在 00-配置/同步配置.json；配置步骤见 00-配置/多端同步.md"
  },

  "课表": {
    "来源": "05-日程安排/_资源/日历/课表-当前.ics",
    "跳过前缀": ["📚"],
    "_说明": "课表源固定这个名字（换表靠替换文件，不靠改配置）；跳过前缀 = 不当作课/不打卡的条目。"
  },

  "打卡": { "规则文件": "00-配置/底线规则.json" }
}
JSON

write_if 05-日程安排/00-配置/底线规则.json <<'JSON'
{
  "_说明": "打卡项由当周真实课表自动生成。**改这个文件就能改规则，不用动代码**。",
  "_理念": "零意志力底线：把新习惯寄存在『你本来就要去做的事』上（必修课、通勤、饭点）。难的不是坚持，是不用额外做决定。",

  "每节课": {
    "启用": true,
    "模板": "上课 · {课程名} {开始}–{结束}",
    "_说明": "每节课单独一项（出勤打卡）。{课程名}/{开始}/{结束} 替换成课表里的真实值；不想每节课都成项就把 启用 改成 false。"
  },

  "触发": [
    { "当": { "课程匹配": "（例）需要课上背单词的那门课" }, "项目": ["课上 Anki 20 分钟"] },
    { "当": { "课程匹配": "（例）适合当背景音的那门课" },   "项目": ["课上泛听"] },
    { "当": { "星期": 6 },                                  "项目": ["通勤泛听 2 小时"] }
  ],
  "_触发说明": "统一规则表：条件 → 打卡项。条件支持『课程匹配』（正则，命中当天某节课才生成，可配 {课程名}/{开始}/{结束} 占位）与『星期』（1=周一 … 7=周日）。想加一条：照抄一行改掉就行，不用碰代码。",

  "每天都有": ["今天没崩（崩了也不补课）"],
  "_每天都有说明": "不管课表怎样都出现的项；即使整天崩了，勾掉它连续记录就不断。",

  "例外": {
    "停课": {
      "_说明": "临时停课（学校临时通知）。格式：日期 → [『课程名 开始–结束』]。那天那节课从出勤里去掉，改留一条已勾的『停课 · …』记录（不计缺勤）。同时在课表 ics 里给那节课加 EXDATE，Google 日历里的课也会取消。",
      "2026-09-16": ["（例）某门课 14:00–16:45"]
    }
  },

  "打卡页说明": "每节课一项（出勤）；底线项按 `00-配置/底线规则.json` 的规则自动挂到对应课程 / 星期上。"
}
JSON

write_if 05-日程安排/00-配置/同步配置.json <<'JSON'
{
  "calendar": "日程安排 (Obsidian)",
  "calendar_id": "",
  "_calendar_id说明": "Google 后端必填：Google 日历 → 该日历 → 设置 → 日历 ID。建好专用日历后把它共享给服务账号（权限：更改事件）。",
  "credentials_file": "",
  "_credentials_file说明": "服务账号密钥路径。建议放库外，如 /home/你/.config/schedule-sync/service-account.json（留空则自动找 _脚本/service-account.json）。",
  "timezone": "Asia/Shanghai",
  "scope": "app",
  "reminder_minutes": 10,
  "completed": "prefix",
  "window_past_days": 14,
  "window_future_days": 180,
  "task_globs": ["05-日程安排/06-日志/*/????-W??.md", "05-日程安排/04-检查点与待核实.md"],
  "_task_globs说明": "周决策笔记 = 06-日志/<周号>/<周号>.md（一周一个文件夹）；只扫那里的任务，扫不到打卡页和日记",
  "ics_files": ["05-日程安排/_资源/日历/课表-当前.ics"],
  "ics_color_id": "7",
  "ics_reminder_minutes": 20,
  "ics_skip_summary_prefixes": ["📚"]
}
JSON

write_if 05-日程安排/_脚本/周表.tsv <<'TSV'
周一	09:00–12:00 主线科目（课内）	—	19:00–22:00 主线作业 + 复习	23:30
周二	写你固定的时间块（课表里已有的课不用写）	—	晚上块	23:30
周三	…	—	…	23:30
周四	…	…	…	24:00
周五	…	…	…	23:30
周六	…	兼职/通勤（可挂泛听）	…	23:00
周日	12:05 周决策 20min（起床第一件事）	13:30–15:30 复盘与补漏	20:00–22:30 ★留白（不许占）	23:30
TSV

write_if 05-日程安排/_资源/日历/课表示例.ics <<'ICS'
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//AI 学习工作流//课表示例//CN
CALSCALE:GREGORIAN
X-WR-CALNAME:课表示例（请换成你自己的课表）
X-WR-TIMEZONE:Asia/Shanghai
BEGIN:VEVENT
UID:sample-monday@schedule
DTSTAMP:20260101T000000Z
DTSTART;TZID=Asia/Shanghai:20260105T100000
DTEND;TZID=Asia/Shanghai:20260105T114000
RRULE:FREQ=WEEKLY
SUMMARY:（示例）主线科目
LOCATION:教学楼 A101
DESCRIPTION:第1-2节
END:VEVENT
BEGIN:VEVENT
UID:sample-wednesday@schedule
DTSTAMP:20260101T000000Z
DTSTART;TZID=Asia/Shanghai:20260107T140000
DTEND;TZID=Asia/Shanghai:20260107T154000
RRULE:FREQ=WEEKLY
SUMMARY:（示例）通识课
LOCATION:教学楼 B203
DESCRIPTION:第5-6节
END:VEVENT
END:VCALENDAR
ICS

echo "==> 3. 通用化（只改「来自库」的路径，绝不碰本脚本/README/CI）"
if ! $DRY; then
    python3 - "$REPO_ROOT" <<'PY'
import os, sys, pathlib
root = pathlib.Path(sys.argv[1])
# 只通用化这些目录（= 从库里拷过来的部分）；scripts/ .github/ README 等仓库自有文件不碰
FROM_VAULT = ("00-", "01-", "02-", "03-", "04-", "05-", "AGENTS.md", "CLAUDE.md",
              "copilot", ".claude", ".pi", ".obsidian", "_工具")
# 替换清单从本地文件读（仓库里绝不放个人词）：
#   scripts/scrub-map.local.txt   每行 `原词<TAB>替换成`（.gitignore 已排除，只留本地）
#   scripts/scrub-map.example.txt 通用示例（进仓库，供他人参考）
MAP_FILES = [root / "scripts/scrub-map.local.txt", root / "scripts/scrub-map.example.txt"]
PAIRS = []
for mf in MAP_FILES:
    if not mf.exists():
        continue
    for line in mf.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2 or len(parts[0].strip()) < 2 or parts[0].startswith("<"):
            continue
        PAIRS.append((parts[0], parts[1]))
print(f"    替换表：{len(PAIRS)} 条（来自 {[m.name for m in MAP_FILES if m.exists()]}）")
EXT = {".md", ".py", ".sh", ".json", ".tsv", ".desktop"}
touched = hits = 0
for dp, dn, fns in os.walk(root):
    dn[:] = [d for d in dn if d not in {".git", "__pycache__", "dist"}]
    rel_dir = os.path.relpath(dp, root)
    for fn in fns:
        # 仓库根目录只放行 AGENTS.md / CLAUDE.md，其余根文件（README/CHANGELOG/安装.sh 等）是仓库自有，绝不碰
        if rel_dir == ".":
            if fn not in {"AGENTS.md", "CLAUDE.md"}:
                continue
        elif not rel_dir.startswith(FROM_VAULT):
            continue
        f = pathlib.Path(dp) / fn
        if f.suffix not in EXT:
            continue
        try:
            t = f.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        o = t
        for a, b in PAIRS:
            t = t.replace(a, b)
        if t != o:
            f.write_text(t, encoding="utf-8")
            touched += 1
            hits += sum(o.count(a) for a, _ in PAIRS)
print(f"    通用化：{touched} 个文件 / {hits} 处")
PY
else
    echo "  [将通用化] 来自库的路径里的个人词 → 占位说法"
fi

echo "==> 4. 隐私扫描（扫到就中止）"
# 扫描词 = 本地替换表里的原词（+ 固定兜底：密钥文件名类）
FORBIDDEN="$(cut -f1 scripts/scrub-map.local.txt 2>/dev/null | grep -v '^#' | grep -v '^<\|^$' | paste -sd'|' -)"
[ -n "$FORBIDDEN" ] || echo "  ⚠️ 没有本地替换表 scripts/scrub-map.local.txt，本次只做文件级检查"
if grep -rInE "$FORBIDDEN" "$REPO_ROOT" \
     --include='*.md' --include='*.py' --include='*.sh' --include='*.json' \
     --include='*.tsv' --include='*.desktop' \
     --exclude-dir=.git --exclude-dir=dist --exclude-dir=scripts --exclude='main.js' 2>/dev/null; then
    echo "  ❌ 上面这些行疑似个人信息，先处理掉再提交" >&2
    exit 1
fi
echo "  ✅ 没扫到个人信息"
echo "==> 5. 不该出现的文件（密钥/日记/个人主题/本地专属说明）"
if find "$REPO_ROOT" -path '*/.git' -prune -o -type f \( -name '🔒*' -o -name '*隐私*' -o -name '*.local.md' \) -print | grep . ; then
    echo "  ❌ 本地专属说明不该进仓库" >&2
    exit 1
fi
if find "$REPO_ROOT" -path '*/.git' -prune -o -type f \
     \( -name 'calender-*.json' -o -name 'service-account*.json' -o -name 'token.json' \
        -o -name 'mineru_token.txt' -o -name '*.ics' -o -name '*.ical' -o -name '*.tsv' \) -print \
   | grep -vE "周表.tsv|_资源/日历/课表示例.ics" ; then
    echo "  ❌ 上面这些文件不应进仓库" >&2
    exit 1
fi
if find "$REPO_ROOT/05-日程安排" -maxdepth 2 -name '20??-W*' -o -maxdepth 2 -name '说明*' >/dev/null 2>&1; then :; fi
[ -d "$REPO_ROOT/05-日程安排/06-日志" ] && \
  find "$REPO_ROOT/05-日程安排/06-日志" -mindepth 1 -maxdepth 1 -type d | grep . && \
  { echo "  ❌ 周文件夹不该进仓库（只留说明-怎么打卡.md）" >&2; exit 1; }
echo "  ✅ 密钥/课表/日记/个人主题都没进仓库"

echo "==> 6. 结果"
n=$(find "$REPO_ROOT" -type f -not -path "*/.git/*" -not -path "*/dist/*" | wc -l)
echo "    仓库文件数：$n ｜ 待提交变更：$(cd "$REPO_ROOT" && git status --porcelain | wc -l) 项"
$DRY || (cd "$REPO_ROOT" && git status --short | head -25)
echo "下一步：cd $REPO_ROOT && git add -A && git commit -m '...' && git push"