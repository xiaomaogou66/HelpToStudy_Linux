#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  给 Obsidian 的 quark-sync 插件配一个「本机免认证」WebDAV 网关
#
#  为什么：OpenList / Alist 的 WebDAV 只支持 Basic 认证，插件就不得不把
#  用户名密码明文写在 .obsidian/plugins/quark-sync/data.json 里。
#  这里用 rclone 在 127.0.0.1 上再起一层「不认证」的 WebDAV，
#  夸克口令他继续以 obscured 密文放在 rclone.conf 里，
#  插件那边用户名/密码留空 —— 配置文件里不再有任何密码。
#
#  用法：
#     ./设置夸克同步网关.sh                    # 安装/更新（127.0.0.1:5245）
#     ./设置夸克同步网关.sh --port 5250        # 换端口
#     ./设置夸克同步网关.sh --remote "quark:AI学习工作流"
#     ./设置夸克同步网关.sh --status
#     ./设置夸克同步网关.sh --uninstall
#
#  前置：OpenList（或 Alist）已在跑，且 rclone.conf 里有指向它的 remote（默认 quark）。
# ---------------------------------------------------------------------------
set -euo pipefail

UNIT_NAME="rclone-webdav-obsidian.service"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_PATH="$UNIT_DIR/$UNIT_NAME"
PORT=5245
REMOTE="quark:AI学习工作流"
ACTION="install"

while [ $# -gt 0 ]; do
    case "$1" in
        --port)      PORT="${2:?--port 需要参数}"; shift 2 ;;
        --remote)    REMOTE="${2:?--remote 需要参数}"; shift 2 ;;
        --status)    ACTION="status"; shift ;;
        --uninstall) ACTION="uninstall"; shift ;;
        -h|--help)   sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "[错误] 未知参数：$1（--help 看用法）" >&2; exit 1 ;;
    esac
done

SERVICE_STATUS() { systemctl --user is-active "$UNIT_NAME" 2>/dev/null || true; }
PROBE() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X PROPFIND -H 'Depth: 0' "http://127.0.0.1:$PORT/" 2>/dev/null || true; }

case "$ACTION" in
status)
    echo "unit  : $UNIT_PATH"
    echo "状态  : $(SERVICE_STATUS)"
    echo "上游  : $(grep -oP 'serve webdav "\K[^"]+' "$UNIT_PATH" 2>/dev/null | head -1 || echo '（未安装）')"
    echo "探活  : http://127.0.0.1:$PORT/ → $(PROBE)"
    exit 0 ;;
uninstall)
    systemctl --user disable --now "$UNIT_NAME" 2>/dev/null || true
    rm -f "$UNIT_PATH"
    systemctl --user daemon-reload
    echo "已移除 $UNIT_NAME。记得把 quark-sync 的 WebDAV 地址改回 OpenList（如 http://127.0.0.1:5244/dav）。"
    exit 0 ;;
esac

# ---------- 依赖检查 ----------
command -v rclone >/dev/null || { echo "[错误] 没装 rclone：sudo pacman -S rclone" >&2; exit 1; }
command -v curl   >/dev/null || { echo "[错误] 没装 curl：sudo pacman -S curl" >&2; exit 1; }

REMOTE_NAME="${REMOTE%%:*}"
if ! rclone listremotes 2>/dev/null | grep -qx "$REMOTE_NAME:"; then
    echo "[错误] rclone 里没有名为 $REMOTE_NAME 的 remote。" >&2
    echo "       先配一个指向 OpenList 的 WebDAV remote：rclone config" >&2
    echo "       （url = http://127.0.0.1:5244/dav，user/pass 用 OpenList 里的账号）" >&2
    exit 1
fi

echo "==> 1. 生成 systemd 用户单元"
mkdir -p "$UNIT_DIR"
cat > "$UNIT_PATH" <<UNIT
[Unit]
Description=rclone WebDAV (loopback, no auth) for Obsidian vault -> Quark
Documentation=https://rclone.org/commands/rclone_serve_webdav/
After=network-online.target openlist.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone serve webdav "$REMOTE" \\
    --addr 127.0.0.1:$PORT \\
    --vfs-cache-mode writes \\
    --vfs-cache-max-age 1h \\
    --dir-cache-time 30s \\
    --log-level NOTICE
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
echo "    写入 $UNIT_PATH"

echo "==> 2. 启用并启动"
systemctl --user daemon-reload
systemctl --user enable "$UNIT_NAME" >/dev/null 2>&1 || true
systemctl --user restart "$UNIT_NAME"
for _ in $(seq 1 20); do [ "$(PROBE)" = "207" ] && break; sleep 0.5; done

code="$(PROBE)"
if [ "$code" = "207" ]; then
    echo "    ✅ 网关已就绪：http://127.0.0.1:$PORT/（PROPFIND → 207）"
else
    echo "    ⚠️  探活返回 $code，查日志：journalctl --user -u $UNIT_NAME -n 30" >&2
    exit 1
fi

cat <<TIP

==> 3. 去 Obsidian 里这样填（设置 → Quark Sync）

    WebDAV 地址 : http://127.0.0.1:$PORT
    用户名      : （留空）
    密码        : （留空）
    远端目录    : （留空，网关根就是 $REMOTE）
    同步模式    : 松散
    冲突策略    : 本地优先（local-priority，别用 diff3——它会往 JSON 里写冲突标记）
    同步 .obsidian 配置目录 : 关（无）
    过滤规则    : 加一条  **/.obsidian   排除

  为什么必须关掉配置目录同步：各设备的网关地址不同（手机连不到 127.0.0.1），
  同步 .obsidian 只会让两台机器的 appearance.json / community-plugins.json 互相覆盖。

  只监听 127.0.0.1，别的机器连不上；夸克口令仍是 rclone.conf 里的 obscured 密文。
TIP
