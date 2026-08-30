#!/usr/bin/env bash
# 保存 MinerU Token（免费注册 https://mineru.net，登录后 API Token → Create Token）
set -euo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
TOKEN_FILE="$(pwd)/mineru_token.txt"

echo "================================================"
echo "  保存 MinerU Token"
echo "  免费注册：https://mineru.net"
echo "  登录后：API Token → Create Token → Copy"
echo "================================================"
echo ""

read -r -p "粘贴 Token：" TOKEN
if [ -z "$TOKEN" ]; then
    echo "没有输入 Token，退出。"
    exit 1
fi

printf '%s' "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
echo ""
echo "已保存到 $TOKEN_FILE（仅当前用户可读）"
