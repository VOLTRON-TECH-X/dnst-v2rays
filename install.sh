#!/bin/bash
# ================================================================
# DNSTT + V2RAY (XRAY) BACKEND — FINAL
# DNSTT pekee, backend ni V2Ray pekee (hakuna SSH)
# ================================================================

C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_UL=$'\033[4m'
C_RED=$'\033[38;5;196m'; C_GREEN=$'\033[38;5;46m'; C_YELLOW=$'\033[38;5;226m'
C_BLUE=$'\033[38;5;39m'; C_PURPLE=$'\033[38;5;135m'; C_CYAN=$'\033[38;5;51m'
C_WHITE=$'\033[38;5;255m'; C_GRAY=$'\033[38;5;245m'; C_ORANGE=$'\033[38;5;208m'

# ============ VIGEZO ============
DESEC_TOKEN="3WxD4Hkiu5VYBLWVizVhf1rzyKbz"
DESEC_DOMAIN="voltrontechtx.shop"

DB_DIR="/etc/dnstt-v2ray"
DB_FILE="$DB_DIR/users.db"
LOGS_DIR="$DB_DIR/logs"
CONFIG_DIR="$DB_DIR/config"
BANDWIDTH_DIR="$DB_DIR/bandwidth"
BANNER_DIR="$DB_DIR/banners"
DNSTT_KEYS_DIR="$DB_DIR/dnstt"
MTU_CONFIG="$CONFIG_DIR/mtu"
INSTALL_FLAG_FILE="$DB_DIR/.install"

# ============ DNSTT ============
DNSTT_SERVICE_FILE="/etc/systemd/system/dnstt.service"
DNSTT_BINARY="/usr/local/bin/dnstt-server"
DNSTT_CLIENT="/usr/local/bin/dnstt-client"
DNSTT_CONFIG_FILE="$DB_DIR/dnstt_info.conf"

# ============ V2RAY (XRAY) ============
V2RAY_SERVICE_FILE="/etc/systemd/system/v2ray-dnstt.service"
V2RAY_BIN="/usr/local/bin/xray"
V2RAY_CONFIG_DIR="$DB_DIR/v2ray"
V2RAY_CONFIG_FILE="$V2RAY_CONFIG_DIR/config.json"
V2RAY_INFO_FILE="$DB_DIR/v2ray_info.conf"
V2RAY_UUID_FILE="$V2RAY_CONFIG_DIR/uuid.txt"
V2RAY_PORT="10086"
V2RAY_PROTOCOL="vless"

_APT_UPDATED=0
ff_apt_update() {
    (( _APT_UPDATED )) && return
    DEBIAN_FRONTEND=noninteractive apt-get update 2>/dev/null || true
    _APT_UPDATED=1
}
ff_apt_install() { ff_apt_update; DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Use-Pty=0 install "$@"; }
ff_apt_purge() { DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Use-Pty=0 purge "$@"; }

press_enter() { echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to continue..." && read -r; }
get_current_mtu() { [ -f "$MTU_CONFIG" ] && cat "$MTU_CONFIG" || echo "512"; }

# ============================================================
# BANNER
# ============================================================
show_banner() {
    [[ -t 1 ]] && clear
    local os_name=$(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || echo "Linux")
    local up=$(uptime -p 2>/dev/null | sed 's/up //' || echo "unknown")
    local ram=$(free -m | awk '/^Mem:/{if($2>0){printf "%.2f", $3*100/$2}else{print "0.00"}}')
    local load=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    echo
    echo -e "${C_PURPLE}   DNSTT + V2RAY (XRAY) BACKEND ${C_RESET}${C_DIM}| Final Edition${C_RESET}"
    echo -e "${C_BLUE}   ─────────────────────────────────────────────────────────${C_RESET}"
    printf "   ${C_GRAY}%-10s${C_RESET} %-20s ${C_GRAY}|${C_RESET} %s\n" "OS" "$os_name" "Uptime: $up"
    printf "   ${C_GRAY}%-10s${C_RESET} %-20s ${C_GRAY}|${C_RESET} %s\n" "Memory" "${ram}% Used" "Load: ${C_GREEN}${load}${C_RESET}"
    echo -e "${C_BLUE}   ─────────────────────────────────────────────────────────${C_RESET}"
}

# ============================================================
# V2RAY (XRAY) BACKEND
# ============================================================
download_v2ray_binary() {
    local arch=$(uname -m) url
    case "$arch" in
        x86_64|amd64)  url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" ;;
        aarch64|arm64) url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip" ;;
        armv7l)        url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm32-v7a.zip" ;;
        *) echo -e "${C_RED}❌ Arch unsupported: $arch${C_RESET}"; return 1 ;;
    esac
    local tmp="/tmp/xray.zip"
    curl -sL "$url" -o "$tmp" || { echo -e "${C_RED}❌ Download fail${C_RESET}"; return 1; }
    command -v unzip &>/dev/null || ff_apt_install unzip >/dev/null 2>&1
    rm -rf /tmp/xray-extract; mkdir -p /tmp/xray-extract
    unzip -o "$tmp" -d /tmp/xray-extract >/dev/null 2>&1
    install -m 755 /tmp/xray-extract/xray "$V2RAY_BIN" || { echo -e "${C_RED}❌ Install fail${C_RESET}"; return 1; }
    rm -rf /tmp/xray-extract "$tmp"
    echo -e "${C_GREEN}✅ V2Ray binary tayari${C_RESET}"
}

