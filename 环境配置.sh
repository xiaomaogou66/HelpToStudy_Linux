#!/usr/bin/env bash
# =============================================================
#  AI 学习工作流 · 一键环境配置（Linux 版，CachyOS / Arch 优先）
#
#  检测并安装：Obsidian、Python、Node.js、Git、Claude Code、cc-switch
#  安装来源优先级：pacman / apt / dnf 官方仓库 > AUR（Arch 系）> npm > 官方下载
#
#  用法：
#     ./环境配置.sh                 检测并安装缺失环境
#     ./环境配置.sh --check-only    只检测，不安装
#     ./环境配置.sh --update        检测到旧版本时直接升级
#     ./环境配置.sh --skip-claude   跳过 Claude Code
# =============================================================
set -euo pipefail

# ---------- 参数 ----------
CHECK_ONLY=false
UPDATE=false
SKIP_CLAUDE=false

for arg in "$@"; do
    case "$arg" in
        --check-only)  CHECK_ONLY=true ;;
        --update)      UPDATE=true ;;
        --skip-claude) SKIP_CLAUDE=true ;;
        -h|--help)
            echo "用法：环境配置.sh [--check-only|--update|--skip-claude]"
            echo "  --check-only   只检测并报告各工具状态，不安装任何东西"
            echo "  --update       检测到旧版本时直接升级，不再询问"
            echo "  --skip-claude  跳过 Claude Code 的检测与安装"
            exit 0
            ;;
        *)
            echo "未知参数：$arg"
            exit 1
            ;;
    esac
done

# ---------- 输出工具 ----------
ok()   { printf '  [OK] %s\n' "$1"; }
warn() { printf '  [提示] %s\n' "$1"; }
info() { printf '  %s\n' "$1"; }
head() { printf '\n==> %s\n' "$1"; }
err()  { printf '  [错误] %s\n' "$1" >&2; }

# ---------- 平台检测 ----------
detect_pkg_manager() {
    if command -v pacman >/dev/null 2>&1; then
        echo pacman
    elif command -v apt-get >/dev/null 2>&1; then
        echo apt
    elif command -v dnf >/dev/null 2>&1; then
        echo dnf
    elif command -v zypper >/dev/null 2>&1; then
        echo zypper
    else
        echo none
    fi
}
PKG_MANAGER="$(detect_pkg_manager)"
if [ "$PKG_MANAGER" = "none" ]; then
    err "未能识别包管理器（支持 pacman / apt / dnf / zypper）"
    exit 1
fi

# root 时不需要 sudo
run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ---------- 通用工具函数 ----------
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

version_of() {  # version_of <cmd> [args...]
    local cmd="$1"; shift
    local out
    out="$("$cmd" "$@" 2>/dev/null | head -n 1)" || true
    printf '%s' "$out" | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1 || true
}

# GitHub 最新 Release 中匹配文件名的下载地址（仓库名 owner/repo，文件名用正则）
github_latest_asset() {
    local repo="$1" pattern="$2"
    if ! cmd_exists python3; then
        return 1
    fi
    python3 - "$repo" "$pattern" <<'PY' || true
import json, re, sys, urllib.request
repo, pat = sys.argv[1], sys.argv[2]
try:
    with urllib.request.urlopen(f"https://api.github.com/repos/{repo}/releases/latest", timeout=30) as r:
        data = json.load(r)
    for a in data.get("assets", []):
        if re.search(pat, a["name"]):
            print(a["browser_download_url"])
            break
except Exception:
    pass
PY
}

download_with_retry() {  # download_with_retry <url> <dest>
    local url="$1" dest="$2" i
    for i in 1 2 3; do
        if curl -fsSL --retry 3 --connect-timeout 30 -o "$dest" "$url"; then
            return 0
        fi
        if [ "$i" -lt 3 ]; then
            warn "下载失败，5 秒后自动重试（第 $i/3 次）"
            sleep 5
        fi
    done
    return 1
}

find_aur_helper() {
    for h in paru yay; do
        if cmd_exists "$h"; then
            echo "$h"
            return 0
        fi
    done
    return 1
}

REPORT=()

