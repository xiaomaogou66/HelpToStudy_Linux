#!/usr/bin/env bash
# =============================================================
#  AI 学习工作流 · 一键安装（Release 引导器）
#
#  下载 Release 库压缩包 → 解压 → 环境配置 → 安装库 → 打开 Obsidian
#  用法：QuickInstall.sh [--skip-env|--skip-claude|--update|安装.sh 参数]
# =============================================================
set -euo pipefail

REPO="${REPO:-}"
TAG="${TAG:-}"
ZIP="${ZIP:-}"
URL="${URL:-}"

# ---------- 选择 Python（Linux 用 python3；Windows Git Bash 兜底 python） ----------
PY=""
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    PY="python3"
elif command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
    PY="python"
fi
if [ -z "$PY" ]; then
    echo "[错误] 需要 Python 3（用于解析版本号与解压 zip）"
    exit 1
fi

# ---------- 解析仓库 ----------
if [ -z "$REPO" ]; then
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        url="$(git config --get remote.origin.url 2>/dev/null || true)"
        REPO="$(printf '%s' "$url" | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+?)(\.git)?$#\1#p')"
    fi
    [ -z "$REPO" ] && REPO="xiaomaogou66/HelpToStudy_Linux"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------- 下载 ----------
if [ -z "$URL" ] || [ -z "$ZIP" ]; then
    if [ -z "$TAG" ]; then
        TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])' 2>/dev/null || true)"
        if [ -z "$TAG" ]; then
            echo "[错误] 无法获取 $REPO 的最新 Release 版本号，可用环境变量 TAG/URL 指定。"
            exit 1
        fi
    fi
    ZIP="HelpToStudy-Vault-$TAG.zip"
    URL="https://github.com/$REPO/releases/download/$TAG/$ZIP"
fi

echo "[1/3] 下载库压缩包：$URL"
curl -fL --retry 3 --connect-timeout 30 -o "$WORK/$ZIP" "$URL"

echo "[2/3] 解压库压缩包"
mkdir -p "$WORK/vault"
"$PY" -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$WORK/$ZIP" "$WORK/vault"
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

# ---------- 安装 ----------
echo "[3/3] 环境配置 + 安装库"
ENV_ARGS=()
INSTALL_ARGS=()
SKIP_ENV=false
for arg in "$@"; do
    case "$arg" in
        --skip-env)     SKIP_ENV=true ;;
        --skip-claude|--update) ENV_ARGS+=("$arg") ;;
        *)              INSTALL_ARGS+=("$arg") ;;
    esac
done

if [ "$SKIP_ENV" = false ]; then
    bash "$WORK/vault/环境配置.sh" "${ENV_ARGS[@]}"
fi
bash "$WORK/vault/安装.sh" "${INSTALL_ARGS[@]}"

echo ""
echo "============== 全部完成 =============="
echo "  1) Obsidian 已打开（或在应用菜单中打开）"
echo "  2) 首次打开若提示「信任社区插件」，请选择信任"
echo "  3) 右侧边栏打开 Claudian，在设置里选择后端（本机 Codex 或 Claude Code）"
echo "  4) 扫描版/数学书才需要：运行 _工具/设置MinerU令牌.sh 保存 Token"
echo "  5) 打开 00-使用指南/📖 使用说明.md 开始使用"
echo "======================================"