generate_v2ray_uuid() {
    mkdir -p "$V2RAY_CONFIG_DIR"
    local uuid
    [[ -x "$V2RAY_BIN" ]] && uuid=$("$V2RAY_BIN" uuid 2>/dev/null)
    [[ -z "$uuid" ]] && uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
    [[ -z "$uuid" ]] && uuid=$(head /dev/urandom | tr -dc 'a-f0-9' | head -c 32 | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/')
    echo "$uuid" > "$V2RAY_UUID_FILE"; chmod 600 "$V2RAY_UUID_FILE"
    echo "$uuid"
}

write_v2ray_config() {
    mkdir -p "$V2RAY_CONFIG_DIR"
    local uuid="$1" proto="${2:-vless}"
    case "$proto" in
        vless)
            cat > "$V2RAY_CONFIG_FILE" <<EOF
{
  "log": { "loglevel": "warning", "access": "none", "error": "$LOGS_DIR/v2ray-error.log" },
  "inbounds": [{
    "listen": "127.0.0.1",
    "port": $V2RAY_PORT,
    "protocol": "vless",
    "settings": { "clients": [{ "id": "$uuid", "flow": "" }], "decryption": "none" },
    "streamSettings": { "network": "tcp", "security": "none" },
    "tag": "dnstt-inbound"
  }],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
EOF
            ;;
        vmess)
            cat > "$V2RAY_CONFIG_FILE" <<EOF
{
  "log": { "loglevel": "warning", "access": "none", "error": "$LOGS_DIR/v2ray-error.log" },
  "inbounds": [{
    "listen": "127.0.0.1",
    "port": $V2RAY_PORT,
    "protocol": "vmess",
    "settings": { "clients": [{ "id": "$uuid", "alterId": 0 }] },
    "streamSettings": { "network": "tcp", "security": "none" },
    "tag": "dnstt-inbound"
  }],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
EOF
            ;;
        trojan)
            cat > "$V2RAY_CONFIG_FILE" <<EOF
{
  "log": { "loglevel": "warning", "access": "none", "error": "$LOGS_DIR/v2ray-error.log" },
  "inbounds": [{
    "listen": "127.0.0.1",
    "port": $V2RAY_PORT,
    "protocol": "trojan",
    "settings": { "clients": [{ "password": "$uuid" }] },
    "streamSettings": { "network": "tcp", "security": "none" },
    "tag": "dnstt-inbound"
  }],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
EOF
            ;;
        *) echo -e "${C_RED}❌ Protocol unsupported${C_RESET}"; return 1 ;;
    esac
    chmod 600 "$V2RAY_CONFIG_FILE"
}

create_v2ray_service() {
    cat > "$V2RAY_SERVICE_FILE" <<EOF
[Unit]
Description=V2Ray (Xray) — DNSTT Backend
After=network.target
Before=dnstt.service

[Service]
Type=simple
User=root
ExecStart=$V2RAY_BIN run -c $V2RAY_CONFIG_FILE
Restart=always
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable v2ray-dnstt.service >/dev/null 2>&1
}

save_v2ray_info() {
    printf 'V2RAY_UUID="%s"\nV2RAY_PORT="%s"\nV2RAY_PROTOCOL="%s"\n' "$1" "$2" "$3" > "$V2RAY_INFO_FILE"
}

setup_v2ray_backend() {
    echo -e "\n${C_BLUE}🔷 V2Ray (Xray) backend setup...${C_RESET}"

    if [ -f "$V2RAY_SERVICE_FILE" ]; then
        echo -e "  ${C_GREEN}✅ V2Ray tayari imesakinishwa${C_RESET}"
        source "$V2RAY_INFO_FILE" 2>/dev/null
        systemctl is-active --quiet v2ray-dnstt.service || systemctl start v2ray-dnstt.service
        return 0
    fi

    echo -e "  ${C_BLUE}[1/4] Dependencies...${C_RESET}"
    ff_apt_install curl unzip >/dev/null 2>&1

    echo -e "  ${C_BLUE}[2/4] Download V2Ray...${C_RESET}"
    download_v2ray_binary || return 1

    echo -e "  ${C_BLUE}[3/4] Chagua protocol:${C_RESET}"
    echo -e "    ${C_GREEN}1)${C_RESET} VLESS   ${C_DIM}(inapendekezwa)${C_RESET}"
    echo -e "    ${C_GREEN}2)${C_RESET} VMess"
    echo -e "    ${C_GREEN}3)${C_RESET} Trojan"
    read -p "  👉 [1]: " pc; pc=${pc:-1}
    case $pc in 2) V2RAY_PROTOCOL="vmess";; 3) V2RAY_PROTOCOL="trojan";; *) V2RAY_PROTOCOL="vless";; esac

    echo -e "  ${C_BLUE}[4/4] UUID + port...${C_RESET}"
    local uuid=$(generate_v2ray_uuid)
    read -p "  👉 Listen port [${V2RAY_PORT}]: " np
    [[ -n "$np" && "$np" =~ ^[0-9]+$ ]] && V2RAY_PORT="$np"

    write_v2ray_config "$uuid" "$V2RAY_PROTOCOL"
    save_v2ray_info "$uuid" "$V2RAY_PORT" "$V2RAY_PROTOCOL"
    create_v2ray_service
    systemctl start v2ray-dnstt.service
    sleep 2

    if systemctl is-active --quiet v2ray-dnstt.service; then
        echo -e "  ${C_GREEN}✅ V2Ray: 127.0.0.1:$V2RAY_PORT ($V2RAY_PROTOCOL)${C_RESET}"
        echo -e "  ${C_CYAN}UUID${C_RESET} : ${C_YELLOW}$uuid${C_RESET}"
        return 0
    else
        echo -e "  ${C_RED}❌ V2Ray fail${C_RESET}"
        journalctl -u v2ray-dnstt.service -n 15 --no-pager
        return 1
    fi
}

uninstall_v2ray_backend() {
    systemctl stop v2ray-dnstt.service 2>/dev/null
    systemctl disable v2ray-dnstt.service 2>/dev/null
    rm -f "$V2RAY_SERVICE_FILE" "$V2RAY_BIN" "$V2RAY_INFO_FILE"
    rm -rf "$V2RAY_CONFIG_DIR"
    systemctl daemon-reload
}

