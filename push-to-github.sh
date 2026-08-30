#!/usr/bin/env bash
# =============================================================
#  把本仓库推送到你的 GitHub（首次使用）
#  优先使用 GitHub CLI（gh）创建仓库并推送；
#  未安装 gh 时改用 git push（首次会提示登录）。
#  用法：./push-to-github.sh [仓库名] [public|private]
# =============================================================
set -euo pipefail

REPO_NAME="${1:-HelpToStudy_Linux}"
VISIBILITY="${2:-private}"
DESCRIPTION="AI 学习工作流 Linux 版：可一键复现的 Obsidian + AI 学习流程（MinerU 拆书 / 五级拆解 / 二八计划 / 十问测试 / 速查表）"

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cd "$REPO_ROOT"

if command -v gh >/dev/null 2>&1; then
    gh repo create "$REPO_NAME" "--$VISIBILITY" --source . --remote origin --push --description "$DESCRIPTION"
    who="$(gh api user --jq .login | tr -d '\r\n')"
    echo "已完成！仓库地址：https://github.com/$who/$REPO_NAME"
else
    echo "未检测到 GitHub CLI (gh)。改用 git push（首次会提示登录）。"
    read -r -p "请输入你的 GitHub 用户名：" user
    if [ -z "$user" ]; then
        echo "未输入用户名"
        exit 1
    fi
    git remote remove origin 2>/dev/null || true
    git remote add origin "https://github.com/$user/$REPO_NAME.git"
    git push -u origin main
    echo "已完成！仓库地址：https://github.com/$user/$REPO_NAME"
    echo "提示：若想把仓库设为 private，请到 GitHub 仓库页面 Settings -> General 修改可见性。"
fi
