#!/bin/bash
# ================================================================
# DNSTT + V2RAY (XRAY) BACKEND — COMPLETE EDITION
# V2Ray users, trial, banner, limiter (Xray Stats API), boosters 7
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
V2RAY_USERS_DB="$DB_DIR/v2ray_users.db"
LOGS_DIR="$DB_DIR/logs"
CONFIG_DIR="$DB_DIR/config"
BANDWIDTH_DIR="$DB_DIR/bandwidth"
BANNER_DIR="$DB_DIR/banners"
DNSTT_KEYS_DIR="$DB_DIR/dnstt"
MTU_CONFIG="$CONFIG_DIR/mtu"
INSTALL_FLAG_FILE="$DB_DIR/.install"
TRIAL_CLEANUP_SCRIPT="/usr/local/bin/dnstt-v2ray-trial-cleanup.sh"

DNSTT_SERVICE_FILE="/etc/systemd/system/dnstt.service"
DNSTT_BINARY="/usr/local/bin/dnstt-server"
DNSTT_CLIENT="/usr/local/bin/dnstt-client"
DNSTT_CONFIG_FILE="$DB_DIR/dnstt_info.conf"

V2RAY_SERVICE_FILE="/etc/systemd/system/v2ray-dnstt.service"
V2RAY_BIN="/usr/local/bin/xray"
V2RAY_CONFIG_DIR="$DB_DIR/v2ray"
V2RAY_CONFIG_FILE="$V2RAY_CONFIG_DIR/config.json"
V2RAY_INFO_FILE="$DB_DIR/v2ray_info.conf"
V2RAY_UUID_FILE="$V2RAY_CONFIG_DIR/uuid.txt"
V2RAY_PORT="10086"
V2RAY_PROTOCOL="vless"
V2RAY_STATS_PORT="10085"
V2RAY_LIMITER_SCRIPT="/usr/local/bin/v2ray-limiter.sh"
V2RAY_LIMITER_SERVICE="/etc/systemd/system/v2ray-limiter.service"
CONFIG_DIRTY_FLAG="/tmp/v2ray-config-dirty"
BANNER_ENABLED_FILE="$DB_DIR/banners_enabled"
BANNER_BUILDER="/usr/local/bin/v2ray-banner-build.sh"

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
    echo -e "${C_PURPLE}   DNSTT + V2RAY (XRAY) BACKEND ${C_RESET}${C_DIM}| Complete Edition${C_RESET}"
    echo -e "${C_BLUE}   ─────────────────────────────────────────────────────────${C_RESET}"
    printf "   ${C_GRAY}%-10s${C_RESET} %-20s ${C_GRAY}|${C_RESET} %s\n" "OS" "$os_name" "Uptime: $up"
    printf "   ${C_GRAY}%-10s${C_RESET} %-20s ${C_GRAY}|${C_RESET} %s\n" "Memory" "${ram}% Used" "Load: ${C_GREEN}${load}${C_RESET}"
    echo -e "${C_BLUE}   ─────────────────────────────────────────────────────────${C_RESET}"
}

# ============================================================
# HELPERS
# ============================================================
format_size() {
    local bytes=$1
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    if (( bytes >= 1073741824 )); then
        awk "BEGIN{printf \"%.2f GB\", $bytes/1073741824}"
    elif (( bytes >= 1048576 )); then
        awk "BEGIN{printf \"%.2f MB\", $bytes/1048576}"
    elif (( bytes >= 1024 )); then
        awk "BEGIN{printf \"%.2f KB\", $bytes/1024}"
    else
        echo "${bytes} B"
    fi
}