v2ray_backend_menu() {
    while true; do
        clear; show_banner
        source "$V2RAY_INFO_FILE" 2>/dev/null
        local st=""; systemctl is-active --quiet v2ray-dnstt.service 2>/dev/null && st="${C_GREEN}● RUNNING${C_RESET}" || st="${C_RED}● STOPPED${C_RESET}"

        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}              🔷 V2RAY BACKEND SETTINGS${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
        echo -e "  ${C_CYAN}Status${C_RESET}   : $st"
        echo -e "  ${C_CYAN}Protocol${C_RESET} : ${C_YELLOW}${V2RAY_PROTOCOL}${C_RESET}"
        echo -e "  ${C_CYAN}Listen${C_RESET}   : 127.0.0.1:${V2RAY_PORT}"
        echo -e "  ${C_CYAN}UUID${C_RESET}     : ${C_YELLOW}${V2RAY_UUID}${C_RESET}\n"
        echo -e "  ${C_GREEN}1)${C_RESET} Restart V2Ray"
        echo -e "  ${C_GREEN}2)${C_RESET} View config"
        echo -e "  ${C_GREEN}3)${C_RESET} View logs"
        echo -e "  ${C_GREEN}4)${C_RESET} Change UUID"
        echo -e "  ${C_GREEN}5)${C_RESET} Change port"
        echo -e "  ${C_GREEN}6)${C_RESET} Change protocol"
        echo -e "  ${C_RED}0)${C_RESET} Return"
        read -p "👉 Choice: " c
        case $c in
            1) systemctl restart v2ray-dnstt.service; sleep 2; systemctl is-active --quiet v2ray-dnstt.service && echo "✅" || echo "❌"; press_enter ;;
            2) clear; cat "$V2RAY_CONFIG_FILE" 2>/dev/null; press_enter ;;
            3) clear; journalctl -u v2ray-dnstt.service -n 40 --no-pager; press_enter ;;
            4)
                read -p "New UUID (Enter=auto): " nu
                [[ -z "$nu" ]] && nu=$(generate_v2ray_uuid)
                echo "$nu" > "$V2RAY_UUID_FILE"
                write_v2ray_config "$nu" "$V2RAY_PROTOCOL"
                save_v2ray_info "$nu" "$V2RAY_PORT" "$V2RAY_PROTOCOL"
                systemctl restart v2ray-dnstt.service
                echo -e "${C_GREEN}✅ UUID: $nu${C_RESET}"; press_enter ;;
            5)
                read -p "New port [${V2RAY_PORT}]: " np
                [[ ! "$np" =~ ^[0-9]+$ ]] && { echo "❌"; press_enter; continue; }
                V2RAY_PORT="$np"
                write_v2ray_config "$V2RAY_UUID" "$V2RAY_PROTOCOL"
                save_v2ray_info "$V2RAY_UUID" "$V2RAY_PORT" "$V2RAY_PROTOCOL"
                [ -f "$DNSTT_SERVICE_FILE" ] && {
                    sed -i "s|127.0.0.1:[0-9]*|127.0.0.1:$V2RAY_PORT|g" "$DNSTT_SERVICE_FILE"
                    systemctl daemon-reload; systemctl restart dnstt.service
                }
                systemctl restart v2ray-dnstt.service
                echo -e "${C_GREEN}✅ Port: $V2RAY_PORT${C_RESET}"; press_enter ;;
            6)
                echo -e "  1) VLESS  2) VMess  3) Trojan"
                read -p "  👉 [1]: " pc; pc=${pc:-1}
                case $pc in 2) V2RAY_PROTOCOL="vmess";; 3) V2RAY_PROTOCOL="trojan";; *) V2RAY_PROTOCOL="vless";; esac
                write_v2ray_config "$V2RAY_UUID" "$V2RAY_PROTOCOL"
                save_v2ray_info "$V2RAY_UUID" "$V2RAY_PORT" "$V2RAY_PROTOCOL"
                systemctl restart v2ray-dnstt.service
                echo -e "${C_GREEN}✅ Protocol: $V2RAY_PROTOCOL${C_RESET}"; press_enter ;;
            0) return ;;
        esac
    done
}

# ============================================================
# SPEED BOOSTERS
# ============================================================
_detect_ifaces() {
    ip -o -4 route show default 2>/dev/null | awk '{print $5}' | sort -u
}

_apply_tfo_bbr() {
    modprobe tcp_bbr 2>/dev/null
    modprobe sch_fq 2>/dev/null
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_notsent_lowat=16384 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_ecn=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_time=60 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_intvl=10 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fin_timeout=15 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
}

apply_booster_standard_ultimate() {
    echo -e "\n${C_BLUE}⚡ STANDARD (1000x) — buffer 512${C_RESET}"
    _apply_tfo_bbr
    sysctl -w net.ipv4.udp_rmem_min=512 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=512 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_early_demux=1 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=1073741824 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=1073741824 >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=1000000 >/dev/null 2>&1
    sysctl -w net.core.somaxconn=524288 >/dev/null 2>&1
    ulimit -n 10485760 2>/dev/null
    echo -e "${C_GREEN}✅ 1000x${C_RESET}"
}

apply_booster_medium_ultimate() {
    echo -e "\n${C_BLUE}⚡ MEDIUM (2000x) — buffer 5120${C_RESET}"
    _apply_tfo_bbr
    sysctl -w net.ipv4.udp_rmem_min=5120 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=5120 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_early_demux=1 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=2147483648 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=2147483648 >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=2000000 >/dev/null 2>&1
    sysctl -w net.core.somaxconn=1048576 >/dev/null 2>&1
    ulimit -n 20971520 2>/dev/null
    echo -e "${C_GREEN}✅ 2000x${C_RESET}"
}

apply_booster_high_ultimate() {
    echo -e "\n${C_BLUE}⚡ HIGH (3000x) — buffer 51200${C_RESET}"
    _apply_tfo_bbr
    sysctl -w net.ipv4.udp_rmem_min=51200 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=51200 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_early_demux=1 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=4294967296 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=4294967296 >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=4000000 >/dev/null 2>&1
    sysctl -w net.core.somaxconn=2097152 >/dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_max=160000000 >/dev/null 2>&1
    ulimit -n 41943040 2>/dev/null
    echo -e "${C_GREEN}✅ 3000x${C_RESET}"
}

apply_booster_ultra_ultimate() {
    echo -e "\n${C_BLUE}🚀 ULTRA (5000x) — buffer 512000${C_RESET}"
    _apply_tfo_bbr
    sysctl -w net.ipv4.udp_rmem_min=512000 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=512000 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_early_demux=1 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=8589934592 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=8589934592 >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=6000000 >/dev/null 2>&1
    sysctl -w net.core.somaxconn=4194304 >/dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_max=320000000 >/dev/null 2>&1
    ulimit -n 83886080 2>/dev/null
    for i in /sys/class/net/*/queues/*/rps_cpus; do [[ -f "$i" ]] && echo ffffffff > "$i" 2>/dev/null; done
    echo -e "${C_GREEN}✅ 5000x${C_RESET}"
}

apply_booster_extreme_ultimate() {
    echo -e "\n${C_BLUE}💥 EXTREME (10000x) — buffer 5120000${C_RESET}"
    _apply_tfo_bbr
    sysctl -w net.ipv4.udp_rmem_min=5120000 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=5120000 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_early_demux=1 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=17179869184 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=17179869184 >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=10000000 >/dev/null 2>&1
    sysctl -w net.core.somaxconn=8388608 >/dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_max=640000000 >/dev/null 2>&1
    ulimit -n 167772160 2>/dev/null
    for i in /sys/class/net/*/queues/*/rps_cpus; do [[ -f "$i" ]] && echo ffffffff > "$i" 2>/dev/null; done
    echo -e "${C_GREEN}✅ 10000x${C_RESET}"
}

