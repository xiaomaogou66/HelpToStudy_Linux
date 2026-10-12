#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""「今天」的条目清单 + 桌面小组件的勾选写回。

为什么要有它：
  首页「📅 今天」是 Dataview 渲染的，桌面小组件跑不了 Dataview；而且勾选要**写回原文件**。
  解析 markdown 的知识（📅 日期、时间段、周号规则）已经全在 Python 这边了，所以不重复实现：
  小组件（Noctalia Luau）只负责显示 + 把点击转成一次命令行调用，读写都走这一个脚本。

用法：
    ./勾选.sh list                     # 列今天可勾的条目（人看）
    ./勾选.sh list --json              # 列今天可勾的条目（小组件用，stdout 一行 JSON）
    ./勾选.sh list --date 2026-10-08   # 指定日期
    ./勾选.sh check   <文件> <行号> <哈希>   # 勾上
    ./勾选.sh uncheck <文件> <行号> <哈希>   # 取消
    ./勾选.sh toggle  <文件> <行号> <哈希>   # 翻转
    ./勾选.sh check ... --dry-run      # 只看会改成什么，不落盘
    ./勾选.sh check ... --json         # 机器可读结果（小组件用）

数据来源（与首页「📅 今天」两块完全一致）：
  ① 06-日志/<周号>/打卡.md     形如 `- [ ] 10-08 · 上课 · 专业课A 18:30–22:00`
  ② 06-日志/<周号>/<周号>.md   形如 `- [ ] 外语精读 4h ★黄金日 📅 2026-10-08 13:30 - 17:30`
     —— ② 复用 `sync_gcal.parse_tasks`，所以小组件上看到的任务**就是**进日历的那批，不会两套口径。

身份怎么标（uid）：
  `sha1("<库内相对路径>::<整行原文>")[:16]` —— 和 `sync_gcal` 给日历事件算 uid 的算法**同一个**。
  因为哈希里含 `[ ]` / `[x]`，所以「你屏幕上看到的那一行」和「要写的那一行」必然同状态：
  别人先勾过了 / 文件被重新生成过 → 哈希对不上 → 拒绝写，绝不猜。

写回规则（三条硬要求）：
  1. 只翻转那一行方括号里的 1 个字符，其余字节（📅 时间、全角空格、行尾 CRLF、缩进）原样保留；
  2. flock 排它锁 + 同目录临时文件 + `os.replace` 原子替换（和 `导出ics.py` 同款）；
  3. 写前核对「行号 + 行哈希」，对不上就退出码 2 拒绝；行号漂移但内容哈希全库唯一时按内容命中。

退出码：0 成功 · 2 拒绝（对不上 / 不是任务行） · 3 用法错误
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import time
from contextlib import contextmanager
from datetime import date, datetime, timedelta
from pathlib import Path


def _force_utf8_io() -> None:
    """Windows 上输出被管道捕获时默认不是 UTF-8，中文会触发 UnicodeEncodeError。

    交互式双击 .bat 有 `chcp 65001` 兜着，但 CI / 重定向 / 被别的脚本调用时必须自己设。
    """
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:                              # noqa: BLE001
            pass


_force_utf8_io()

SCRIPT_DIR = Path(__file__).resolve().parent
VAULT = SCRIPT_DIR.parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

LOG_DIR = VAULT / "05-日程安排/06-日志"
LOCK_FILE = SCRIPT_DIR / ".勾选.lock"

import sync_gcal as S  # noqa: E402  复用任务解析（📅 / 时间段 / uid）

# `- [ ] 10-08 · 内容`（打卡页）——与 打卡.py 的 parse_existing 同口径，只是多认了 `*` 号
CHECKIN_RE = re.compile(
    r"^\s*[-*]\s*\[(?P<mark>[ xX])\]\s*(?P<date>\d{2}-\d{2})\s*·\s*(?P<body>.+?)\s*$"
)
# 翻转用：head(`- [`) + mark(1 字符) + rest(`] 后面的全部`)
MARKER_RE = re.compile(r"^(?P<head>\s*[-*]\s*\[)(?P<mark>[ xX])(?P<rest>\].*)$")
DONE_MARKS = "xX"