build_bar() {
    local pct=$1
    local blocks=${2:-10}
    [[ $pct -gt 100 ]] && pct=100
    [[ $pct -lt 0 ]] && pct=0
    local filled=$(( pct * blocks / 100 ))
    local empty=$(( blocks - filled ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo "$bar"
}

get_bar_color() {
    local pct=$1
    if   (( pct >= 95 )); then echo "\033[38;5;196m"
    elif (( pct >= 85 )); then echo "\033[38;5;196m"
    elif (( pct >= 70 )); then echo "\033[38;5;208m"
    elif (( pct >= 50 )); then echo "\033[38;5;226m"
    else                        echo "\033[38;5;46m"
    fi
}

# ============================================================
# SELECT USER INTERFACES
# ============================================================
_select_v2ray_user_interface() {
    local title="$1"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}${title}${C_RESET}\n"
    if [[ ! -s "$V2RAY_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️  No users.${C_RESET}"
        SELECTED_USER="NO_USERS"
        return
    fi
    mapfile -t all_users < <(cut -d: -f1 "$V2RAY_USERS_DB" | sort)
    if [ ${#all_users[@]} -ge 15 ]; then
        read -p "👉 Search: " st
        if [[ -n "$st" ]]; then
            mapfile -t users < <(printf "%s\n" "${all_users[@]}" | grep -i "$st")
        else
            users=("${all_users[@]}")
        fi
    else
        users=("${all_users[@]}")
    fi
    if [ ${#users[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}ℹ️  None.${C_RESET}"
        SELECTED_USER="NO_USERS"
        return
    fi
    echo -e "\nSelect user:\n"
    for i in "${!users[@]}"; do
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "${users[$i]}"
    done
    echo -e "\n  ${C_RED}[ 0]${C_RESET} Cancel"
    while true; do
        read -p "👉 Number: " c
        if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 0 ] && [ "$c" -le "${#users[@]}" ]; then
            if [ "$c" -eq 0 ]; then
                SELECTED_USER=""
                return
            else
                SELECTED_USER="${users[$((c-1))]}"
                return
            fi
        else
            echo -e "${C_RED}❌ Invalid.${C_RESET}"
        fi
    done
}

_select_multi_v2ray_user_interface() {
    local title="$1"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}${title}${C_RESET}\n"
    SELECTED_USERS=()
    if [[ ! -s "$V2RAY_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️  No users.${C_RESET}"
        SELECTED_USERS=("NO_USERS")
        return
    fi
    mapfile -t all_users < <(cut -d: -f1 "$V2RAY_USERS_DB" | sort)
    if [ ${#all_users[@]} -ge 15 ]; then
        read -p "👉 Search: " st
        if [[ -n "$st" ]]; then
            mapfile -t users < <(printf "%s\n" "${all_users[@]}" | grep -i "$st")
        else
            users=("${all_users[@]}")
        fi
    else
        users=("${all_users[@]}")
    fi
    if [ ${#users[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}ℹ️  None.${C_RESET}"
        SELECTED_USERS=("NO_USERS")
        return
    fi
    echo -e "\nSelect users:\n"
    for i in "${!users[@]}"; do
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "${users[$i]}"
    done
    echo -e "\n  ${C_GREEN}[all]${C_RESET} Select ALL   ${C_RED}[ 0]${C_RESET} Cancel"
    while true; do
        read -p "👉 Numbers: " c
        c=$(echo "$c" | tr ',' ' ')
        if [[ -z "$c" ]]; then echo -e "${C_RED}❌ Invalid.${C_RESET}"; continue; fi
        if [[ "$c" == "0" ]]; then SELECTED_USERS=(); return; fi
        if [[ "${c,,}" == "all" ]]; then SELECTED_USERS=("${users[@]}"); return; fi
        local valid=true; local si=()
        for t in $c; do
            if [[ "$t" =~ ^[0-9]+-[0-9]+$ ]]; then
                local s=${t%-*}; local e=${t#*-}
                if [ "$s" -le "$e" ]; then
                    for (( i=s; i<=e; i++ )); do
                        if [ "$i" -ge 1 ] && [ "$i" -le "${#users[@]}" ]; then
                            si+=($i)
                        else
                            valid=false; break
                        fi
                    done
                else
                    valid=false; break
                fi
            elif [[ "$t" =~ ^[0-9]+$ ]]; then
                if [ "$t" -ge 1 ] && [ "$t" -le "${#users[@]}" ]; then
                    si+=($t)
                else
                    valid=false; break
                fi
            else
                valid=false; break
            fi
        done
        if [[ "$valid" == true && ${#si[@]} -gt 0 ]]; then
            mapfile -t ui < <(printf "%s\n" "${si[@]}" | sort -u -n)
            for i in "${ui[@]}"; do
                SELECTED_USERS+=("${users[$((i-1))]}")
            done
            return
        else
            echo -e "${C_RED}❌ Invalid.${C_RESET}"
        fi
    done
}

# ============================================================
# SPEED BOOSTERS — 7 LEVELS
# ============================================================
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
    for i in /sys/class/net/*/queues/*/rps_cpus; do
        [[ -f "$i" ]] && echo ffffffff > "$i" 2>/dev/null
    done
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
    for i in /sys/class/net/*/queues/*/rps_cpus; do
        [[ -f "$i" ]] && echo ffffffff > "$i" 2>/dev/null
    done
    echo -e "${C_GREEN}✅ 10000x${C_RESET}"
}

apply_booster_ultra_plus() {
    echo -e "\n${C_BLUE}🚀 ULTRA PLUS (768MB) — buffer 6291456${C_RESET}"
    _apply_tfo_bbr
    sysctl -w net.ipv4.udp_rmem_min=6291456 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=6291456 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_early_demux=1 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=805306368 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=805306368 >/dev/null 2>&1
    echo -e "${C_GREEN}✅ Ultra+${C_RESET}"
}

apply_booster_extreme_plus() {
    echo -e "\n${C_BLUE}💥 EXTREME PLUS (1GB) — buffer 12582912${C_RESET}"
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
               echo "✅ Reset to Default"
               press_enter ;;
            0) return ;;
        esac
    done
}

# ============================================================
# V2RAY (XRAY) CORE
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
    echo "$uuid"
}

generate_unique_uuid() {
    local uuid
    local i=0
    while (( i < 10 )); do
        uuid=$(generate_v2ray_uuid)
        if [ ! -f "$V2RAY_USERS_DB" ] || ! grep -q ":$uuid:" "$V2RAY_USERS_DB"; then
            echo "$uuid"
            return
        fi
        ((i++))
    done
    echo "$uuid"
}

# ============ SOMA ACTIVE V2RAY CLIENTS (KWA CONFIG) ============
get_active_v2ray_clients() {
    local json=""
    local first=1
    if [ ! -f "$V2RAY_USERS_DB" ]; then
        echo ""
        return
    fi
    while IFS=: read -r user uuid expiry limit bw traffic status; do
        [[ -z "$user" || "$user" == \#* ]] && continue
        [[ "$status" == "LOCKED" || "$status" == "EXPIRED" || "$status" == "EXHAUSTED" ]] && continue
        local et=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
        local now=$(date +%s)
        [[ $et -gt 0 && $et -lt $now ]] && continue
        if [[ "$bw" != "0" && -n "$bw" ]]; then
            local qb=$(awk "BEGIN{printf \"%.0f\", $bw*1073741824}")
            local ub=$(awk "BEGIN{printf \"%.0f\", $traffic*1073741824}" 2>/dev/null || echo 0)
            [[ "$ub" -ge "$qb" ]] && continue
        fi
        if [[ $first -eq 0 ]]; then json+=","; fi
        json+="{\"id\":\"$uuid\",\"email\":\"${user}@dnstt\"}"
        first=0
    done < "$V2RAY_USERS_DB"
    echo "$json"
}

write_v2ray_config() {
    mkdir -p "$V2RAY_CONFIG_DIR"
    local proto="${V2RAY_PROTOCOL:-vless}"
    source "$V2RAY_INFO_FILE" 2>/dev/null

    case "$proto" in
        vless)
            local clients=$(get_active_v2ray_clients)
            cat > "$V2RAY_CONFIG_FILE" <<EOF
{
  "log": { "loglevel": "warning", "access": "none", "error": "$LOGS_DIR/v2ray-error.log" },
  "api": { "tag": "api", "services": ["StatsService"] },
  "stats": {},
  "policy": {
    "levels": { "0": { "statsUserUplink": true, "statsUserDownlink": true } },
    "system": { "statsInboundUplink": true, "statsInboundDownlink": true }
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": $V2RAY_PORT,
      "protocol": "vless",
      "settings": { "clients": [$clients], "decryption": "none" },
      "streamSettings": { "network": "tcp", "security": "none" },
      "tag": "dnstt-inbound"
    },
    {
      "listen": "127.0.0.1",
      "port": $V2RAY_STATS_PORT,
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" },
      "tag": "api"
    }
  ],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }],
  "routing": {
    "rules": [{ "type": "field", "inboundTag": ["api"], "outboundTag": "api" }]
  }
}
EOF
            ;;
        vmess)
            local vmess_clients=""
            local first=1
            if [ -f "$V2RAY_USERS_DB" ]; then
                while IFS=: read -r user uuid expiry limit bw traffic status; do
                    [[ -z "$user" || "$user" == \#* ]] && continue
                    [[ "$status" == "LOCKED" || "$status" == "EXPIRED" || "$status" == "EXHAUSTED" ]] && continue
                    local et=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
                    [[ $et -gt 0 && $et -lt $(date +%s) ]] && continue
                    if [[ "$bw" != "0" && -n "$bw" ]]; then
                        local qb=$(awk "BEGIN{printf \"%.0f\", $bw*1073741824}")
                        local ub=$(awk "BEGIN{printf \"%.0f\", $traffic*1073741824}" 2>/dev/null || echo 0)
                        [[ "$ub" -ge "$qb" ]] && continue
                    fi
                    if [[ $first -eq 0 ]]; then vmess_clients+=","; fi
                    vmess_clients+="{\"id\":\"$uuid\",\"alterId\":0,\"email\":\"${user}@dnstt\"}"
                    first=0
                done < "$V2RAY_USERS_DB"
            fi
            cat > "$V2RAY_CONFIG_FILE" <<EOF
{
  "log": { "loglevel": "warning", "access": "none", "error": "$LOGS_DIR/v2ray-error.log" },
  "api": { "tag": "api", "services": ["StatsService"] },
  "stats": {},
  "policy": { "levels": { "0": { "statsUserUplink": true, "statsUserDownlink": true } } },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": $V2RAY_PORT,
      "protocol": "vmess",
      "settings": { "clients": [$vmess_clients] },
      "streamSettings": { "network": "tcp", "security": "none" },
      "tag": "dnstt-inbound"
    },
    {
      "listen": "127.0.0.1",
      "port": $V2RAY_STATS_PORT,
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" },
      "tag": "api"
    }
  ],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }],
  "routing": { "rules": [{ "type": "field", "inboundTag": ["api"], "outboundTag": "api" }] }
}
EOF
            ;;
        trojan)
            local trojan_clients=""
            local first=1
            if [ -f "$V2RAY_USERS_DB" ]; then
                while IFS=: read -r user uuid expiry limit bw traffic status; do
                    [[ -z "$user" || "$user" == \#* ]] && continue
                    [[ "$status" == "LOCKED" || "$status" == "EXPIRED" || "$status" == "EXHAUSTED" ]] && continue
                    local et=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
                    [[ $et -gt 0 && $et -lt $(date +%s) ]] && continue
                    if [[ "$bw" != "0" && -n "$bw" ]]; then
                        local qb=$(awk "BEGIN{printf \"%.0f\", $bw*1073741824}")
                        local ub=$(awk "BEGIN{printf \"%.0f\", $traffic*1073741824}" 2>/dev/null || echo 0)
                        [[ "$ub" -ge "$qb" ]] && continue
                    fi
                    if [[ $first -eq 0 ]]; then trojan_clients+=","; fi
                    trojan_clients+="{\"password\":\"$uuid\",\"email\":\"${user}@dnstt\"}"
                    first=0
                done < "$V2RAY_USERS_DB"
            fi
            cat > "$V2RAY_CONFIG_FILE" <<EOF
{
  "log": { "loglevel": "warning", "access": "none", "error": "$LOGS_DIR/v2ray-error.log" },
  "api": { "tag": "api", "services": ["StatsService"] },
  "stats": {},
  "policy": { "levels": { "0": { "statsUserUplink": true, "statsUserDownlink": true } } },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": $V2RAY_PORT,
      "protocol": "trojan",
      "settings": { "clients": [$trojan_clients] },
      "streamSettings": { "network": "tcp", "security": "none" },
      "tag": "dnstt-inbound"
    },
    {
      "listen": "127.0.0.1",
      "port": $V2RAY_STATS_PORT,
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" },
      "tag": "api"
    }
  ],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }],
  "routing": { "rules": [{ "type": "field", "inboundTag": ["api"], "outboundTag": "api" }] }
}
EOF
            ;;
        *) echo -e "${C_RED}❌ Protocol unsupported${C_RESET}"; return 1 ;;
    esac
    chmod 600 "$V2RAY_CONFIG_FILE"
}

sync_v2ray_config() {
    echo -e "${C_BLUE}🔄 Syncing V2Ray config...${C_RESET}"
    if [ -x "$V2RAY_BIN" ]; then
        write_v2ray_config
        if "$V2RAY_BIN" run -test -c "$V2RAY_CONFIG_FILE" 2>/dev/null; then
            echo -e "${C_GREEN}✅ Config valid${C_RESET}"
        else
            echo -e "${C_YELLOW}⚠️  Config test failed${C_RESET}"
        fi
    else
        write_v2ray_config
    fi
    systemctl restart v2ray-dnstt.service 2>/dev/null
    sleep 1
    if systemctl is-active --quiet v2ray-dnstt.service; then
        echo -e "${C_GREEN}✅ V2Ray reloaded${C_RESET}"
    else
        echo -e "${C_RED}❌ V2Ray failed to reload${C_RESET}"
    fi
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
    printf 'V2RAY_PORT="%s"\nV2RAY_PROTOCOL="%s"\nV2RAY_STATS_PORT="%s"\n' "$1" "$2" "$3" > "$V2RAY_INFO_FILE"
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
    case $pc in
        2) V2RAY_PROTOCOL="vmess" ;;
        3) V2RAY_PROTOCOL="trojan" ;;
        *) V2RAY_PROTOCOL="vless" ;;
    esac

    echo -e "  ${C_BLUE}[4/4] Port...${C_RESET}"
    read -p "  👉 Listen port [${V2RAY_PORT}]: " np
    [[ -n "$np" && "$np" =~ ^[0-9]+$ ]] && V2RAY_PORT="$np"

    save_v2ray_info "$V2RAY_PORT" "$V2RAY_PROTOCOL" "$V2RAY_STATS_PORT"
    write_v2ray_config
    create_v2ray_service
    systemctl start v2ray-dnstt.service
    sleep 2

    if systemctl is-active --quiet v2ray-dnstt.service; then
        echo -e "  ${C_GREEN}✅ V2Ray: 127.0.0.1:$V2RAY_PORT ($V2RAY_PROTOCOL)${C_RESET}"
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

# ============================================================
# V2RAY BACKEND MENU
# ============================================================
v2ray_backend_menu() {
    while true; do
        clear; show_banner
        source "$V2RAY_INFO_FILE" 2>/dev/null
        local st=""
        systemctl is-active --quiet v2ray-dnstt.service 2>/dev/null && st="${C_GREEN}● RUNNING${C_RESET}" || st="${C_RED}● STOPPED${C_RESET}"
        local total=$(grep -c . "$V2RAY_USERS_DB" 2>/dev/null || echo 0)
        local active=$(get_active_v2ray_clients | grep -o '"id"' | wc -l 2>/dev/null || echo 0)

        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}              🔷 V2RAY BACKEND SETTINGS${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
        echo -e "  ${C_CYAN}Status${C_RESET}      : $st"
        echo -e "  ${C_CYAN}Protocol${C_RESET}    : ${C_YELLOW}${V2RAY_PROTOCOL}${C_RESET}"
        echo -e "  ${C_CYAN}Listen${C_RESET}      : 127.0.0.1:${V2RAY_PORT}"
        echo -e "  ${C_CYAN}Stats API${C_RESET}   : 127.0.0.1:${V2RAY_STATS_PORT}"
        echo -e "  ${C_CYAN}Total Users${C_RESET} : ${C_WHITE}$total${C_RESET} (${C_GREEN}$active active${C_RESET})\n"
        echo -e "  ${C_GREEN}1)${C_RESET} Restart V2Ray"
        echo -e "  ${C_GREEN}2)${C_RESET} View config"
        echo -e "  ${C_GREEN}3)${C_RESET} View logs"
        echo -e "  ${C_GREEN}4)${C_RESET} Change Protocol"
        echo -e "  ${C_GREEN}5)${C_RESET} Change Port"
        echo -e "  ${C_GREEN}6)${C_RESET} Sync Config (from DB)"
        echo -e "  ${C_RED}0)${C_RESET} Return"
        read -p "👉 Choice: " c
        case $c in
            1) systemctl restart v2ray-dnstt.service; sleep 2; systemctl is-active --quiet v2ray-dnstt.service && echo "✅" || echo "❌"; press_enter ;;
            2) clear; cat "$V2RAY_CONFIG_FILE" 2>/dev/null; press_enter ;;
            3) clear; journalctl -u v2ray-dnstt.service -n 40 --no-pager; press_enter ;;
            4)
                echo -e "  1) VLESS  2) VMess  3) Trojan"
                read -p "  👉 [1]: " pc; pc=${pc:-1}
                case $pc in
                    2) V2RAY_PROTOCOL="vmess" ;;
                    3) V2RAY_PROTOCOL="trojan" ;;
                    *) V2RAY_PROTOCOL="vless" ;;
                esac
                save_v2ray_info "$V2RAY_PORT" "$V2RAY_PROTOCOL" "$V2RAY_STATS_PORT"
                sync_v2ray_config
                echo -e "${C_GREEN}✅ Protocol: $V2RAY_PROTOCOL${C_RESET}"
                press_enter ;;
            5)
                read -p "New port [${V2RAY_PORT}]: " np
                [[ ! "$np" =~ ^[0-9]+$ ]] && { echo "❌"; press_enter; continue; }
                V2RAY_PORT="$np"
                save_v2ray_info "$V2RAY_PORT" "$V2RAY_PROTOCOL" "$V2RAY_STATS_PORT"
                sync_v2ray_config
                if [ -f "$DNSTT_SERVICE_FILE" ]; then
                    sed -i "s|127.0.0.1:[0-9]*|127.0.0.1:$V2RAY_PORT|g" "$DNSTT_SERVICE_FILE"
                    systemctl daemon-reload
                    systemctl restart dnstt.service
                fi
                echo -e "${C_GREEN}✅ Port: $V2RAY_PORT${C_RESET}"
                press_enter ;;
            6) sync_v2ray_config; press_enter ;;
            0) return ;;
        esac
    done
}

# ============================================================
# V2RAY USER MANAGEMENT
# ============================================================
v2ray_user_exists() {
    local user="$1"
    [ -f "$V2RAY_USERS_DB" ] && grep -q "^${user}:" "$V2RAY_USERS_DB"
}

get_v2ray_user() {
    grep "^${1}:" "$V2RAY_USERS_DB" 2>/dev/null
}

# ============ STATUS (FIXED — jina tofauti ili kuepuka conflict) ============
get_v2ray_status() {
    local user="$1"
    local line=$(get_v2ray_user "$user")
    [[ -z "$line" ]] && { echo "NOT_FOUND"; return; }

    local uuid=$(echo "$line" | cut -d: -f2)
    local expiry=$(echo "$line" | cut -d: -f3)
    local limit=$(echo "$line" | cut -d: -f4)
    local bw=$(echo "$line" | cut -d: -f5)
    local traffic=$(echo "$line" | cut -d: -f6)
    local account_status=$(echo "$line" | cut -d: -f7)

    # LOCKED kwanza
    if [[ "$account_status" == "LOCKED" ]]; then
        echo "LOCKED"
        return
    fi

    # EXPIRED
    local et=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
    local now=$(date +%s)
    if [[ $et -gt 0 && $et -lt $now ]]; then
        echo "EXPIRED"
        return
    fi

    # EXHAUSTED
    if [[ "$bw" != "0" && -n "$bw" ]]; then
        local qb=$(awk "BEGIN{printf \"%.0f\", $bw*1073741824}")
        local ub=$(awk "BEGIN{printf \"%.0f\", $traffic*1073741824}" 2>/dev/null || echo 0)
        if [[ "$ub" -ge "$qb" ]]; then
            echo "EXHAUSTED"
            return
        fi
    fi

    echo "ACTIVE"
}

get_v2ray_days_left() {
    local user="$1"
    local line=$(get_v2ray_user "$user")
    [[ -z "$line" ]] && { echo 0; return; }
    local expiry=$(echo "$line" | cut -d: -f3)
    local et=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
    local now=$(date +%s)
    echo $(( (et - now) / 86400 ))
}