apply_booster_ultra_plus() {
    echo -e "\n${C_BLUE}🚀 ULTRA PLUS — buffer 6291456${C_RESET}"
    _apply_tfo_bbr
    sysctl -w net.ipv4.udp_rmem_min=6291456 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=6291456 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_early_demux=1 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=805306368 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=805306368 >/dev/null 2>&1
    echo -e "${C_GREEN}✅ Ultra+${C_RESET}"
}

apply_booster_extreme_plus() {
    echo -e "\n${C_BLUE}💥 EXTREME PLUS — buffer 12582912${C_RESET}"
    _apply_tfo_bbr
    sysctl -w net.ipv4.udp_rmem_min=12582912 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=12582912 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_early_demux=1 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=1073741824 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=1073741824 >/dev/null 2>&1
    echo -e "${C_GREEN}✅ Extreme+${C_RESET}"
}

dnstt_speed_menu() {
    while true; do
        clear; show_banner
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}                 ⚡ DNSTT SPEED BOOSTERS${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
        echo -e "  ${C_GREEN}[1]${C_RESET} Standard   (1000x)   ${C_DIM}→ buffer 512${C_RESET}"
        echo -e "  ${C_GREEN}[2]${C_RESET} Medium     (2000x)   ${C_DIM}→ buffer 5120${C_RESET}"
        echo -e "  ${C_GREEN}[3]${C_RESET} High       (3000x)   ${C_DIM}→ buffer 51200${C_RESET}"
        echo -e "  ${C_GREEN}[4]${C_RESET} ${C_BOLD}Ultra      (5000x)${C_RESET}   ${C_YELLOW}★ buffer 512000${C_RESET}"
        echo -e "  ${C_GREEN}[5]${C_RESET} Extreme    (10000x)  ${C_DIM}→ buffer 5120000${C_RESET}"
        echo -e "  ${C_GREEN}[6]${C_RESET} Ultra Plus (768MB)   ${C_DIM}→ buffer 6291456${C_RESET}"
        echo -e "  ${C_GREEN}[7]${C_RESET} Extreme+   (1GB)     ${C_DIM}→ buffer 12582912${C_RESET}"
        echo ""
        echo -e "  ${C_CYAN}ℹ️  All levels: TCP Fast Open + BBR + fq${C_RESET}"
        echo ""
        echo -e "  ${C_YELLOW}[8]${C_RESET} View Current Settings"
        echo -e "  ${C_RED}[9]${C_RESET} Reset to Default"
        echo ""
        echo -e "  ${C_RED}[0]${C_RESET} Return"
        read -p "👉 Choice: " c
        case $c in
            1) apply_booster_standard_ultimate; press_enter ;;
            2) apply_booster_medium_ultimate; press_enter ;;
            3) apply_booster_high_ultimate; press_enter ;;
            4) apply_booster_ultra_ultimate; press_enter ;;
            5) apply_booster_extreme_ultimate; press_enter ;;
            6) apply_booster_ultra_plus; press_enter ;;
            7) apply_booster_extreme_plus; press_enter ;;
            8) clear; show_banner
               echo -e "\n  TCP CC:   $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
               echo -e "  TFO:      $(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null) (3=on)"
               echo -e "  QDisc:    $(sysctl -n net.core.default_qdisc 2>/dev/null)"
               echo -e "  UDP rmem: $(sysctl -n net.ipv4.udp_rmem_min 2>/dev/null)"
               echo -e "  UDP wmem: $(sysctl -n net.ipv4.udp_wmem_min 2>/dev/null)"
               echo -e "  rmem_max: $(sysctl -n net.core.rmem_max 2>/dev/null)"
               echo -e "  wmem_max: $(sysctl -n net.core.wmem_max 2>/dev/null)"
               press_enter ;;
            9) sysctl -w net.core.rmem_max=212992 >/dev/null 2>&1
               sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
               sysctl -w net.ipv4.tcp_fastopen=1 >/dev/null 2>&1
               sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1
               echo "✅ Reset"; press_enter ;;
            0) return ;;
        esac
    done
}

# ============================================================
# DNSTT CORE
# ============================================================
download_dnstt_binary() {
    local arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        curl -sL "https://dnstt.network/dnstt-server-linux-amd64" -o "$DNSTT_BINARY"
        curl -sL "https://dnstt.network/dnstt-client-linux-amd64" -o "$DNSTT_CLIENT"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        curl -sL "https://dnstt.network/dnstt-server-linux-arm64" -o "$DNSTT_BINARY"
        curl -sL "https://dnstt.network/dnstt-client-linux-arm64" -o "$DNSTT_CLIENT"
    else echo "❌ Unsupported: $arch"; return 1; fi
    chmod +x "$DNSTT_BINARY" "$DNSTT_CLIENT"
    echo -e "${C_GREEN}✅ Binaries${C_RESET}"
}

mtu_selection_during_install() {
    echo -e "\n${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_PURPLE}                 📡 MTU CONFIGURATION${C_RESET}"
    echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
    echo -e "  ${C_GREEN}1)${C_RESET} 512   ${C_DIM}(default)${C_RESET}"
    echo -e "  ${C_GREEN}2)${C_RESET} 900   ${C_DIM}(stable)${C_RESET}"
    echo -e "  ${C_GREEN}3)${C_RESET} 1200  ${C_DIM}(balanced)${C_RESET}"
    echo -e "  ${C_GREEN}4)${C_RESET} 1400  ${C_DIM}(fast)${C_RESET}"
    echo -e "  ${C_GREEN}5)${C_RESET} 1500  ${C_DIM}(max)${C_RESET}"
    echo -e "  ${C_GREEN}6)${C_RESET} Custom ${C_DIM}(512-1500)${C_RESET}"
    echo ""
    read -p "👉 Choice [1]: " mtu_choice; mtu_choice=${mtu_choice:-1}
    case $mtu_choice in
        1) MTU=512 ;;
        2) MTU=900 ;;
        3) MTU=1200 ;;
        4) MTU=1400 ;;
        5) MTU=1500 ;;
        6) read -p "👉 MTU: " cm; if [[ "$cm" =~ ^[0-9]+$ ]] && [ "$cm" -ge 512 ] && [ "$cm" -le 1500 ]; then MTU=$cm; else MTU=512; fi ;;
        *) MTU=512 ;;
    esac
    mkdir -p "$CONFIG_DIR"; echo "$MTU" > "$MTU_CONFIG"
    echo -e "\n${C_GREEN}✅ MTU set to: $MTU${C_RESET}"
}

