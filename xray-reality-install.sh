#!/usr/bin/env bash
# ==============================================================================
#  xray-reality-install.sh  —  VLESS + REALITY 一键安装（加强版 · v2）
#
#  为什么不用 233boy/v2ray 的默认值：
#    233boy 的脚本装的是 v2fly v2ray-core，默认协议是 VMess-TCP（无 TLS），
#    而且 v2fly 根本不支持 REALITY（REALITY 是 Xray 独有的）。
#    本脚本装 Xray，默认就是 VLESS + REALITY + Vision：
#      · 主动探测防护：探测者连上来看到的是 dest 那个真实站点的 TLS 证书
#      · 无需自己的域名/证书（只有一个公网 IP 也能用）
#      · Vision 流控降低 TLS-in-TLS 特征
#
#  两种出口，可单用也可同时开：
#    · 直连（默认）：出站 freedom，出口 = 本机机房 IP
#    · 链式（--chain）：主入口出站到上游（如 AaITR 住宅机隧道内网），出口 = 家宽 IP
#    · 加 --direct-port 再开一个直连入口 → 两条线并存：
#        「有 AaITR 时用主入口走家宽，没有 AaITR 时用直连入口照样能用」
#
#  设计原则（不碰你已有的东西）：
#    · 自己一个目录      /opt/xray
#    · 自己一个配置      /opt/xray/config.json
#    · 自己一个服务      xray-reality.service
#    · 不读写 /etc/v2ray、/usr/local/bin/v2ray、aaitr-link 等任何已有组件
#    · 已存在配置时默认拒绝覆盖，必须显式 --force
#
#  用法：
#    bash install.sh                                  # 443 直连，dest=www.microsoft.com
#    bash install.sh --port 8443                      # 换主入口端口
#    bash install.sh --dest www.apple.com:443         # 换伪装目标（SNI 自动跟随）
#    bash install.sh --tag "日本-REALITY"              # 节点显示名
#    bash install.sh --chain 10.88.123.2:33358:UUID   # 主入口走上游（家宽出口）
#    bash install.sh --chain 10.88.123.2:33358:UUID --direct-port 8443
#                                                     # 443 走家宽 + 8443 直连，两条并存
#    bash install.sh --check                          # 只看当前参数和状态，不改任何东西
#    bash install.sh --uninstall                      # 彻底卸载（只删本脚本装的东西）
#    bash install.sh --force                          # 覆盖重建（会重置 UUID/密钥）
# ==============================================================================
# 注意：这里故意不开 pipefail。
# `cmd | head -1`、`... | grep -q` 这类管道会让左侧进程收到 SIGPIPE（退出码 141），
# 开了 pipefail 会把正常的提前退出误判为失败，甚至让 if 条件错误地走 false 分支。
set -eu

APP_DIR=${APP_DIR:-/opt/xray}
SVC=${SVC:-xray-reality}
BIN=$APP_DIR/xray
CONF=$APP_DIR/config.json
META=$APP_DIR/meta.env
UNIT=/etc/systemd/system/$SVC.service

PORT=443
DIRECT_PORT=0          # 0 = 不额外开直连入口
DEST="www.microsoft.com:443"
SNI="www.microsoft.com"
TAG="REALITY"
CHAIN=""
FORCE=0

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_ylw=$'\033[33m'; c_cyn=$'\033[36m'; c_rst=$'\033[0m'
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s\n' "${c_grn}[OK]${c_rst} $*"; }
warn() { printf '%s\n' "${c_ylw}[!]${c_rst} $*"; }
die()  { printf '%s\n' "${c_red}[x]${c_rst} $*" >&2; exit 1; }

usage() {
  sed -n '3,45p' "$0" | sed 's/^# \{0,1\}//'
}

require_root() {
  [ "$(id -u)" = "0" ] || die "请用 root 执行（sudo bash install.sh ...）"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo 64 ;;
    aarch64|arm64) echo arm64-arm64 ;;
    *) die "不支持的架构: $(uname -m)" ;;
  esac
}