# ============================================================
# CREATE V2RAY USER
# ============================================================
create_v2ray_user() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ✨ Create V2Ray User ---${C_RESET}\n"
    read -p "👉 Username (or '0' cancel): " username
    [[ "$username" == "0" || -z "$username" ]] && { press_enter; return; }

    if v2ray_user_exists "$username"; then
        echo -e "\n${C_RED}❌ User '$username' tayari ipo.${C_RESET}"
        press_enter; return
    fi

    echo -e "\n🔑 UUID:"
    echo -e "  ${C_GREEN}[1]${C_RESET} Auto-generate (unique)"
    echo -e "  ${C_GREEN}[2]${C_RESET} Weka mwenyewe"
    read -p "👉 [1]: " uc; uc=${uc:-1}

    local uuid
    if [[ "$uc" == "2" ]]; then
        read -p "UUID: " uuid
        [[ -z "$uuid" ]] && { echo -e "${C_RED}❌ Empty${C_RESET}"; press_enter; return; }
    else
        uuid=$(generate_unique_uuid)
        echo -e "  ${C_GREEN}✅ UUID: ${C_YELLOW}$uuid${C_RESET}"
    fi

    read -p "📅 Expiry (days) [30]: " days; days=${days:-30}
    [[ ! "$days" =~ ^[0-9]+$ ]] && { echo -e "${C_RED}❌ Invalid${C_RESET}"; press_enter; return; }

    read -p "📶 Connection limit [999]: " limit; limit=${limit:-999}
    read -p "📦 Bandwidth GB (0=unlimited) [0]: " bw; bw=${bw:-0}

    local expiry=$(date -d "+$days days" +%Y-%m-%d)

    echo "$username:$uuid:$expiry:$limit:$bw:0:ACTIVE" >> "$V2RAY_USERS_DB"
    touch "$BANDWIDTH_DIR/v2ray_${username}.usage"
    echo "0" > "$BANDWIDTH_DIR/v2ray_${username}.usage"

    sync_v2ray_config

    clear; show_banner
    echo -e "${C_GREEN}✅ User '$username' created!${C_RESET}\n"
    echo -e "  👤 Username : ${C_YELLOW}$username${C_RESET}"
    echo -e "  🔑 UUID     : ${C_YELLOW}$uuid${C_RESET}"
    echo -e "  📅 Expiry   : ${C_YELLOW}$expiry ($days days)${C_RESET}"
    echo -e "  📶 Limit    : ${C_YELLOW}$limit${C_RESET}"
    [[ "$bw" == "0" ]] && echo -e "  📦 BW       : ${C_GREEN}Unlimited${C_RESET}" || echo -e "  📦 BW       : ${C_YELLOW}$bw GB${C_RESET}"

    echo -e "\n${C_CYAN}📱 Nekobox Link:${C_RESET}"
    case "$V2RAY_PROTOCOL" in
        vless)  echo -e "  ${C_DIM}vless://$uuid@127.0.0.1:$V2RAY_PORT?encryption=none&security=none&type=tcp#$username${C_RESET}" ;;
        vmess)  echo -e "  ${C_DIM}vmess://$uuid@127.0.0.1:$V2RAY_PORT#$username${C_RESET}" ;;
        trojan) echo -e "  ${C_DIM}trojan://$uuid@127.0.0.1:$V2RAY_PORT#$username${C_RESET}" ;;
    esac
    echo -e "\n${C_ORANGE}⚠️  Mteja LAZIMA kutumia SlipNet kwanza (DNSTT tunnel)${C_RESET}"
    press_enter
}

# ============================================================
# DELETE V2RAY USER
# ============================================================
delete_v2ray_user() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️  Delete V2Ray User ---${C_RESET}\n"

    if [ ! -s "$V2RAY_USERS_DB" ]; then
        echo -e "${C_YELLOW}ℹ️  No users.${C_RESET}"; press_enter; return
    fi

    mapfile -t users < <(cut -d: -f1 "$V2RAY_USERS_DB" | sort)
    for i in "${!users[@]}"; do
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "${users[$i]}"
    done
    echo -e "\n  ${C_RED}[ 0]${C_RESET} Cancel\n"
    read -p "👉 Numbers (comma-separated, 'all'): " c
    [[ "$c" == "0" || -z "$c" ]] && { press_enter; return; }

    local -a to_delete=()
    if [[ "${c,,}" == "all" ]]; then
        to_delete=("${users[@]}")
    else
        c=$(echo "$c" | tr ',' ' ')
        for t in $c; do
            if [[ "$t" =~ ^[0-9]+$ ]] && [ "$t" -ge 1 ] && [ "$t" -le "${#users[@]}" ]; then
                to_delete+=("${users[$((t-1))]}")
            fi
        done
    fi

    [[ ${#to_delete[@]} -eq 0 ]] && { echo -e "${C_RED}❌ No valid selection${C_RESET}"; press_enter; return; }

    echo -e "\n${C_RED}⚠️  Delete ${#to_delete[@]} user(s)?${C_RESET}"
    read -p "Confirm (y/n): " confirm
    [[ "$confirm" != "y" ]] && { press_enter; return; }

    for u in "${to_delete[@]}"; do
        sed -i "/^${u}:/d" "$V2RAY_USERS_DB"
        rm -f "$BANDWIDTH_DIR/v2ray_${u}.usage"
        rm -f "$BANNER_DIR/v2ray_${u}.txt"
        echo -e "  ✅ ${C_YELLOW}$u${C_RESET} deleted"
    done

    sync_v2ray_config
    press_enter
}

# ============================================================
# EDIT V2RAY USER
# ============================================================
edit_v2ray_user() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ✏️  Edit V2Ray User ---${C_RESET}\n"

    if [ ! -s "$V2RAY_USERS_DB" ]; then
        echo -e "${C_YELLOW}ℹ️  No users.${C_RESET}"; press_enter; return
    fi

    mapfile -t users < <(cut -d: -f1 "$V2RAY_USERS_DB" | sort)
    for i in "${!users[@]}"; do
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "${users[$i]}"
    done
    echo -e "\n  ${C_RED}[ 0]${C_RESET} Cancel\n"
    read -p "👉 Select: " c
    [[ "$c" == "0" || -z "$c" ]] && { press_enter; return; }
    [[ ! "$c" =~ ^[0-9]+$ || "$c" -lt 1 || "$c" -gt "${#users[@]}" ]] && { press_enter; return; }

    local username="${users[$((c-1))]}"

    while true; do
        clear; show_banner
        local line=$(get_v2ray_user "$username")
        local uuid=$(echo "$line" | cut -d: -f2)
        local expiry=$(echo "$line" | cut -d: -f3)
        local limit=$(echo "$line" | cut -d: -f4)
        local bw=$(echo "$line" | cut -d: -f5)
        [[ -z "$bw" ]] && bw="0"

        echo -e "${C_BOLD}${C_PURPLE}--- Editing: ${C_YELLOW}$username${C_RESET}\n"
        echo -e "  🔑 UUID     : ${C_YELLOW}$uuid${C_RESET}"
        echo -e "  📅 Expiry   : ${C_YELLOW}$expiry${C_RESET}"
        echo -e "  📶 Limit    : ${C_YELLOW}$limit${C_RESET}"
        echo -e "  📦 BW       : ${C_YELLOW}${bw} GB${C_RESET}\n"
        echo -e "  ${C_GREEN}1)${C_RESET} 🔑 Change UUID"
        echo -e "  ${C_GREEN}2)${C_RESET} 📅 Change Expiry"
        echo -e "  ${C_GREEN}3)${C_RESET} 📶 Change Limit"
        echo -e "  ${C_GREEN}4)${C_RESET} 📦 Change Bandwidth"
        echo -e "  ${C_GREEN}5)${C_RESET} 🔄 Reset Bandwidth Usage"
        echo -e "  ${C_RED}0)${C_RESET} Finish\n"

        read -p "👉 Choice: " ec
        case $ec in
            1)
                read -p "New UUID (Enter=auto): " nu
                [[ -z "$nu" ]] && nu=$(generate_unique_uuid)
                awk -F: -v u="$username" -v x="$nu" 'BEGIN{OFS=":"} $1==u{$2=x}1' "$V2RAY_USERS_DB" > "$V2RAY_USERS_DB.tmp" && mv "$V2RAY_USERS_DB.tmp" "$V2RAY_USERS_DB"
                sync_v2ray_config
                echo -e "${C_GREEN}✅ UUID updated${C_RESET}"; press_enter ;;
            2)
                read -p "New days: " d
                if [[ "$d" =~ ^[0-9]+$ ]]; then
                    local ne=$(date -d "+$d days" +%Y-%m-%d)
                    awk -F: -v u="$username" -v e="$ne" 'BEGIN{OFS=":"} $1==u{$3=e;$7="ACTIVE"}1' "$V2RAY_USERS_DB" > "$V2RAY_USERS_DB.tmp" && mv "$V2RAY_USERS_DB.tmp" "$V2RAY_USERS_DB"
                    sync_v2ray_config
                    echo -e "${C_GREEN}✅ Expiry: $ne${C_RESET}"
                fi
                press_enter ;;
            3)
                read -p "New limit: " nl
                [[ "$nl" =~ ^[0-9]+$ ]] && {
                    awk -F: -v u="$username" -v l="$nl" 'BEGIN{OFS=":"} $1==u{$4=l}1' "$V2RAY_USERS_DB" > "$V2RAY_USERS_DB.tmp" && mv "$V2RAY_USERS_DB.tmp" "$V2RAY_USERS_DB"
                    echo -e "${C_GREEN}✅ Limit: $nl${C_RESET}"
                }
                press_enter ;;
            4)
                read -p "New BW (GB, 0=unlimited): " nb
                [[ "$nb" =~ ^[0-9]+\.?[0-9]*$ ]] && {
                    awk -F: -v u="$username" -v b="$nb" 'BEGIN{OFS=":"} $1==u{$5=b}1' "$V2RAY_USERS_DB" > "$V2RAY_USERS_DB.tmp" && mv "$V2RAY_USERS_DB.tmp" "$V2RAY_USERS_DB"
                    sync_v2ray_config
                    echo -e "${C_GREEN}✅ BW: $nb GB${C_RESET}"
                }
                press_enter ;;
            5)
                echo "0" > "$BANDWIDTH_DIR/v2ray_${username}.usage"
                awk -F: -v u="$username" 'BEGIN{OFS=":"} $1==u{$6=0}1' "$V2RAY_USERS_DB" > "$V2RAY_USERS_DB.tmp" && mv "$V2RAY_USERS_DB.tmp" "$V2RAY_USERS_DB"
                sync_v2ray_config
                echo -e "${C_GREEN}✅ BW usage reset${C_RESET}"; press_enter ;;
            0) return ;;
        esac
    done
}