generate_keys() {
    mkdir -p "$DNSTT_KEYS_DIR"; cd "$DNSTT_KEYS_DIR"; rm -f server.key server.pub
    "$DNSTT_BINARY" -gen-key -privkey-file server.key -pubkey-file server.pub 2>/dev/null || {
        openssl rand -hex 32 > server.key
        cat server.key | sha256sum | awk '{print $1}' > server.pub
    }
    chmod 600 server.key; chmod 644 server.pub
    PUBLIC_KEY=$(cat server.pub)
}

setup_domain() {
    echo -e "\n${C_BLUE}🌐 Domain config${C_RESET}\n"
    echo -e "  ${C_GREEN}1)${C_RESET} Custom domain"
    echo -e "  ${C_GREEN}2)${C_RESET} Auto-generate with deSEC"
    read -p "👉 [2]: " opt; opt=${opt:-2}
    if [[ "$opt" == "2" ]]; then
        local rand=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 3)
        local ns="ns-$rand"; local tun="tun-$rand"
        local ip=$(curl -s -4 icanhazip.com)
        curl -s -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" -H "Authorization: Token $DESEC_TOKEN" -H "Content-Type: application/json" --data "[{\"subname\":\"$ns\",\"type\":\"A\",\"ttl\":3600,\"records\":[\"$ip\"]}]" >/dev/null 2>&1
        local r=$(curl -s -w "%{http_code}" -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" -H "Authorization: Token $DESEC_TOKEN" -H "Content-Type: application/json" --data "[{\"subname\":\"$tun\",\"type\":\"NS\",\"ttl\":3600,\"records\":[\"$ns.$DESEC_DOMAIN.\"]}]")
        [[ "${r: -3}" -eq 201 ]] && { DOMAIN="$tun.$DESEC_DOMAIN"; echo -e "${C_GREEN}✅ $DOMAIN${C_RESET}"; } || read -p "Domain: " DOMAIN
    else read -p "Domain: " DOMAIN; fi
    echo "$DOMAIN" > "$DB_DIR/domain.txt"
}

create_dnstt_service() {
    local domain=$1 mtu=$2
    mkdir -p "$LOGS_DIR"

    if [ ! -f "$V2RAY_INFO_FILE" ]; then
        echo -e "${C_RED}❌ V2Ray info haipo. Inatakiwa kusakinisha V2Ray kwanza.${C_RESET}"
        return 1
    fi
    source "$V2RAY_INFO_FILE"
    local upstream="127.0.0.1:${V2RAY_PORT}"
    echo -e "${C_GREEN}🔷 Backend: V2Ray ($V2RAY_PROTOCOL) @ $upstream${C_RESET}"

    cat > "$DNSTT_SERVICE_FILE" <<EOF
[Unit]
Description=DNSTT Server (V2Ray Backend)
After=network.target v2ray-dnstt.service
Requires=v2ray-dnstt.service

[Service]
Type=simple
User=root
WorkingDirectory=$DB_DIR
ExecStart=$DNSTT_BINARY -udp :5300 -privkey-file $DNSTT_KEYS_DIR/server.key -mtu $mtu $domain $upstream
Restart=always
RestartSec=5
LimitNOFILE=2097152

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable dnstt.service >/dev/null 2>&1
    echo "$upstream" > "$DB_DIR/dnstt_upstream.txt"
}

save_dnstt_info() {
    printf 'TUNNEL_DOMAIN="%s"\nPUBLIC_KEY="%s"\nMTU_VALUE="%s"\nBACKEND_PORT="%s"\n' "$1" "$2" "$3" "$4" > "$DNSTT_CONFIG_FILE"
}

show_client_commands() {
    local pk=$(cat "$DNSTT_KEYS_DIR/server.pub" 2>/dev/null)
    source "$V2RAY_INFO_FILE" 2>/dev/null

    echo -e "\n${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_PURPLE}                 📱 CLIENT CONNECTION${C_RESET}"
    echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
    echo -e "  ${C_CYAN}Tunnel Domain${C_RESET} : ${C_YELLOW}$1${C_RESET}"
    echo -e "  ${C_CYAN}Public Key${C_RESET}    : ${C_YELLOW}$pk${C_RESET}"
    echo -e "  ${C_CYAN}MTU${C_RESET}           : ${C_YELLOW}$2${C_RESET}"
    echo -e "  ${C_CYAN}Protocol${C_RESET}      : ${C_YELLOW}$V2RAY_PROTOCOL${C_RESET}"
    echo -e "  ${C_CYAN}UUID${C_RESET}          : ${C_YELLOW}$V2RAY_UUID${C_RESET}"
    echo -e "  ${C_CYAN}Internal Port${C_RESET} : ${C_YELLOW}$V2RAY_PORT${C_RESET} (127.0.0.1 pekee)\n"
    echo -e "  ${C_ORANGE}⚠️  Upande wa mteja (tabaka mbili):${C_RESET}"
    echo -e "     1. SlipNet → Proxy Only Mode → SOCKS 127.0.0.1:1080"
    echo -e "     2. Nekobox → $V2RAY_PROTOCOL + SOCKS5 outbound → 127.0.0.1:1080"
    echo -e "     3. SlipNet kwenye bypass ya Nekobox (kuzuia loop)"
    press_enter
}

configure_dnstt_firewall() {
    echo -e "\n${C_BLUE}🔥 Configuring firewall...${C_RESET}"
    ! command -v iptables &>/dev/null && ff_apt_install iptables iptables-persistent
    iptables -t nat -F 2>/dev/null; iptables -F 2>/dev/null
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p udp --sport 53 -j ACCEPT
    iptables -A INPUT -p udp --dport 5300 -j ACCEPT
    iptables -A OUTPUT -p udp --sport 5300 -j ACCEPT
    iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    echo -e "${C_GREEN}✅ Firewall configured${C_RESET}"
}

install_dnstt() {
    clear; show_banner
    [ -f "$DNSTT_SERVICE_FILE" ] && { read -p "Reinstall? (y/n): " r; [[ "$r" != "y" ]] && return; systemctl stop dnstt.service 2>/dev/null; }

    echo -e "\n${C_BLUE}[1/6] Dependencies...${C_RESET}"
    ff_apt_install wget curl openssl bc dnsutils unzip

    echo -e "${C_BLUE}[2/6] Download DNSTT binary...${C_RESET}"
    download_dnstt_binary

    echo -e "${C_BLUE}[3/6] V2Ray backend setup...${C_RESET}"
    setup_v2ray_backend || { echo -e "${C_RED}❌ V2Ray ni lazima. Install imesimama.${C_RESET}"; press_enter; return 1; }

    echo -e "${C_BLUE}[4/6] MTU selection...${C_RESET}"
    mtu_selection_during_install

    echo -e "${C_BLUE}[5/6] Domain + keys...${C_RESET}"
    setup_domain
    generate_keys

    echo -e "${C_BLUE}[6/6] Creating DNSTT service (V2Ray backend)...${C_RESET}"
    create_dnstt_service "$DOMAIN" "$MTU" || { press_enter; return 1; }
    save_dnstt_info "$DOMAIN" "$PUBLIC_KEY" "$MTU" "$(cat "$DB_DIR/dnstt_upstream.txt" | cut -d: -f2)"
    configure_dnstt_firewall
    systemctl start dnstt.service; sleep 2

    if systemctl is-active --quiet dnstt.service; then
        echo -e "\n${C_GREEN}✅ DNSTT running (V2Ray backend)${C_RESET}"
        show_client_commands "$DOMAIN" "$MTU"
    else
        journalctl -u dnstt.service -n 20 --no-pager
        press_enter
    fi
}

uninstall_dnstt() {
    systemctl stop dnstt.service 2>/dev/null
    systemctl disable dnstt.service 2>/dev/null
    uninstall_v2ray_backend
    rm -f "$DNSTT_SERVICE_FILE" "$DNSTT_BINARY" "$DNSTT_CLIENT" \
          "$DNSTT_KEYS_DIR/server.key" "$DNSTT_KEYS_DIR/server.pub" \
          "$DB_DIR/domain.txt" "$DNSTT_CONFIG_FILE" "$MTU_CONFIG" "$DB_DIR/dnstt_upstream.txt"
    systemctl daemon-reload
    echo -e "${C_GREEN}✅ DNSTT + V2Ray removed${C_RESET}"
    press_enter
}

# ============================================================
# DNSTT MENUS
# ============================================================
dnstt_main_menu() {
    while true; do
        clear; show_banner
        [ ! -f "$DNSTT_SERVICE_FILE" ] && { echo -e "\n${C_RED}❌ DNSTT haijasakinishwa!${C_RESET}"; press_enter; return; }
        local st=""; systemctl is-active --quiet dnstt 2>/dev/null && st="${C_GREEN}● RUNNING${C_RESET}" || st="${C_RED}● STOPPED${C_RESET}"
        source "$V2RAY_INFO_FILE" 2>/dev/null

        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}              📡 DNSTT MANAGEMENT (V2Ray Backend)${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
        echo -e "  ${C_CYAN}Status${C_RESET}     : $st"
        echo -e "  ${C_CYAN}Domain${C_RESET}     : ${C_YELLOW}$(cat "$DB_DIR/domain.txt" 2>/dev/null || echo 'Not set')${C_RESET}"
        echo -e "  ${C_CYAN}MTU${C_RESET}        : ${C_YELLOW}$(get_current_mtu)${C_RESET}"
        echo -e "  ${C_CYAN}Backend${C_RESET}    : ${C_GREEN}$V2RAY_PROTOCOL @ 127.0.0.1:$V2RAY_PORT${C_RESET}"
        echo -e "  ${C_CYAN}UUID${C_RESET}       : ${C_YELLOW}${V2RAY_UUID:-not set}${C_RESET}"
        echo -e "  ${C_CYAN}Public Key${C_RESET} : ${C_GREEN}$(cat "$DNSTT_KEYS_DIR/server.pub" 2>/dev/null | cut -c1-35)...${C_RESET}\n"
        echo -e "  ${C_GREEN} 1)${C_RESET} 🌐 Domain Management"
        echo -e "  ${C_GREEN} 2)${C_RESET} 🔑 Public Key Management"
        echo -e "  ${C_GREEN} 3)${C_RESET} 📡 MTU Settings"
        echo -e "  ${C_GREEN} 4)${C_RESET} ⚡ Speed Boosters"
        echo -e "  ${C_GREEN} 5)${C_RESET} 📊 Full Details"
        echo -e "  ${C_GREEN} 6)${C_RESET} 🔷 V2Ray Backend Settings"
        echo ""
        echo -e "  ${C_RED} 0)${C_RESET} Return"
        read -p "👉 Choice: " c
        case $c in
            1) dnstt_domain_menu ;;
            2) dnstt_key_menu ;;
            3) dnstt_mtu_menu ;;
            4) dnstt_speed_menu ;;
            5) show_dnstt_full_details ;;
            6) v2ray_backend_menu ;;
            0) return ;;
        esac
    done
}