ensure_deps() {
  local need=()
  command -v curl  >/dev/null 2>&1 || need+=(curl)
  command -v unzip >/dev/null 2>&1 || need+=(unzip)
  [ ${#need[@]} -eq 0 ] && return 0
  say "安装依赖: ${need[*]}"
  if   command -v apt-get >/dev/null 2>&1; then apt-get update -qq && apt-get install -y -qq "${need[@]}" >/dev/null
  elif command -v dnf     >/dev/null 2>&1; then dnf install -y -q "${need[@]}" >/dev/null
  elif command -v yum     >/dev/null 2>&1; then yum install -y -q "${need[@]}" >/dev/null
  elif command -v apk     >/dev/null 2>&1; then apk add --no-cache "${need[@]}" >/dev/null
  else die "找不到包管理器，请先手动安装: ${need[*]}"
  fi
}

install_binary() {
  local arch; arch=$(detect_arch)
  say "下载 Xray: Xray-linux-${arch}.zip"
  mkdir -p "$APP_DIR"
  local tmpd; tmpd=$(mktemp -d)
  trap 'rm -rf "$tmpd"' RETURN
  curl -fsSL -o "$tmpd/xray.zip" \
    "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${arch}.zip" \
    || die "下载失败，请检查服务器的外网连通性"
  unzip -o -q "$tmpd/xray.zip" -d "$APP_DIR"
  chmod +x "$BIN"
  "$BIN" version 2>/dev/null | sed -n '1p'
}

load_or_gen_meta() {
  if [ -f "$META" ] && [ "$FORCE" = "0" ]; then
    # shellcheck disable=SC1090
    . "$META"
    PORT="${META_PORT:-$PORT}"
    DIRECT_PORT="${META_DIRECT_PORT:-0}"
    DEST="${META_DEST:-$DEST}"
    SNI="${META_SNI:-$SNI}"
    TAG="${META_TAG:-$TAG}"
    CHAIN="${META_CHAIN:-$CHAIN}"
    say "复用已有凭据（UUID=${UUID}）"
    return 0
  fi
  say "生成新的凭据"
  local out priv pub
  out=$("$BIN" x25519)
  priv=$(printf '%s\n' "$out" | awk -F': ' '/^PrivateKey/{print $2}' | tr -d '\r')
  pub=$(printf '%s\n' "$out" | awk -F': ' '/PublicKey|Password/{print $2}' | tr -d '\r')
  [ -n "$priv" ] && [ -n "$pub" ] || die "x25519 密钥生成失败"
  UUID=$("$BIN" uuid); UUID=$(printf '%s' "$UUID" | tr -d '\r')
  if command -v openssl >/dev/null 2>&1; then
    SHORT=$(openssl rand -hex 4)
  else
    SHORT=$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')
  fi
  PRIV=$priv; PUB=$pub
  mkdir -p "$APP_DIR"; chmod 700 "$APP_DIR"
  cat > "$META" <<EOF
# 由 xray-reality-install.sh 生成；删除本文件会重置所有凭据
UUID=$UUID
PRIV=$PRIV
PUB=$PUB
SHORT=$SHORT
META_PORT=$PORT
META_DIRECT_PORT=$DIRECT_PORT
META_DEST=$DEST
META_SNI=$SNI
META_TAG=$TAG
META_CHAIN=$CHAIN
EOF
  chmod 600 "$META"
}

mk_inbound() {  # $1=tag  $2=port
  cat <<EOF
    {
      "tag": "$1",
      "listen": "0.0.0.0",
      "port": $2,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID", "flow": "xtls-rprx-vision" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "$DEST",
          "serverNames": ["$SNI"],
          "privateKey": "$PRIV",
          "shortIds": ["$SHORT"]
        }
      }
    }
EOF
}

write_config() {
  local inbounds rule_json="" routing="" upstream=""

  inbounds="$(mk_inbound reality-in "$PORT")"

  if [ "$DIRECT_PORT" != "0" ] && [ "$DIRECT_PORT" != "" ]; then
    [ "$DIRECT_PORT" = "$PORT" ] && die "--direct-port 不能和 --port 相同"
    inbounds="$inbounds,
$(mk_inbound direct-in "$DIRECT_PORT")"
    rule_json='{ "type": "field", "inboundTag": ["direct-in"], "outboundTag": "direct" }'
  fi

  if [ -n "$CHAIN" ]; then
    local ch_host ch_port ch_uuid ch_aid
    ch_host=$(printf '%s' "$CHAIN" | cut -d: -f1)
    ch_port=$(printf '%s' "$CHAIN" | cut -d: -f2)
    ch_uuid=$(printf '%s' "$CHAIN" | cut -d: -f3)
    ch_aid=$(printf '%s' "$CHAIN" | cut -d: -f4); ch_aid=${ch_aid:-0}
    [ -n "$ch_host" ] && [ -n "$ch_port" ] && [ -n "$ch_uuid" ] \
      || die "--chain 格式应为 host:port:uuid[:alterId]"
    upstream=$(cat <<EOF
    ,{
      "tag": "upstream",
      "protocol": "vmess",
      "settings": { "vnext": [{ "address": "$ch_host", "port": $ch_port,
        "users": [{ "id": "$ch_uuid", "alterId": $ch_aid, "security": "auto" }] }] },
      "streamSettings": { "network": "tcp" }
    }
EOF
)
    local up_rule='{ "type": "field", "inboundTag": ["reality-in"], "outboundTag": "upstream" }'
    if [ -n "$rule_json" ]; then rule_json="$rule_json,
    $up_rule"; else rule_json="$up_rule"; fi
  fi

  if [ -n "$rule_json" ]; then
    routing="  \"routing\": { \"rules\": [
    $rule_json
  ] },