# ─────────────────────────── 行 / 锁 / 原子写 ───────────────────────────


def iter_lines(path: Path) -> list[tuple[str, str]]:
    """[(正文, 行尾)] —— 行尾单独拿出来，保证回写时 CRLF/LF 一个字节都不变。"""
    text = path.read_bytes().decode("utf-8")
    out: list[tuple[str, str]] = []
    for raw in text.splitlines(keepends=True):
        for eol in ("\r\n", "\n", "\r"):
            if raw.endswith(eol):
                out.append((raw[: -len(eol)], eol))
                break
        else:
            out.append((raw, ""))
    return out


def line_uid(rel: str, body: str) -> str:
    """与 sync_gcal 完全同一个算法：文件相对路径 + 整行原文。"""
    return hashlib.sha1(f"{rel}::{body}".encode("utf-8")).hexdigest()[:16]


@contextmanager
def _exclusive_lock(timeout: float = 5.0):
    """跨进程排它锁：防「小组件连点两下」和「周决策那天两个脚本同时写」。

    Windows 上没有 fcntl，退回 msvcrt；再不行就退化成无锁（小组件只在 Linux 跑）。
    """
    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    fh = open(LOCK_FILE, "a+b")
    locked = False
    try:
        try:
            import fcntl
        except ImportError:                            # Windows
            fcntl = None                               # type: ignore[assignment]
        if fcntl is not None:
            deadline = time.monotonic() + timeout
            while True:
                try:
                    fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                    locked = True
                    break
                except OSError:
                    if time.monotonic() >= deadline:
                        raise RuntimeError("等锁超时：有别的东西正在写这个文件")
                    time.sleep(0.05)
        yield
    finally:
        if locked:
            try:
                fcntl.flock(fh.fileno(), fcntl.LOCK_UN)     # type: ignore[possibly-undefined]
            except Exception:                               # noqa: BLE001
                pass
        fh.close()


def _atomic_write(path: Path, text: str) -> None:
    """同目录临时文件 + 原子替换：订阅方（Obsidian / ics 导出）不会读到半截文件。"""
    tmp = path.with_name(path.name + ".tmp")
    try:
        mode = path.stat().st_mode
        tmp.write_bytes(text.encode("utf-8"))
        os.chmod(tmp, mode)
        tmp.replace(path)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


# ─────────────────────────── 解析「今天」 ───────────────────────────


def week_of(d: date) -> str:
    iso = d.isocalendar()
    return f"{iso[0]}-W{iso[1]:02d}"


def week_dates(week: str) -> tuple[date, date]:
    m = re.fullmatch(r"(\d{4})-W(\d{1,2})", week.strip())
    if not m:
        sys.exit(f"❌ 周号格式应为 2026-W41，收到：{week}")
    mon = date.fromisocalendar(int(m.group(1)), int(m.group(2)), 1)
    return mon, mon + timedelta(days=6)


def _split_time(text: str) -> tuple[str, str | None, str | None, str | None]:
    """打卡项正文里若末尾带着时间段，就把它摘出来单独显示（避免右列重复）

    「上课 · 专业课A 18:30–22:00」→ 正文「上课 · 专业课A」+ time「18:30–22:00」
    「课上泛听　（专业课A 18:30）」→ 原样不动（不是区间）

    返回 (正文, 给人看的区间, 机器用开始, 机器用结束)。后两个给顶栏算「现在该做什么」。
    """
    m = re.search(r"(?P<h1>\d{1,2}:\d{2})\s*[-–—~至]\s*(?P<h2>\d{1,2}:\d{2})", text)
    if not m:
        return text, None, None, None
    rng = f"{m.group('h1')}–{m.group('h2')}"
    h1, h2 = m.group("h1"), m.group("h2")
    if text[m.end():].strip() == "":                    # 只截末尾的，中间提到的时间不动
        return text[: m.start()].rstrip(" 　·、-—"), rng, h1, h2
    return text, rng, h1, h2