dnstt_domain_menu() {
    while true; do
        clear; show_banner
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}                    🌐 DOMAIN MANAGEMENT${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
        echo -e "  ${C_CYAN}Current${C_RESET}: ${C_YELLOW}$(cat "$DB_DIR/domain.txt" 2>/dev/null || echo 'Not set')${C_RESET}\n"
        echo -e "  ${C_GREEN}1)${C_RESET} Set Custom Domain"
        echo -e "  ${C_GREEN}2)${C_RESET} Auto-Generate Domain"
        echo -e "  ${C_RED}0)${C_RESET} Return"
        read -p "👉 Choice: " c
        case $c in 1) set_custom_dnstt_domain ;; 2) change_dnstt_domain ;; 0) return ;; esac
    done
}

dnstt_key_menu() {
    while true; do
        clear; show_banner
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}                    🔑 PUBLIC KEY MANAGEMENT${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
        echo -e "  ${C_CYAN}Current${C_RESET}: ${C_GREEN}$(cat "$DNSTT_KEYS_DIR/server.pub" 2>/dev/null || echo 'Not set')${C_RESET}\n"
        echo -e "  ${C_GREEN}1)${C_RESET} Set Custom Public Key"
        echo -e "  ${C_GREEN}2)${C_RESET} Regenerate Keys"
        echo -e "  ${C_RED}0)${C_RESET} Return"
        read -p "👉 Choice: " c
        case $c in 1) set_custom_dnstt_public_key ;; 2) regenerate_dnstt_keys ;; 0) return ;; esac
    done
}