"
  fi

  cat > "$CONF" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
$inbounds
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom" }${upstream}
  ],
${routing}  "remark": "managed by xray-reality-install.sh"
}
EOF
  "$BIN" run -test -c "$CONF" >/dev/null 2>&1 || {
    say "--- 配置校验失败，原始输出 ---"
    "$BIN" run -test -c "$CONF" 2>&1 | tail -6
    die "配置无效（常见原因：dest 不可达 / 端口被占用 / --chain 上游地址写错）"
  }
  ok "配置校验通过"
}

write_unit() {
  cat > "$UNIT" <<'EOF'
[Unit]
Description=Xray VLESS+REALITY (managed by xray-reality-install.sh)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=__BIN__ run -c __CONF__
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
  sed -i "s|__BIN__|$BIN|g; s|__CONF__|$CONF|g" "$UNIT"
  systemctl daemon-reload
}

open_one_port() {
  local p=$1
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "$p/tcp" >/dev/null && ok "ufw 已放行 $p/tcp"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="$p/tcp" >/dev/null
    firewall-cmd --reload >/dev/null
    ok "firewalld 已放行 $p/tcp"
  else
    warn "未检测到活动防火墙（ufw/firewalld）；如云厂商有安全组，请自行放行 $p/tcp"
  fi
}

open_firewall() {
  open_one_port "$PORT"
  if [ "$DIRECT_PORT" != "0" ] && [ "$DIRECT_PORT" != "" ]; then open_one_port "$DIRECT_PORT"; fi
}

port_in_use() {  # $1=port
  ss -lntp 2>/dev/null | awk -v p=":$1 " '$4 ~ p' | grep -q .
}

check_ports() {
  local p
  for p in "$PORT" "$DIRECT_PORT"; do
    [ "$p" = "0" ] && continue
    if port_in_use "$p" && ! systemctl is-active --quiet "$SVC" 2>/dev/null; then
      die "端口 $p 已被其它进程占用"
    fi
  done
}

start_service() {
  systemctl enable "$SVC" >/dev/null 2>&1 || true
  systemctl restart "$SVC"
  sleep 2
  systemctl is-active --quiet "$SVC" || {
    journalctl -u "$SVC" -n 20 --no-pager
    die "服务启动失败，日志见上"
  }
  ok "服务已启动: $SVC"
}

mk_link() {  # $1=port  $2=name
  printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#%s' \
    "$UUID" "$WAN_IP" "$1" "$SNI" "$PUB" "$SHORT" "$2"
}