# =============================================================
# 0) 基础工具：文件选择（zenity）、xdg-open、下载（curl）、
#    扫描版降采样（ghostscript：拆书上传前把 300 DPI 压到 200 DPI）
#    niri / GNOME 等无 kdialog 的环境靠 zenity 完成图形选目录/选文件
# =============================================================
ensure_base_tools() {
    case "$PKG_MANAGER" in
        pacman)
            run_privileged pacman -S --noconfirm --needed zenity xdg-utils curl ghostscript
            ;;
        apt)
            run_privileged apt-get update -qq
            run_privileged apt-get install -y zenity xdg-utils curl ghostscript
            ;;
        dnf)
            run_privileged dnf install -y zenity xdg-utils curl ghostscript
            ;;
        zypper)
            run_privileged zypper install -y zenity xdg-utils curl ghostscript
            ;;
    esac
}

if [ "$CHECK_ONLY" = false ]; then
    head "检查基础工具（zenity / xdg-utils / curl / ghostscript）"
    if ensure_base_tools; then
        ok "基础工具已就绪"
        REPORT+=("基础工具(zenity/xdg-utils/curl/ghostscript): 已就绪")
    else
        warn "基础工具安装失败（不影响核心流程，但图形选文件可能不可用）"
        REPORT+=("基础工具(zenity/xdg-utils/curl/ghostscript): 安装失败")
    fi
fi

# =============================================================
# 1) Obsidian
# =============================================================
head "检查 Obsidian"
OBSIDIAN_INSTALLED=false
OBSIDIAN_VER=""
if cmd_exists obsidian; then
    OBSIDIAN_INSTALLED=true
    OBSIDIAN_VER="$(version_of obsidian --version)"
    if [ -z "$OBSIDIAN_VER" ] && [ "$PKG_MANAGER" = "pacman" ]; then
        OBSIDIAN_VER="$(pacman -Q obsidian 2>/dev/null | awk '{print $2}')" || true
    fi
    if [ -n "$OBSIDIAN_VER" ]; then
        info "已安装版本：$OBSIDIAN_VER"
    else
        info "已安装"
    fi
else
    info "未安装"
fi

install_obsidian() {
    case "$PKG_MANAGER" in
        pacman)
            run_privileged pacman -S --noconfirm --needed obsidian
            ;;
        apt)
            local url tmp
            url="$(github_latest_asset obsidianmd/obsidian-releases 'Obsidian-[0-9.]+\.deb')"
            if [ -z "$url" ]; then
                warn "无法获取 Obsidian 官方 .deb 下载地址，请到 https://obsidian.md 手动安装后重试"
                return 1
            fi
            tmp="$(mktemp --suffix=.deb)"
            download_with_retry "$url" "$tmp" || { warn "下载 Obsidian 失败"; rm -f "$tmp"; return 1; }
            run_privileged dpkg -i "$tmp" || run_privileged apt-get install -f -y
            rm -f "$tmp"
            ;;
        dnf)
            local url tmp
            url="$(github_latest_asset obsidianmd/obsidian-releases 'Obsidian-[0-9.]+\.rpm')"
            if [ -z "$url" ]; then
                warn "无法获取 Obsidian 官方 .rpm 下载地址，请到 https://obsidian.md 手动安装后重试"
                return 1
            fi
            tmp="$(mktemp --suffix=.rpm)"
            download_with_retry "$url" "$tmp" || { warn "下载 Obsidian 失败"; rm -f "$tmp"; return 1; }
            run_privileged dnf install -y "$tmp"
            rm -f "$tmp"
            ;;
        zypper)
            warn "zypper 系统请手动安装 Obsidian（官方 .rpm）"
            return 1
            ;;
    esac
}

if [ "$CHECK_ONLY" = true ]; then
    if [ "$OBSIDIAN_INSTALLED" = true ]; then
        REPORT+=("Obsidian: 已安装${OBSIDIAN_VER:+（$OBSIDIAN_VER）}")
        ok "Obsidian 已安装${OBSIDIAN_VER:+（$OBSIDIAN_VER）}"
    else
        REPORT+=("Obsidian: 缺失")
        warn "Obsidian 未安装"
    fi
else
    if [ "$OBSIDIAN_INSTALLED" = false ]; then
        echo "    正在安装 Obsidian ..."
        if install_obsidian; then
            ok "Obsidian 安装完成"
            REPORT+=("Obsidian: 已安装（本次安装）")
        else
            warn "Obsidian 安装失败，请手动安装"
            REPORT+=("Obsidian: 安装失败（请手动安装）")
        fi
    elif [ "$UPDATE" = true ] && [ "$PKG_MANAGER" = "pacman" ]; then
        echo "    正在升级 Obsidian ..."
        run_privileged pacman -S --noconfirm obsidian || true
        ok "Obsidian 已升级"
        REPORT+=("Obsidian: 已升级")
    else
        ok "无需操作"
        REPORT+=("Obsidian: 已安装${OBSIDIAN_VER:+（$OBSIDIAN_VER）}")
    fi
