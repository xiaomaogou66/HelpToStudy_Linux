#!/usr/bin/env bash
# =============================================================
#  拆书（Linux 版 · MinerU 单流程）
#  - PDF            → MinerU 云端 OCR（公式转 LaTeX）+ 按章拆分
#  - 00-MinerU解析全文.md → 直接按章节重切分（不耗额度）
#  用法：拆书.sh [PDF 或 00-MinerU解析全文.md 的路径] [传给 split_textbook.py 的额外参数]
#  例如：拆书.sh 某本书.pdf --mineru-chunk-mb 10   # 上行网络慢，每份传得更小
#        拆书.sh 某本书.pdf --mineru-dpi 150       # 扫描页降得更狠（默认 200）
#        拆书.sh 某本书.pdf --mineru-dry-run       # 只看分块计划，不耗额度
#  章标题识别不到（如《某外语教材》每课的 UNIDAD）：已默认自动处理（auto），
#  拿已生成的全文重切不耗额度：
#        拆书.sh "04-教材分块/<书名>/00-MinerU解析全文.md"
#        （想自己指定章界锚点：--chapter-end-pattern '习题\s*\(Ejercicios'；关掉：off）
# =============================================================
set -euo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
VAULT="$(cd .. && pwd)"
SCRIPT="$(pwd)/split_textbook.py"
OUT="$VAULT/04-教材分块"
TOKEN_FILE="$(pwd)/mineru_token.txt"

if [ -x "$(pwd)/.venv/bin/python" ]; then
    PY="$(pwd)/.venv/bin/python"
else
    PY="python3"
fi

if [ -x "$(pwd)/.venv/bin/mineru-open-api" ]; then
    MINERU_CLI="$(pwd)/.venv/bin/mineru-open-api"
else
    MINERU_CLI="$(command -v mineru-open-api 2>/dev/null || true)"
fi

echo "================================================"
echo "  拆书 · MinerU 云端（公式转 LaTeX + 章节拆分）"
echo "  PDF            → 云端 OCR + 按章拆分"
echo "  00-MinerU解析全文.md → 重切分（不耗额度）"
echo "================================================"
echo ""

FILE="${1:-}"
if [ -z "$FILE" ]; then
    IS_KDE=false
    case "${XDG_CURRENT_DESKTOP:-}" in
        *KDE*) IS_KDE=true ;;
    esac
    if [ "$IS_KDE" = true ] && command -v kdialog >/dev/null 2>&1; then
        FILE="$(kdialog --getopenfilename . '*.pdf *.md|PDF / Markdown' 2>/dev/null)" || true
    elif command -v zenity >/dev/null 2>&1; then
        FILE="$(zenity --file-selection --file-filter='PDF / Markdown | *.pdf *.md' 2>/dev/null)" || true
    fi
fi
if [ -z "$FILE" ]; then
    read -r -p "请把 PDF 或 00-MinerU解析全文.md 的路径粘贴到这里，然后按回车：" FILE
fi
if [ -z "$FILE" ]; then
    echo "没有输入文件路径，退出。"
    exit 1
fi
FILE="$(readlink -f "$FILE")"

echo "选定文件：$FILE"
echo "输出目录：$OUT"
echo ""

EXT="${FILE##*.}"
EXTRA=("${@:2}")
if [ "${EXT,,}" = "md" ]; then
    echo "检测到 Markdown 全文，按章节重切分（不消耗 MinerU 额度）..."
    "$PY" "$SCRIPT" "$FILE" --out "$OUT" --split-mode chapter "${EXTRA[@]}"
elif [ "${EXT,,}" = "pdf" ]; then
    # MinerU Token：环境变量 > token 文件 > 手动输入
    TOKEN=""
    if [ -f "$TOKEN_FILE" ]; then
        TOKEN="$(cat "$TOKEN_FILE" | tr -d '\r\n')"
    fi
    if [ -z "$TOKEN" ]; then
        read -r -p "还没有保存 MinerU Token。请粘贴 Token（免费注册 https://mineru.net）：" TOKEN
    fi
    if [ -z "$TOKEN" ]; then
        echo "[错误] 没有 Token，无法使用 MinerU。可先运行 _工具/设置MinerU令牌.sh 保存。"
        exit 1
    fi
    if [ -z "$MINERU_CLI" ]; then
        echo "[错误] 找不到 mineru-open-api 命令行工具。"
        echo "       请先运行安装脚本创建虚拟环境：$VAULT/_工具/.venv/bin/pip install mineru-open-api"
        exit 1
    fi
    export AIWF_MINERU_CLI="$MINERU_CLI"
    export AIWF_MINERU_TOKEN_FILE="$TOKEN_FILE"
    echo "上传到 MinerU 云端解析并按章节拆分。750 页的书大约需要 20-40 分钟，请耐心等待..."
    echo "（扫描版超大会自动降到 200 DPI 并按 ≤25 MB/份 分块上传，失败会自动切小重传）"
    "$PY" "$SCRIPT" "$FILE" --out "$OUT" --ocr mineru --split-mode chapter --mineru-token "$TOKEN" "${EXTRA[@]}"
else
    echo "[错误] Linux 版仅支持 PDF（MinerU 云端识别）或 00-MinerU解析全文.md 重切分。"
    exit 1
fi

if [ $? -eq 0 ]; then
    echo ""
    echo "[OK] 完成！分块笔记在：$OUT"
    echo "     打开 01-全书大纲.md 查看章节清单与进度勾选。"
fi