print_all() {
  WAN_IP=$(curl -fsS --max-time 8 -4 https://api.ipify.org 2>/dev/null \
        || curl -fsS --max-time 8 -4 https://ifconfig.me 2>/dev/null || echo "你的公网IP")
  local main_desc
  if [ -n "$CHAIN" ]; then main_desc="出口=上游家宽（$CHAIN）"; else main_desc="出口=本机机房"; fi

  echo
  say "${c_cyn}================ 客户端参数 ================${c_rst}"
  printf '  地址      : %s\n' "$WAN_IP"
  printf '  UUID      : %s\n' "$UUID"
  printf '  flow      : xtls-rprx-vision ｜ 传输: tcp ｜ 安全: reality\n'
  printf '  SNI       : %s\n' "$SNI"
  printf '  公钥(pbk) : %s\n' "$PUB"
  printf '  shortId   : %s\n' "$SHORT"
  echo
  say "${c_cyn}================ vless:// 链接 ================${c_rst}"
  printf '  [主入口 %s] %s\n' "$PORT" "$main_desc"
  printf '  %s\n' "$(mk_link "$PORT" "${TAG}-${PORT}")"
  if [ "$DIRECT_PORT" != "0" ] && [ "$DIRECT_PORT" != "" ]; then
    echo
    printf '  [直连入口 %s] 出口=本机机房（不依赖上游）\n' "$DIRECT_PORT"
    printf '  %s\n' "$(mk_link "$DIRECT_PORT" "${TAG}-direct-${DIRECT_PORT}")"
  fi
  echo
  say "复制上面每行 vless:// 到 v2rayN → 从剪贴板导入。"
}

do_check() {
  [ -f "$META" ] || die "尚未安装（找不到 $META）"
  # shellcheck disable=SC1090
  . "$META"
  PORT="${META_PORT:-443}"; DIRECT_PORT="${META_DIRECT_PORT:-0}"
  DEST="${META_DEST:-}"; SNI="${META_SNI:-}"; TAG="${META_TAG:-REALITY}"; CHAIN="${META_CHAIN:-}"
  say "主入口端口 : $PORT"
  if [ "$DIRECT_PORT" = "0" ]; then say "直连端口   : （未启用）"; else say "直连端口   : $DIRECT_PORT"; fi
  say "dest/SNI   : $DEST / $SNI"
  say "节点名     : $TAG"
  say "链式上游   : ${CHAIN:-（无，直连出网）}"
  say "服务状态   : $(systemctl is-active "$SVC" 2>/dev/null || echo unknown)"
  say "监听       :"
  ss -lntp 2>/dev/null | awk -v a=":$PORT " -v b=":$DIRECT_PORT " '($4 ~ a) || ($4 ~ b)' | sed 's/^/    /'
  print_all
}

do_uninstall() {
  if [ -f "$META" ]; then
    # shellcheck disable=SC1090
    . "$META"
    PORT="${META_PORT:-$PORT}"; DIRECT_PORT="${META_DIRECT_PORT:-0}"
  fi
  say "卸载中（只删本脚本装的东西）…"
  systemctl disable --now "$SVC" >/dev/null 2>&1 || true
  rm -f "$UNIT"
  systemctl daemon-reload >/dev/null 2>&1 || true
  if command -v ufw >/dev/null 2>&1; then
    ufw delete allow "$PORT/tcp" >/dev/null 2>&1 || true
    if [ "$DIRECT_PORT" != "0" ]; then ufw delete allow "$DIRECT_PORT/tcp" >/dev/null 2>&1 || true; fi
  fi
  rm -rf "$APP_DIR"
  ok "已卸载：$SVC / $APP_DIR / ufw 规则（$PORT/tcp）"
  say "已有的 v2ray / aaitr-link 等组件未受影响。"
}

# ---------------------------- 参数解析 --------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --port)        PORT="${2:?}"; shift 2 ;;
    --direct-port) DIRECT_PORT="${2:?}"; shift 2 ;;
    --dest)        DEST="${2:?}"; SNI="${2%%:*}"; shift 2 ;;
    --sni)         SNI="${2:?}"; shift 2 ;;
    --tag)         TAG="${2:?}"; shift 2 ;;
    --chain)       CHAIN="${2:?}"; shift 2 ;;
    --force)       FORCE=1; shift ;;
    --check)       require_root; do_check; exit 0 ;;
    --uninstall)   require_root; do_uninstall; exit 0 ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "未知参数: $1（--help 查看用法）" ;;
  esac
done

# ---------------------------- 主流程 ----------------------------------------
require_root

if [ -f "$CONF" ] && [ "$FORCE" = "0" ]; then
  warn "检测到已有配置: $CONF"
  say  "为保护正在运行的节点，本次不覆盖。"
  say  "  · 只想查看参数: bash install.sh --check"
  say  "  · 确实要重建（会重置 UUID/密钥）: bash install.sh --force"
  exit 1
fi

check_ports
ensure_deps
install_binary
load_or_gen_meta
write_config
write_unit
open_firewall
start_service
print_all

say "${c_grn}完成。${c_rst} 服务名: $SVC ｜ 配置: $CONF ｜ 卸载: bash install.sh --uninstall"
say "${c_ylw}提示：${c_rst}dest 默认借用 www.microsoft.com 的 TLS 握手；如果该站点被干扰，换一个即可："
say "      bash install.sh --force --dest www.apple.com:443"