dnstt_mtu_menu() {
    while true; do
        clear; show_banner
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}                    📡 MTU SETTINGS${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
        echo -e "  ${C_CYAN}Current${C_RESET}: ${C_YELLOW}$(get_current_mtu)${C_RESET}\n"
        echo -e "  ${C_GREEN}1)${C_RESET} 512   ${C_GREEN}4)${C_RESET} 1400"
        echo -e "  ${C_GREEN}2)${C_RESET} 900   ${C_GREEN}5)${C_RESET} 1500"
        echo -e "  ${C_GREEN}3)${C_RESET} 1200  ${C_GREEN}6)${C_RESET} Custom"
        echo -e "  ${C_RED}0)${C_RESET} Return"
        read -p "👉 Choice: " c
        case $c in
            1) set_dnstt_mtu "512"; press_enter ;;
            2) set_dnstt_mtu "900"; press_enter ;;
            3) set_dnstt_mtu "1200"; press_enter ;;
            4) set_dnstt_mtu "1400"; press_enter ;;
            5) set_dnstt_mtu "1500"; press_enter ;;
            6) read -p "MTU (512-1500): " m; set_dnstt_mtu "$m"; press_enter ;;
            0) return ;;
        esac
    done
}

set_dnstt_mtu() {
    local m="$1"
    [[ ! "$m" =~ ^[0-9]+$ || "$m" -lt 512 || "$m" -gt 1500 ]] && { echo -e "${C_RED}❌ 512-1500${C_RESET}"; return 1; }
    echo "$m" > "$MTU_CONFIG"
    [ -f "$DNSTT_SERVICE_FILE" ] && { sed -i "s/-mtu [0-9]*/-mtu $m/g" "$DNSTT_SERVICE_FILE"; systemctl daemon-reload; systemctl restart dnstt.service 2>/dev/null; echo -e "${C_GREEN}✅ MTU: $m${C_RESET}"; }
}

set_custom_dnstt_domain() {
    clear; show_banner
    read -p "New domain: " nd; [[ -z "$nd" ]] && return
    echo "$nd" > "$DB_DIR/domain.txt"
    local m=$(get_current_mtu)
    source "$V2RAY_INFO_FILE" 2>/dev/null
    systemctl stop dnstt.service 2>/dev/null
    sed -i "s|ExecStart=.*|ExecStart=$DNSTT_BINARY -udp :5300 -privkey-file $DNSTT_KEYS_DIR/server.key -mtu $m $nd 127.0.0.1:$V2RAY_PORT|" "$DNSTT_SERVICE_FILE"
    [ -f "$DNSTT_CONFIG_FILE" ] && sed -i "s|TUNNEL_DOMAIN=.*|TUNNEL_DOMAIN=\"$nd\"|" "$DNSTT_CONFIG_FILE"
    systemctl daemon-reload; systemctl restart dnstt.service; sleep 2
    echo -e "${C_GREEN}✅ $nd${C_RESET}"; press_enter
}