# ============================================================
# LIST V2RAY USERS (na BANDWIDTH BAR)
# ============================================================
list_v2ray_users() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}═══ 📋 V2RAY USERS LIST ═══${C_RESET}\n"

    if [ ! -s "$V2RAY_USERS_DB" ]; then
        echo -e "${C_YELLOW}ℹ️  No users.${C_RESET}"; press_enter; return
    fi

    local total=0
    while IFS=: read -r user uuid expiry limit bw traffic account_status; do
        [[ -z "$user" || "$user" == \#* ]] && continue
        ((total++))

        # ============ BANDWIDTH BAR ============
        local ub=0
        [[ -f "$BANDWIDTH_DIR/v2ray_${user}.usage" ]] && ub=$(cat "$BANDWIDTH_DIR/v2ray_${user}.usage" 2>/dev/null | tr -d '[:space:]')
        [[ ! "$ub" =~ ^[0-9]+$ ]] && ub=0

        local bw_display=""
        if [[ "$bw" == "0" || -z "$bw" ]]; then
            bw_display="${C_GREEN}Unlimited ∞${C_RESET}"
        else
            local qb=$(awk "BEGIN{printf \"%.0f\", $bw*1073741824}")
            local pct=0
            (( qb > 0 )) && pct=$(awk "BEGIN{printf \"%.1f\", ($ub/$qb)*100}")
            local pct_int=$(awk "BEGIN{printf \"%d\", $pct}")
            [[ $pct_int -gt 100 ]] && pct_int=100
            [[ $pct_int -lt 0 ]] && pct_int=0
            local bar=$(build_bar "$pct_int" 10)
            local color=$(get_bar_color "$pct_int")
            local used_disp=$(format_size "$ub")
            local limit_disp=$(format_size "$qb")
            bw_display="${color}${bar}${C_RESET} ${pct}% | ${used_disp}/${limit_disp}"
        fi

        # ============ STATUS ============
        local st=$(get_v2ray_status "$user")
        local st_display=""; local st_color=""
        case "$st" in
            ACTIVE)    st_display="✅ ACTIVE"; st_color="$C_GREEN" ;;
            LOCKED)    st_display="🔒 LOCKED"; st_color="$C_RED" ;;
            EXPIRED)   st_display="🗓️ EXPIRED"; st_color="$C_ORANGE" ;;
            EXHAUSTED) st_display="📦 EXHAUSTED"; st_color="$C_ORANGE" ;;
            *)         st_display="❓ UNKNOWN"; st_color="$C_GRAY" ;;
        esac

        # ============ DAYS LEFT ============
        local dl=$(get_v2ray_days_left "$user")
        local dl_display="${dl} days"
        [[ $dl -lt 0 ]] && dl_display="expired"
        [[ $dl -eq 0 ]] && dl_display="today"

        echo -e "${C_CYAN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
        printf "${C_CYAN}│${C_RESET} USER:   ${C_WHITE}%-51s${C_CYAN}│${C_RESET}\n" "$user"
        printf "${C_CYAN}│${C_RESET} UUID:   ${C_WHITE}%-51s${C_CYAN}│${C_RESET}\n" "$uuid"
        printf "${C_CYAN}│${C_RESET} EXPIRY: ${C_WHITE}%-51s${C_CYAN}│${C_RESET}\n" "$expiry ($dl_display)"
        printf "${C_CYAN}│${C_RESET} BW:     %-51b${C_CYAN}│${C_RESET}\n" "$bw_display"
        printf "${C_CYAN}│${C_RESET} STATUS: ${st_color}%-51s${C_RESET}${C_CYAN}│${C_RESET}\n" "$st_display"
        echo -e "${C_CYAN}└─────────────────────────────────────────────────────────────┘${C_RESET}"
    done < "$V2RAY_USERS_DB"

    echo -e "\n  ${C_CYAN}Total: $total users${C_RESET}"
    press_enter
}

# ============================================================
# LOCK V2RAY USER
# ============================================================
lock_v2ray_user() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔒 Lock V2Ray User ---${C_RESET}\n"
    mapfile -t users < <(cut -d: -f1 "$V2RAY_USERS_DB" | sort)
    [[ ${#users[@]} -eq 0 ]] && { echo -e "${C_YELLOW}No users.${C_RESET}"; press_enter; return; }

    for i in "${!users[@]}"; do
        local st=$(get_v2ray_status "${users[$i]}")
        printf "  ${C_GREEN}[%2d]${C_RESET} %-20s ${C_DIM}(%s)${C_RESET}\n" "$((i+1))" "${users[$i]}" "$st"
    done
    echo -e "\n  ${C_RED}[ 0]${C_RESET} Cancel\n"
    read -p "👉 Numbers (comma-separated, 'all'): " c
    [[ "$c" == "0" || -z "$c" ]] && { press_enter; return; }

    local -a to_lock=()
    if [[ "${c,,}" == "all" ]]; then
        to_lock=("${users[@]}")
    else
        c=$(echo "$c" | tr ',' ' ')
        for t in $c; do
            if [[ "$t" =~ ^[0-9]+$ ]] && [ "$t" -ge 1 ] && [ "$t" -le "${#users[@]}" ]; then
                to_lock+=("${users[$((t-1))]}")
            fi
        done
    fi

    for u in "${to_lock[@]}"; do
        awk -F: -v u="$u" 'BEGIN{OFS=":"} $1==u{$7="LOCKED"}1' "$V2RAY_USERS_DB" > "$V2RAY_USERS_DB.tmp" && mv "$V2RAY_USERS_DB.tmp" "$V2RAY_USERS_DB"
        echo -e "  ✅ ${C_YELLOW}$u${C_RESET} locked"
    done

    sync_v2ray_config
    press_enter
}

# ============================================================
# UNLOCK V2RAY USER
# ============================================================
unlock_v2ray_user() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔓 Unlock V2Ray User ---${C_RESET}\n"
    mapfile -t users < <(cut -d: -f1 "$V2RAY_USERS_DB" | sort)
    [[ ${#users[@]} -eq 0 ]] && { echo -e "${C_YELLOW}No users.${C_RESET}"; press_enter; return; }

    for i in "${!users[@]}"; do
        local st=$(get_v2ray_status "${users[$i]}")
        printf "  ${C_GREEN}[%2d]${C_RESET} %-20s ${C_DIM}(%s)${C_RESET}\n" "$((i+1))" "${users[$i]}" "$st"
    done
    echo -e "\n  ${C_RED}[ 0]${C_RESET} Cancel\n"
    read -p "👉 Numbers (comma-separated, 'all'): " c
    [[ "$c" == "0" || -z "$c" ]] && { press_enter; return; }

    local -a to_unlock=()
    if [[ "${c,,}" == "all" ]]; then
        to_unlock=("${users[@]}")
    else
        c=$(echo "$c" | tr ',' ' ')
        for t in $c; do
            if [[ "$t" =~ ^[0-9]+$ ]] && [ "$t" -ge 1 ] && [ "$t" -le "${#users[@]}" ]; then
                to_unlock+=("${users[$((t-1))]}")
            fi
        done
    fi

    for u in "${to_unlock[@]}"; do
        awk -F: -v u="$u" 'BEGIN{OFS=":"} $1==u{$7="ACTIVE"}1' "$V2RAY_USERS_DB" > "$V2RAY_USERS_DB.tmp" && mv "$V2RAY_USERS_DB.tmp" "$V2RAY_USERS_DB"
        echo -e "  ✅ ${C_YELLOW}$u${C_RESET} unlocked"
    done

    sync_v2ray_config
    press_enter
}

# ============================================================
# RENEW V2RAY USER
# ============================================================
renew_v2ray_user() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔄 Renew V2Ray User ---${C_RESET}\n"
    mapfile -t users < <(cut -d: -f1 "$V2RAY_USERS_DB" | sort)
    [[ ${#users[@]} -eq 0 ]] && { echo -e "${C_YELLOW}No users.${C_RESET}"; press_enter; return; }

    for i in "${!users[@]}"; do
        local dl=$(get_v2ray_days_left "${users[$i]}")
        printf "  ${C_GREEN}[%2d]${C_RESET} %-20s ${C_DIM}(%s days)${C_RESET}\n" "$((i+1))" "${users[$i]}" "$dl"
    done
    echo -e "\n  ${C_RED}[ 0]${C_RESET} Cancel\n"
    read -p "👉 Numbers (comma-separated, 'all'): " c
    [[ "$c" == "0" || -z "$c" ]] && { press_enter; return; }

    read -p "Days to extend [30]: " days; days=${days:-30}
    [[ ! "$days" =~ ^[0-9]+$ ]] && { press_enter; return; }

    local -a to_renew=()
    if [[ "${c,,}" == "all" ]]; then
        to_renew=("${users[@]}")
    else
        c=$(echo "$c" | tr ',' ' ')
        for t in $c; do
            if [[ "$t" =~ ^[0-9]+$ ]] && [ "$t" -ge 1 ] && [ "$t" -le "${#users[@]}" ]; then
                to_renew+=("${users[$((t-1))]}")
            fi
        done
    fi

    for u in "${to_renew[@]}"; do
        local line=$(get_v2ray_user "$u")
        local old_expiry=$(echo "$line" | cut -d: -f3)
        local old_et=$(date -d "$old_expiry" +%s 2>/dev/null || echo $(date +%s))
        local now=$(date +%s)
        [[ $old_et -lt $now ]] && old_et=$now
        local new_et=$((old_et + days * 86400))
        local new_expiry=$(date -d "@$new_et" +%Y-%m-%d)

        awk -F: -v u="$u" -v e="$new_expiry" 'BEGIN{OFS=":"} $1==u{$3=e;$7="ACTIVE"}1' "$V2RAY_USERS_DB" > "$V2RAY_USERS_DB.tmp" && mv "$V2RAY_USERS_DB.tmp" "$V2RAY_USERS_DB"
        echo -e "  ✅ ${C_YELLOW}$u${C_RESET} → ${C_GREEN}$new_expiry${C_RESET}"
    done

    sync_v2ray_config
    press_enter
}

# ============================================================
# CLEANUP EXPIRED V2RAY USERS
# ============================================================
cleanup_expired_v2ray() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🧹 Cleanup Expired V2Ray Users ---${C_RESET}\n"

    local -a expired=()
    while IFS=: read -r user uuid expiry limit bw traffic status; do
        [[ -z "$user" ]] && continue
        local et=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
        [[ $et -gt 0 && $et -lt $(date +%s) ]] && expired+=("$user")
    done < "$V2RAY_USERS_DB"

    if [[ ${#expired[@]} -eq 0 ]]; then
        echo -e "${C_GREEN}✅ No expired users.${C_RESET}"; press_enter; return
    fi

    echo -e "Expired: ${C_RED}${expired[*]}${C_RESET}\n"
    read -p "Delete all? (y/n): " c
    [[ "$c" == "y" ]] || { press_enter; return; }

    for u in "${expired[@]}"; do
        sed -i "/^${u}:/d" "$V2RAY_USERS_DB"
        rm -f "$BANDWIDTH_DIR/v2ray_${u}.usage"
        rm -f "$BANNER_DIR/v2ray_${u}.txt"
        echo -e "  ✅ ${C_YELLOW}$u${C_RESET} deleted"
    done

    sync_v2ray_config
    press_enter
}

# ============================================================
# BULK CREATE V2RAY USERS
# ============================================================
bulk_create_v2ray() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📦 Bulk Create V2Ray Users ---${C_RESET}\n"

    read -p "Prefix: " prefix
    [[ -z "$prefix" ]] && { press_enter; return; }

    read -p "Count (1-100) [10]: " count; count=${count:-10}
    [[ ! "$count" =~ ^[0-9]+$ || "$count" -lt 1 || "$count" -gt 100 ]] && { press_enter; return; }

    read -p "Days [30]: " days; days=${days:-30}
    read -p "Limit [999]: " limit; limit=${limit:-999}
    read -p "BW GB [0]: " bw; bw=${bw:-0}

    local expiry=$(date -d "+$days days" +%Y-%m-%d)
    local created=0

    for ((i=1; i<=count; i++)); do
        local u="${prefix}${i}"
        v2ray_user_exists "$u" && continue
        local uuid=$(generate_unique_uuid)
        echo "$u:$uuid:$expiry:$limit:$bw:0:ACTIVE" >> "$V2RAY_USERS_DB"
        echo "0" > "$BANDWIDTH_DIR/v2ray_${u}.usage"
        printf "  ${C_GREEN}%-15s${C_RESET} | ${C_CYAN}%-38s${C_RESET} | ${C_YELLOW}%-12s${C_RESET}\n" "$u" "$uuid" "$expiry"
        ((created++))
    done

    sync_v2ray_config
    echo -e "\n${C_GREEN}✅ Created $created users${C_RESET}"
    press_enter
}

# ============================================================
# VIEW V2RAY BANDWIDTH (WIMA — box kwa kila user)
# ============================================================
view_v2ray_bandwidth() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📊 V2Ray Bandwidth ---${C_RESET}\n"

    if [ ! -s "$V2RAY_USERS_DB" ]; then
        echo -e "${C_YELLOW}No users.${C_RESET}"; press_enter; return
    fi

    while IFS=: read -r user uuid expiry limit bw traffic status; do
        [[ -z "$user" ]] && continue

        local ub=0
        [[ -f "$BANDWIDTH_DIR/v2ray_${user}.usage" ]] && ub=$(cat "$BANDWIDTH_DIR/v2ray_${user}.usage" 2>/dev/null | tr -d '[:space:]')
        [[ ! "$ub" =~ ^[0-9]+$ ]] && ub=0

        local bw_display=""
        local used_limit_disp=""

        if [[ "$bw" == "0" || -z "$bw" ]]; then
            bw_display="${C_GREEN}Unlimited ∞${C_RESET}"
            used_limit_disp="$(format_size "$ub") / ∞"
        else
            local qb=$(awk "BEGIN{printf \"%.0f\", $bw*1073741824}")
            local pct=0
            (( qb > 0 )) && pct=$(awk "BEGIN{printf \"%.1f\", ($ub/$qb)*100}")
            local pct_int=$(awk "BEGIN{printf \"%d\", $pct}")
            [[ $pct_int -gt 100 ]] && pct_int=100
            [[ $pct_int -lt 0 ]] && pct_int=0
            local bar=$(build_bar "$pct_int" 10)
            local color=$(get_bar_color "$pct_int")
            local used_disp=$(format_size "$ub")
            local limit_disp=$(format_size "$qb")
            bw_display="${color}${bar}${C_RESET} ${pct}%"
            used_limit_disp="${used_disp} / ${limit_disp}"
        fi

        local st=$(get_v2ray_status "$user")
        local st_display=""
        case "$st" in
            ACTIVE)    st_display="${C_GREEN}✅ ACTIVE${C_RESET}" ;;
            LOCKED)    st_display="${C_RED}🔒 LOCKED${C_RESET}" ;;
            EXPIRED)   st_display="${C_ORANGE}🗓️ EXPIRED${C_RESET}" ;;
            EXHAUSTED) st_display="${C_ORANGE}📦 EXHAUSTED${C_RESET}" ;;
            *)         st_display="${C_GRAY}❓ UNKNOWN${C_RESET}" ;;
        esac

        echo -e "${C_CYAN}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
        echo -e "${C_CYAN}│${C_RESET} 👤 USER   : ${C_GREEN}${user}${C_RESET}"
        echo -e "${C_CYAN}│${C_RESET} 📊 BW     : ${bw_display}  (${used_limit_disp})"
        echo -e "${C_CYAN}│${C_RESET} 📌 STATUS : ${st_display}"
        echo -e "${C_CYAN}└─────────────────────────────────────────────────────────────┘${C_RESET}"
        echo ""
    done < "$V2RAY_USERS_DB"

    press_enter
}

# ============================================================
# SHOW V2RAY CLIENT CONFIG
# ============================================================
show_v2ray_client_config() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📱 V2Ray Client Config ---${C_RESET}\n"

    mapfile -t users < <(cut -d: -f1 "$V2RAY_USERS_DB" | sort)
    [[ ${#users[@]} -eq 0 ]] && { echo -e "${C_YELLOW}No users.${C_RESET}"; press_enter; return; }

    for i in "${!users[@]}"; do
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "${users[$i]}"
    done
    echo -e "\n  ${C_RED}[ 0]${C_RESET} Cancel\n"
    read -p "👉 Select: " c
    [[ "$c" == "0" || -z "$c" ]] && { press_enter; return; }
    [[ ! "$c" =~ ^[0-9]+$ || "$c" -lt 1 || "$c" -gt "${#users[@]}" ]] && { press_enter; return; }

    local username="${users[$((c-1))]}"
    local line=$(get_v2ray_user "$username")
    local uuid=$(echo "$line" | cut -d: -f2)
    local expiry=$(echo "$line" | cut -d: -f3)
    local limit=$(echo "$line" | cut -d: -f4)
    local bw=$(echo "$line" | cut -d: -f5)
    local traffic=$(echo "$line" | cut -d: -f6)

    source "$V2RAY_INFO_FILE" 2>/dev/null
    local pubkey=$(cat "$DNSTT_KEYS_DIR/server.pub" 2>/dev/null)
    local domain=$(cat "$DB_DIR/domain.txt" 2>/dev/null)
    local mtu=$(get_current_mtu)

    echo ""
    echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_PURPLE}              📱 CLIENT CONFIG: $username${C_RESET}"
    echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"

    echo -e "${C_GREEN}🔐 DNSTT Tunnel (SlipNet):${C_RESET}"
    echo -e "  Domain      : ${C_YELLOW}$domain${C_RESET}"
    echo -e "  Public Key  : ${C_YELLOW}$pubkey${C_RESET}"
    echo -e "  DNS Resolver: ${C_YELLOW}8.8.8.8:53${C_RESET}"
    echo -e "  MTU         : ${C_YELLOW}$mtu${C_RESET}\n"

    echo -e "${C_GREEN}🔷 V2Ray Protocol (Nekobox):${C_RESET}"
    echo -e "  Protocol    : ${C_YELLOW}$V2RAY_PROTOCOL${C_RESET}"
    echo -e "  Address     : ${C_YELLOW}127.0.0.1${C_RESET}"
    echo -e "  Port        : ${C_YELLOW}$V2RAY_PORT${C_RESET}"
    echo -e "  UUID/Pass   : ${C_YELLOW}$uuid${C_RESET}"
    echo -e "  Encryption  : ${C_YELLOW}none${C_RESET}"
    echo -e "  Transport   : ${C_YELLOW}tcp${C_RESET}"
    echo -e "  Security    : ${C_YELLOW}none${C_RESET}\n"

    echo -e "${C_CYAN}📋 Nekobox Link:${C_RESET}"
    case "$V2RAY_PROTOCOL" in
        vless)  echo -e "  ${C_DIM}vless://$uuid@127.0.0.1:$V2RAY_PORT?encryption=none&security=none&type=tcp#$username${C_RESET}" ;;
        vmess)  echo -e "  ${C_DIM}vmess://$uuid@127.0.0.1:$V2RAY_PORT#$username${C_RESET}" ;;
        trojan) echo -e "  ${C_DIM}trojan://$uuid@127.0.0.1:$V2RAY_PORT#$username${C_RESET}" ;;
    esac

    echo -e "\n${C_ORANGE}⚠️  HATUA MUHIMU:${C_RESET}"
    echo -e "  1. Nekobox → Outbound → SOCKS5 127.0.0.1:1080"
    echo -e "  2. Nekobox → Routing → 127.0.0.1/32 → Direct"
    echo -e "  3. Washa SlipNet KWANZA, kisha Nekobox\n"

    echo -e "${C_CYAN}📅 Expiry    : ${C_YELLOW}$expiry${C_RESET}"
    echo -e "${C_CYAN}📶 Limit     : ${C_YELLOW}$limit${C_RESET}"
    echo -e "${C_CYAN}📦 BW        : ${C_YELLOW}$bw GB${C_RESET}"
    echo -e "${C_CYAN}📊 Used      : ${C_YELLOW}$traffic GB${C_RESET}"

    press_enter
}