def load_checkin(day: date, week: str) -> tuple[str, list[dict]]:
    """打卡页里属于这一天的条目（保持文件原顺序）。"""
    path = LOG_DIR / week / "打卡.md"
    rel = str(path.relative_to(VAULT))
    if not path.exists():
        return rel, []
    want = day.strftime("%m-%d")
    items: list[dict] = []
    for lineno, (body, _eol) in enumerate(iter_lines(path), 1):
        m = CHECKIN_RE.match(body)
        if not m or m.group("date") != want:
            continue
        text, rng, t1, t2 = _split_time(m.group("body").strip())
        items.append(
            {
                "uid": line_uid(rel, body),
                "file": rel,
                "line": lineno,
                "text": text,
                "done": m.group("mark") in DONE_MARKS,
                "time": rng,
                "start": t1,
                "end": t2,
                "source": "checkin",
            }
        )
    return rel, items


def load_study(day: date, week: str) -> tuple[str, list[dict]]:
    """周决策里排在这一天的学习块（复用日历那套解析，口径完全一致）。"""
    path = LOG_DIR / week / f"{week}.md"
    rel = str(path.relative_to(VAULT))
    if not path.exists():
        return rel, []
    cfg = S.load_config()
    tz = S.get_tz(cfg["timezone"])
    tasks = S.parse_tasks(VAULT, [f"05-日程安排/06-日志/{week}/{week}.md"], tz)
    items: list[dict] = []
    for t in tasks:
        if t["start"].date() != day:
            continue
        items.append(
            {
                "uid": t["uid"],
                "file": t["file"],
                "line": t["line"],
                "text": t["title"],
                "done": t["done"],
                "time": t["t_start"].strftime("%H:%M") if t["t_start"] else None,
                "start": t["t_start"].strftime("%H:%M") if t["t_start"] else None,
                "end": t["t_end"].strftime("%H:%M") if t["t_end"] else None,
                "source": "study",
            }
        )
    return rel, items


def _minutes(hm: str | None) -> int | None:
    """'18:30' → 1110。不是 HH:MM 就返回 None。"""
    if not hm or not re.fullmatch(r"\d{1,2}:\d{2}", hm):
        return None
    h, m = hm.split(":")
    return int(h) * 60 + int(m)


def _covers_now(item: dict, now_hm: str) -> bool:
    """这条的时间段是否包含「现在」。只给了开始时间（无结束）就按往后 60 分钟算。"""
    start, end = _minutes(item.get("start")), _minutes(item.get("end"))
    now = _minutes(now_hm)
    if start is None or now is None:
        return False
    if end is None:
        end = min(24 * 60, start + 60)
    if end <= start:                     # 跨午夜（22:00-01:00）
        end += 24 * 60
        if now < start:
            now += 24 * 60
    return start <= now <= end


def cmd_list(day: date, as_json: bool) -> int:
    week = week_of(day)
    checkin_rel, checkin = load_checkin(day, week)
    study_rel, study = load_study(day, week)
    done = sum(1 for i in checkin + study if i["done"])
    total = len(checkin) + len(study)

    if as_json:
        print(
            json.dumps(
                {
                    "ok": True,
                    "date": day.isoformat(),
                    "weekday": "周" + "一二三四五六日"[day.weekday()],
                    "week": week,
                    "checkin": {"file": checkin_rel, "items": checkin},
                    "study": {"file": study_rel, "items": study},
                    "counts": {
                        "checkin": [sum(1 for i in checkin if i["done"]), len(checkin)],
                        "study": [sum(1 for i in study if i["done"]), len(study)],
                        "done": done,
                        "total": total,
                    },
                },
                ensure_ascii=False,
            )
        )
        return 0

    mon, sun = week_dates(week)
    wd = "一二三四五六日"[day.weekday()]
    print(f"📅 {day:%Y-%m-%d}（周{wd}）· {week}（{mon:%m-%d} ~ {sun:%m-%d}）")
    boxes = [
        ("✅ 打卡", "checkin", checkin, checkin_rel),
        ("📚 学习块", "study", study, study_rel),
    ]
    for title, _key, items, rel in boxes:
        done_n = sum(1 for i in items if i["done"])
        print(f"\n{title}（{done_n}/{len(items)}）")
        if not items and not (VAULT / rel).exists():
            print("   ⚪ （文件还没生成）")
            continue
        if not items:
            print("   （今天没有条目）")
            continue
        now_hm = datetime.now().strftime("%H:%M")
        for i in items:
            mark = "x" if i["done"] else " "
            when = f"{i['time']}  " if i["time"] else ""
            live = "▶ " if _covers_now(i, now_hm) else "  "
            print(f" {live}[{mark}] {when}{i['text']}")
    print(f"\n🔥 合计 {done}/{total} 项")
    print("   勾选用： ./勾选.sh check <文件> <行号> <uid>   （uid 见 --json 输出）")
    return 0