change_dnstt_domain() {
    clear; show_banner
    [ -f "$DB_DIR/domain.txt" ] && { local o=$(cat "$DB_DIR/domain.txt"); curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$(echo $o|cut -d. -f1)/NS/" -H "Authorization: Token $DESEC_TOKEN" >/dev/null 2>&1; }
    local rand=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 3)
    local ns="ns-$rand"; local tun="tun-$rand"; local ip=$(curl -s -4 icanhazip.com)
    curl -s -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" -H "Authorization: Token $DESEC_TOKEN" -H "Content-Type: application/json" --data "[{\"subname\":\"$ns\",\"type\":\"A\",\"ttl\":3600,\"records\":[\"$ip\"]}]" >/dev/null 2>&1
    local r=$(curl -s -w "%{http_code}" -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" -H "Authorization: Token $DESEC_TOKEN" -H "Content-Type: application/json" --data "[{\"subname\":\"$tun\",\"type\":\"NS\",\"ttl\":3600,\"records\":[\"$ns.$DESEC_DOMAIN.\"]}]")
    if [[ "${r: -3}" -eq 201 ]]; then
        local nd="$tun.$DESEC_DOMAIN"
        echo "$nd" > "$DB_DIR/domain.txt"
        local m=$(get_current_mtu)
        source "$V2RAY_INFO_FILE" 2>/dev/null
        systemctl stop dnstt.service 2>/dev/null
        sed -i "s|ExecStart=.*|ExecStart=$DNSTT_BINARY -udp :5300 -privkey-file $DNSTT_KEYS_DIR/server.key -mtu $m $nd 127.0.0.1:$V2RAY_PORT|" "$DNSTT_SERVICE_FILE"
        [ -f "$DNSTT_CONFIG_FILE" ] && sed -i "s|TUNNEL_DOMAIN=.*|TUNNEL_DOMAIN=\"$nd\"|" "$DNSTT_CONFIG_FILE"
        systemctl daemon-reload; systemctl restart dnstt.service
        echo -e "${C_GREEN}✅ $nd${C_RESET}"
    else echo -e "${C_RED}❌ HTTP ${r: -3}${C_RESET}"; fi
    press_enter
}

set_custom_dnstt_public_key() {
    clear; show_banner
    read -p "New public key: " cp; [[ ${#cp} -lt 30 ]] && { echo "❌"; press_enter; return; }
    echo "$cp" > "$DNSTT_KEYS_DIR/server.pub"; chmod 644 "$DNSTT_KEYS_DIR/server.pub"
    [ -f "$DNSTT_CONFIG_FILE" ] && sed -i "s|PUBLIC_KEY=.*|PUBLIC_KEY=\"$cp\"|" "$DNSTT_CONFIG_FILE"
    systemctl restart dnstt.service 2>/dev/null
    echo -e "${C_GREEN}✅${C_RESET}"; press_enter
}

regenerate_dnstt_keys() {
    clear; show_banner
    read -p "Regenerate? (y/n): " c; [[ "$c" != "y" ]] && return
    systemctl stop dnstt.service 2>/dev/null
    cd "$DNSTT_KEYS_DIR"; rm -f server.key server.pub
    "$DNSTT_BINARY" -gen-key -privkey-file server.key -pubkey-file server.pub 2>/dev/null || {
        openssl rand -hex 32 > server.key
        cat server.key | sha256sum | awk '{print $1}' > server.pub
    }
    chmod 600 server.key; chmod 644 server.pub
    local np=$(cat server.pub)
    [ -f "$DNSTT_CONFIG_FILE" ] && sed -i "s|PUBLIC_KEY=.*|PUBLIC_KEY=\"$np\"|" "$DNSTT_CONFIG_FILE"
    systemctl restart dnstt.service; sleep 2
    echo -e "${C_GREEN}✅ $np${C_RESET}"; press_enter
}

show_dnstt_full_details() {
    clear; show_banner
    [ ! -f "$DB_DIR/domain.txt" ] && { echo "Not installed"; press_enter; return; }
    local d=$(cat "$DB_DIR/domain.txt") m=$(get_current_mtu) pk=$(cat "$DNSTT_KEYS_DIR/server.pub" 2>/dev/null)
    local st=""; systemctl is-active --quiet dnstt.service 2>/dev/null && st="${C_GREEN}● RUNNING${C_RESET}" || st="${C_RED}● STOPPED${C_RESET}"
    source "$V2RAY_INFO_FILE" 2>/dev/null
    local vst=""; systemctl is-active --quiet v2ray-dnstt.service 2>/dev/null && vst="${C_GREEN}● RUNNING${C_RESET}" || vst="${C_RED}● STOPPED${C_RESET}"

    echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_PURPLE}                 📊 DNSTT DETAILS${C_RESET}"
    echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
    echo -e "  ${C_CYAN}DNSTT Status${C_RESET}  : $st"
    echo -e "  ${C_CYAN}V2Ray Status${C_RESET}  : $vst"
    echo -e "  ${C_CYAN}Domain${C_RESET}        : ${C_YELLOW}$d${C_RESET}"
    echo -e "  ${C_CYAN}MTU${C_RESET}           : ${C_YELLOW}$m${C_RESET}"
    echo -e "  ${C_CYAN}Backend${C_RESET}       : ${C_GREEN}$V2RAY_PROTOCOL @ 127.0.0.1:$V2RAY_PORT${C_RESET}"
    echo -e "  ${C_CYAN}UUID${C_RESET}          : ${C_YELLOW}$V2RAY_UUID${C_RESET}"
    echo -e "  ${C_CYAN}Public Key${C_RESET}    : ${C_GREEN}$pk${C_RESET}"
    echo -e "  ${C_CYAN}Upstream${C_RESET}      : ${C_YELLOW}$(cat "$DB_DIR/dnstt_upstream.txt" 2>/dev/null)${C_RESET}"
    echo -e "  ${C_CYAN}TCP CC${C_RESET}        : ${C_GREEN}$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)${C_RESET}"
    echo -e "  ${C_CYAN}TFO${C_RESET}           : ${C_GREEN}$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)${C_RESET}"
    press_enter
}

# ============================================================
# INITIAL SETUP
# ============================================================
initial_setup() {
    echo -e "\n${C_BLUE}🔧 Initial setup...${C_RESET}"
    ff_apt_install curl wget bc iptables openssl dnsutils unzip >/dev/null 2>&1
    mkdir -p "$DB_DIR" "$LOGS_DIR" "$CONFIG_DIR" "$BANDWIDTH_DIR" "$BANNER_DIR" "$DNSTT_KEYS_DIR" "$V2RAY_CONFIG_DIR"
    touch "$DB_FILE"
    echo -e "${C_GREEN}✅ Setup complete${C_RESET}"
}

# ============================================================
# UNINSTALL
# ============================================================
uninstall_all() {
    clear; show_banner
    read -p "Type YES to uninstall everything: " c
    [[ "$c" != "YES" ]] && { echo "Cancelled"; press_enter; return; }

    systemctl stop dnstt v2ray-dnstt 2>/dev/null
    systemctl disable dnstt v2ray-dnstt 2>/dev/null
    rm -f "$DNSTT_SERVICE_FILE" "$V2RAY_SERVICE_FILE"
    systemctl daemon-reload

    rm -f "$DNSTT_BINARY" "$DNSTT_CLIENT" "$V2RAY_BIN"
    rm -rf "$DB_DIR"

    # Clean iptables rules
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null
    iptables -D INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -p udp --sport 53 -j ACCEPT 2>/dev/null
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -p udp --sport 5300 -j ACCEPT 2>/dev/null

    echo -e "${C_GREEN}✅ Uninstalled${C_RESET}"
    sleep 2
    rm -f "$0"
    exit 0
}

# ============================================================
# MAIN MENU
# ============================================================
main_menu() {
    while true; do
        show_banner

        # Status za haraka
        local d_st=""; systemctl is-active --quiet dnstt 2>/dev/null && d_st="${C_GREEN}●${C_RESET}" || d_st="${C_RED}○${C_RESET}"
        local v_st=""; systemctl is-active --quiet v2ray-dnstt 2>/dev/null && v_st="${C_GREEN}●${C_RESET}" || v_st="${C_RED}○${C_RESET}"

        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}              DNSTT + V2RAY (XRAY) BACKEND${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
        echo -e "  ${C_CYAN}DNSTT${C_RESET}  : $d_st    ${C_CYAN}V2Ray${C_RESET}: $v_st\n"
        echo -e "  ${C_GREEN}[1]${C_RESET} 🚀 Install DNSTT + V2Ray"
        echo -e "  ${C_GREEN}[2]${C_RESET} 📡 DNSTT Management"
        echo -e "  ${C_GREEN}[3]${C_RESET} ⚡ Speed Boosters"
        echo -e "  ${C_GREEN}[4]${C_RESET} 🔷 V2Ray Backend Settings"
        echo -e "  ${C_GREEN}[5]${C_RESET} 🔄 Restart All Services"
        echo -e "  ${C_GREEN}[6]${C_RESET} 📊 View Status"
        echo ""
        echo -e "  ${C_RED}[99]${C_RESET} 🗑️  Uninstall All"
        echo -e "  ${C_RED}[0]${C_RESET}  Exit"
        echo ""
        read -p "👉 Select: " choice
        case $choice in
            1) install_dnstt ;;
            2) dnstt_main_menu ;;
            3) dnstt_speed_menu ;;
            4) v2ray_backend_menu ;;
            5) systemctl restart v2ray-dnstt dnstt 2>/dev/null; sleep 2
               systemctl is-active --quiet v2ray-dnstt && echo -e "${C_GREEN}✅ V2Ray${C_RESET}" || echo -e "${C_RED}❌ V2Ray${C_RESET}"
               systemctl is-active --quiet dnstt && echo -e "${C_GREEN}✅ DNSTT${C_RESET}" || echo -e "${C_RED}❌ DNSTT${C_RESET}"
               press_enter ;;
            6) show_dnstt_full_details ;;
            99) uninstall_all ;;
            0) echo -e "\n${C_GREEN}👋 Goodbye!${C_RESET}\n"; exit 0 ;;
            *) echo -e "\n${C_RED}❌ Invalid option${C_RESET}"; sleep 1 ;;
        esac
    done
}

# ============================================================
# ENTRY POINT
# ============================================================
[[ $EUID -ne 0 ]] && { echo -e "${C_RED}❌ Run as root!${C_RESET}"; exit 1; }
[[ "$1" == "--install-setup" ]] && { initial_setup; exit 0; }
[[ ! -f "$INSTALL_FLAG_FILE" ]] && { initial_setup; touch "$INSTALL_FLAG_FILE"; }
main_menu