# ============================================================
# V2RAY TRIAL ACCOUNT
# ============================================================
setup_trial_cleanup_script() {
    cat > "$TRIAL_CLEANUP_SCRIPT" << 'TREOF'
#!/bin/bash
username="$1"
[[ -z "$username" ]] && exit 1
sed -i "/^${username}:/d" /etc/dnstt-v2ray/v2ray_users.db
rm -f /etc/dnstt-v2ray/bandwidth/v2ray_${username}.usage
rm -f /etc/dnstt-v2ray/banners/v2ray_${username}.txt
systemctl restart v2ray-dnstt.service 2>/dev/null
TREOF
    chmod +x "$TRIAL_CLEANUP_SCRIPT"
}

create_trial_v2ray() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ⏱️  V2Ray Trial Account ---${C_RESET}\n"

    if ! command -v at &>/dev/null; then
        ff_apt_install at >/dev/null 2>&1
        systemctl enable atd &>/dev/null
        systemctl start atd &>/dev/null
    fi

    setup_trial_cleanup_script

    echo -e "\nSelect duration:\n"
    echo -e "  ${C_GREEN}[1]${C_RESET} 1 Hour    ${C_GREEN}[5]${C_RESET} 12 Hours"
    echo -e "  ${C_GREEN}[2]${C_RESET} 2 Hours   ${C_GREEN}[6]${C_RESET} 1 Day"
    echo -e "  ${C_GREEN}[3]${C_RESET} 3 Hours   ${C_GREEN}[7]${C_RESET} 3 Days"
    echo -e "  ${C_GREEN}[4]${C_RESET} 6 Hours   ${C_GREEN}[8]${C_RESET} Custom"
    echo -e "\n  ${C_RED}[0]${C_RESET} Cancel"
    read -p "👉 Choice: " dur_choice

    local duration_hours=0
    local duration_label=""

    case $dur_choice in
        1) duration_hours=1; duration_label="1 Hour" ;;
        2) duration_hours=2; duration_label="2 Hours" ;;
        3) duration_hours=3; duration_label="3 Hours" ;;
        4) duration_hours=6; duration_label="6 Hours" ;;
        5) duration_hours=12; duration_label="12 Hours" ;;
        6) duration_hours=24; duration_label="1 Day" ;;
        7) duration_hours=72; duration_label="3 Days" ;;
        8)
            read -p "Hours: " ch
            [[ ! "$ch" =~ ^[0-9]+$ ]] && return
            duration_hours=$ch
            duration_label="$ch Hours"
            ;;
        0) return ;;
        *) return ;;
    esac

    local rand_suffix=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 5)
    local default_username="trial_${rand_suffix}"

    read -p "👤 Username [${default_username}]: " username
    username=${username:-$default_username}

    if v2ray_user_exists "$username"; then
        echo -e "\n${C_RED}❌ Exists.${C_RESET}"; press_enter; return
    fi

    local uuid=$(generate_unique_uuid)
    read -p "📶 Limit [999]: " limit; limit=${limit:-999}
    read -p "📦 BW GB [0]: " bw; bw=${bw:-0}

    local expire_date
    if [[ "$duration_hours" -ge 24 ]]; then
        expire_date=$(date -d "+$((duration_hours/24)) days" +%Y-%m-%d)
    else
        expire_date=$(date -d "+1 day" +%Y-%m-%d)
    fi

    local expiry_timestamp=$(date -d "+${duration_hours} hours" '+%Y-%m-%d %H:%M:%S')

    echo "$username:$uuid:$expire_date:$limit:$bw:0:ACTIVE" >> "$V2RAY_USERS_DB"
    echo "0" > "$BANDWIDTH_DIR/v2ray_${username}.usage"

    echo "$TRIAL_CLEANUP_SCRIPT $username" | at now + ${duration_hours} hours 2>/dev/null

    sync_v2ray_config

    clear; show_banner
    echo -e "${C_GREEN}✅ Trial created!${C_RESET}\n"
    echo -e "  👤 ${C_YELLOW}$username${C_RESET}"
    echo -e "  🔑 ${C_YELLOW}$uuid${C_RESET}"
    echo -e "  ⏱️  ${C_CYAN}$duration_label${C_RESET}"
    echo -e "  🕐 ${C_RED}$expiry_timestamp${C_RESET}"
    press_enter
}

# ============================================================
# V2RAY DYNAMIC BANNER
# ============================================================
create_v2ray_banner_builder() {
    cat > "$BANNER_BUILDER" << 'BBEOF'
#!/bin/bash
user="$1"
expiry="$2"
bandwidth_gb="$3"
status="$4"
status_color="$5"
traffic="$6"

BANDWIDTH_DIR="/etc/dnstt-v2ray/bandwidth"

format_size() {
    local bytes=$1
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    if (( bytes >= 1073741824 )); then
        awk "BEGIN{printf \"%.2f GB\", $bytes/1073741824}"
    elif (( bytes >= 1048576 )); then
        awk "BEGIN{printf \"%.2f MB\", $bytes/1048576}"
    elif (( bytes >= 1024 )); then
        awk "BEGIN{printf \"%.2f KB\", $bytes/1024}"
    else
        echo "${bytes} B"
    fi
}

bw_info=""
if [[ "$bandwidth_gb" == "0" || -z "$bandwidth_gb" ]]; then
    bw_info="Unlimited"
else
    ub=0
    usage_file="$BANDWIDTH_DIR/v2ray_${user}.usage"
    [[ -f "$usage_file" ]] && ub=$(cat "$usage_file" 2>/dev/null | tr -d '[:space:]')
    [[ ! "$ub" =~ ^[0-9]+$ ]] && ub=0

    limit_bytes=$(awk "BEGIN{printf \"%.0f\", $bandwidth_gb*1073741824}")
    [[ "$limit_bytes" -le 0 ]] && limit_bytes=1
    pct=$(awk "BEGIN{printf \"%.1f\", ($ub/$limit_bytes)*100}")
    pct_int=$(awk "BEGIN{printf \"%d\", $pct}")
    [[ "$pct_int" -gt 100 ]] && pct_int=100
    [[ "$pct_int" -lt 0 ]] && pct_int=0

    used_disp=$(format_size "$ub")
    limit_disp=$(format_size "$limit_bytes")

    total_blocks=10
    filled=$((pct_int * total_blocks / 100))
    bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=filled; i<total_blocks; i++)); do bar+="░"; done

    bw_info="${bar} ${pct}% | ${used_disp}/${limit_disp}"