fi

# =============================================================
# 2) Python
# =============================================================
head "检查 Python"
PYTHON_INSTALLED=false
PYTHON_VER=""
if cmd_exists python3; then
    PYTHON_INSTALLED=true
    PYTHON_VER="$(version_of python3 --version)"
    info "已安装版本：${PYTHON_VER:-未知}"
else
    info "未安装"
fi

install_python() {
    case "$PKG_MANAGER" in
        pacman)
            run_privileged pacman -S --noconfirm --needed python python-pip python-venv
            ;;
        apt)
            run_privileged apt-get update -qq
            run_privileged apt-get install -y python3 python3-pip python3-venv
            ;;
        dnf)
            run_privileged dnf install -y python3 python3-pip
            ;;
        zypper)
            run_privileged zypper install -y python3 python3-pip
            ;;
    esac
}

if [ "$CHECK_ONLY" = true ]; then
    if [ "$PYTHON_INSTALLED" = true ]; then
        REPORT+=("Python: 已安装（$PYTHON_VER）")
        ok "Python 已安装（$PYTHON_VER）"
    else
        REPORT+=("Python: 缺失")
        warn "Python 未安装"
    fi
else
    if [ "$PYTHON_INSTALLED" = false ]; then
        echo "    正在安装 Python ..."
        if install_python; then
            ok "Python 安装完成"
            REPORT+=("Python: 已安装（本次安装）")
        else
            warn "Python 安装失败，请手动安装 python3"
            REPORT+=("Python: 安装失败（请手动安装）")
        fi
    elif [ "$UPDATE" = true ]; then
        case "$PKG_MANAGER" in
            pacman) run_privileged pacman -S --noconfirm python python-pip python-venv || true ;;
            apt)    run_privileged apt-get install --only-upgrade -y python3 python3-pip python3-venv || true ;;
            dnf)    run_privileged dnf upgrade -y python3 || true ;;
            zypper) run_privileged zypper update -y python3 || true ;;
        esac
        ok "Python 已升级"
        REPORT+=("Python: 已升级")
    else
        ok "无需操作"
        REPORT+=("Python: 已安装（$PYTHON_VER）")
    fi
fi

if ! python3 -m venv --help >/dev/null 2>&1; then
    warn "python3-venv 不可用：Debian/Ubuntu 请安装 python3-venv，Arch 系请安装 python-venv"
fi

# =============================================================
# 3) Node.js
# =============================================================
head "检查 Node.js"
NODE_INSTALLED=false
NODE_VER=""
if cmd_exists node; then
    NODE_INSTALLED=true
    NODE_VER="$(version_of node --version)"
    info "已安装版本：${NODE_VER:-未知}"
else
    info "未安装"
fi

install_node() {
    case "$PKG_MANAGER" in
        pacman)
            run_privileged pacman -S --noconfirm --needed nodejs npm
            ;;
        apt)
            run_privileged apt-get update -qq
            run_privileged apt-get install -y nodejs npm
            warn "若系统 npm 版本过旧，可改用 NodeSource 官方源安装新版 Node.js"
            ;;
        dnf)
            run_privileged dnf install -y nodejs npm
            ;;
        zypper)
            run_privileged zypper install -y nodejs npm
            ;;
    esac
}

if [ "$CHECK_ONLY" = true ]; then
    if [ "$NODE_INSTALLED" = true ]; then
        REPORT+=("Node.js: 已安装（$NODE_VER）")
        ok "Node.js 已安装（$NODE_VER）"
    else
        REPORT+=("Node.js: 缺失")
        warn "Node.js 未安装"
    fi
else
    if [ "$NODE_INSTALLED" = false ]; then
        echo "    正在安装 Node.js ..."
        if install_node; then
            ok "Node.js 安装完成"
            REPORT+=("Node.js: 已安装（本次安装）")
        else
            warn "Node.js 安装失败，请手动安装 nodejs"
            REPORT+=("Node.js: 安装失败（请手动安装）")
        fi
    elif [ "$UPDATE" = true ]; then
        case "$PKG_MANAGER" in
            pacman) run_privileged pacman -S --noconfirm nodejs npm || true ;;
            apt)    run_privileged apt-get install --only-upgrade -y nodejs npm || true ;;
            dnf)    run_privileged dnf upgrade -y nodejs || true ;;
            zypper) run_privileged zypper update -y nodejs || true ;;
        esac
        ok "Node.js 已升级"
        REPORT+=("Node.js: 已升级")
    else
        ok "无需操作"
        REPORT+=("Node.js: 已安装（$NODE_VER）")
    fi
