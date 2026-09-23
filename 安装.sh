#!/usr/bin/env bash
# =============================================================
#  AI 学习工作流 · 库安装（Linux 版）
#
#  在目标位置创建完整库结构，复制模板/提示词/命令/插件，
#  创建 Python 虚拟环境并安装拆书依赖（MinerU），生成可执行启动器。
#
#  用法：
#     ./安装.sh
#     ./安装.sh --vault-path "/home/me/我的资料/AI学习工作流"
#     ./安装.sh --skip-python --skip-mineru
# =============================================================
set -euo pipefail

# ---------- 参数 ----------
VAULT_PATH=""
SKIP_PYTHON=false
SKIP_MINERU=false
SKIP_PLUGINS=false
NO_DIALOG=false
FORCE=false
OPEN_OBSIDIAN=true
NO_DESKTOP=false

while [ $# -gt 0 ]; do
    case "$1" in
        --vault-path)
            VAULT_PATH="$2"; shift 2
            ;;
        --vault-path=*)
            VAULT_PATH="${1#*=}"; shift
            ;;
        --skip-python)      SKIP_PYTHON=true; shift ;;
        --skip-mineru)      SKIP_MINERU=true; shift ;;
        --skip-plugins)     SKIP_PLUGINS=true; shift ;;
        --no-dialog)        NO_DIALOG=true; shift ;;
        --force)            FORCE=true; shift ;;
        --no-open-obsidian) OPEN_OBSIDIAN=false; shift ;;
        --no-desktop)       NO_DESKTOP=true; shift ;;
        -h|--help)
            echo "用法：安装.sh [--vault-path 路径|--skip-python|--skip-mineru|--skip-plugins|--no-dialog|--force|--no-open-obsidian|--no-desktop]"
            exit 0
            ;;
        *)
            echo "未知参数：$1"
            exit 1
            ;;
    esac
done

# ---------- 输出工具 ----------
ok()   { printf '  [完成] %s\n' "$1"; }
warn() { printf '  [提示] %s\n' "$1"; }
head() { printf '\n==> %s\n' "$1"; }

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
VAULT_NAME="AI学习工作流"

# ---------- 选择 Python（Linux 用 python3；Windows Git Bash 兜底 python） ----------
PY_CMD=""
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    PY_CMD="python3"
elif command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
    PY_CMD="python"
fi

# ---------- 读取 workflow.config.json ----------
if [ -f "$REPO_ROOT/workflow.config.json" ] && [ -n "$PY_CMD" ]; then
    cfg_vault="$("$PY_CMD" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("vaultPath",""))' "$REPO_ROOT/workflow.config.json" 2>/dev/null || true)"
    cfg_mineru="$("$PY_CMD" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get("installMineru", True)).lower())' "$REPO_ROOT/workflow.config.json" 2>/dev/null || true)"
    if [ -z "$VAULT_PATH" ] && [ -n "$cfg_vault" ]; then
        VAULT_PATH="$cfg_vault"
    fi
    if [ "$cfg_mineru" = "false" ]; then
        SKIP_MINERU=true
    fi
fi

DEFAULT_VAULT="$HOME/ObsidianVaults/$VAULT_NAME"
if [ -z "$VAULT_PATH" ]; then
    VAULT_PATH="$DEFAULT_VAULT"
fi

# niri / GNOME 等环境用 zenity；KDE 才优先 kdialog
is_kde() {
    case "${XDG_CURRENT_DESKTOP:-}" in
        *KDE*) return 0 ;;
    esac
    return 1
}

echo ""
echo "============================================"
echo "   AI 学习工作流 · 一键安装（Linux）"
echo "============================================"
echo "   安装位置: $VAULT_PATH"

# ---------- 选目录对话框（kdialog > zenity > 命令行） ----------
if [ "$NO_DIALOG" = false ] && [ -t 0 ]; then
    picked=""
    if is_kde && command -v kdialog >/dev/null 2>&1; then
        picked="$(kdialog --getexistingdirectory "$(dirname "$DEFAULT_VAULT")" 2>/dev/null)" || true
    elif command -v zenity >/dev/null 2>&1; then
        picked="$(zenity --file-selection --directory --title="选择「$VAULT_NAME」库的安装位置" 2>/dev/null)" || true
    fi
    if [ -n "$picked" ]; then
        VAULT_PATH="$picked"
        ok "已选择安装位置：$VAULT_PATH"
    else
        read -r -p "未选择位置。使用默认位置 $DEFAULT_VAULT？(Y/N) " ans
        case "$ans" in
            [yY]*) ;;
            *) echo "已取消安装"; exit 1 ;;
        esac
    fi
fi
VAULT_PATH="$(readlink -f -m "$VAULT_PATH")"