fi

uptime_str=$(uptime -p | sed 's/up //')
load_str=$(awk '{print $1}' /proc/loadavg)

echo "<br>"
echo "<center><b>🔷 VOLTRON V2RAY 🔷</b></center><br>"
echo "<center>👤 Username : <b>$user</b></center><br>"
echo "<center>📅 Expiry   : <b>$expiry</b></center><br>"
echo "<center>📊 BW       : $bw_info</center><br>"
echo "<center>📌 Status   : <font color=\"$status_color\"><b>$status</b></font></center><br>"
echo "<center>📈 Load     : $load_str</center><br>"
echo "<center>⏱️  Uptime   : $uptime_str</center><br>"
BBEOF
    chmod +x "$BANNER_BUILDER"
}

generate_v2ray_banner() {
    local username="$1"
    local expiry="$2"
    local bw="$3"
    local traffic="$4"
    mkdir -p "$BANNER_DIR"

    local st=$(get_v2ray_status "$username")
    local st_display=""; local st_color=""
    case "$st" in
        ACTIVE)    st_display="✅ ACTIVE"; st_color="#6BCB77" ;;
        LOCKED)    st_display="🔒 LOCKED"; st_color="#FF6B6B" ;;
        EXPIRED)   st_display="🗓️ EXPIRED"; st_color="#FF9F43" ;;
        EXHAUSTED) st_display="📦 EXHAUSTED"; st_color="#FF9F43" ;;
        *)         st_display="❓ UNKNOWN"; st_color="#888888" ;;
    esac

    "$BANNER_BUILDER" "$username" "$expiry" "$bw" "$st_display" "$st_color" "$traffic" > "$BANNER_DIR/v2ray_${username}.txt" 2>/dev/null
    chmod 644 "$BANNER_DIR/v2ray_${username}.txt" 2>/dev/null
}

v2ray_banner_menu() {
    while true; do
        clear; show_banner
        local st="DISABLED"
        [[ -f "$BANNER_ENABLED_FILE" ]] && st="${C_GREEN}ENABLED${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}                 🎨 V2RAY DYNAMIC BANNER${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
        echo -e "  ${C_CYAN}Status${C_RESET} : $st\n"
        echo -e "  ${C_GREEN}[1]${C_RESET} Enable Dynamic Banner"
        echo -e "  ${C_RED}[2]${C_RESET} Disable Dynamic Banner"
        echo -e "  ${C_GREEN}[3]${C_RESET} Refresh/Regenerate All"
        echo -e "  ${C_GREEN}[4]${C_RESET} Preview User Banner"
        echo -e "  ${C_RED}[0]${C_RESET} Return"
        read -p "👉 Choice: " c
        case $c in
            1)
                mkdir -p "$BANNER_DIR"
                touch "$BANNER_ENABLED_FILE"
                create_v2ray_banner_builder
                while IFS=: read -r user uuid expiry limit bw traffic status; do
                    [[ -z "$user" ]] && continue
                    generate_v2ray_banner "$user" "$expiry" "$bw" "$traffic"
                done < "$V2RAY_USERS_DB"
                echo -e "${C_GREEN}✅ Enabled${C_RESET}"; press_enter ;;
            2)
                rm -f "$BANNER_ENABLED_FILE"
                echo -e "${C_GREEN}✅ Disabled${C_RESET}"; press_enter ;;
            3)
                create_v2ray_banner_builder
                while IFS=: read -r user uuid expiry limit bw traffic status; do
                    [[ -z "$user" ]] && continue
                    generate_v2ray_banner "$user" "$expiry" "$bw" "$traffic"
                done < "$V2RAY_USERS_DB"
                echo -e "${C_GREEN}✅ Refreshed${C_RESET}"; press_enter ;;
            4)
                _select_v2ray_user_interface "--- Preview Banner ---"
                local u=$SELECTED_USER
                [[ -z "$u" || "$u" == "NO_USERS" ]] && return
                [[ -f "$BANNER_DIR/v2ray_${u}.txt" ]] && cat "$BANNER_DIR/v2ray_${u}.txt" || echo "Not found"
                press_enter ;;
            0) return ;;
        esac
    done
}

# ============================================================
# V2RAY LIMITER (Xray Stats API — email-based)
# ============================================================
create_v2ray_limiter() {
    cat > "$V2RAY_LIMITER_SCRIPT" <<'LIMEOF'
#!/bin/bash
DB_FILE="/etc/dnstt-v2ray/v2ray_users.db"
BW_DIR="/etc/dnstt-v2ray/bandwidth"
V2RAY_CONFIG="/etc/dnstt-v2ray/v2ray/config.json"
XRAY_BIN="/usr/local/bin/xray"
XRAY_API="127.0.0.1:10085"
SCAN=15
CONFIG_DIRTY="/tmp/v2ray-config-dirty"
BANNER_ENABLED="/etc/dnstt-v2ray/banners_enabled"
BANNER_BUILDER="/usr/local/bin/v2ray-banner-build.sh"

mkdir -p "$BW_DIR"

while true; do
    [[ ! -s "$DB_FILE" ]] && { sleep $SCAN; continue; }
    dirty=0

    while IFS=: read -r user uuid expiry limit bw traffic status; do
        [[ -z "$user" || "$user" == \#* ]] && continue

        # ============ PATA STATS KWA EMAIL ============
        local email="${user}@dnstt"

        local uplink=$("$XRAY_BIN" api statsquery --server=$XRAY_API \
            -pattern "user>>>$email>>>traffic>>>uplink" 2>/dev/null | \
            grep -oP '"value":\s*\K[0-9]+' | head -1)
        local downlink=$("$XRAY_BIN" api statsquery --server=$XRAY_API \
            -pattern "user>>>$email>>>traffic>>>downlink" 2>/dev/null | \
            grep -oP '"value":\s*\K[0-9]+' | head -1)

        [[ -z "$uplink" ]] && uplink=0
        [[ -z "$downlink" ]] && downlink=0

        local total=$((uplink + downlink))
        local total_gb=$(awk "BEGIN{printf \"%.4f\", $total/1073741824}")

        # ============ UPDATE DATABASE ============
        awk -F: -v u="$user" -v t="$total_gb" \
            'BEGIN{OFS=":"} $1==u{$6=t}1' "$DB_FILE" > "$DB_FILE.tmp" && \
            mv "$DB_FILE.tmp" "$DB_FILE"

        printf "%s\n" "$total" > "$BW_DIR/v2ray_${user}.usage"

        # ============ KAGUA BANDWIDTH ============
        if [[ "$bw" != "0" && -n "$bw" ]]; then
            local qb=$(awk "BEGIN{printf \"%.0f\", $bw*1073741824}")
            if (( total >= qb )); then
                if [[ "$status" != "EXHAUSTED" ]]; then
                    awk -F: -v u="$user" \
                        'BEGIN{OFS=":"} $1==u{$7="EXHAUSTED"}1' "$DB_FILE" > "$DB_FILE.tmp" && \
                        mv "$DB_FILE.tmp" "$DB_FILE"
                    dirty=1
                fi
            fi
        fi

        # ============ KAGUA EXPIRY ============
        local et=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
        if [[ $et -gt 0 && $et -lt $(date +%s) ]]; then
            if [[ "$status" != "EXPIRED" ]]; then
                awk -F: -v u="$user" \
                    'BEGIN{OFS=":"} $1==u{$7="EXPIRED"}1' "$DB_FILE" > "$DB_FILE.tmp" && \
                    mv "$DB_FILE.tmp" "$DB_FILE"
                dirty=1
            fi
        fi

        # ============ UPDATE BANNER ============
        if [[ -f "$BANNER_ENABLED" && -x "$BANNER_BUILDER" ]]; then
            "$BANNER_BUILDER" "$user" "$expiry" "$bw" "$status" "$dirty" "$total_gb" > "/etc/dnstt-v2ray/banners/v2ray_${user}.txt" 2>/dev/null
        fi
    done < "$DB_FILE"

    # ============ RELOAD V2RAY KAMA CONFIG IMEBADILIKA ============
    if [[ $dirty -eq 1 ]]; then
        touch "$CONFIG_DIRTY"
    fi

    sleep $SCAN
done
LIMEOF
    chmod +x "$V2RAY_LIMITER_SCRIPT"

    cat > "$V2RAY_LIMITER_SERVICE" <<EOF
[Unit]
Description=V2Ray Limiter (Xray Stats API)
After=network.target v2ray-dnstt.service
Requires=v2ray-dnstt.service

[Service]
Type=simple
ExecStart=$V2RAY_LIMITER_SCRIPT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable v2ray-limiter.service >/dev/null 2>&1
    systemctl restart v2ray-limiter.service >/dev/null 2>&1
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
    else
        echo "❌ Unsupported: $arch"
        return 1
    fi
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
    read -p "👉 Choice [1]: " mtu_choice
    mtu_choice=${mtu_choice:-1}
    case $mtu_choice in
        1) MTU=512 ;;
        2) MTU=900 ;;
        3) MTU=1200 ;;
        4) MTU=1400 ;;
        5) MTU=1500 ;;
        6)
            read -p "👉 MTU: " cm
            if [[ "$cm" =~ ^[0-9]+$ ]] && [ "$cm" -ge 512 ] && [ "$cm" -le 1500 ]; then
                MTU=$cm
            else
                MTU=512
            fi
            ;;
        *) MTU=512 ;;
    esac
    mkdir -p "$CONFIG_DIR"
    echo "$MTU" > "$MTU_CONFIG"
    echo -e "\n${C_GREEN}✅ MTU set to: $MTU${C_RESET}"
}

generate_keys() {
    mkdir -p "$DNSTT_KEYS_DIR"
    cd "$DNSTT_KEYS_DIR"
    rm -f server.key server.pub
    "$DNSTT_BINARY" -gen-key -privkey-file server.key -pubkey-file server.pub 2>/dev/null || {
        openssl rand -hex 32 > server.key
        cat server.key | sha256sum | awk '{print $1}' > server.pub
    }
    chmod 600 server.key
    chmod 644 server.pub
    PUBLIC_KEY=$(cat server.pub)
}

setup_domain() {
    echo -e "\n${C_BLUE}🌐 Domain config${C_RESET}\n"
    echo -e "  ${C_GREEN}1)${C_RESET} Custom domain"
    echo -e "  ${C_GREEN}2)${C_RESET} Auto-generate with deSEC"
    read -p "👉 [2]: " opt
    opt=${opt:-2}
    if [[ "$opt" == "2" ]]; then
        local rand=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 3)
        local ns="ns-$rand"
        local tun="tun-$rand"
        local ip=$(curl -s -4 icanhazip.com)
        curl -s -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
            -H "Authorization: Token $DESEC_TOKEN" \
            -H "Content-Type: application/json" \
            --data "[{\"subname\":\"$ns\",\"type\":\"A\",\"ttl\":3600,\"records\":[\"$ip\"]}]" >/dev/null 2>&1
        local r=$(curl -s -w "%{http_code}" -X POST \
            "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
            -H "Authorization: Token $DESEC_TOKEN" \
            -H "Content-Type: application/json" \
            --data "[{\"subname\":\"$tun\",\"type\":\"NS\",\"ttl\":3600,\"records\":[\"$ns.$DESEC_DOMAIN.\"]}]")
        if [[ "${r: -3}" -eq 201 ]]; then
            DOMAIN="$tun.$DESEC_DOMAIN"
            echo -e "${C_GREEN}✅ $DOMAIN${C_RESET}"
        else
            read -p "Domain: " DOMAIN
        fi
    else
        read -p "Domain: " DOMAIN
    fi
    echo "$DOMAIN" > "$DB_DIR/domain.txt"
}