# ─────────────────────────── 写回 ───────────────────────────


class Refused(Exception):
    """拒绝写：目标行对不上（被别人改过 / 被重新生成 / 不是任务行）。"""


def _locate(lines: list[tuple[str, str]], rel: str, line_no: int, uid: str) -> tuple[int, str]:
    """先按行号+哈希，再退到「内容哈希在文件里唯一」。"""
    idx = line_no - 1
    if 0 <= idx < len(lines) and line_uid(rel, lines[idx][0]) == uid:
        return idx, "行号 + 哈希都对上"
    hits = [i for i, (body, _e) in enumerate(lines) if line_uid(rel, body) == uid]
    if len(hits) == 1:
        return hits[0], f"行号漂移到第 {hits[0] + 1} 行（按内容哈希命中）"
    if not hits:
        raise Refused(
            "找不到这一行：原文已经变了（可能被重新生成过，或已经有人先勾了）"
        )
    raise Refused(f"这段原文在文件里出现 {len(hits)} 次，不知道勾哪一个 —— 请到 Obsidian 里勾")


def cmd_mark(action: str, rel: str, line_no: int, uid: str, dry_run: bool, as_json: bool) -> int:
    path = (VAULT / rel).resolve()
    if not str(path).startswith(str(VAULT)):
        raise Refused(f"文件必须在库内：{rel}")
    if not path.exists():
        raise Refused(f"文件不存在：{rel}")

    want = {"check": "x", "uncheck": " ", "toggle": None}[action]

    def _plan(lines: list[tuple[str, str]]) -> tuple[int, str, str, str, str]:
        """→ (行索引, 旧标记, 新整行原文, 新标记, 为什么能确定是这一行)"""
        idx, why = _locate(lines, rel, line_no, uid)
        body, _eol = lines[idx]
        m = MARKER_RE.match(body)
        if not m:
            raise Refused(f"第 {idx + 1} 行不是 `- [ ]` 任务行：{body.strip()[:40]}")
        cur = m.group("mark")
        new = want if want is not None else (" " if cur in DONE_MARKS else "x")
        return idx, cur, f"{m.group('head')}{new}{m.group('rest')}", new, why

    with _exclusive_lock():
        lines = iter_lines(path)
        idx, old_mark, new_body, new_mark, why = _plan(lines)
        unchanged = new_mark == old_mark
        if dry_run:
            result = {"ok": True, "dry_run": True, "file": rel, "line": idx + 1,
                      "from": old_mark, "to": new_mark, "unchanged": unchanged, "note": why}
        else:
            if not unchanged:
                lines[idx] = (new_body, lines[idx][1])
                _atomic_write(path, "".join(b + e for b, e in lines))
                # 写完立刻复核：确认磁盘上真的是我们想要的那一行
                after = iter_lines(path)
                if len(after) != len(lines) or after[idx][0] != new_body:
                    raise Refused("写回后复核失败：磁盘内容不是预期的样子（已中止，未再改动）")
            shown = CHECKIN_RE.match(new_body) or S.TASK_RE.match(new_body)
            result = {
                "ok": True,
                "dry_run": False,
                "file": rel,
                "line": idx + 1,
                "from": old_mark,
                "to": new_mark,
                "unchanged": unchanged,
                "uid": line_uid(rel, new_body),
                "text": shown.group("body").strip() if shown else new_body.strip(),
                "note": why,
            }

    if as_json:
        print(json.dumps(result, ensure_ascii=False))
        return 0

    label = result.get("text") or new_body.strip()
    if unchanged:
        print(f"🤷 没有变化（已经是 - [{new_mark}]）：{rel} 第 {idx + 1} 行")
        print(f"   {label}")
        return 0
    verb = {"check": "已勾选", "uncheck": "已取消", "toggle": "已翻转"}[action]
    if dry_run:
        print(f"🔎 --dry-run（没有写文件）｜{result['note']}")
        print(f"   {rel} 第 {idx + 1} 行")
        print(f"   - [{old_mark}] → - [{new_mark}]  {label}")
        return 0
    print(f"✅ {verb}：{rel} 第 {idx + 1} 行")
    print(f"   - [{old_mark}]  →  - [{new_mark}]")
    print(f"   {label}")
    if "漂移" in result["note"]:
        print(f"   ⚠️ {result['note']}")
    return 0


