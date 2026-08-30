#!/usr/bin/env bash
# =============================================================
#  构建 HelpToStudy Linux 一键安装 Release 资产
#  生成三个文件（默认输出到当前目录）：
#    HelpToStudy-Vault-<tag>.zip     库完整内容（UTF-8 安全的中文文件名，.sh 带可执行位）
#    HelpToStudy-QuickInstall.sh     一键入口（内嵌版本号与直链下载 URL）
#    release-notes.md                Release 说明（中文）
#  用法：./scripts/build-release.sh [-t v1.0.0] [-r owner/repo] [-o 输出目录]
# =============================================================
set -euo pipefail

TAG=""
REPO=""
OUT_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        -t|--tag)  TAG="$2"; shift 2 ;;
        -r|--repo) REPO="$2"; shift 2 ;;
        -o|--out)  OUT_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "用法：build-release.sh [-t v1.0.0] [-r owner/repo] [-o 输出目录]"
            exit 0
            ;;
        *) echo "未知参数：$1"; exit 1 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

# ---------- 解析版本号 ----------
if [ -z "$TAG" ]; then
    TAG="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || true)"
    if [ -z "$TAG" ]; then
        echo "未指定 -t/--tag，且仓库里没有可用 tag。请先打 tag 或传 -t v1.0.0"
        exit 1
    fi
fi
case "$TAG" in
    v[0-9A-Za-z._-]*) ;;
    *) echo "-t/--tag 必须是安全的版本号（如 v1.0.0），当前值：$TAG"; exit 1 ;;
esac

# ---------- 解析仓库 ----------
if [ -z "$REPO" ]; then
    url="$(git -C "$REPO_ROOT" config --get remote.origin.url 2>/dev/null || true)"
    REPO="$(printf '%s' "$url" | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+?)(\.git)?$#\1#p')"
fi
if [ -z "$REPO" ]; then
    echo "无法从 origin 解析仓库名，请用 -r owner/repo 指定"
    exit 1
fi

if [ -z "$OUT_DIR" ]; then
    OUT_DIR="$(pwd)"
fi
mkdir -p "$OUT_DIR"

ZIP_NAME="HelpToStudy-Vault-$TAG.zip"
SH_NAME="HelpToStudy-QuickInstall.sh"
NOTES_NAME="release-notes.md"

# ---------- 选择 Python（Linux 用 python3；Windows Git Bash 兜底 python） ----------
PY=""
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    PY="python3"
elif command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
    PY="python"
else
    echo "需要 Python 3 才能构建 Release 资产"
    exit 1
fi

echo "打包库内容 -> $OUT_DIR/$ZIP_NAME"
"$PY" - "$REPO_ROOT" "$OUT_DIR" "$TAG" "$REPO" "$ZIP_NAME" "$SH_NAME" "$NOTES_NAME" <<'PY'
import os
import sys
import zipfile

repo_root, out_dir, tag, repo, zip_name, sh_name, notes_name = sys.argv[1:8]
zip_path = os.path.join(out_dir, zip_name)

# ---------- 1. 库压缩包：UTF-8 文件名 + .sh 可执行位 ----------
skip_names = {".git", ".venv", "__pycache__", "dist", "_备份"}
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(repo_root):
        dirs[:] = [d for d in dirs if d not in skip_names]
        for f in files:
            full = os.path.join(root, f)
            rel = os.path.relpath(full, repo_root).replace(os.sep, "/")
            zi = zipfile.ZipInfo(rel)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (0o755 if f.endswith(".sh") else 0o644) << 16
            with open(full, "rb") as fh:
                zf.writestr(zi, fh.read())
print(f"  zip: {zip_path}")