create_dnstt_service() {
    local domain=$1 mtu=$2
    mkdir -p "$LOGS_DIR"

    if [ ! -f "$V2RAY_INFO_FILE" ]; then
        echo -e "${C_RED}❌ V2Ray info haipo.${C_RESET}"
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

configure_dnstt_firewall() {
    echo -e "\n${C_BLUE}🔥 Configuring firewall...${C_RESET}"
    ! command -v iptables &>/dev/null && ff_apt_install iptables iptables-persistent
    iptables -t nat -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p udp --sport 53 -j ACCEPT
    iptables -A INPUT -p udp --dport 5300 -j ACCEPT
    iptables -A OUTPUT -p udp --sport 5300 -j ACCEPT
    iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    echo -e "${C_GREEN}✅ Firewall configured${C_RESET}"
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
    echo -e "  ${C_CYAN}Port${C_RESET}          : ${C_YELLOW}$V2RAY_PORT${C_RESET} (127.0.0.1)\n"
    echo -e "  ${C_ORANGE}⚠️  Upande wa mteja:${C_RESET}"
    echo -e "     1. SlipNet → Proxy Only Mode → SOCKS 127.0.0.1:1080"
    echo -e "     2. Nekobox → $V2RAY_PROTOCOL + SOCKS5 outbound"
    echo -e "     3. SlipNet kwenye bypass ya Nekobox\n"
    press_enter
}

install_dnstt() {
    clear; show_banner
    [ -f "$DNSTT_SERVICE_FILE" ] && {
        read -p "Reinstall? (y/n): " r
        [[ "$r" != "y" ]] && return
        systemctl stop dnstt.service 2>/dev/null
    }

    echo -e "\n${C_BLUE}[1/6] Dependencies...${C_RESET}"
    ff_apt_install wget curl openssl bc dnsutils unzip

    echo -e "${C_BLUE}[2/6] Download DNSTT binary...${C_RESET}"
    download_dnstt_binary

    echo -e "${C_BLUE}[3/6] V2Ray backend setup...${C_RESET}"
    setup_v2ray_backend || {
        echo -e "${C_RED}❌ V2Ray ni lazima.${C_RESET}"
        press_enter
        return 1
    }

    echo -e "${C_BLUE}[4/6] MTU selection...${C_RESET}"
    mtu_selection_during_install

    echo -e "${C_BLUE}[5/6] Domain + keys...${C_RESET}"
    setup_domain
    generate_keys

    echo -e "${C_BLUE}[6/6] Creating DNSTT service...${C_RESET}"
    create_dnstt_service "$DOMAIN" "$MTU" || { press_enter; return 1; }
    save_dnstt_info "$DOMAIN" "$PUBLIC_KEY" "$MTU" "$(cat "$DB_DIR/dnstt_upstream.txt" | cut -d: -f2)"
    configure_dnstt_firewall
    systemctl start dnstt.service
    sleep 2

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
# DNSTT MAIN MENU
# ============================================================
dnstt_main_menu() {
    while true; do
        clear; show_banner
        [ ! -f "$DNSTT_SERVICE_FILE" ] && {
            echo -e "\n${C_RED}❌ DNSTT haijasakinishwa!${C_RESET}"
            press_enter
            return
        }
        local st=""
        systemctl is-active --quiet dnstt 2>/dev/null && st="${C_GREEN}● RUNNING${C_RESET}" || st="${C_RED}● STOPPED${C_RESET}"
        source "$V2RAY_INFO_FILE" 2>/dev/null

        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}              📡 DNSTT MANAGEMENT (V2Ray Backend)${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
        echo -e "  ${C_CYAN}Status${C_RESET}     : $st"
        echo -e "  ${C_CYAN}Domain${C_RESET}     : ${C_YELLOW}$(cat "$DB_DIR/domain.txt" 2>/dev/null || echo 'Not set')${C_RESET}"
        echo -e "  ${C_CYAN}MTU${C_RESET}        : ${C_YELLOW}$(get_current_mtu)${C_RESET}"
        echo -e "  ${C_CYAN}Backend${C_RESET}    : ${C_GREEN}$V2RAY_PROTOCOL @ 127.0.0.1:$V2RAY_PORT${C_RESET}"
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
        case $c in
            1) set_custom_dnstt_domain ;;
            2) change_dnstt_domain ;;
            0) return ;;
        esac
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
        case $c in
            1) set_custom_dnstt_public_key ;;
            2) regenerate_dnstt_keys ;;
            0) return ;;
        esac
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
    [[ ! "$m" =~ ^[0-9]+$ || "$m" -lt 512 || "$m" -gt 1500 ]] && {
        echo -e "${C_RED}❌ 512-1500${C_RESET}"
        return 1
    }
    echo "$m" > "$MTU_CONFIG"
    [ -f "$DNSTT_SERVICE_FILE" ] && {
        sed -i "s/-mtu [0-9]*/-mtu $m/g" "$DNSTT_SERVICE_FILE"
        systemctl daemon-reload
        systemctl restart dnstt.service 2>/dev/null
        echo -e "${C_GREEN}✅ MTU: $m${C_RESET}"
    }
}

set_custom_dnstt_domain() {
    clear; show_banner
    read -p "New domain: " nd
    [[ -z "$nd" ]] && return
    echo "$nd" > "$DB_DIR/domain.txt"
    local m=$(get_current_mtu)
    source "$V2RAY_INFO_FILE" 2>/dev/null
    systemctl stop dnstt.service 2>/dev/null
    sed -i "s|ExecStart=.*|ExecStart=$DNSTT_BINARY -udp :5300 -privkey-file $DNSTT_KEYS_DIR/server.key -mtu $m $nd 127.0.0.1:$V2RAY_PORT|" "$DNSTT_SERVICE_FILE"
    [ -f "$DNSTT_CONFIG_FILE" ] && sed -i "s|TUNNEL_DOMAIN=.*|TUNNEL_DOMAIN=\"$nd\"|" "$DNSTT_CONFIG_FILE"
    systemctl daemon-reload
    systemctl restart dnstt.service
    sleep 2
    echo -e "${C_GREEN}✅ $nd${C_RESET}"
    press_enter
}

change_dnstt_domain() {
    clear; show_banner
    [ -f "$DB_DIR/domain.txt" ] && {
        local o=$(cat "$DB_DIR/domain.txt")
        curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$(echo $o|cut -d. -f1)/NS/" \
            -H "Authorization: Token $DESEC_TOKEN" >/dev/null 2>&1
    }
    local rand=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 3)
    local ns="ns-$rand"
    local tun="tun-$rand"
    local ip=$(curl -s -4 icanhazip.com)
    curl -s -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
        -H "Authorization: Token $DESEC_TOKEN" \
        -H "Content-Type: application/json" \
        --data "[{\"subname\":\"$ns\",\"type\":\"A\",\"ttl\":3600,\"records\":[\"$ip\"]}]" >/dev/null 2>&1
    local r=$(curl -s -w "%{http_code}" -X POST \
        "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
        -H "Authorization: Token $DESEC_TOKEN" \
        -H "Content-Type: application/json" \
        --data "[{\"subname\":\"$tun\",\"type\":\"NS\",\"ttl\":3600,\"records\":[\"$ns.$DESEC_DOMAIN.\"]}]")
    if [[ "${r: -3}" -eq 201 ]]; then
        local nd="$tun.$DESEC_DOMAIN"
        echo "$nd" > "$DB_DIR/domain.txt"
        local m=$(get_current_mtu)
        source "$V2RAY_INFO_FILE" 2>/dev/null
        systemctl stop dnstt.service 2>/dev/null
        sed -i "s|ExecStart=.*|ExecStart=$DNSTT_BINARY -udp :5300 -privkey-file $DNSTT_KEYS_DIR/server.key -mtu $m $nd 127.0.0.1:$V2RAY_PORT|" "$DNSTT_SERVICE_FILE"
        [ -f "$DNSTT_CONFIG_FILE" ] && sed -i "s|TUNNEL_DOMAIN=.*|TUNNEL_DOMAIN=\"$nd\"|" "$DNSTT_CONFIG_FILE"
        systemctl daemon-reload
        systemctl restart dnstt.service
        echo -e "${C_GREEN}✅ $nd${C_RESET}"
    else
        echo -e "${C_RED}❌ HTTP ${r: -3}${C_RESET}"
    fi
    press_enter
}