# ---------- 已存在处理 ----------
if [ -e "$VAULT_PATH" ]; then
    existing_count="$(find "$VAULT_PATH" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
    if [ "$existing_count" -gt 0 ] && [ "$FORCE" = false ]; then
        read -r -p "目标目录已存在且非空：$VAULT_PATH。继续会覆盖其中的模板/命令/工具文件（个人笔记不受影响）。输入 y 继续：" ans
        case "$ans" in
            [yY]*) ;;
            *) echo "已取消安装"; exit 1 ;;
        esac
    fi
    if [ "$existing_count" -gt 0 ]; then
        warn "目标目录已存在：保留现有个人笔记，覆盖/补充工作流文件"
    fi
fi

# ---------- 1. 创建目录 ----------
head "第 1 步：创建库目录结构"
mkdir -p "$VAULT_PATH"/{00-使用指南,01-提示词库,02-模板,03-学习主题,04-教材分块,_工具,copilot/copilot-custom-prompts,images}
mkdir -p "$VAULT_PATH/05-日程安排"/{00-配置,_脚本,06-日志,_资源/日历,_归档} \
         "$VAULT_PATH/.pi/skills"
ok "目录结构已就绪"

# ---------- 2. 复制内容 ----------
head "第 2 步：复制模板 / 提示词 / 命令 / 配置"
for d in 00-使用指南 01-提示词库 02-模板 05-日程安排 .claude .pi copilot .obsidian; do
    [ -d "$REPO_ROOT/$d" ] || continue
    mkdir -p "$VAULT_PATH/$d"
    cp -R "$REPO_ROOT/$d"/. "$VAULT_PATH/$d"/
done

if [ "$SKIP_PLUGINS" = true ] && [ -d "$VAULT_PATH/.obsidian/plugins" ]; then
    rm -rf "$VAULT_PATH/.obsidian/plugins"
fi
# 排除本机专属文件（可能含 API 密钥的 data.json 与窗口布局 workspace.json）
find "$VAULT_PATH/.obsidian" \( -name data.json -o -name workspace.json \) -delete 2>/dev/null || true

cp -R "$REPO_ROOT/_工具"/. "$VAULT_PATH/_工具"/
rm -rf "$VAULT_PATH/_工具/.venv" "$VAULT_PATH/_工具/__pycache__"

# 日程安排层：只带“骨架”进来，个人内容（日志/课表/词库/密钥）一律不带
find "$VAULT_PATH/05-日程安排" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
rm -f "$VAULT_PATH/05-日程安排/_脚本"/calender-*.json \
      "$VAULT_PATH/05-日程安排/_脚本"/service-account*.json \
      "$VAULT_PATH/05-日程安排/_脚本"/token.json 2>/dev/null || true
# 课表样例：没有真课表时用它先跑通；换课表时直接覆盖 _资源/日历/课表-当前.ics
if [ ! -f "$VAULT_PATH/05-日程安排/_资源/日历/课表-当前.ics" ]; then
    cp -f "$REPO_ROOT/05-日程安排/_资源/日历/课表示例.ics" \
          "$VAULT_PATH/05-日程安排/_资源/日历/课表-当前.ics" 2>/dev/null || true
fi
mkdir -p "$VAULT_PATH/05-日程安排/06-日志" "$VAULT_PATH/05-日程安排/_归档"

cp -f "$REPO_ROOT/03-学习主题/📌 从这里开始.md" "$VAULT_PATH/03-学习主题/" 2>/dev/null || true
cp -f "$REPO_ROOT/04-教材分块/📖 教材分块说明.md" "$VAULT_PATH/04-教材分块/" 2>/dev/null || true
cp -f "$REPO_ROOT/AGENTS.md" "$VAULT_PATH/" 2>/dev/null || true
cp -f "$REPO_ROOT/CLAUDE.md" "$VAULT_PATH/" 2>/dev/null || true