# ---------- 2. 一键引导器（内嵌版本号与直链，独立可用） ----------
sh_path = os.path.join(out_dir, sh_name)
quick = """#!/usr/bin/env bash
# =============================================================
#  AI 学习工作流 · 一键安装引导器（Release 生成版）
#  版本: {tag}
#  仓库: {repo}
# =============================================================
set -euo pipefail
REPO="{repo}"
TAG="{tag}"
ZIP="HelpToStudy-Vault-{tag}.zip"
URL="https://github.com/{repo}/releases/download/{tag}/$ZIP"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[1/3] 下载库压缩包 ..."
curl -fL --retry 3 --connect-timeout 30 -o "$WORK/$ZIP" "$URL"

echo "[2/3] 解压库压缩包 ..."
mkdir -p "$WORK/vault"
python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$WORK/$ZIP" "$WORK/vault"
if [ ! -f "$WORK/vault/QuickInstall.sh" ]; then
    sub="$(find "$WORK/vault" -maxdepth 2 -name QuickInstall.sh -printf '%h' -quit)"
    if [ -n "$sub" ]; then
        mv "$sub"/* "$WORK/vault"/
    fi
fi
if [ ! -f "$WORK/vault/QuickInstall.sh" ]; then
    echo "[错误] 解压内容异常：未找到 QuickInstall.sh"
    exit 1
fi
chmod +x "$WORK/vault"/*.sh "$WORK/vault/_工具"/*.sh 2>/dev/null || true

echo "[3/3] 环境配置 + 安装库 ..."
exec bash "$WORK/vault/QuickInstall.sh" "$@"
""".replace("{tag}", tag).replace("{repo}", repo)
with open(sh_path, "w", encoding="utf-8", newline="\n") as fh:
    fh.write(quick)
os.chmod(sh_path, 0o755)
print(f"  sh : {sh_path}")

# ---------- 3. Release 说明（中文，UTF-8） ----------
notes = f"""# AI 学习工作流 · Linux 版 · {tag}

一套把「厚教材 → 能真正学会」的固定流程封装成可一键复现的 Obsidian 库：
MinerU 拆书 → 五级水平拆解 → 二八定律学习计划 → 十问测试 → 一页速查表。

## 一键安装（CachyOS / Arch，推荐）

1. 下载本页资产 **HelpToStudy-QuickInstall.sh**
2. 终端运行：
   ```
   chmod +x HelpToStudy-QuickInstall.sh
   ./HelpToStudy-QuickInstall.sh
   ```
   它会自动完成：
   - 从 Release 下载库压缩包并解压
   - 检测/安装环境：Obsidian、Python、Node.js、Git、Claude Code、cc-switch
     （CachyOS：Obsidian 走官方仓库，cc-switch 走 AUR `cc-switch-bin`）
   - 安装「AI 学习工作流」Obsidian 库（默认 `~/ObsidianVaults/AI学习工作流`）
   - 装完自动打开 Obsidian
3. 首次打开 Obsidian 若提示「信任社区插件」，选信任
4. 右侧边栏打开 Claudian，选择后端（本机 Codex 或 Claude Code）即可使用

## 常用参数

```
./HelpToStudy-QuickInstall.sh --vault-path "/home/me/我的资料/AI学习工作流"
./HelpToStudy-QuickInstall.sh --skip-env
./HelpToStudy-QuickInstall.sh --skip-mineru --no-open-obsidian
```

| 参数 | 作用 |
| --- | --- |
| `--skip-env` | 跳过环境检测/安装，只装库 |
| `--skip-claude` | 跳过 Claude Code 安装 |
| `--update` | 检测到旧版本时直接升级 |
| `--vault-path "路径"` | 指定库安装位置 |
| `--no-dialog` | 不弹目录选择框，用默认位置 |
| `--skip-python` | 跳过 Python 虚拟环境与拆书依赖 |
| `--skip-mineru` | 不装 MinerU 云端 OCR 工具 |
| `--no-open-obsidian` | 装完不自动打开 Obsidian |
| `--force` | 目标目录已存在时不询问，直接继续 |

## 手动安装（备用）

下载 **HelpToStudy-Vault-{tag}.zip**，解压后先运行「环境配置.sh」，
再运行「安装.sh」。

## 说明

- Linux 版只保留 MinerU 拆书：教材请提供 **PDF**（扫描版/数学书均可，
  云端 OCR + 公式转 LaTeX）；EPUB / Word 不在支持范围。
- 库内容与 Windows 版仓库保持一致；`_工具` 为平台差异区。
- 升级旧库：再次运行引导器；目标目录已存在时会询问是否继续，
  个人笔记不受影响，只覆盖/补充工作流文件。
"""
with open(os.path.join(out_dir, notes_name), "w", encoding="utf-8", newline="\n") as fh:
    fh.write(notes)
print(f"  md : {os.path.join(out_dir, notes_name)}")
PY

echo ""
echo "============== 构建完成 =============="
echo "  ZIP : $OUT_DIR/$ZIP_NAME"
echo "  SH  : $OUT_DIR/$SH_NAME"
echo "  说明: $OUT_DIR/$NOTES_NAME"
echo "======================================"