set_custom_dnstt_public_key() {
    clear; show_banner
    read -p "New public key: " cp
    [[ ${#cp} -lt 30 ]] && { echo "❌"; press_enter; return; }
    echo "$cp" > "$DNSTT_KEYS_DIR/server.pub"
    chmod 644 "$DNSTT_KEYS_DIR/server.pub"
    [ -f "$DNSTT_CONFIG_FILE" ] && sed -i "s|PUBLIC_KEY=.*|PUBLIC_KEY=\"$cp\"|" "$DNSTT_CONFIG_FILE"
    systemctl restart dnstt.service 2>/dev/null
    echo -e "${C_GREEN}✅${C_RESET}"
    press_enter
}

regenerate_dnstt_keys() {
    clear; show_banner
    read -p "Regenerate? (y/n): " c
    [[ "$c" != "y" ]] && return
    systemctl stop dnstt.service 2>/dev/null
    cd "$DNSTT_KEYS_DIR"
    rm -f server.key server.pub
    "$DNSTT_BINARY" -gen-key -privkey-file server.key -pubkey-file server.pub 2>/dev/null || {
        openssl rand -hex 32 > server.key
        cat server.key | sha256sum | awk '{print $1}' > server.pub
    }
    chmod 600 server.key
    chmod 644 server.pub
    local np=$(cat server.pub)
    [ -f "$DNSTT_CONFIG_FILE" ] && sed -i "s|PUBLIC_KEY=.*|PUBLIC_KEY=\"$np\"|" "$DNSTT_CONFIG_FILE"
    systemctl restart dnstt.service
    sleep 2
    echo -e "${C_GREEN}✅ $np${C_RESET}"
    press_enter
}

show_dnstt_full_details() {
    clear; show_banner
    [ ! -f "$DB_DIR/domain.txt" ] && { echo "Not installed"; press_enter; return; }
    local d=$(cat "$DB_DIR/domain.txt")
    local m=$(get_current_mtu)
    local pk=$(cat "$DNSTT_KEYS_DIR/server.pub" 2>/dev/null)
    local st=""
    systemctl is-active --quiet dnstt.service 2>/dev/null && st="${C_GREEN}● RUNNING${C_RESET}" || st="${C_RED}● STOPPED${C_RESET}"
    source "$V2RAY_INFO_FILE" 2>/dev/null
    local vst=""
    systemctl is-active --quiet v2ray-dnstt.service 2>/dev/null && vst="${C_GREEN}● RUNNING${C_RESET}" || vst="${C_RED}● STOPPED${C_RESET}"

    echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_PURPLE}                 📊 DNSTT DETAILS${C_RESET}"
    echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
    echo -e "  ${C_CYAN}DNSTT Status${C_RESET}  : $st"
    echo -e "  ${C_CYAN}V2Ray Status${C_RESET}  : $vst"
    echo -e "  ${C_CYAN}Domain${C_RESET}        : ${C_YELLOW}$d${C_RESET}"
    echo -e "  ${C_CYAN}MTU${C_RESET}           : ${C_YELLOW}$m${C_RESET}"
    echo -e "  ${C_CYAN}Backend${C_RESET}       : ${C_GREEN}$V2RAY_PROTOCOL @ 127.0.0.1:$V2RAY_PORT${C_RESET}"
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
    ff_apt_install curl wget bc iptables openssl dnsutils unzip at >/dev/null 2>&1
    mkdir -p "$DB_DIR" "$LOGS_DIR" "$CONFIG_DIR" "$BANDWIDTH_DIR" "$BANNER_DIR" "$DNSTT_KEYS_DIR" "$V2RAY_CONFIG_DIR"
    touch "$DB_FILE" "$V2RAY_USERS_DB"
    create_v2ray_limiter
    create_v2ray_banner_builder
    systemctl enable atd &>/dev/null
    systemctl start atd &>/dev/null
    echo -e "${C_GREEN}✅ Setup complete${C_RESET}"
}

# ============================================================
# VPS DASHBOARD
# ============================================================
show_vps_dashboard() {
    clear; show_banner
    local ip=$(curl -s -4 icanhazip.com)
    local up=$(uptime -p | sed 's/up //')
    local load=$(awk '{print $1" / "$2" / "$3}' /proc/loadavg)
    local cores=$(nproc)
    local cpu_pct=$(awk "BEGIN{printf \"%d\", ($1/$cores)*100}" <<< "$(awk '{print $1}' /proc/loadavg)")

    read total used <<< $(free -m | awk '/^Mem:/ {print $2, $3}')
    local ram_pct=0
    (( total > 0 )) && ram_pct=$(( used * 100 / total ))
    local ram_bar=$(build_bar "$ram_pct" 20)
    local ram_color=$(get_bar_color "$ram_pct")
    local ram_human=$(free -h | awk '/^Mem:/ {print $3" / "$2}')

    read used total <<< $(df -BM / | awk 'NR==2 {gsub("M",""); print $3, $2}')
    local disk_pct=0
    (( total > 0 )) && disk_pct=$(( used * 100 / total ))
    local disk_bar=$(build_bar "$disk_pct" 20)
    local disk_color=$(get_bar_color "$disk_pct")
    local disk_human=$(df -h / | awk 'NR==2 {print $3" / "$2}')

    read stotal sused <<< $(free -m | awk '/^Swap:/ {print $2, $3}')
    local swap_pct=0
    (( stotal > 0 )) && swap_pct=$(( sused * 100 / stotal ))
    local swap_bar=$(build_bar "$swap_pct" 20)
    local swap_color=$(get_bar_color "$swap_pct")
    local swap_human=$(free -h | awk '/^Swap:/ {print $3" / "$2}')

    local cpu_bar=$(build_bar "$cpu_pct" 20)
    local cpu_color=$(get_bar_color "$cpu_pct")

    echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_PURPLE}                    🖥️  VPS DASHBOARD${C_RESET}"
    echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
    echo -e "  ${C_CYAN}IP${C_RESET}     : $ip"
    echo -e "  ${C_CYAN}Uptime${C_RESET} : $up"
    echo -e "  ${C_CYAN}Load${C_RESET}   : $load\n"
    echo -e "  ${C_CYAN}RAM${C_RESET}   : ${ram_color}${ram_bar}${C_RESET} ${ram_pct}% | ${ram_human}"
    echo -e "  ${C_CYAN}Disk${C_RESET}  : ${disk_color}${disk_bar}${C_RESET} ${disk_pct}% | ${disk_human}"
    echo -e "  ${C_CYAN}CPU${C_RESET}   : ${cpu_color}${cpu_bar}${C_RESET} ${cpu_pct}%"
    echo -e "  ${C_CYAN}Swap${C_RESET}  : ${swap_color}${swap_bar}${C_RESET} ${swap_pct}% | ${swap_human}\n"

    echo -e "  ${C_CYAN}Services:${C_RESET}"
    for s in sshd dnstt v2ray-dnstt v2ray-limiter atd; do
        st=$(systemctl is-active "$s" 2>/dev/null)
        [[ "$st" == "active" ]] && echo -e "    ${C_GREEN}● $s${C_RESET}" || echo -e "    ${C_DIM}○ $s${C_RESET}"
    done

    echo -e "\n  ${C_CYAN}Users:${C_RESET} $(grep -c . "$V2RAY_USERS_DB" 2>/dev/null || echo 0) V2Ray"
    press_enter
}

# ============================================================
# SYSTEM UTILITIES
# ============================================================
backup_users() {
    clear; show_banner
    read -p "Path [/root/v2ray-backup.tar.gz]: " p
    p=${p:-/root/v2ray-backup.tar.gz}
    tar -czf "$p" -C "$(dirname "$DB_DIR")" "$(basename "$DB_DIR")" 2>/dev/null && \
        echo -e "${C_GREEN}✅ $p${C_RESET}" || echo -e "${C_RED}❌ Failed${C_RESET}"
    press_enter
}

restore_users() {
    clear; show_banner
    read -p "Path: " p
    [ ! -f "$p" ] && { echo -e "${C_RED}❌ Not found${C_RESET}"; press_enter; return; }
    read -p "Confirm? (y/n): " c
    [[ "$c" == "y" ]] && {
        local td=$(mktemp -d)
        tar -xzf "$p" -C "$td" 2>/dev/null
        [ -f "$td/dnstt-v2ray/v2ray_users.db" ] && cp "$td/dnstt-v2ray/v2ray_users.db" "$V2RAY_USERS_DB"
        rm -rf "$td"
        sync_v2ray_config
        echo -e "${C_GREEN}✅ Restored${C_RESET}"
    }
    press_enter
}

cache_cleaner_menu() {
    while true; do
        clear; show_banner
        local st="DISABLED"
        [ -f /etc/cron.d/dnstt-v2ray-cache ] && st="ENABLED"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}                    🧹 CACHE CLEANER${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
        echo -e "  Status: ${C_YELLOW}$st${C_RESET}\n"
        echo -e "  ${C_GREEN}1)${C_RESET} Enable"
        echo -e "  ${C_RED}2)${C_RESET} Disable"
        echo -e "  ${C_RED}0)${C_RESET} Return"
        read -p "👉 Choice: " c
        case $c in
            1)
                cat > /etc/cron.d/dnstt-v2ray-cache <<EOF
0 0 * * * root apt clean && apt autoclean && apt autoremove -y && journalctl --vacuum-time=3d && rm -rf /tmp/*
EOF
                echo -e "${C_GREEN}✅ Enabled${C_RESET}"; press_enter ;;
            2) rm -f /etc/cron.d/dnstt-v2ray-cache
               echo -e "${C_GREEN}✅ Disabled${C_RESET}"; press_enter ;;
            0) return ;;
        esac
    done
}

system_utilities_menu() {
    while true; do
        clear; show_banner
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}                    ⚙️  SYSTEM UTILITIES${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"
        echo -e "  ${C_GREEN}1)${C_RESET} 💾 Backup Users"
        echo -e "  ${C_GREEN}2)${C_RESET} 📥 Restore Users"
        echo -e "  ${C_GREEN}3)${C_RESET} 🖥️  VPS Dashboard"
        echo -e "  ${C_GREEN}4)${C_RESET} 🧹 Cache Cleaner"
        echo -e "  ${C_GREEN}5)${C_RESET} ⚡ Speed Boosters"
        echo -e "  ${C_RED}0)${C_RESET} Return"
        read -p "👉 Choice: " c
        case $c in
            1) backup_users ;;
            2) restore_users ;;
            3) show_vps_dashboard ;;
            4) cache_cleaner_menu ;;
            5) dnstt_speed_menu ;;
            0) return ;;
        esac
    done
}

# ============================================================
# UNINSTALL ALL
# ============================================================
uninstall_all() {
    clear; show_banner
    read -p "Type YES to uninstall everything: " c
    [[ "$c" != "YES" ]] && { echo "Cancelled"; press_enter; return; }

    systemctl stop dnstt v2ray-dnstt v2ray-limiter 2>/dev/null
    systemctl disable dnstt v2ray-dnstt v2ray-limiter 2>/dev/null
    rm -f "$DNSTT_SERVICE_FILE" "$V2RAY_SERVICE_FILE" "$V2RAY_LIMITER_SERVICE"
    systemctl daemon-reload

    rm -f "$DNSTT_BINARY" "$DNSTT_CLIENT" "$V2RAY_BIN" "$V2RAY_LIMITER_SCRIPT" "$BANNER_BUILDER"
    rm -rf "$DB_DIR"

    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null
    iptables -D INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -p udp --sport 53 -j ACCEPT 2>/dev/null
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -p udp --sport 5300 -j ACCEPT 2>/dev/null

    rm -f /etc/cron.d/dnstt-v2ray-cache 2>/dev/null

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

        local d_st=""
        systemctl is-active --quiet dnstt 2>/dev/null && d_st="${C_GREEN}●${C_RESET}" || d_st="${C_RED}○${C_RESET}"
        local v_st=""
        systemctl is-active --quiet v2ray-dnstt 2>/dev/null && v_st="${C_GREEN}●${C_RESET}" || v_st="${C_RED}○${C_RESET}"
        local total_users=$(grep -c . "$V2RAY_USERS_DB" 2>/dev/null || echo 0)
        local active_users=$(get_active_v2ray_clients | grep -o '"id"' | wc -l 2>/dev/null || echo 0)

        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}          DNSTT + V2RAY (XRAY) BACKEND - MAIN MENU${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════════${C_RESET}\n"

        echo -e "  ${C_CYAN}📊 Server Status${C_RESET}"
        echo -e "  ${C_BLUE}─────────────────────────────────────────────────────────${C_RESET}"
        echo -e "  DNSTT  : $d_st      V2Ray : $v_st"
        echo -e "  Domain : ${C_YELLOW}$(cat "$DB_DIR/domain.txt" 2>/dev/null || echo 'Not set')${C_RESET}"
        echo -e "  Users  : ${C_WHITE}$total_users${C_RESET} total | ${C_GREEN}$active_users${C_RESET} active\n"

        echo -e "  ${C_PURPLE}🔷 V2RAY USER MANAGEMENT${C_RESET}"
        echo -e "  ${C_BLUE}─────────────────────────────────────────────────────────${C_RESET}"
        printf "  ${C_GREEN}[%2d]${C_RESET} %-25s ${C_GREEN}[%2d]${C_RESET} %s\n" 1 "Create User" 7 "Renew User"
        printf "  ${C_GREEN}[%2d]${C_RESET} %-25s ${C_GREEN}[%2d]${C_RESET} %s\n" 2 "Delete User" 8 "Cleanup Expired"
        printf "  ${C_GREEN}[%2d]${C_RESET} %-25s ${C_GREEN}[%2d]${C_RESET} %s\n" 3 "Edit User" 9 "Bulk Create"
        printf "  ${C_GREEN}[%2d]${C_RESET} %-25s ${C_GREEN}[%2d]${C_RESET} %s\n" 4 "Lock User" 10 "View Bandwidth"
        printf "  ${C_GREEN}[%2d]${C_RESET} %-25s ${C_GREEN}[%2d]${C_RESET} %s\n" 5 "Unlock User" 11 "Client Config"
        printf "  ${C_GREEN}[%2d]${C_RESET} %-25s ${C_GREEN}[%2d]${C_RESET} %s\n" 6 "List Users" 12 "Trial Account"
        echo ""

        echo -e "  ${C_PURPLE}🔧 SYSTEM & BACKEND${C_RESET}"
        echo -e "  ${C_BLUE}─────────────────────────────────────────────────────────${C_RESET}"
        printf "  ${C_GREEN}[%2d]${C_RESET} %-25s ${C_GREEN}[%2d]${C_RESET} %s\n" 13 "Install DNSTT + V2Ray" 17 "Speed Boosters"
        printf "  ${C_GREEN}[%2d]${C_RESET} %-25s ${C_GREEN}[%2d]${C_RESET} %s\n" 14 "DNSTT Management" 18 "VPS Dashboard"
        printf "  ${C_GREEN}[%2d]${C_RESET} %-25s ${C_GREEN}[%2d]${C_RESET} %s\n" 15 "V2Ray Backend" 19 "System Utilities"
        printf "  ${C_GREEN}[%2d]${C_RESET} %-25s ${C_GREEN}[%2d]${C_RESET} %s\n" 16 "Sync V2Ray Config" 20 "Dynamic Banner"
        echo ""

        echo -e "  ${C_BLUE}─────────────────────────────────────────────────────────${C_RESET}"
        printf "  ${C_RED}[99]${C_RESET} %-25s ${C_RED}[ 0]${C_RESET} %s\n\n" "Uninstall All" "Exit"

        read -p "  👉 Select: " choice
        case $choice in
            1) create_v2ray_user ;;
            2) delete_v2ray_user ;;
            3) edit_v2ray_user ;;
            4) lock_v2ray_user ;;
            5) unlock_v2ray_user ;;
            6) list_v2ray_users ;;
            7) renew_v2ray_user ;;
            8) cleanup_expired_v2ray ;;
            9) bulk_create_v2ray ;;
            10) view_v2ray_bandwidth ;;
            11) show_v2ray_client_config ;;
            12) create_trial_v2ray ;;
            13) install_dnstt ;;
            14) dnstt_main_menu ;;
            15) v2ray_backend_menu ;;
            16) sync_v2ray_config; press_enter ;;
            17) dnstt_speed_menu ;;
            18) show_vps_dashboard ;;
            19) system_utilities_menu ;;
            20) v2ray_banner_menu ;;
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