chmod +x "$VAULT_PATH/_工具"/*.sh "$VAULT_PATH/05-日程安排/_脚本"/*.sh 2>/dev/null || true
ok "内容复制完成（启动器已赋予可执行权限）"

# ---------- 2.5 应用启动器条目（niri / fuzzel / rofi / 各类应用菜单可用） ----------
if [ "$NO_DESKTOP" = false ]; then
    APPS_DIR="$HOME/.local/share/applications"
    mkdir -p "$APPS_DIR"
    enc_vault="$VAULT_PATH"
    if [ -n "$PY_CMD" ]; then
        enc_vault="$("$PY_CMD" -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$VAULT_PATH" 2>/dev/null || printf '%s' "$VAULT_PATH")"
    fi
    write_desktop() {
        local file="$1" name="$2" comment="$3" exec_cmd="$4" terminal="$5"
        cat > "$APPS_DIR/$file" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$name
Comment=$comment
Terminal=$terminal
Exec=$exec_cmd
Icon=document-save
Categories=Utility;
EOF
        chmod +x "$APPS_DIR/$file"
    }
    write_desktop \
        "helptostudy-split.desktop" \
        "拆书（MinerU）" \
        "导入 PDF，MinerU 云端识别并按章节拆分（AI学习工作流）" \
        "sh -c \"cd '$VAULT_PATH/_工具' && exec ./拆书.sh\"" \
        "true"
    write_desktop \
        "helptostudy-token.desktop" \
        "设置MinerU令牌" \
        "保存 MinerU Token（AI学习工作流）" \
        "sh -c \"cd '$VAULT_PATH/_工具' && exec ./设置MinerU令牌.sh\"" \
        "true"
    write_desktop \
        "helptostudy-vault.desktop" \
        "打开 AI学习工作流 库" \
        "用 Obsidian 打开已安装的 AI学习工作流 库" \
        "xdg-open \"obsidian://open?path=$enc_vault\"" \
        "false"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    fi
    ok "应用启动器已注册：拆书（MinerU）、设置MinerU令牌、打开库（$APPS_DIR）"
fi

# ---------- 3. Python 环境 ----------
VENV_PY="$VAULT_PATH/_工具/.venv/bin/python"
if [ "$SKIP_PYTHON" = false ]; then
    head "第 3 步：创建 Python 虚拟环境并安装拆书依赖"
    if ! command -v python3 >/dev/null 2>&1; then
        echo "    未找到 Python3。请先运行 ./环境配置.sh，或安装 python3 / python3-venv。"
        exit 1
    fi
    if [ ! -x "$VENV_PY" ]; then
        python3 -m venv "$VAULT_PATH/_工具/.venv" || {
            echo "    创建 Python 虚拟环境失败（Debian/Ubuntu 需先安装 python3-venv）。"
            exit 1
        }
    fi
    pip_retry() {
        local label="$1"; shift
        local i
        for i in 1 2 3; do
            if "$VENV_PY" -m pip install --disable-pip-version-check -q "$@"; then
                return 0
            fi
            if [ "$i" -lt 3 ]; then
                warn "$label 第 $i 次尝试失败，5 秒后自动重试（网络波动常见，最多重试 3 次）"
                sleep 5
            fi
        done
        return 1
    }
    pip_retry "拆书依赖" -r "$REPO_ROOT/_工具/requirements.txt"
    ok "拆书依赖已安装（pypdf）"

    if [ "$SKIP_MINERU" = false ]; then
        if pip_retry "MinerU 工具" mineru-open-api; then
            ok "MinerU 云端 OCR 工具已安装"
        else
            warn "MinerU 工具安装失败，可稍后手动执行：$VENV_PY -m pip install mineru-open-api"
        fi
    fi

    # 日程安排层依赖（Google 日历后端；不装也完全能用 ics 后端）
    SCHED_REQ="$REPO_ROOT/05-日程安排/_脚本/requirements.txt"
    if [ -f "$SCHED_REQ" ]; then
        if pip_retry "日程同步依赖" -r "$SCHED_REQ"; then
            ok "日程同步依赖已安装（google-api-python-client / google-auth-oauthlib / PySocks）"
        else
            warn "日程同步依赖没装上：Google 后端暂时不可用，ics 后端不受影响。"
            warn "稍后可手动执行：$VENV_PY -m pip install -r 05-日程安排/_脚本/requirements.txt"
        fi
    fi
else
    warn "已跳过 Python 环境安装（--skip-python）"
fi

# ---------- 4. 收尾 ----------
head "第 4 步：收尾"
echo ""
echo "============== 安装完成 =============="
echo "  库位置: $VAULT_PATH"
echo ""
echo "  接下来："
echo "  1) 用 Obsidian 打开该文件夹（作为库）"
echo "  2) 首次打开若提示「信任社区插件」，请选择信任"
echo "  3) 右侧边栏打开 Claudian，在设置里选择后端（本机 Codex 或 Claude Code）"
echo "  4) 扫描版/数学书才需要：运行 _工具/设置MinerU令牌.sh 保存 Token"
echo "  5) （可选）自检一遍：05-日程安排/_脚本/自检.sh
  6) 打开 00-使用指南/📖 使用说明.md 开始使用"
echo "======================================"

if [ "$OPEN_OBSIDIAN" = true ]; then
    enc="$VAULT_PATH"
    if [ -n "$PY_CMD" ]; then
        enc="$("$PY_CMD" -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$VAULT_PATH" 2>/dev/null || printf '%s' "$VAULT_PATH")"
    fi
    if xdg-open "obsidian://open?path=$enc" >/dev/null 2>&1; then
        ok "已尝试用 Obsidian 打开该库"
    else
        warn "请手动用 Obsidian 打开：$VAULT_PATH"
    fi
fi