fi

# =============================================================
# 4) Git
# =============================================================
head "检查 Git"
GIT_INSTALLED=false
GIT_VER=""
if cmd_exists git; then
    GIT_INSTALLED=true
    GIT_VER="$(version_of git --version)"
    info "已安装版本：${GIT_VER:-未知}"
else
    info "未安装"
fi

install_git() {
    case "$PKG_MANAGER" in
        pacman) run_privileged pacman -S --noconfirm --needed git ;;
        apt)    run_privileged apt-get update -qq; run_privileged apt-get install -y git ;;
        dnf)    run_privileged dnf install -y git ;;
        zypper) run_privileged zypper install -y git ;;
    esac
}

if [ "$CHECK_ONLY" = true ]; then
    if [ "$GIT_INSTALLED" = true ]; then
        REPORT+=("Git: 已安装（$GIT_VER）")
        ok "Git 已安装（$GIT_VER）"
    else
        REPORT+=("Git: 缺失")
        warn "Git 未安装"
    fi
else
    if [ "$GIT_INSTALLED" = false ]; then
        echo "    正在安装 Git ..."
        if install_git; then
            ok "Git 安装完成"
            REPORT+=("Git: 已安装（本次安装）")
        else
            warn "Git 安装失败，请手动安装 git"
            REPORT+=("Git: 安装失败（请手动安装）")
        fi
    elif [ "$UPDATE" = true ]; then
        case "$PKG_MANAGER" in
            pacman) run_privileged pacman -S --noconfirm git || true ;;
            apt)    run_privileged apt-get install --only-upgrade -y git || true ;;
            dnf)    run_privileged dnf upgrade -y git || true ;;
            zypper) run_privileged zypper update -y git || true ;;
        esac
        ok "Git 已升级"
        REPORT+=("Git: 已升级")
    else
        ok "无需操作"
        REPORT+=("Git: 已安装（$GIT_VER）")
    fi
fi

# =============================================================
# 5) Claude Code
# =============================================================
if [ "$SKIP_CLAUDE" = true ]; then
    warn "已跳过 Claude Code（--skip-claude）"
    REPORT+=("Claude Code: 已跳过（--skip-claude）")
else
    head "检查 Claude Code"
    CLAUDE_INSTALLED=false
    CLAUDE_VER=""
    if cmd_exists claude; then
        CLAUDE_INSTALLED=true
        CLAUDE_VER="$(version_of claude --version)"
        info "已安装版本：${CLAUDE_VER:-未知}"
    else
        info "未安装"
    fi

    install_claude() {
        if ! cmd_exists npm; then
            warn "npm 不可用，无法安装 Claude Code。请先安装 Node.js 后重试。"
            return 1
        fi
        run_privileged npm install -g @anthropic-ai/claude-code
    }

    if [ "$CHECK_ONLY" = true ]; then
        if [ "$CLAUDE_INSTALLED" = true ]; then
            REPORT+=("Claude Code: 已安装（$CLAUDE_VER）")
            ok "Claude Code 已安装（$CLAUDE_VER）"
        else
            REPORT+=("Claude Code: 缺失")
            warn "Claude Code 未安装"
        fi
    else
        if [ "$CLAUDE_INSTALLED" = false ]; then
            echo "    正在安装 Claude Code ..."
            if install_claude; then
                ok "Claude Code 安装完成"
                REPORT+=("Claude Code: 已安装（本次安装）")
            else
                warn "Claude Code 安装失败，请手动执行：npm install -g @anthropic-ai/claude-code"
                REPORT+=("Claude Code: 安装失败（请手动安装）")
            fi
        elif [ "$UPDATE" = true ]; then
            echo "    正在升级 Claude Code ..."
            run_privileged npm install -g @anthropic-ai/claude-code || true
            ok "Claude Code 已升级"
            REPORT+=("Claude Code: 已升级")
        else
            ok "无需操作"
            REPORT+=("Claude Code: 已安装（$CLAUDE_VER）")
        fi
    fi
fi