# ─────────────────────────── 入口 ───────────────────────────

USAGE = """用法：
    ./勾选.sh list [--json] [--date YYYY-MM-DD]     # 列「今天」可勾的条目
    ./勾选.sh check   <文件> <行号> <uid> [--dry-run] [--json]
    ./勾选.sh uncheck <文件> <行号> <uid> [--dry-run] [--json]
    ./勾选.sh toggle  <文件> <行号> <uid> [--dry-run] [--json]

示例：
    ./勾选.sh list
    ./勾选.sh list --json | python3 -m json.tool
    ./勾选.sh check 05-日程安排/06-日志/2026-W41/打卡.md 37 1a2b3c4d5e6f7788 --dry-run
"""


def main() -> int:
    argv = sys.argv[1:]
    flags = {a for a in argv if a.startswith("--")}
    as_json = "--json" in flags
    dry_run = "--dry-run" in flags

    # --date 带值：先摘掉值本身，剩下的才是位置参数（子命令 / 文件 / 行号 / uid）
    positional: list[str] = []
    date_raw = ""
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--date":
            if i + 1 >= len(argv):
                print("❌ --date 后面要跟 YYYY-MM-DD", file=sys.stderr)
                return 3
            date_raw = argv[i + 1]
            i += 2
            continue
        if not a.startswith("--"):
            positional.append(a)
        i += 1

    if not positional or positional[0] in ("-h", "help"):
        print(USAGE)
        return 0 if positional else 3

    cmd = positional[0]
    try:
        if cmd == "list":
            raw = date_raw or (positional[1] if len(positional) > 1 else "")
            if raw:
                try:
                    day = datetime.strptime(raw, "%Y-%m-%d").date()
                except ValueError:
                    print(f"❌ 日期应为 YYYY-MM-DD（如 2026-10-08），收到：{raw}", file=sys.stderr)
                    return 3
            else:
                day = date.today()
            return cmd_list(day, as_json)

        if cmd in ("check", "uncheck", "toggle"):
            if len(positional) < 4:
                print(USAGE)
                return 3
            rel, line_s, uid = positional[1], positional[2], positional[3]
            return cmd_mark(cmd, rel, int(line_s), uid, dry_run, as_json)
    except Refused as e:
        if as_json:
            print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))
        else:
            print(f"⛔ 拒绝写：{e}", file=sys.stderr)
        return 2
    except ValueError as e:
        print(f"❌ 参数不对：{e}", file=sys.stderr)
        return 3
    except RuntimeError as e:
        print(f"❌ {e}", file=sys.stderr)
        return 2

    print(USAGE)
    return 3


if __name__ == "__main__":
    raise SystemExit(main())
