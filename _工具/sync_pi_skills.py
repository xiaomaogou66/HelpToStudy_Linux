#!/usr/bin/env python3
"""把 .claude/commands/*.md 同步为 pi 的 skills（.pi/skills/*.md）。

用法：
    python3 _工具/sync_pi_skills.py

修改了 .claude/commands 下的命令后重新运行一次即可。
pi skill 的 name 只允许小写字母/数字/连字符，因此用固定映射生成拼音名。
"""
import json
import re
import sys
from pathlib import Path

VAULT = Path(__file__).resolve().parent.parent
SRC = VAULT / ".claude" / "commands"
DST = VAULT / ".pi" / "skills"

# 中文名 -> pi skill 名（kebab-case，拼音）
NAME_MAP = {
    "拆书": "chai-shu",
    "测试我": "ce-shi-wo",
    "速查表": "su-cha-biao",
    "新主题-拆解与计划": "xin-zhu-ti-chaifen-jihua",
    "学案": "xue-an",
    "更新进度": "gengxin-jindu",
    "周决策": "zhou-jue-ce",
    "课表": "ke-biao",
}

FM_RE = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.S)


def parse_frontmatter(text: str):
    """极简 frontmatter 解析：只取 key: value 与 'key:' 开头的简单列表。"""
    m = FM_RE.match(text)
    if not m:
        return {}, text
    meta, body = {}, text[m.end():]
    key = None
    for line in m.group(1).splitlines():
        lm = re.match(r"([A-Za-z\u4e00-\u9fff][^:]*):\s*(.*)", line)
        if lm and not line.startswith(" "):
            key = lm.group(1).strip()
            val = lm.group(2).strip().strip("'\"")
            meta[key] = val if val else []
        elif line.strip().startswith("- ") and key:
            if isinstance(meta[key], list):
                meta[key].append(line.strip()[2:].strip())
    return meta, body


def to_skill(src: Path):
    stem = src.stem
    name = NAME_MAP.get(stem)
    if not name:
        print(f"跳过 {src.name}：NAME_MAP 中没有对应条目", file=sys.stderr)
        return None
    meta, body = parse_frontmatter(src.read_text(encoding="utf-8"))
    desc = meta.get("description") or f"来自 Claude 命令 /{stem}"
    if meta.get("argument-hint"):
        desc = f"{desc}（参数：{meta['argument-hint']}）"
    # 用 JSON 双引号转义，避免描述里含 " 破坏 YAML
    lines = ["---", f"name: {name}", f"description: {json.dumps(desc, ensure_ascii=False)}"]
    at = meta.get("allowed-tools")
    if isinstance(at, list) and at:
        lines.append(f"allowed-tools: {' '.join(at)}")
    lines += ["---", "", f"> 本 skill 由 Claude 命令 `/{stem}` 自动生成，请勿直接编辑。", ""]
    return name, "\n".join(lines) + body


def main():
    if not SRC.is_dir():
        sys.exit(f"找不到源目录：{SRC}")
    DST.mkdir(parents=True, exist_ok=True)
    written, names = [], set()
    for src in sorted(SRC.glob("*.md")):
        result = to_skill(src)
        if not result:
            continue
        name, text = result
        names.add(name)
        out = DST / f"{name}.md"
        out.write_text(text, encoding="utf-8")
        written.append(out.relative_to(VAULT).as_posix())
    # 清理已失效的旧 skill（只删本脚本命名规则下的文件）
    for old in DST.glob("*.md"):
        if old.stem not in names and old.stem in NAME_MAP.values():
            old.unlink()
    print("已同步：")
    for w in written:
        print(f"  {w}")


if __name__ == "__main__":
    main()