# =============================================================
# 6) cc-switch
# =============================================================
head "检查 cc-switch"

resolve_ccswitch() {
    if cmd_exists cc-switch; then
        echo cc-switch
        return 0
    fi
    if cmd_exists cc-switch-bin; then
        echo cc-switch-bin
        return 0
    fi
    local p
    for p in "$HOME/.local/bin"/CC-Switch* "$HOME/Applications"/CC-Switch* /opt/cc-switch*; do
        if [ -e "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

CCSWITCH_INSTALLED=false
if resolve_ccswitch >/dev/null 2>&1; then
    CCSWITCH_INSTALLED=true
    info "已安装"
else
    info "未安装"
fi

install_ccswitch() {
    case "$PKG_MANAGER" in
        pacman)
            local helper
            helper="$(find_aur_helper || true)"
            if [ -n "$helper" ]; then
                "$helper" -S --noconfirm cc-switch-bin
            else
                warn "未检测到 AUR 助手（paru/yay），请手动安装："
                warn "  git clone https://aur.archlinux.org/cc-switch-bin.git"
                warn "  cd cc-switch-bin && makepkg -si"
                return 1
            fi
            ;;
        apt)
            local url tmp
            url="$(github_latest_asset farion1231/cc-switch 'CC-Switch-.*Linux.*\.deb')"
            if [ -z "$url" ]; then
                warn "无法获取 cc-switch 官方 .deb 下载地址"
                return 1
            fi
            tmp="$(mktemp --suffix=.deb)"
            download_with_retry "$url" "$tmp" || { warn "下载 cc-switch 失败"; rm -f "$tmp"; return 1; }
            run_privileged dpkg -i "$tmp" || run_privileged apt-get install -f -y
            rm -f "$tmp"
            ;;
        dnf)
            local url tmp
            url="$(github_latest_asset farion1231/cc-switch 'CC-Switch-.*Linux.*\.AppImage')"
            if [ -z "$url" ]; then
                warn "无法获取 cc-switch 官方 AppImage 下载地址"
                return 1
            fi
            mkdir -p "$HOME/.local/bin"
            tmp="$HOME/.local/bin/cc-switch"
            download_with_retry "$url" "$tmp" || { warn "下载 cc-switch 失败"; return 1; }
            chmod +x "$tmp"
            ;;
        zypper)
            warn "zypper 系统请手动安装 cc-switch（官方 AppImage 或 AUR）"
            return 1
            ;;
    esac
}

if [ "$CHECK_ONLY" = true ]; then
    if [ "$CCSWITCH_INSTALLED" = true ]; then
        REPORT+=("cc-switch: 已安装")
        ok "cc-switch 已安装"
    else
        REPORT+=("cc-switch: 缺失")
        warn "cc-switch 未安装"
    fi
else
    if [ "$CCSWITCH_INSTALLED" = false ]; then
        echo "    正在安装 cc-switch ..."
        if install_ccswitch; then
            ok "cc-switch 安装完成"
            REPORT+=("cc-switch: 已安装（本次安装）")
        else
            warn "cc-switch 安装失败，请手动安装"
            REPORT+=("cc-switch: 安装失败（请手动安装）")
        fi
    else
        ok "无需操作"
        REPORT+=("cc-switch: 已安装")
    fi
fi

# ---------- 收尾 ----------
head "环境报告"
for line in "${REPORT[@]}"; do
    info "$line"
done

if [ "$CHECK_ONLY" = true ]; then
    echo ""
    echo "检测完成。以上为各工具的版本状态。"
    exit 0
fi

# 打开 cc-switch 供粘贴 API Key
if [ "$CCSWITCH_INSTALLED" = true ]; then
    head "打开 cc-switch"
    local_cc="$(resolve_ccswitch || true)"
    if [ -n "$local_cc" ]; then
        nohup "$local_cc" >/dev/null 2>&1 &
        ok "已尝试打开 cc-switch"
    else
        warn "未找到 cc-switch，请从应用菜单手动打开。"
    fi
fi

echo ""
echo "================ 下一步 ================"
echo "1) 在 cc-switch 中点击「添加供应商」"
echo "2) 选择或填写 Base URL，粘贴你的 API Key"
echo "3) 切换到该供应商（自动写入 Claude Code 配置）"
echo "4) 运行 ./安装.sh 安装「AI 学习工作流」Obsidian 库"
echo "5) 打开 Obsidian，Claudian 后端选择 Claude Code 即可使用"
echo "========================================"
