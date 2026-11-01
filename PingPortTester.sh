#!/usr/bin/env bash
#
# PingPortTester - network connectivity toolkit for Linux & macOS
# https://github.com/NUCL3ARN30N/PingPortTester
#
# Copyright (C) NUCL3ARN30N - GPLv3
#
# Runs on bash 3.2+ (macOS default) and bash 4/5 (Linux). Works when piped:
#   curl -sSL ppt.genius-space.org/PingPortTester.sh | bash
#
# shellcheck disable=SC2155,SC2034

PPT_VERSION="5.0.0"

# ============================================================================
#  SETTINGS (overridable via environment or command-line flags)
# ============================================================================
LOG_ENABLED="${PPT_LOG:-1}"
LOG_PATH="${PPT_LOG_PATH:-./NetworkTest.log}"
MAX_LOG_SIZE_BYTES=$((20 * 1024 * 1024))
NET_TIMEOUT="${PPT_TIMEOUT:-3}"
USE_COLOR=1
USE_UNICODE=1
OS="$(uname -s 2>/dev/null)"
TMP_DIR=""

# ============================================================================
#  GENERIC HELPERS
# ============================================================================
have() { command -v "$1" >/dev/null 2>&1; }

cleanup() {
    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR" 2>/dev/null
    printf '\033[?25h' 2>/dev/null   # always restore cursor
}

mk_tmp() {
    if [ -z "$TMP_DIR" ]; then
        TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t ppt)"
    fi
}

# Milliseconds since epoch; portable down to bash 3.2 / macOS.
now_ms() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local s="${EPOCHREALTIME/[.,]/}"
        echo "${s:0:${#s}-3}"
        return
    fi
    local n
    n="$(date +%s%N 2>/dev/null)"
    case "$n" in
        *N|"") ;;
        *) echo "${n:0:${#n}-6}"; return ;;
    esac
    if have perl; then perl -MTime::HiRes=time -e 'printf("%d\n", time()*1000)'; return; fi
    if have python3; then python3 -c 'import time;print(int(time.time()*1000))'; return; fi
    echo "$(( $(date +%s) * 1000 ))"
}

# with_timeout SECONDS cmd args...  (GNU timeout, gtimeout, or perl alarm)
with_timeout() {
    local t="$1"; shift
    if have timeout; then timeout "$t" "$@"; return $?; fi
    if have gtimeout; then gtimeout "$t" "$@"; return $?; fi
    if have perl; then
        local ti; ti="$(awk -v t="$t" 'BEGIN{x=int(t); if (x<t) x++; if (x<1) x=1; print x}')"
        perl -e 'alarm shift; exec @ARGV or exit 127' "$ti" "$@"
        return $?
    fi
    "$@"
}

file_size() { wc -c < "$1" 2>/dev/null | tr -d ' '; }

is_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

is_ipv4() {
    echo "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

is_private_ip() {
    case "$1" in
        10.*|127.*|192.168.*|169.254.*|0.*) return 0 ;;
        172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 0 ;;
        100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) return 0 ;; # CGNAT
        fe80:*|fc*|fd*|::1) return 0 ;;
    esac
    return 1
}

# Tiny JSON field extractor: json_get <json> <key>  (jq > python3 > sed)
json_get() {
    local json="$1" key="$2"
    if have jq; then
        printf '%s' "$json" | jq -r --arg k "$key" '
            def walk_get($p): reduce ($p|split(".")[]) as $s (.; if type=="object" then .[$s] else null end);
            walk_get($k) // empty | tostring' 2>/dev/null
        return
    fi
    if have python3; then
        printf '%s' "$json" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    for p in sys.argv[1].split("."):
        d=d.get(p) if isinstance(d,dict) else None
    if d is not None:
        print(str(d).lower() if isinstance(d,bool) else d)
except Exception:
    pass' "$key" 2>/dev/null
        return
    fi
    local leaf="${key##*.}"
    printf '%s' "$json" | tr -d '\n' | sed -n "s/.*\"$leaf\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" | head -1
}

http_get() { curl -fsS --max-time "${2:-10}" -A "PingPortTester/$PPT_VERSION" "$1" 2>/dev/null; }

service_name() {
    case "$1" in
        20|21) echo FTP ;; 22) echo SSH ;; 23) echo Telnet ;; 25) echo SMTP ;;
        53) echo DNS ;; 67|68) echo DHCP ;; 69) echo TFTP ;; 80) echo HTTP ;;
        110) echo POP3 ;; 111) echo RPC ;; 123) echo NTP ;; 135) echo MS-RPC ;;
        137|138|139) echo NetBIOS ;; 143) echo IMAP ;; 161|162) echo SNMP ;;
        389) echo LDAP ;; 443) echo HTTPS ;; 445) echo SMB ;; 465) echo SMTPS ;;
        500) echo IKE ;; 514) echo Syslog ;; 587) echo Submission ;; 636) echo LDAPS ;;
        853) echo DoT ;; 993) echo IMAPS ;; 995) echo POP3S ;; 1194) echo OpenVPN ;;
        1433) echo MSSQL ;; 1521) echo Oracle ;; 1883) echo MQTT ;; 2049) echo NFS ;;
        3000) echo Dev-HTTP ;; 3306) echo MySQL ;; 3389) echo RDP ;; 4500) echo IPsec-NAT ;;
        5060|5061) echo SIP ;; 5353) echo mDNS ;; 5432) echo PostgreSQL ;; 5900) echo VNC ;;
        6379) echo Redis ;; 8080|8000|8888) echo HTTP-Alt ;; 8443) echo HTTPS-Alt ;;
        9000) echo Portainer ;; 9200) echo Elasticsearch ;; 11211) echo Memcached ;;
        25565) echo Minecraft ;; 27017) echo MongoDB ;; 51820) echo WireGuard ;;
        *) echo "" ;;
    esac
}

COMMON_PORTS="21,22,23,25,53,80,110,111,135,139,143,161,389,443,445,465,587,636,993,995,1194,1433,1521,1883,2049,3000,3306,3389,5060,5432,5900,6379,8000,8080,8443,8888,9000,9200,11211,25565,27017,51820"

# Expand "22,80,8000-8010,common" into one port per line.
expand_ports() {
    local spec="$1" part a b p
    spec="$(echo "$spec" | tr -d ' ')"
    spec="${spec//common/$COMMON_PORTS}"
    local IFS=','
    for part in $spec; do
        case "$part" in
            *-*)
                a="${part%-*}"; b="${part#*-}"
                if is_int "$a" && is_int "$b" && [ "$a" -le "$b" ]; then
                    p="$a"
                    while [ "$p" -le "$b" ]; do
                        [ "$p" -ge 1 ] && [ "$p" -le 65535 ] && echo "$p"
                        p=$((p + 1))
                    done
                fi ;;
            *)
                is_int "$part" && [ "$part" -ge 1 ] && [ "$part" -le 65535 ] && echo "$part" ;;
        esac
    done
}

# ============================================================================
#  LOGGING
# ============================================================================
init_log() {
    [ "$LOG_ENABLED" = "1" ] || return
    if ! touch "$LOG_PATH" 2>/dev/null; then
        LOG_PATH="${HOME:-/tmp}/NetworkTest.log"
        touch "$LOG_PATH" 2>/dev/null || LOG_ENABLED=0
    fi
}

write_log() {
    [ "$LOG_ENABLED" = "1" ] || return 0
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_PATH" 2>/dev/null
}

check_log_size() {
    [ "$LOG_ENABLED" = "1" ] && [ -f "$LOG_PATH" ] || return 0
    local size; size="$(file_size "$LOG_PATH")"
    if [ -n "$size" ] && [ "$size" -ge "$MAX_LOG_SIZE_BYTES" ]; then
        local archive; archive="$(dirname "$LOG_PATH")/NetworkTest_$(date '+%Y%m%d_%H%M%S').tar.gz"
        tar -czf "$archive" -C "$(dirname "$LOG_PATH")" "$(basename "$LOG_PATH")" 2>/dev/null && : > "$LOG_PATH"
        ui_info "Log archived to $archive"
    fi
}

# ============================================================================
#  UI TOOLKIT
# ============================================================================
init_ui() {
    if [ "$USE_COLOR" = "1" ] && [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
        C_RST=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'; C_INV=$'\033[7m'
        C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[34m'
        C_MAG=$'\033[35m'; C_CYN=$'\033[36m'; C_GRY=$'\033[90m'; C_WHT=$'\033[97m'
        C_ACC=$'\033[38;5;45m'; C_ACC2=$'\033[38;5;141m'; C_SEL=$'\033[48;5;24m\033[97m'
    else
        C_RST=""; C_B=""; C_DIM=""; C_INV=""; C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""
        C_MAG=""; C_CYN=""; C_GRY=""; C_WHT=""; C_ACC=""; C_ACC2=""; C_SEL=""
    fi

    local loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    case "$loc" in *UTF-8*|*utf8*|*UTF8*|*utf-8*) ;; *) [ "$OS" = "Darwin" ] || USE_UNICODE=0 ;; esac

    if [ "$USE_UNICODE" = "1" ]; then
        B_H="─"; B_V="│"; B_TL="╭"; B_TR="╮"; B_BL="╰"; B_BR="╯"; B_LT="├"; B_RT="┤"
        G_OK="✔"; G_FAIL="✘"; G_WARN="▲"; G_INFO="●"; G_ARROW="›"; G_PTR="▶"
        G_FULL="█"; G_EMPTY="░"; G_DOT="·"; G_RIGHT="→"
        SPARK=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
        SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    else
        B_H="-"; B_V="|"; B_TL="+"; B_TR="+"; B_BL="+"; B_BR="+"; B_LT="+"; B_RT="+"
        G_OK="+"; G_FAIL="x"; G_WARN="!"; G_INFO="*"; G_ARROW=">"; G_PTR=">"
        G_FULL="#"; G_EMPTY="."; G_DOT="."; G_RIGHT="->"
        SPARK=('_' '.' '-' '-' '=' '=' '^' '^')
        SPIN=('|' '/' '-' '\')
    fi
    term_size
}

term_size() {
    TERM_COLS="$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")"
    TERM_ROWS="$(tput lines 2>/dev/null || echo "${LINES:-40}")"
    is_int "$TERM_COLS" || TERM_COLS=80
    is_int "$TERM_ROWS" || TERM_ROWS=40
    UI_W=$((TERM_COLS - 4))
    [ "$UI_W" -gt 92 ] && UI_W=92
    [ "$UI_W" -lt 50 ] && UI_W=50
}

# trunc STRING MAX -> shortened with an ellipsis (plain text only)
trunc() {
    local str="$1" max="$2"
    if [ "${#str}" -gt "$max" ]; then printf '%s...' "${str:0:$((max - 3))}"; else printf '%s' "$str"; fi
}

repeat() { local i s=""; for ((i = 0; i < $2; i++)); do s="$s$1"; done; printf '%s' "$s"; }

# Visible length of a string (strips ANSI escapes).
vlen() {
    local s; s="$(printf '%s' "$1" | sed $'s/\033\\[[0-9;]*[a-zA-Z]//g')"
    echo "${#s}"
}

clear_screen() { printf '\033[H\033[2J\033[3J'; }

ui_logo() {
    local l1 l2 l3
    if [ "$USE_UNICODE" = "1" ]; then
        l1="  ┏━┓╻┏┓╻┏━╸┏━┓┏━┓┏━┓╺┳╸╺┳╸┏━╸┏━┓╺┳╸┏━╸┏━┓"
        l2="  ┣━┛┃┃┗┫┃╺┓┣━┛┃ ┃┣┳┛ ┃  ┃ ┣╸ ┗━┓ ┃ ┣╸ ┣┳┛"
        l3="  ╹  ╹╹ ╹┗━┛╹  ┗━┛╹┗╸ ╹  ╹ ┗━╸┗━┛ ╹ ┗━╸╹┗╸"
    else
        l1="   ___ _           ___         _  _____         _"
        l2="  | _ (_)_ _  __ _| _ \\___ _ _| ||_   _|__ ___| |_ ___ _ _"
        l3="  |  _/ | ' \\/ _\` |  _/ _ \\ '_|  _|| |/ -_|_-<  _/ -_) '_|"
    fi
    printf '%s%s%s\n%s%s%s\n%s%s%s\n' "$C_ACC" "$l1" "$C_RST" "$C_ACC" "$l2" "$C_RST" "$C_ACC2" "$l3" "$C_RST"
}

# Box drawing: ui_box_top "Title" ; ui_box_line "text" ; ui_box_bottom
ui_box_top() {
    local title="$1" tl
    if [ -n "$title" ]; then
        tl="$(vlen "$title")"
        printf '  %s%s%s %s%s%s %s%s%s\n' "$C_GRY" "$B_TL$B_H" "$C_RST" "$C_B$C_WHT" "$title" "$C_RST" "$C_GRY" "$(repeat "$B_H" $((UI_W - tl - 5)))$B_TR" "$C_RST"
    else
        printf '  %s%s%s\n' "$C_GRY" "$B_TL$(repeat "$B_H" $((UI_W - 2)))$B_TR" "$C_RST"
    fi
}
ui_box_line() {
    local text="$1" l pad
    l="$(vlen "$text")"
    pad=$((UI_W - 4 - l)); [ "$pad" -lt 0 ] && pad=0
    printf '  %s%s%s %s%*s %s%s%s\n' "$C_GRY" "$B_V" "$C_RST" "$text" "$pad" "" "$C_GRY" "$B_V" "$C_RST"
}
ui_box_sep()    { printf '  %s%s%s\n' "$C_GRY" "$B_LT$(repeat "$B_H" $((UI_W - 2)))$B_RT" "$C_RST"; }
ui_box_bottom() { printf '  %s%s%s\n' "$C_GRY" "$B_BL$(repeat "$B_H" $((UI_W - 2)))$B_BR" "$C_RST"; }

ui_header() {
    clear_screen
    term_size
    ui_logo
    printf '  %sv%s %s %s%s\n\n' "$C_GRY" "$PPT_VERSION" "$G_DOT" "$1" "$C_RST"
}

ui_section() {
    local t="$1" l
    l="$(vlen "$t")"
    printf '\n  %s%s%s %s%s%s %s%s%s\n' "$C_ACC" "$B_H$B_H" "$C_RST" "$C_B" "$t" "$C_RST" "$C_GRY" "$(repeat "$B_H" $((UI_W - l - 4)))" "$C_RST"
}

ui_kv() { printf '    %s%-18s%s %s%s%s\n' "$C_GRY" "$1" "$C_RST" "${3:-}" "$2" "$C_RST"; }

ui_ok()   { printf '  %s%s%s %s\n' "$C_GRN" "$G_OK"   "$C_RST" "$1"; }
ui_fail() { printf '  %s%s%s %s\n' "$C_RED" "$G_FAIL" "$C_RST" "$1"; }
ui_warn() { printf '  %s%s%s %s\n' "$C_YEL" "$G_WARN" "$C_RST" "$1"; }
ui_info() { printf '  %s%s%s %s\n' "$C_ACC" "$G_INFO" "$C_RST" "$1"; }
ui_note() { printf '  %s%s%s\n' "$C_GRY" "$1" "$C_RST"; }

# Colour for a latency value in ms.
lat_color() {
    awk -v v="$1" 'BEGIN{ if (v < 50) print "g"; else if (v < 150) print "y"; else print "r" }' | {
        read -r c
        case "$c" in g) printf '%s' "$C_GRN" ;; y) printf '%s' "$C_YEL" ;; *) printf '%s' "$C_RED" ;; esac
    }
}

# ui_bar VALUE MAX WIDTH [color]
ui_bar() {
    local filled
    filled="$(awk -v v="$1" -v m="$2" -v w="$3" 'BEGIN{ if (m<=0) m=1; f=int(v/m*w+0.5); if (f>w) f=w; if (f<0) f=0; print f }')"
    printf '%s%s%s%s%s' "${4:-$C_ACC}" "$(repeat "$G_FULL" "$filled")" "$C_GRY" "$(repeat "$G_EMPTY" $(($3 - filled)))" "$C_RST"
}

# Progress line (overwrites current line).
ui_progress() {
    local cur="$1" total="$2" label="$3" w=30 pct
    [ "$total" -le 0 ] && total=1
    pct=$((cur * 100 / total))
    printf '\r\033[K  %s %3d%% %s%s%s' "$(ui_bar "$cur" "$total" "$w")" "$pct" "$C_GRY" "$label" "$C_RST"
}

# sparkline from space separated values
sparkline() {
    local vals="$1" out="" v idx
    local max; max="$(echo "$vals" | tr ' ' '\n' | awk '$1 ~ /^[0-9.]+$/ { if ($1+0>m) m=$1+0 } END{ print m+0 }')"
    for v in $vals; do
        if [ "$v" = "x" ]; then out="$out${C_RED}${G_FAIL}${C_RST}"; continue; fi
        idx="$(awk -v v="$v" -v m="$max" 'BEGIN{ if (m<=0) m=1; i=int(v/m*7+0.5); if (i>7) i=7; print i }')"
        out="$out$(lat_color "$v")${SPARK[$idx]}${C_RST}"
    done
    printf '%s' "$out"
}

# Spinner while a background PID runs: spin_wait PID "label"
spin_wait() {
    local pid="$1" label="$2" i=0
    printf '\033[?25l'
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r\033[K  %s%s%s %s' "$C_ACC" "${SPIN[$((i % ${#SPIN[@]}))]}" "$C_RST" "$label"
        i=$((i + 1))
        sleep 0.1 2>/dev/null || sleep 1
    done
    printf '\r\033[K\033[?25h'
    wait "$pid"
}

# ----------------------------------------------------------------------------
#  Input
# ----------------------------------------------------------------------------
# ask VAR "Prompt" [default]
ask() {
    local __var="$1" __prompt="$2" __def="${3:-}" __ans __hint=""
    [ -n "$__def" ] && __hint=" ${C_GRY}[$__def]${C_RST}"
    printf '  %s%s%s %s%s: ' "$C_ACC" "$G_ARROW" "$C_RST" "$__prompt" "$__hint"
    IFS= read -r __ans
    [ -z "$__ans" ] && __ans="$__def"
    eval "$__var=\$__ans"
}

# ask_required VAR "Prompt" [default]
ask_required() {
    local __v
    while :; do
        ask __v "$2" "${3:-}"
        __v="$(echo "$__v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [ -n "$__v" ]; then
            case "$__v" in
                *[\;\|\$\`\<\>\"\'\\]*) ui_fail "Invalid characters in input" ;;
                *) eval "$1=\$__v"; return ;;
            esac
        else
            ui_fail "A value is required"
        fi
    done
}

# ask_int VAR "Prompt" default min max
ask_int() {
    local __v
    while :; do
        ask __v "$2" "$3"
        if is_int "$__v" && [ "$__v" -ge "$4" ] && [ "$__v" -le "$5" ]; then
            eval "$1=\$__v"; return
        fi
        ui_fail "Enter a whole number between $4 and $5"
    done
}

# ask_num VAR "Prompt" default min   (allows decimals, e.g. 0.5)
ask_num() {
    local __v
    while :; do
        ask __v "$2" "$3"
        if echo "$__v" | grep -Eq '^[0-9]+(\.[0-9]+)?$' && awk -v v="$__v" -v m="$4" 'BEGIN{ exit !(v >= m) }'; then
            eval "$1=\$__v"; return
        fi
        ui_fail "Enter a number >= $4"
    done
}

ask_yn() {
    local __v
    ask __v "$1 (y/n)" "${2:-n}"
    case "$__v" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ask_choice VAR "Title" default "opt1" "opt2" ...
ask_choice() {
    local __var="$1" __title="$2" __def="$3"; shift 3
    local i=1 o
    printf '  %s%s%s\n' "$C_B" "$__title" "$C_RST"
    for o in "$@"; do
        printf '    %s%d%s  %s\n' "$C_ACC" "$i" "$C_RST" "$o"
        i=$((i + 1))
    done
    ask_int "$__var" "Choice" "$__def" 1 $#
}

read_key() {
    local k k2 k3
    IFS= read -rsn1 k 2>/dev/null || { KEY="q"; return; }
    if [ "$k" = $'\033' ]; then
        IFS= read -rsn1 -t 1 k2 2>/dev/null
        IFS= read -rsn1 -t 1 k3 2>/dev/null
        case "$k2$k3" in
            '[A'|'OA') KEY="UP" ;; '[B'|'OB') KEY="DOWN" ;;
            '[C'|'OC') KEY="RIGHT" ;; '[D'|'OD') KEY="LEFT" ;;
            '[H'|'OH') KEY="HOME" ;; '[F'|'OF') KEY="END" ;;
            *) KEY="ESC" ;;
        esac
    elif [ -z "$k" ]; then
        KEY="ENTER"
    else
        KEY="$k"
    fi
}

pause() {
    printf '\n  %sPress any key to return to the menu...%s' "$C_GRY" "$C_RST"
    read_key
    echo
}

# Wait up to N seconds for a key; sets KEY (empty on timeout). Fractions on bash>=4.
wait_key() {
    local t="$1" k=""
    if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
        t="$(awk -v t="$t" 'BEGIN{ x=int(t+0.5); if (x<1) x=1; print x }')"
    fi
    KEY=""
    IFS= read -rsn1 -t "$t" k 2>/dev/null && KEY="${k:-ENTER}"
}

# ============================================================================
#  NETWORK PRIMITIVES
# ============================================================================
# ping_once HOST [timeout] [ttl] -> prints RTT ms on success
ping_once() {
    local host="$1" t="${2:-$NET_TIMEOUT}" ttl="${3:-}" out args
    if [ "$OS" = "Darwin" ]; then
        args="-c 1 -W $((t * 1000))"; [ -n "$ttl" ] && args="$args -m $ttl"
    else
        args="-c 1 -W $t"; [ -n "$ttl" ] && args="$args -t $ttl"
    fi
    # shellcheck disable=SC2086
    out="$(ping -n $args "$host" 2>&1)"
    local rtt; rtt="$(echo "$out" | sed -n 's/.*time[=<]\([0-9.]*\).*/\1/p' | head -1)"
    if [ -n "$rtt" ]; then echo "$rtt"; return 0; fi
    return 1
}

# tcp_connect HOST PORT [timeout] -> prints connect time in ms
tcp_connect() {
    local host="$1" port="$2" t="${3:-$NET_TIMEOUT}" start end
    start="$(now_ms)"
    if with_timeout "$t" bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; then
        end="$(now_ms)"
        echo $((end - start))
        return 0
    fi
    return 1
}

# udp_probe HOST PORT [timeout] -> prints open | closed | open|filtered
udp_probe() {
    local host="$1" port="$2" t="${3:-$NET_TIMEOUT}"
    if have python3; then
        python3 - "$host" "$port" "$t" <<'PY' 2>/dev/null
import socket, sys, os
host, port, t = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
payloads = {
    53:  bytes.fromhex("abcd01000001000000000000000002000001"),          # DNS: . NS
    123: b"\x1b" + 47 * b"\0",                                            # NTP client
    161: bytes.fromhex("302602010104067075626c6963a019020400000001020100020100300b300906052b060102010500"),
    1900: b"M-SEARCH * HTTP/1.1\r\nHOST:239.255.255.250:1900\r\nMAN:\"ssdp:discover\"\r\nMX:1\r\nST:ssdp:all\r\n\r\n",
    5353: bytes.fromhex("000000000001000000000000095f7365727669636573075f646e732d7364045f756470056c6f63616c00000c0001"),
}
data = payloads.get(port, b"PingPortTester\r\n")
try:
    fam = socket.getaddrinfo(host, port, 0, socket.SOCK_DGRAM)[0]
    s = socket.socket(fam[0], socket.SOCK_DGRAM)
    s.settimeout(t)
    s.connect(fam[4])
    s.send(data)
    s.recv(2048)
    print("open")
except ConnectionRefusedError:
    print("closed")
except socket.timeout:
    print("open|filtered")
except OSError as e:
    print("closed" if getattr(e, "errno", 0) in (111, 61, 10054) else "error")
PY
        return
    fi
    if have nc; then
        local out
        out="$(printf 'PingPortTester\r\n' | with_timeout $((t + 1)) nc -u -w "$t" "$host" "$port" 2>&1)"
        case "$out" in
            *refused*) echo "closed" ;;
            "") echo "open|filtered" ;;
            *) echo "open" ;;
        esac
        return
    fi
    echo "error"
}

# dns_query NAME TYPE [SERVER] -> one record per line
dns_query() {
    local name="$1" type="${2:-A}" server="${3:-}"
    if have dig; then
        if [ -n "$server" ]; then
            dig +short +time=2 +tries=1 "@$server" "$name" "$type" 2>/dev/null | grep -v '^;'
        else
            dig +short +time=2 +tries=1 "$name" "$type" 2>/dev/null | grep -v '^;'
        fi
        return
    fi
    if have host; then
        # shellcheck disable=SC2086
        host -W 2 -t "$type" "$name" $server 2>/dev/null | awk -v t="$type" '
            t=="A"     && /has address/      { print $NF }
            t=="AAAA"  && /has IPv6 address/ { print $NF }
            t=="MX"    && /mail is handled/  { print $(NF-1), $NF }
            t=="NS"    && /name server/      { print $NF }
            t=="CNAME" && /is an alias/      { print $NF }
            t=="TXT"   && /descriptive text/ { sub(/.*descriptive text /, ""); print }
            t=="SOA"   && /has SOA record/   { sub(/.*has SOA record /, ""); print }
            t=="CAA"   && /has CAA record/   { sub(/.*has CAA record /, ""); print }'
        return
    fi
    if have nslookup; then
        # shellcheck disable=SC2086
        nslookup -timeout=2 -type="$type" "$name" $server 2>/dev/null | awk -v t="$type" '
            /^Name:/ { seen=1; next }
            t=="A"    && seen && /^Address/ { print $NF }
            t=="AAAA" && seen && /^Address/ && /:.*:/ { print $NF }
            t=="MX"   && /mail exchanger/ { print $(NF-1), $NF }
            t=="NS"   && /nameserver =/   { print $NF }
            t=="TXT"  && /text =/          { sub(/.*text = /, ""); print }
            t=="CNAME"&& /canonical name/  { print $NF }'
        return
    fi
    if [ "$type" = "A" ] && [ -z "$server" ]; then
        if have getent; then getent ahostsv4 "$name" 2>/dev/null | awk '{print $1}' | sort -u
        elif have python3; then python3 -c 'import socket,sys;[print(a) for a in sorted({i[4][0] for i in socket.getaddrinfo(sys.argv[1],None,socket.AF_INET)})]' "$name" 2>/dev/null
        fi
    fi
}

dns_tool_available() { have dig || have host || have nslookup; }

# Resolve a host to its first IPv4 (or echo input if it already is one)
resolve_ip() {
    if is_ipv4 "$1"; then echo "$1"; return; fi
    local ip
    ip="$(dns_query "$1" A | grep -E '^[0-9.]+$' | head -1)"
    [ -z "$ip" ] && have getent && ip="$(getent hosts "$1" 2>/dev/null | awk '{print $1; exit}')"
    echo "$ip"
}

public_ip() {
    local s ip
    for s in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com https://ipv4.icanhazip.com; do
        ip="$(http_get "$s" 6 | tr -d '[:space:]')"
        if is_ipv4 "$ip"; then echo "$ip"; return 0; fi
    done
    return 1
}

# geo_lookup IP -> sets GEO_CC GEO_CITY GEO_AS GEO_ORG GEO_LAT GEO_LON GEO_TZ GEO_PROXY GEO_HOSTING
geo_lookup() {
    GEO_CC=""; GEO_CITY=""; GEO_AS=""; GEO_ORG=""; GEO_LAT=""; GEO_LON=""; GEO_TZ=""; GEO_PROXY=""; GEO_HOSTING=""; GEO_COUNTRY=""; GEO_REGION=""
    local ip="$1" out
    out="$(http_get "http://ip-api.com/line/$ip?fields=status,country,countryCode,regionName,city,lat,lon,timezone,isp,as,proxy,hosting" 6)"
    if [ "$(echo "$out" | sed -n 1p)" = "success" ]; then
        GEO_COUNTRY="$(echo "$out" | sed -n 2p)"; GEO_CC="$(echo "$out" | sed -n 3p)"
        GEO_REGION="$(echo "$out" | sed -n 4p)"; GEO_CITY="$(echo "$out" | sed -n 5p)"
        GEO_LAT="$(echo "$out" | sed -n 6p)"; GEO_LON="$(echo "$out" | sed -n 7p)"
        GEO_TZ="$(echo "$out" | sed -n 8p)"; GEO_ORG="$(echo "$out" | sed -n 9p)"
        GEO_AS="$(echo "$out" | sed -n 10p)"; GEO_PROXY="$(echo "$out" | sed -n 11p)"
        GEO_HOSTING="$(echo "$out" | sed -n 12p)"
        return 0
    fi
    out="$(http_get "https://ipinfo.io/$ip/json" 6)"
    [ -z "$out" ] && return 1
    GEO_CITY="$(json_get "$out" city)"; GEO_REGION="$(json_get "$out" region)"
    GEO_CC="$(json_get "$out" country)"; GEO_COUNTRY="$GEO_CC"
    GEO_TZ="$(json_get "$out" timezone)"; GEO_AS="$(json_get "$out" org)"; GEO_ORG="$GEO_AS"
    local loc; loc="$(json_get "$out" loc)"
    GEO_LAT="${loc%,*}"; GEO_LON="${loc#*,}"
    [ -n "$GEO_CC" ]
}

# ============================================================================
#  1. ICMP PING MONITOR
# ============================================================================
mode_ping_monitor() {
    local target interval
    ui_header "ICMP Ping Monitor"
    ask_required target "Target host" "1.1.1.1"
    ask_num interval "Interval in seconds" "1" "0.2"

    ui_header "Ping Monitor ${G_RIGHT} $target"
    ui_note "Press Q (or Ctrl+C) to stop."
    echo
    write_log "Ping monitor started: $target"

    local total=0 failed=0 sum=0 min="" max=0 spark="" rtt ts stop=0 streak=0
    trap 'stop=1' INT
    while [ "$stop" -eq 0 ]; do
        total=$((total + 1))
        check_log_size
        ts="$(date '+%H:%M:%S')"
        printf '\r\033[K'
        if rtt="$(ping_once "$target")"; then
            streak=0
            sum="$(awk -v a="$sum" -v b="$rtt" 'BEGIN{print a+b}')"
            [ -z "$min" ] && min="$rtt"
            min="$(awk -v a="$min" -v b="$rtt" 'BEGIN{print (b<a)?b:a}')"
            max="$(awk -v a="$max" -v b="$rtt" 'BEGIN{print (b>a)?b:a}')"
            printf '  %s%s%s %s%s%s  reply from %-20s %s%8s ms%s  %s\n' "$C_GRN" "$G_OK" "$C_RST" "$C_GRY" "$ts" "$C_RST" "$target" "$(lat_color "$rtt")" "$rtt" "$C_RST" "$(ui_bar "$rtt" 200 20 "$(lat_color "$rtt")")"
            spark="$spark $rtt"
        else
            failed=$((failed + 1)); streak=$((streak + 1))
            printf '  %s%s%s %s%s%s  %sno reply from %s%s\n' "$C_RED" "$G_FAIL" "$C_RST" "$C_GRY" "$ts" "$C_RST" "$C_RED" "$target" "$C_RST"
            write_log "DROPPED - Ping to $target failed"
            spark="$spark x"
        fi
        spark="$(echo "$spark" | awk '{ s=""; n=NF; st=(n>40)?n-39:1; for(i=st;i<=n;i++) s=s" "$i; print s }')"
        local ok=$((total - failed)) avg="-" loss
        [ "$ok" -gt 0 ] && avg="$(awk -v s="$sum" -v n="$ok" 'BEGIN{printf "%.1f", s/n}')"
        loss="$(awk -v f="$failed" -v t="$total" 'BEGIN{printf "%.1f", f*100/t}')"
        printf '  %s%s%s sent %d  lost %d (%s%%)  min/avg/max %s/%s/%s ms  %s' "$C_ACC" "$B_V" "$C_RST" "$total" "$failed" "$loss" "${min:--}" "$avg" "$max" "$(sparkline "$spark")"
        [ "$streak" -ge 3 ] && printf '  %s%s outage%s' "$C_RED" "$G_WARN" "$C_RST"
        wait_key "$interval"
        case "$KEY" in q|Q) stop=1 ;; esac
    done
    trap - INT
    echo; echo
    write_log "Ping monitor stopped: $target sent=$total lost=$failed"
    ui_info "Stopped after $total probes."
    pause
}

# ============================================================================
#  2. PACKET LOSS ANALYSIS  (issue #1)
# ============================================================================
mode_packet_loss() {
    local target count interval
    ui_header "Packet Loss & Jitter Analysis"
    ask_required target "Target host" "1.1.1.1"
    ask_int count "Number of packets" "100" 10 10000
    ask_num interval "Interval in seconds (min 0.2 without root)" "0.2" "0.01"

    ui_header "Packet Loss Analysis ${G_RIGHT} $target"
    write_log "Packet loss analysis: $target count=$count interval=$interval"
    mk_tmp
    local raw="$TMP_DIR/pl_raw" rtts="$TMP_DIR/pl_rtts"
    : > "$rtts"

    local wflag="-W $NET_TIMEOUT"
    [ "$OS" = "Darwin" ] && wflag="-W $((NET_TIMEOUT * 1000))"
    local seen=0 line seq rtt stop=0
    trap 'stop=1' INT
    printf '\033[?25l'
    # shellcheck disable=SC2086
    while IFS= read -r line; do
        [ "$stop" -eq 1 ] && break
        seq="$(echo "$line" | sed -n 's/.*icmp_seq=\([0-9]*\).*/\1/p')"
        rtt="$(echo "$line" | sed -n 's/.*time[=<]\([0-9.]*\).*/\1/p')"
        if [ -n "$seq" ] && [ -n "$rtt" ]; then
            echo "$seq $rtt" >> "$rtts"
            seen=$((seen + 1))
            ui_progress "$seq" "$count" "seq $seq  rtt ${rtt} ms  received $seen"
        fi
    done < <(ping -n -c "$count" -i "$interval" $wflag "$target" 2>&1 | tee "$raw")
    trap - INT
    printf '\r\033[K\033[?25h'

    if grep -qiE 'unknown host|cannot resolve|Name or service not known|not known' "$raw"; then
        ui_fail "Could not resolve $target"; pause; return
    fi
    if grep -qiE 'cannot flood|minimal interval|Operation not permitted' "$raw"; then
        ui_fail "ping rejected the interval $interval (try 0.2 or run as root)"; pause; return
    fi

    local sent; sent="$(sed -n 's/^\([0-9]*\) packets transmitted.*/\1/p' "$raw" | head -1)"
    is_int "$sent" || sent="$(awk 'END{print NR}' "$rtts")"
    [ "$sent" -eq 0 ] && { ui_fail "No packets were sent"; pause; return; }

    # All statistics in one awk pass.
    local stats
    stats="$(sort -n -k1,1 "$rtts" | awk -v sent="$sent" '
        { seq[NR]=$1; r[NR]=$2; s+=$2; ss+=$2*$2;
          if (NR==1 || $2<mn) mn=$2; if ($2>mx) mx=$2;
          if (NR>1) { d=$2-prev; if (d<0) d=-d; js+=d; jn++ } prev=$2;
          if (seq[NR]==lastseq) dup++; lastseq=seq[NR] }
        END {
          n=NR; lost=sent-n+dup; if (lost<0) lost=0
          if (n==0) { printf "%d 0 %d 100 0 0 0 0 0 0 0 0 0 0 0\n", sent, sent; exit }
          avg=s/n; sd=sqrt((ss/n)-(avg*avg)); if (sd!=sd) sd=0
          jit=(jn>0)?js/jn:0
          # percentiles on sorted rtts
          for (i=1;i<=n;i++) v[i]=r[i]
          for (i=2;i<=n;i++){ x=v[i]; j=i-1; while (j>0 && v[j]>x){ v[j+1]=v[j]; j-- } v[j+1]=x }
          p50=v[int((n-1)*0.50)+1]; p90=v[int((n-1)*0.90)+1]; p95=v[int((n-1)*0.95)+1]; p99=v[int((n-1)*0.99)+1]
          # longest burst of consecutive lost sequence numbers
          burst=0; cur=0; first=seq[1]
          for (i=2;i<=n;i++){ g=seq[i]-seq[i-1]-1; if (g>burst) burst=g }
          printf "%d %d %d %.2f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %d %d\n", sent, n, lost, lost*100/sent, mn, avg, mx, sd, jit, p50, p90, p95, p99, burst, dup
        }')"
    # shellcheck disable=SC2086
    set -- $stats
    local s_sent=$1 s_recv=$2 s_lost=$3 s_loss=$4 s_min=$5 s_avg=$6 s_max=$7 s_sd=$8 s_jit=$9
    local s_p50=${10} s_p90=${11} s_p95=${12} s_p99=${13} s_burst=${14} s_dup=${15}

    ui_box_top "Results"
    ui_box_line "Packets      sent ${C_B}$s_sent${C_RST}   received ${C_B}$s_recv${C_RST}   lost ${C_B}$s_lost${C_RST}   duplicates $s_dup"
    local lcol="$C_GRN"
    awk -v l="$s_loss" 'BEGIN{exit !(l>=1)}' && lcol="$C_YEL"
    awk -v l="$s_loss" 'BEGIN{exit !(l>=5)}' && lcol="$C_RED"
    ui_box_line "Packet loss  ${lcol}${C_B}${s_loss}%${C_RST}   longest loss burst: $s_burst packet(s)"
    ui_box_sep
    ui_box_line "Latency      min ${s_min}  avg $(lat_color "$s_avg")${s_avg}${C_RST}  max ${s_max}  stddev ${s_sd}  (ms)"
    ui_box_line "Jitter       $(lat_color "$(awk -v j="$s_jit" 'BEGIN{print j*5}')")${s_jit} ms${C_RST}  (mean deviation between consecutive replies)"
    ui_box_line "Percentiles  p50 ${s_p50}  p90 ${s_p90}  p95 ${s_p95}  p99 ${s_p99}  (ms)"
    ui_box_bottom

    if [ "$s_recv" -gt 0 ]; then
        ui_section "Latency distribution"
        awk -v mn="$s_min" -v mx="$s_max" '{ print $2 }' "$rtts" | awk -v mn="$s_min" -v mx="$s_max" '
            { v[NR]=$1 } END {
              b=8; w=(mx-mn)/b; if (w<=0) w=1
              for (i=1;i<=NR;i++){ k=int((v[i]-mn)/w); if (k>=b) k=b-1; c[k]++ }
              for (k=0;k<b;k++) printf "%.1f %.1f %d %d\n", mn+k*w, mn+(k+1)*w, c[k]+0, NR }' | \
        while read -r lo hi c n; do
            printf '    %8s - %-8s ms %s %4d  %s%5.1f%%%s\n' "$lo" "$hi" "$(ui_bar "$c" "$n" 30 "$(lat_color "$hi")")" "$c" "$C_GRY" "$(awk -v c="$c" -v n="$n" 'BEGIN{print c*100/n}')" "$C_RST"
        done

        ui_section "Timeline (each cell = 1 packet, ${G_FAIL} = lost)"
        local tl
        tl="$(awk -v sent="$s_sent" 'NR==1{ base=$1 } { got[$1]=$2; if ($1<base) base=$1 } END {
            if (base>1) base=1; for (i=base;i<base+sent;i++) printf "%s ", (i in got)?got[i]:"x" }' "$rtts")"
        echo "$tl" | tr ' ' '\n' | grep -v '^$' | awk -v w=$((UI_W - 6)) '{ a[NR]=$0 } END { for (i=1;i<=NR;i+=w){ s=""; for (j=i;j<i+w && j<=NR;j++) s=s" "a[j]; print s } }' | \
        while IFS= read -r chunk; do printf '    %s\n' "$(sparkline "$chunk")"; done
    fi

    # Quality estimate (simplified ITU-T E-model) -> MOS for VoIP / gaming feel.
    local verdict
    verdict="$(awk -v a="$s_avg" -v j="$s_jit" -v l="$s_loss" 'BEGIN{
        e=a+2*j+10; if (e<160) r=93.2-e/40; else r=93.2-(e-120)/10; r=r-2.5*l; if (r<0) r=0; if (r>100) r=100
        mos=1+0.035*r+0.000007*r*(r-60)*(100-r); if (mos<1) mos=1
        q=(mos>=4.3)?"Excellent":(mos>=4.0)?"Good":(mos>=3.6)?"Fair":(mos>=3.1)?"Poor":"Bad"
        printf "%.2f %s", mos, q }')"
    ui_section "Quality"
    ui_kv "MOS (VoIP est.)" "${verdict% *} / 4.50  ${verdict#* }" "$C_B"
    case "${verdict#* }" in
        Excellent|Good) ui_ok "Connection is suitable for VoIP, video calls and gaming." ;;
        Fair) ui_warn "Usable, but calls/gaming may show occasional glitches." ;;
        *) ui_fail "Poor quality - expect choppy calls and lag." ;;
    esac
    write_log "Packet loss $target: sent=$s_sent recv=$s_recv loss=${s_loss}% avg=${s_avg}ms jitter=${s_jit}ms p95=${s_p95} MOS=${verdict}"
    pause
}

# ============================================================================
#  3. TCP PORT MONITOR
# ============================================================================
mode_tcp_monitor() {
    local target port interval
    ui_header "TCP Port Monitor"
    ask_required target "Target host" "example.com"
    ui_note "    Common: HTTP 80  HTTPS 443  SSH 22  RDP 3389  SMB 445"
    ask_int port "Port" "443" 1 65535
    ask_num interval "Interval in seconds" "2" "0.2"

    ui_header "TCP Monitor ${G_RIGHT} $target:$port $(service_name "$port")"
    ui_note "Press Q (or Ctrl+C) to stop."
    echo
    write_log "TCP monitor started: $target:$port"
    local total=0 failed=0 sum=0 ok=0 spark="" ms ts stop=0 min="" max=0
    trap 'stop=1' INT
    while [ "$stop" -eq 0 ]; do
        total=$((total + 1)); check_log_size
        ts="$(date '+%H:%M:%S')"
        printf '\r\033[K'
        if ms="$(tcp_connect "$target" "$port")"; then
            ok=$((ok + 1)); sum=$((sum + ms))
            [ -z "$min" ] || [ "$ms" -lt "$min" ] && min="$ms"
            [ "$ms" -gt "$max" ] && max="$ms"
            printf '  %s%s%s %s%s%s  port %-6s %sopen%s     connect %s%6s ms%s  %s\n' "$C_GRN" "$G_OK" "$C_RST" "$C_GRY" "$ts" "$C_RST" "$port" "$C_GRN" "$C_RST" "$(lat_color "$ms")" "$ms" "$C_RST" "$(ui_bar "$ms" 300 20 "$(lat_color "$ms")")"
            write_log "Port $port on $target - OPEN (${ms}ms)"
            spark="$spark $ms"
        else
            failed=$((failed + 1))
            printf '  %s%s%s %s%s%s  port %-6s %sclosed / filtered / timeout%s\n' "$C_RED" "$G_FAIL" "$C_RST" "$C_GRY" "$ts" "$C_RST" "$port" "$C_RED" "$C_RST"
            write_log "Port $port on $target - CLOSED"
            spark="$spark x"
        fi
        spark="$(echo "$spark" | awk '{ s=""; n=NF; st=(n>40)?n-39:1; for(i=st;i<=n;i++) s=s" "$i; print s }')"
        local avg="-"; [ "$ok" -gt 0 ] && avg=$((sum / ok))
        printf '  %s%s%s tries %d  failed %d (%s%%)  min/avg/max %s/%s/%s ms  %s' "$C_ACC" "$B_V" "$C_RST" "$total" "$failed" "$(awk -v f="$failed" -v t="$total" 'BEGIN{printf "%.1f", f*100/t}')" "${min:--}" "$avg" "$max" "$(sparkline "$spark")"
        wait_key "$interval"
        case "$KEY" in q|Q) stop=1 ;; esac
    done
    trap - INT
    echo; echo
    write_log "TCP monitor stopped: $target:$port tries=$total failed=$failed"
    pause
}

# ============================================================================
#  4. UDP PORT TEST
# ============================================================================
mode_udp_test() {
    local target port interval
    ui_header "UDP Port Test"
    ask_required target "Target host" "1.1.1.1"
    ui_note "    Common: DNS 53  NTP 123  SNMP 161  SSDP 1900  mDNS 5353  WireGuard 51820"
    ask_int port "Port" "53" 1 65535
    ask_num interval "Interval in seconds" "2" "0.5"
    have python3 || ui_warn "python3 not found - falling back to netcat heuristics (less accurate)."

    ui_header "UDP Test ${G_RIGHT} $target:$port $(service_name "$port")"
    ui_note "open = got a reply   closed = ICMP port-unreachable   open|filtered = silence"
    ui_note "Press Q (or Ctrl+C) to stop."
    echo
    local total=0 open=0 closed=0 filt=0 st ts stop=0
    trap 'stop=1' INT
    while [ "$stop" -eq 0 ]; do
        total=$((total + 1)); check_log_size
        ts="$(date '+%H:%M:%S')"
        st="$(udp_probe "$target" "$port")"
        printf '\r\033[K'
        case "$st" in
            open)          open=$((open + 1));     printf '  %s%s%s %s%s%s  udp/%-6s %sopen (response received)%s\n' "$C_GRN" "$G_OK" "$C_RST" "$C_GRY" "$ts" "$C_RST" "$port" "$C_GRN" "$C_RST" ;;
            closed)        closed=$((closed + 1)); printf '  %s%s%s %s%s%s  udp/%-6s %sclosed (ICMP unreachable)%s\n' "$C_RED" "$G_FAIL" "$C_RST" "$C_GRY" "$ts" "$C_RST" "$port" "$C_RED" "$C_RST" ;;
            open\|filtered) filt=$((filt + 1));    printf '  %s%s%s %s%s%s  udp/%-6s %sopen|filtered (no response)%s\n' "$C_YEL" "$G_WARN" "$C_RST" "$C_GRY" "$ts" "$C_RST" "$port" "$C_YEL" "$C_RST" ;;
            *)             closed=$((closed + 1)); printf '  %s%s%s %s%s%s  udp/%-6s %serror%s\n' "$C_RED" "$G_FAIL" "$C_RST" "$C_GRY" "$ts" "$C_RST" "$port" "$C_RED" "$C_RST" ;;
        esac
        write_log "UDP $target:$port - $st"
        printf '  %s%s%s probes %d  open %d  open|filtered %d  closed %d' "$C_ACC" "$B_V" "$C_RST" "$total" "$open" "$filt" "$closed"
        wait_key "$interval"
        case "$KEY" in q|Q) stop=1 ;; esac
    done
    trap - INT
    echo; echo
    pause
}

# ============================================================================
#  5. PORT SCAN (parallel)
# ============================================================================
mode_port_scan() {
    local target spec proto par t
    ui_header "Port Scanner"
    ask_required target "Target host" "scanme.nmap.org"
    ui_note "    Examples: 1-1024   22,80,443   8000-8100   common"
    ask_required spec "Ports" "common"
    ask_choice proto "Protocol" 1 "TCP" "UDP"
    ask_int par "Parallel probes" "64" 1 512
    ask_num t "Timeout per port (s)" "1" "0.2"

    local ip; ip="$(resolve_ip "$target")"
    [ -z "$ip" ] && { ui_fail "Could not resolve $target"; pause; return; }
    mk_tmp
    local list="$TMP_DIR/ports" res="$TMP_DIR/scan"; : > "$res"
    expand_ports "$spec" | sort -n -u > "$list"
    local total; total="$(awk 'END{print NR}' "$list")"
    [ "$total" -eq 0 ] && { ui_fail "No valid ports in '$spec'"; pause; return; }

    local pname="TCP"; [ "$proto" = "2" ] && pname="UDP"
    ui_header "Port Scan ${G_RIGHT} $target ($ip)"
    ui_info "Scanning $total $pname port(s), $par in parallel..."
    write_log "Port scan started: $target ($spec) $pname"
    local start; start="$(now_ms)"
    local done_n=0 batch=0 p stop=0
    trap 'stop=1' INT
    printf '\033[?25l'
    while IFS= read -r p; do
        [ "$stop" -eq 1 ] && break
        if [ "$pname" = "TCP" ]; then
            ( ms="$(tcp_connect "$ip" "$p" "$t")" && echo "$p open $ms" >> "$res" ) &
        else
            ( st="$(udp_probe "$ip" "$p" "$t")"; [ "$st" != "closed" ] && [ "$st" != "error" ] && echo "$p $st -" >> "$res" ) &
        fi
        batch=$((batch + 1)); done_n=$((done_n + 1))
        if [ "$batch" -ge "$par" ]; then
            wait; batch=0
            ui_progress "$done_n" "$total" "$done_n/$total ports  found $(awk 'END{print NR}' "$res")"
        fi
    done < "$list"
    wait
    trap - INT
    printf '\r\033[K\033[?25h'
    local elapsed=$(( $(now_ms) - start ))

    local found; found="$(awk 'END{print NR}' "$res")"
    ui_box_top "Scan results  ${C_GRY}($total ports in $(awk -v e="$elapsed" 'BEGIN{printf "%.1f", e/1000}')s)${C_RST}"
    if [ "$found" -eq 0 ]; then
        ui_box_line "${C_YEL}No open ports found.${C_RST}"
    else
        ui_box_line "${C_B}$(printf '%-8s %-15s %-14s %s' PORT STATE SERVICE LATENCY)${C_RST}"
        ui_box_sep
        sort -n "$res" | while read -r p st ms; do
            local col="$C_GRN"; [ "$st" != "open" ] && col="$C_YEL"
            local lat=""; [ "$ms" != "-" ] && lat="${ms} ms"
            ui_box_line "$(printf '%-8s %s%-15s%s %-14s %s' "$p/${pname}" "$col" "$st" "$C_RST" "$(service_name "$p")" "$lat")"
        done
    fi
    ui_box_bottom
    [ "$pname" = "UDP" ] && ui_note "  UDP 'open|filtered' means no answer; firewalls often silently drop probes."
    write_log "Port scan $target: $(sort -n "$res" | awk '{printf "%s(%s) ", $1, $2}')"
    pause
}

# ============================================================================
#  6. TRACEROUTE
# ============================================================================
# discover_hops TARGET MAXHOPS -> lines "hop ip rtt"
discover_hops() {
    local target="$1" max="$2"
    if have traceroute; then
        traceroute -n -q 1 -w 2 -m "$max" "$target" 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+$/ {
            ip="*"; rtt="*"; for (i=2;i<=NF;i++){ if ($i ~ /^[0-9a-f.:]+$/ && $i ~ /[.:]/ && ip=="*") ip=$i; if ($(i+1)=="ms" && rtt=="*") rtt=$i }
            print $1, ip, rtt }'
        return
    fi
    if have tracepath; then
        tracepath -n -m "$max" "$target" 2>/dev/null | awk '$1 ~ /^[0-9]+:/ { h=$1; sub(":","",h); if (h==prev) next; prev=h
            ip=($2=="no")?"*":$2; rtt="*"; for(i=3;i<=NF;i++) if ($i ~ /ms$/) { rtt=$i; sub("ms","",rtt); break }
            print h, ip, rtt }'
        return
    fi
    local ttl ip rtt out
    for ((ttl = 1; ttl <= max; ttl++)); do
        if [ "$OS" = "Darwin" ]; then out="$(ping -n -c 1 -W 2000 -m "$ttl" "$target" 2>&1)"
        else out="$(ping -n -c 1 -W 2 -t "$ttl" "$target" 2>&1)"; fi
        rtt="$(echo "$out" | sed -n 's/.*time[=<]\([0-9.]*\).*/\1/p' | head -1)"
        ip="$(echo "$out" | grep -oE '[Ff]rom [0-9.]+' | head -1 | awk '{print $2}')"
        [ -z "$ip" ] && ip="$(echo "$out" | sed -n 's/.*bytes from \([0-9.]*\).*/\1/p' | head -1)"
        if [ -n "$rtt" ]; then
            echo "$ttl ${ip:-$target} $rtt"; break
        fi
        echo "$ttl ${ip:-*} *"
    done
}

mode_traceroute() {
    local target max
    ui_header "Traceroute"
    ask_required target "Target host" "1.1.1.1"
    ask_int max "Max hops" "30" 1 64
    ui_header "Traceroute ${G_RIGHT} $target"
    write_log "Traceroute to $target"
    ui_box_top "Route"
    ui_box_line "${C_B}$(printf '%-4s %-40s %10s' HOP 'HOST' 'RTT')${C_RST}"
    ui_box_sep
    local hop ip rtt name n=0
    while read -r hop ip rtt; do
        n=$((n + 1))
        if [ "$ip" = "*" ]; then
            ui_box_line "$(printf '%-4s %s%-40s %10s%s' "$hop" "$C_GRY" "* (no reply)" "*" "$C_RST")"
        else
            name="$ip"
            if have dig; then
                local r; r="$(dig +short +time=1 +tries=1 -x "$ip" 2>/dev/null | head -1 | sed 's/\.$//')"
                [ -n "$r" ] && name="$ip ${C_GRY}${r:0:28}${C_RST}"
            fi
            local col; col="$(lat_color "${rtt%.*}")"
            [ "$rtt" = "*" ] && col="$C_GRY"
            ui_box_line "$(printf '%-4s %s' "$hop" "$name")$(printf '%*s' $((41 - $(vlen "$name"))) '')$(printf '%s%9s%s' "$col" "${rtt} ms" "$C_RST")"
        fi
        write_log "Hop $hop: $ip ($rtt ms)"
    done < <(discover_hops "$target" "$max")
    ui_box_bottom
    [ "$n" -eq 0 ] && ui_fail "Traceroute produced no output (install traceroute or run as root)."
    pause
}

# ============================================================================
#  7. NETWORK PATH ANALYSIS - MTR + ASN + GEO  (issue #2)
# ============================================================================
mode_path_analysis() {
    local target rounds max
    ui_header "Network Path Analysis (MTR)"
    ask_required target "Target host" "1.1.1.1"
    ask_int rounds "Probe rounds" "10" 1 500
    ask_int max "Max hops" "30" 1 64
    mk_tmp

    ui_header "Path Analysis ${G_RIGHT} $target"
    local hops="$TMP_DIR/hops"
    ( discover_hops "$target" "$max" > "$hops" ) &
    spin_wait $! "Discovering route to $target..."
    local nh; nh="$(awk 'END{print NR}' "$hops")"
    [ "$nh" -eq 0 ] && { ui_fail "Could not discover any hops (needs traceroute/tracepath or ping TTL support)."; pause; return; }
    write_log "Path analysis to $target ($nh hops, $rounds rounds)"

    # Per-hop stats files: sent recv sum sumsq best worst last
    local i=0 hop ip rtt
    local -a H_IP
    while read -r hop ip rtt; do
        H_IP[$hop]="$ip"
        echo "0 0 0 0 0 0 0" > "$TMP_DIR/h$hop"
    done < "$hops"
    local last_hop; last_hop="$(tail -1 "$hops" | awk '{print $1}')"

    draw_mtr() {
        local h f
        printf '\033[?25l'
        ui_box_top "Round $1/$rounds"
        ui_box_line "${C_B}$(printf '%-3s %-16s %6s %4s %7s %7s %7s %7s' HOP HOST 'LOSS%' SNT LAST AVG BEST WRST)${C_RST}  ${C_B}JITTER${C_RST}"
        ui_box_sep
        for ((h = 1; h <= last_hop; h++)); do
            f="$TMP_DIR/h$h"; [ -f "$f" ] || continue
            local hip="${H_IP[$h]:-*}"
            if [ "$hip" = "*" ]; then
                ui_box_line "$(printf '%-3s %s%-16s %6s %4s %7s %7s %7s %7s%s' "$h" "$C_GRY" "???" "-" "-" "-" "-" "-" "-" "$C_RST")"
                continue
            fi
            read -r s r sum sq best worst last < "$f"
            local line
            line="$(awk -v h="$h" -v ip="$hip" -v s="$s" -v r="$r" -v sum="$sum" -v sq="$sq" -v b="$best" -v w="$worst" -v l="$last" 'BEGIN{
                loss=(s>0)?(s-r)*100/s:0; avg=(r>0)?sum/r:0; sd=(r>0)?sqrt(sq/r-avg*avg):0; if (sd!=sd) sd=0
                printf "%-3s %-16s %6.1f %4d %7.1f %7.1f %7.1f %7.1f|%.1f|%.1f|%.1f", h, substr(ip,1,16), loss, s, l, avg, b, w, sd, loss, avg }')"
            local text="${line%%|*}" rest="${line#*|}"
            local sd="${rest%%|*}" loss avg; rest="${rest#*|}"; loss="${rest%%|*}"; avg="${rest#*|}"
            local col="$C_GRN"
            awk -v l="$loss" 'BEGIN{exit !(l>0)}' && col="$C_YEL"
            awk -v l="$loss" 'BEGIN{exit !(l>=20)}' && col="$C_RED"
            ui_box_line "${col}${text}${C_RST}  $(printf '%6s' "$sd")"
        done
        ui_box_bottom
    }

    local hdr_lines=$((nh + 4)) r stop=0
    trap 'stop=1' INT
    for ((r = 1; r <= rounds; r++)); do
        [ "$stop" -eq 1 ] && break
        while read -r hop ip rtt; do
            [ "$ip" = "*" ] && continue
            (
                f="$TMP_DIR/h$hop"
                v="$(ping_once "$ip" 1)"
                # Serialise updates per hop via its own file (single writer per hop per round)
                read -r s rc sum sq best worst last < "$f"
                s=$((s + 1))
                if [ -n "$v" ]; then
                    awk -v s="$s" -v rc="$rc" -v sum="$sum" -v sq="$sq" -v b="$best" -v w="$worst" -v v="$v" 'BEGIN{
                        rc++; sum+=v; sq+=v*v; if (b==0 || v<b) b=v; if (v>w) w=v; print s, rc, sum, sq, b, w, v }' > "$f.new"
                else
                    echo "$s $rc $sum $sq $best $worst $last" > "$f.new"
                fi
                mv "$f.new" "$f"
            ) &
        done < "$hops"
        wait
        [ "$r" -gt 1 ] && printf '\033[%dA' "$hdr_lines"
        draw_mtr "$r"
        [ "$r" -lt "$rounds" ] && { wait_key 1; case "$KEY" in q|Q) stop=1 ;; esac; }
    done
    trap - INT
    printf '\033[?25h'

    # ASN + Geo enrichment
    ui_section "ASN & geographic route"
    local prev_lat="" prev_lon="" total_km=0 maplink="https://www.google.com/maps/dir" route="" npub=0
    printf '    %s%-3s %-16s %-10s %-34s %s%s\n' "$C_B" HOP IP ASN "OPERATOR" LOCATION "$C_RST"
    while read -r hop ip rtt; do
        if [ "$ip" = "*" ]; then continue; fi
        if is_private_ip "$ip"; then
            printf '    %-3s %-16s %s%-10s %-34s %s%s\n' "$hop" "$ip" "$C_GRY" "-" "private / local network" "-" "$C_RST"
            continue
        fi
        geo_lookup "$ip"
        local asn="${GEO_AS%% *}" opname="${GEO_AS#* }"
        [ -z "$GEO_AS" ] && { asn="?"; opname="${GEO_ORG:-unknown}"; }
        local loc="${GEO_CITY:+$GEO_CITY, }${GEO_CC}"
        local dist=""
        if [ -n "$GEO_LAT" ] && [ -n "$prev_lat" ]; then
            dist="$(awk -v a="$prev_lat" -v b="$prev_lon" -v c="$GEO_LAT" -v d="$GEO_LON" 'BEGIN{
                pi=atan2(0,-1); r=6371; x1=a*pi/180; x2=c*pi/180; dl=(d-b)*pi/180; dp=x2-x1
                h=sin(dp/2)^2+cos(x1)*cos(x2)*sin(dl/2)^2; printf "%d", 2*r*atan2(sqrt(h),sqrt(1-h)) }')"
            total_km=$((total_km + dist))
        fi
        local dtxt=""; [ -n "$dist" ] && [ "$dist" -gt 50 ] && dtxt=" ${C_GRY}(+${dist} km)${C_RST}"
        printf '    %-3s %-16s %s%-10s%s %-34s %s%s\n' "$hop" "$ip" "$C_ACC" "$asn" "$C_RST" "${opname:0:34}" "${loc:-?}" "$dtxt"
        if [ -n "$GEO_LAT" ]; then
            if [ "$GEO_LAT" != "$prev_lat" ] || [ "$GEO_LON" != "$prev_lon" ]; then
                maplink="$maplink/$GEO_LAT,$GEO_LON"
                route="$route${route:+ $G_RIGHT }${GEO_CITY:-?} ${GEO_CC}"
                npub=$((npub + 1))
            fi
            prev_lat="$GEO_LAT"; prev_lon="$GEO_LON"
        fi
        write_log "Hop $hop $ip $GEO_AS $loc"
        sleep 0.3 2>/dev/null   # stay well under ip-api's free rate limit
    done < "$hops"

    if [ "$npub" -gt 0 ]; then
        echo
        ui_kv "Route" "$route"
        ui_kv "Distance" "~${total_km} km (great-circle between hops)"
        [ "$npub" -gt 1 ] && ui_kv "Map" "$maplink"
    fi
    echo
    ui_note "  Loss on intermediate hops that does not continue to the final hop is usually"
    ui_note "  ICMP rate-limiting on that router, not real packet loss."
    pause
}

# ============================================================================
#  8. DNS LOOKUP
# ============================================================================
mode_dns() {
    local domain
    ui_header "DNS Lookup"
    ask_required domain "Domain name" "example.com"
    ui_header "DNS ${G_RIGHT} $domain"
    if ! dns_tool_available; then
        ui_warn "No dig/host/nslookup found - only basic A lookups are possible."
        ui_note "  Install: apt install dnsutils  |  dnf install bind-utils  |  brew install bind"
    fi
    write_log "DNS lookup for $domain"

    ui_section "Resolver comparison (A record)"
    printf '    %s%-16s %-16s %8s  %s%s\n' "$C_B" RESOLVER ADDRESS TIME ANSWER "$C_RST"
    local names="System Google Cloudflare Quad9 OpenDNS"
    local servers=" 8.8.8.8 1.1.1.1 9.9.9.9 208.67.222.222"
    local i=0 n s ans t0 t1 first_ans="" mismatch=0
    set -- $servers
    for n in $names; do
        s=""; [ "$n" != "System" ] && { s="$1"; shift; }
        t0="$(now_ms)"
        ans="$(dns_query "$domain" A "$s" | grep -E '^[0-9.]+$' | sort | tr '\n' ' ')"
        t1="$(now_ms)"
        local ms=$((t1 - t0))
        if [ -n "$ans" ]; then
            printf '    %-16s %-16s %s%6s ms%s  %s%s%s\n' "$n" "${s:-default}" "$(lat_color "$ms")" "$ms" "$C_RST" "$C_GRN" "$ans" "$C_RST"
            [ -z "$first_ans" ] && first_ans="$ans"
            [ "$ans" != "$first_ans" ] && mismatch=1
        else
            printf '    %-16s %-16s %8s  %sno answer%s\n' "$n" "${s:-default}" "-" "$C_YEL" "$C_RST"
        fi
    done
    [ "$mismatch" -eq 1 ] && ui_note "    (Different answers are normal for CDNs/geo-DNS.)"

    local type recs
    for type in AAAA CNAME MX NS TXT SOA CAA; do
        recs="$(dns_query "$domain" "$type")"
        ui_section "$type"
        if [ -n "$recs" ]; then
            echo "$recs" | head -12 | while IFS= read -r l; do printf '    %s%s%s\n' "$C_GRN" "${l:0:$((UI_W - 6))}" "$C_RST"; done
        else
            printf '    %snone%s\n' "$C_GRY" "$C_RST"
        fi
    done

    # Mail security quick checks
    ui_section "Mail security"
    local spf dmarc
    spf="$(dns_query "$domain" TXT | grep -i 'v=spf1' | head -1)"
    dmarc="$(dns_query "_dmarc.$domain" TXT | grep -i 'v=DMARC1' | head -1)"
    if [ -n "$spf" ]; then ui_ok "SPF   ${C_GRY}${spf:0:70}${C_RST}"; else ui_warn "SPF   not found"; fi
    if [ -n "$dmarc" ]; then ui_ok "DMARC ${C_GRY}${dmarc:0:70}${C_RST}"; else ui_warn "DMARC not found"; fi
    write_log "DNS lookup completed for $domain"
    pause
}

# ============================================================================
#  9. BANDWIDTH TEST
# ============================================================================
mode_bandwidth() {
    local size
    ui_header "Bandwidth Test"
    have curl || { ui_fail "curl is required"; pause; return; }
    ask_choice size "Test size" 2 "Quick     (10 MB down /  5 MB up)" "Standard  (25 MB down / 10 MB up)" "Extended (100 MB down / 25 MB up)"
    local down up
    case "$size" in 1) down=10000000; up=5000000 ;; 2) down=25000000; up=10000000 ;; *) down=100000000; up=25000000 ;; esac
    mk_tmp
    ui_header "Bandwidth Test"
    write_log "Bandwidth test started ($((down / 1000000)) MB)"

    ui_section "Latency (Cloudflare)"
    local lat; lat="$(curl -s -o /dev/null -w '%{time_connect}' --max-time 5 https://speed.cloudflare.com/__down?bytes=0 2>/dev/null)"
    local i samples=""
    for i in 1 2 3 4 5; do
        local t; t="$(curl -s -o /dev/null -w '%{time_starttransfer} %{time_pretransfer}' --max-time 5 "https://speed.cloudflare.com/__down?bytes=0" 2>/dev/null | awk '{printf "%.1f", ($1-$2)*1000}')"
        [ -n "$t" ] && samples="$samples $t"
    done
    if [ -n "$samples" ]; then
        local lstats; lstats="$(echo "$samples" | awk '{ for(i=1;i<=NF;i++){ s+=$i; if(i>1){d=$i-$(i-1); if(d<0)d=-d; j+=d} } printf "%.1f %.1f", s/NF, (NF>1)?j/(NF-1):0 }')"
        ui_kv "Idle latency" "${lstats% *} ms" "$(lat_color "${lstats% *}")"
        ui_kv "Jitter" "${lstats#* } ms"
    else
        ui_warn "Could not reach speed.cloudflare.com"
    fi

    ui_section "Download"
    ( curl -s -o /dev/null -w '%{speed_download} %{size_download} %{time_total}' --max-time 120 "https://speed.cloudflare.com/__down?bytes=$down" > "$TMP_DIR/bw_down" 2>/dev/null ) &
    spin_wait $! "Downloading $((down / 1000000)) MB..."
    local r; r="$(cat "$TMP_DIR/bw_down" 2>/dev/null)"
    local dmbps="0"
    if [ -n "$r" ]; then
        dmbps="$(echo "$r" | awk '{printf "%.2f", $1*8/1000000}')"
        ui_kv "Speed" "$dmbps Mbps" "$C_B"
        ui_kv "Transferred" "$(echo "$r" | awk '{printf "%.1f MB in %.2f s", $2/1000000, $3}')"
        printf '    %s\n' "$(ui_bar "$dmbps" 1000 40 "$C_GRN")  ${C_GRY}scale 0-1000 Mbps${C_RST}"
    else
        ui_fail "Download failed"
    fi

    ui_section "Upload"
    head -c "$up" /dev/zero > "$TMP_DIR/bw_up" 2>/dev/null
    ( curl -s -o /dev/null -w '%{speed_upload} %{size_upload} %{time_total}' --max-time 120 --data-binary @"$TMP_DIR/bw_up" "https://speed.cloudflare.com/__up" > "$TMP_DIR/bw_upr" 2>/dev/null ) &
    spin_wait $! "Uploading $((up / 1000000)) MB..."
    r="$(cat "$TMP_DIR/bw_upr" 2>/dev/null)"
    local umbps="0"
    if [ -n "$r" ] && [ "$(echo "$r" | awk '{print int($2)}')" -gt 0 ]; then
        umbps="$(echo "$r" | awk '{printf "%.2f", $1*8/1000000}')"
        ui_kv "Speed" "$umbps Mbps" "$C_B"
        printf '    %s\n' "$(ui_bar "$umbps" 1000 40 "$C_ACC2")  ${C_GRY}scale 0-1000 Mbps${C_RST}"
    else
        ui_fail "Upload failed"
    fi
    rm -f "$TMP_DIR/bw_up"
    write_log "Bandwidth: down=${dmbps}Mbps up=${umbps}Mbps latency=${lstats:-n/a}"
    ui_note "  Single-stream test against Cloudflare; results may be lower than multi-stream tests."
    pause
}

# ============================================================================
#  10. PUBLIC IP & NETWORK INFO
# ============================================================================
local_ip()  {
    if [ "$OS" = "Darwin" ]; then
        local ifc; ifc="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
        ipconfig getifaddr "${ifc:-en0}" 2>/dev/null
    else
        ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
    fi
}
gateway_ip() {
    if [ "$OS" = "Darwin" ]; then route -n get default 2>/dev/null | awk '/gateway:/{print $2}'
    else ip route show default 2>/dev/null | awk '{print $3; exit}'; fi
}
default_iface() {
    if [ "$OS" = "Darwin" ]; then route -n get default 2>/dev/null | awk '/interface:/{print $2}'
    else ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'; fi
}
dns_servers() {
    if [ "$OS" = "Darwin" ]; then scutil --dns 2>/dev/null | awk '/nameserver\[/{print $3}' | sort -u | tr '\n' ' '
    elif have resolvectl && resolvectl dns >/dev/null 2>&1; then
        resolvectl dns 2>/dev/null | awk -F: '{print $2}' | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' '
    else awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | tr '\n' ' '; fi
}

mode_public_ip() {
    ui_header "Public IP & Network Info"
    write_log "Public IP check started"
    ui_section "Local network"
    ui_kv "Hostname" "$(hostname 2>/dev/null)"
    ui_kv "Interface" "$(default_iface)"
    ui_kv "Local IP" "$(local_ip)"
    ui_kv "Gateway" "$(gateway_ip)"
    ui_kv "DNS servers" "$(dns_servers)"

    ui_section "Public address"
    local pip; pip="$(public_ip)"
    if [ -z "$pip" ]; then ui_fail "Could not determine public IPv4 address"; pause; return; fi
    ui_kv "IPv4" "$pip" "$C_GRN$C_B"
    local v6; v6="$(http_get https://api6.ipify.org 5 | tr -d '[:space:]')"
    case "$v6" in *:*) ui_kv "IPv6" "$v6" "$C_GRN" ;; *) ui_kv "IPv6" "not available" "$C_GRY" ;; esac
    local rdns=""; have dig && rdns="$(dig +short -x "$pip" 2>/dev/null | head -1)"
    [ -n "$rdns" ] && ui_kv "Reverse DNS" "$rdns"

    if geo_lookup "$pip"; then
        ui_section "Location & provider"
        ui_kv "City" "$GEO_CITY"
        ui_kv "Region" "$GEO_REGION"
        ui_kv "Country" "$GEO_COUNTRY ($GEO_CC)"
        ui_kv "Coordinates" "$GEO_LAT, $GEO_LON"
        ui_kv "Timezone" "$GEO_TZ"
        ui_kv "ISP" "$GEO_ORG"
        ui_kv "ASN" "$GEO_AS"
        [ "$GEO_PROXY" = "true" ] && ui_warn "This IP is flagged as a proxy / VPN / Tor exit."
        [ "$GEO_HOSTING" = "true" ] && ui_info "This IP belongs to a hosting / datacenter network."
        write_log "Public IP: $pip | $GEO_CITY, $GEO_CC | $GEO_AS"
    else
        ui_warn "Could not fetch location details"
        write_log "Public IP: $pip (no details)"
    fi
    pause
}

# ============================================================================
#  11. EXTERNAL PORT CHECK
# ============================================================================
mode_external_ports() {
    local spec
    ui_header "External Port Check"
    ui_note "  Checks whether ports on your public IP are reachable from the internet"
    ui_note "  (e.g. to verify port forwarding)."
    echo
    ask_required spec "Ports (e.g. 80,443,25565)" "80,443"
    ui_header "External Port Check"
    local pip; pip="$(public_ip)"
    [ -z "$pip" ] && { ui_fail "Could not determine public IP"; pause; return; }
    ui_kv "Public IP" "$pip" "$C_B"
    echo
    write_log "External port check on $pip: $spec"
    local p res method
    for p in $(expand_ports "$spec" | head -50); do
        method="remote"
        res="$(curl -s --max-time 15 -d "remoteAddress=$pip&portNumber=$p" https://ports.yougetsignal.com/check-port.php 2>/dev/null)"
        case "$res" in
            *"is open"*)   ui_ok   "$(printf '%-6s %-12s' "$p" "$(service_name "$p")") ${C_GRN}OPEN${C_RST}  ${C_GRY}(checked from the internet)${C_RST}"; write_log "External $p: OPEN" ;;
            *"is closed"*) ui_fail "$(printf '%-6s %-12s' "$p" "$(service_name "$p")") ${C_RED}CLOSED${C_RST}  ${C_GRY}(checked from the internet)${C_RST}"; write_log "External $p: CLOSED" ;;
            *)
                if tcp_connect "$pip" "$p" 5 >/dev/null; then
                    ui_ok "$(printf '%-6s %-12s' "$p" "$(service_name "$p")") ${C_GRN}OPEN${C_RST}  ${C_YEL}(local hairpin test)${C_RST}"
                else
                    ui_fail "$(printf '%-6s %-12s' "$p" "$(service_name "$p")") ${C_RED}CLOSED/FILTERED${C_RST}  ${C_YEL}(local hairpin test)${C_RST}"
                fi
                write_log "External $p: hairpin test" ;;
        esac
    done
    echo
    ui_note "  'hairpin' = remote checker unavailable; tested by connecting to your own public"
    ui_note "  IP, which many routers do not support (NAT loopback). A service must be listening."
    pause
}

# ============================================================================
#  12. WEB PERFORMANCE  (issue #5)
# ============================================================================
CURL_FMT='%{time_namelookup} %{time_connect} %{time_appconnect} %{time_pretransfer} %{time_starttransfer} %{time_total} %{size_download} %{http_code} %{http_version} %{num_redirects} %{remote_ip} %{content_type}\n'

# url_resolve BASE REF -> absolute URL
url_resolve() {
    local base="$1" ref="$2" scheme host path
    ref="$(echo "$ref" | sed 's/&amp;/\&/g; s/#.*//')"
    case "$ref" in
        http://*|https://*) echo "$ref"; return ;;
        //*) echo "${base%%:*}:$ref"; return ;;
        data:*|javascript:*|mailto:*|"") return ;;
    esac
    scheme="${base%%://*}"; host="${base#*://}"; host="${host%%/*}"
    path="${base#*://$host}"; path="${path%%\?*}"
    case "$ref" in
        /*) echo "$scheme://$host$ref" ;;
        *)  echo "$scheme://$host${path%/*}/$ref" ;;
    esac
}

# phase bar: offset dns connect tls wait recv scale width
waterfall_bar() {
    awk -v o="$1" -v d="$2" -v c="$3" -v t="$4" -v w="$5" -v r="$6" -v sc="$7" -v W="$8" \
        -v cd="$C_GRY" -v cc="$C_YEL" -v ct="$C_MAG" -v cw="$C_ACC" -v cr="$C_GRN" -v z="$C_RST" -v F="$G_FULL" -v E=" " '
        function rep(ch, n,  s,i){ s=""; for(i=0;i<n;i++) s=s ch; return s }
        BEGIN{
        if (sc<=0) sc=1
        po=int(o/sc*W+0.5); pd=int(d/sc*W+0.5); pc=int(c/sc*W+0.5); pt=int(t/sc*W+0.5); pw=int(w/sc*W+0.5); pr=int(r/sc*W+0.5)
        if (pd+pc+pt+pw+pr==0 && d+c+t+w+r>0) { if (w>=r) pw=1; else pr=1 }
        tot=po+pd+pc+pt+pw+pr; while (tot>W && pr>0) { pr--; tot-- }
        printf "%s%s%s%s%s%s%s%s%s%s%s%s%s", rep(E,po), cd, rep(F,pd), cc, rep(F,pc), ct, rep(F,pt), cw, rep(F,pw), cr, rep(F,pr), z, rep(" ", W-tot>0?W-tot:0)
    }'
}

mode_web_perf() {
    local url runs
    ui_header "Web Performance Test"
    have curl || { ui_fail "curl is required"; pause; return; }
    ask_required url "URL" "https://example.com"
    case "$url" in http://*|https://*) ;; *) url="https://$url" ;; esac
    ask_int runs "Timing runs for the main document" "3" 1 20
    mk_tmp
    local host="${url#*://}"; host="${host%%/*}"; host="${host%%:*}"

    ui_header "Web Performance ${G_RIGHT} $url"
    write_log "Web performance test: $url"

    # --- Page load phases -------------------------------------------------
    ui_section "Page load timing (main document, $runs run(s))"
    local i out all=""
    for ((i = 1; i <= runs; i++)); do
        out="$(curl -s -L -o "$TMP_DIR/page.html" -D "$TMP_DIR/headers" -A "Mozilla/5.0 PingPortTester/$PPT_VERSION" --compressed --max-time 30 -w "$CURL_FMT" "$url" 2>/dev/null)"
        [ -n "$out" ] && all="$all$out
"
        ui_progress "$i" "$runs" "run $i/$runs"
    done
    printf '\r\033[K'
    all="$(echo "$all" | grep -v '^$')"
    if [ -z "$all" ] || [ "$(echo "$all" | head -1 | awk '{print $8}')" = "000" ]; then
        ui_fail "Could not load $url"; pause; return
    fi
    # median per column
    local med
    med="$(echo "$all" | awk '{ for (i=1;i<=6;i++) v[i,NR]=$i } END{ n=NR; for (i=1;i<=6;i++){ for(a=1;a<=n;a++) s[a]=v[i,a]; for(a=2;a<=n;a++){x=s[a];b=a-1;while(b>0&&s[b]>x){s[b+1]=s[b];b--}s[b+1]=x} printf "%s ", s[int((n+1)/2)] } }')"
    # shellcheck disable=SC2086
    set -- $med
    local dns=$1 con=$2 tls=$3 pre=$4 ttfb=$5 tot=$6
    local last; last="$(echo "$all" | tail -1)"
    # shellcheck disable=SC2086
    set -- $last
    local size=$7 code=$8 ver=$9 redir=${10} rip=${11} ctype=${12}
    local p_dns p_con p_tls p_wait p_recv
    read -r p_dns p_con p_tls p_wait p_recv <<EOF
$(awk -v d="$dns" -v c="$con" -v t="$tls" -v p="$pre" -v f="$ttfb" -v z="$tot" 'BEGIN{
    if (t==0) t=c; printf "%.1f %.1f %.1f %.1f %.1f", d*1000, (c-d)*1000, (t-c)*1000, (f-p)*1000, (z-f)*1000 }')
EOF
    local scale; scale="$(awk -v z="$tot" 'BEGIN{printf "%.1f", z*1000}')"
    local bw=$((UI_W - 40)); [ "$bw" -lt 20 ] && bw=20
    local acc=0
    print_phase() {
        printf '    %-16s %s%8s ms%s  %s\n' "$1" "$C_B" "$2" "$C_RST" "$(waterfall_bar "$acc" "$3" "$4" "$5" "$6" "$7" "$scale" "$bw")"
        acc="$(awk -v a="$acc" -v b="$2" 'BEGIN{print a+b}')"
    }
    print_phase "DNS lookup" "$p_dns"  "$p_dns" 0 0 0 0
    print_phase "TCP connect" "$p_con" 0 "$p_con" 0 0 0
    print_phase "TLS handshake" "$p_tls" 0 0 "$p_tls" 0 0
    print_phase "Server wait" "$p_wait" 0 0 0 "$p_wait" 0
    print_phase "Content download" "$p_recv" 0 0 0 0 "$p_recv"
    printf '    %-16s %s%8s ms%s\n' "Total" "$C_B" "$scale" "$C_RST"
    echo
    ui_kv "TTFB" "$(awk -v f="$ttfb" 'BEGIN{printf "%.0f ms", f*1000}')" "$(lat_color "$(awk -v f="$ttfb" 'BEGIN{print f*1000/4}')")"
    ui_kv "HTTP status" "$code  (redirects: $redir)"
    ui_kv "Size" "$(awk -v s="$size" 'BEGIN{printf "%.1f KB", s/1024}')  $ctype"
    ui_kv "Server IP" "$rip"

    # --- Protocol support ----------------------------------------------------
    ui_section "Protocol support"
    local h1 h2 h3 alt
    h1="$(curl -s -o /dev/null --http1.1 --max-time 10 -w '%{http_version}' "$url" 2>/dev/null)"
    h2="$(curl -s -o /dev/null --http2 --max-time 10 -w '%{http_version}' "$url" 2>/dev/null)"
    alt="$(grep -i '^alt-svc:' "$TMP_DIR/headers" | tail -1 | tr -d '\r')"
    case "$h1" in 1.1) ui_ok "HTTP/1.1 supported" ;; 1|1.0) ui_warn "Server only speaks HTTP/1.0" ;; *) ui_warn "HTTP/1.1 not confirmed" ;; esac
    if [ "$h2" = "2" ]; then ui_ok "HTTP/2 supported (ALPN h2)"; else ui_warn "HTTP/2 not negotiated"; fi
    if curl --version 2>/dev/null | grep -qi 'HTTP3'; then
        h3="$(curl -s -o /dev/null --http3-only --max-time 10 -w '%{http_version}' "$url" 2>/dev/null)"
        if [ "$h3" = "3" ]; then ui_ok "HTTP/3 (QUIC) supported - verified"; elif echo "$alt" | grep -q 'h3'; then ui_warn "HTTP/3 advertised but QUIC connection failed (UDP 443 blocked?)"; else ui_warn "HTTP/3 not supported"; fi
    else
        if echo "$alt" | grep -q 'h3'; then ui_ok "HTTP/3 advertised via Alt-Svc ${C_GRY}(local curl lacks HTTP/3 to verify)${C_RST}"; else ui_warn "HTTP/3 not advertised"; fi
    fi
    write_log "Web $url: ttfb=${ttfb}s total=${tot}s h2=$h2 alt-svc=${alt:-none}"

    # --- CDN & caching -------------------------------------------------------
    ui_section "CDN & caching"
    local H; H="$(tr -d '\r' < "$TMP_DIR/headers" | awk '/^HTTP\//{buf=""} {buf=buf"\n"$0} END{print buf}')"
    hdr() { echo "$H" | grep -i "^$1:" | tail -1 | cut -d: -f2- | sed 's/^ //'; }
    local cdn=""
    [ -n "$(hdr cf-ray)" ] && cdn="Cloudflare (POP ${C_B}$(hdr cf-ray | sed 's/.*-//')${C_RST})"
    [ -z "$cdn" ] && [ -n "$(hdr x-amz-cf-pop)" ] && cdn="Amazon CloudFront (POP $(hdr x-amz-cf-pop))"
    [ -z "$cdn" ] && echo "$H" | grep -qi '^x-served-by:.*cache-' && cdn="Fastly ($(hdr x-served-by | sed 's/.*cache-//'))"
    [ -z "$cdn" ] && echo "$H" | grep -qiE '^(x-akamai|akamai-)' && cdn="Akamai"
    [ -z "$cdn" ] && [ -n "$(hdr x-vercel-id)" ] && cdn="Vercel ($(hdr x-vercel-id | cut -d: -f1))"
    [ -z "$cdn" ] && [ -n "$(hdr x-nf-request-id)" ] && cdn="Netlify"
    [ -z "$cdn" ] && [ -n "$(hdr x-azure-ref)" ] && cdn="Azure Front Door"
    [ -z "$cdn" ] && echo "$(hdr server)" | grep -qi 'gws\|ESF' && cdn="Google"
    [ -z "$cdn" ] && echo "$(hdr via)" | grep -qi 'varnish' && cdn="Varnish cache"
    [ -z "$cdn" ] && echo "$(hdr server)" | grep -qi 'bunny' && cdn="BunnyCDN"
    if [ -n "$cdn" ]; then ui_ok "CDN detected: $cdn"; else ui_info "No CDN fingerprint found (origin server: $(hdr server))"; fi

    local cache1 cache2 t1 t2
    cache1="$(hdr cf-cache-status)"; [ -z "$cache1" ] && cache1="$(hdr x-cache)"; [ -z "$cache1" ] && cache1="$(hdr x-vercel-cache)"
    local out2; out2="$(curl -s -o /dev/null -D "$TMP_DIR/headers2" --compressed -A "Mozilla/5.0" --max-time 20 -w '%{time_starttransfer}' -L "$url" 2>/dev/null)"
    cache2="$(tr -d '\r' < "$TMP_DIR/headers2" | grep -iE '^(cf-cache-status|x-cache|x-vercel-cache):' | tail -1 | cut -d: -f2- | sed 's/^ //')"
    ui_kv "Cache status" "${cache1:-n/a} ${G_RIGHT} ${cache2:-n/a} (1st ${G_RIGHT} 2nd request)"
    ui_kv "TTFB 2nd req" "$(awk -v f="$out2" 'BEGIN{printf "%.0f ms", f*1000}')"
    ui_kv "Cache-Control" "$(hdr cache-control)"
    ui_kv "Age" "$(hdr age)"
    ui_kv "Compression" "$(hdr content-encoding)"
    case "$cache2" in *HIT*|*hit*) ui_ok "Content is served from the CDN cache" ;;
        *MISS*|*miss*|*DYNAMIC*|*BYPASS*) ui_warn "Content not cached at the edge ($cache2)" ;; esac
    [ -z "$(hdr content-encoding)" ] && ui_warn "Response is not compressed (gzip/br)"
    [ -n "$(hdr strict-transport-security)" ] && ui_ok "HSTS enabled" || { case "$url" in https*) ui_warn "No HSTS header" ;; esac; }

    # --- Resource waterfall --------------------------------------------------
    ui_section "Resource waterfall"
    local final_url; final_url="$(curl -s -o /dev/null -L -w '%{url_effective}' --max-time 15 "$url" 2>/dev/null)"
    [ -z "$final_url" ] && final_url="$url"
    local res="$TMP_DIR/resources"
    tr '\n' ' ' < "$TMP_DIR/page.html" 2>/dev/null | grep -oiE '<(script|img|link|source|iframe)[^>]*>' | \
        grep -viE 'rel="?(preconnect|dns-prefetch|canonical|alternate|manifest)' | \
        grep -oiE '(src|href)="[^"]+"' | sed -E 's/^[A-Za-z]+="//; s/"$//' | \
        while IFS= read -r ref; do url_resolve "$final_url" "$ref"; done | awk '!seen[$0]++' | head -30 > "$res"
    local nres; nres="$(awk 'END{print NR}' "$res")"
    if [ "$nres" -eq 0 ]; then
        ui_note "    No sub-resources found in the HTML (page may be built by JavaScript)."
    else
        local t0; t0="$(now_ms)"
        local n=0 batch=0 r
        while IFS= read -r r; do
            n=$((n + 1))
            (
                s="$(now_ms)"
                o="$(curl -s -o /dev/null --compressed -A "Mozilla/5.0" --max-time 20 -w "$CURL_FMT" "$r" 2>/dev/null)"
                echo "$((s - t0)) $r $o" > "$TMP_DIR/wf_$n"
            ) &
            batch=$((batch + 1))
            [ "$batch" -ge 6 ] && { wait; batch=0; }   # browsers use ~6 connections per host
            ui_progress "$n" "$nres" "fetching resources"
        done < "$res"
        wait
        printf '\r\033[K'
        local wf="$TMP_DIR/wf_all"
        cat "$TMP_DIR"/wf_* 2>/dev/null | grep -v '^$' | sort -n > "$wf"
        local wscale; wscale="$(awk '{ e=$1+$7*1000; if (e>m) m=e } END{ printf "%.0f", m }' "$wf")"
        local nameW=28 barW=$((UI_W - 56)); [ "$barW" -lt 16 ] && barW=16
        printf '    %s%-*s %4s %8s %7s  %s%s\n' "$C_B" "$nameW" RESOURCE CODE SIZE TIME "0 ${G_RIGHT} ${wscale} ms" "$C_RST"
        local totsize=0 slow="" slowt=0
        while read -r off rurl d c a p f t sz code ver nr ip ct; do
            local nm="${rurl##*/}"; nm="${nm%%\?*}"; [ -z "$nm" ] && nm="${rurl#*://}"
            local ms; ms="$(awk -v t="$t" 'BEGIN{printf "%.0f", t*1000}')"
            is_int "${sz%.*}" && totsize=$((totsize + ${sz%.*}))
            [ "$ms" -gt "$slowt" ] && { slowt="$ms"; slow="$nm"; }
            local ph; ph="$(awk -v d="$d" -v c="$c" -v a="$a" -v p="$p" -v f="$f" -v t="$t" 'BEGIN{
                if (a==0) a=c; printf "%.1f %.1f %.1f %.1f %.1f", d*1000, (c-d)*1000, (a-c)*1000, (f-p)*1000, (t-f)*1000 }')"
            local ccol="$C_GRN"; [ "${code:0:1}" != "2" ] && ccol="$C_YEL"; [ "${code:0:1}" = "4" ] || [ "${code:0:1}" = "5" ] || [ "$code" = "000" ] && ccol="$C_RED"
            # shellcheck disable=SC2086
            printf '    %-*s %s%4s%s %7.1fK %5s ms  %s\n' "$nameW" "${nm:0:$nameW}" "$ccol" "$code" "$C_RST" "$(awk -v s="$sz" 'BEGIN{print s/1024}')" "$ms" "$(waterfall_bar "$off" $ph "$wscale" "$barW")"
        done < "$wf"
        echo
        printf '    %sLegend:%s %s%s%s dns  %s%s%s connect  %s%s%s tls  %s%s%s wait  %s%s%s download\n' "$C_GRY" "$C_RST" "$C_GRY" "$G_FULL" "$C_RST" "$C_YEL" "$G_FULL" "$C_RST" "$C_MAG" "$G_FULL" "$C_RST" "$C_ACC" "$G_FULL" "$C_RST" "$C_GRN" "$G_FULL" "$C_RST"
        ui_kv "Resources" "$nres  ($(awk -v s="$totsize" 'BEGIN{printf "%.1f KB", s/1024}') total)"
        ui_kv "Slowest" "$slow (${slowt} ms)"
        ui_kv "Est. page load" "~$(awk -v a="$scale" -v b="$wscale" 'BEGIN{printf "%.0f", a+b}') ms (document + resources, 6 parallel connections)"
        write_log "Web $url: resources=$nres size=${totsize}B slowest=$slow ${slowt}ms"
    fi
    pause
}

# ============================================================================
#  13. SSL/TLS CERTIFICATE CHECK  (issue #3)
# ============================================================================
ssl_probe() { # host port extra-args... -> s_client output
    local host="$1" port="$2"; shift 2
    echo | with_timeout 8 openssl s_client -connect "$host:$port" -servername "$host" "$@" 2>&1
}

date_to_epoch() {
    local d="$1"
    date -d "$d" +%s 2>/dev/null && return
    date -j -f "%b %e %T %Y %Z" "$d" +%s 2>/dev/null && return
    date -j -f "%b %d %T %Y %Z" "$d" +%s 2>/dev/null && return
    have python3 && python3 -c 'import sys,email.utils,datetime as d;print(int(d.datetime.strptime(sys.argv[1].replace("  "," "),"%b %d %H:%M:%S %Y %Z").replace(tzinfo=d.timezone.utc).timestamp()))' "$d" 2>/dev/null
}

mode_ssl() {
    local host port
    ui_header "SSL/TLS Certificate Check"
    have openssl || { ui_fail "openssl is required (apt install openssl / brew install openssl)"; pause; return; }
    ask_required host "Host" "example.com"
    host="${host#*://}"; host="${host%%/*}"
    case "$host" in *:*) port="${host##*:}"; host="${host%:*}" ;; esac
    [ -z "$port" ] && ask_int port "Port" "443" 1 65535
    local starttls=""
    case "$port" in
        25|587) starttls="-starttls smtp" ;; 110) starttls="-starttls pop3" ;;
        143) starttls="-starttls imap" ;; 21) starttls="-starttls ftp" ;;
    esac
    mk_tmp
    ui_header "SSL/TLS ${G_RIGHT} $host:$port"
    write_log "TLS check: $host:$port"

    local out
    # shellcheck disable=SC2086
    ( ssl_probe "$host" "$port" -showcerts -status $starttls > "$TMP_DIR/tls_main" ) &
    spin_wait $! "Connecting..."
    out="$(cat "$TMP_DIR/tls_main")"
    if ! echo "$out" | grep -q 'BEGIN CERTIFICATE'; then
        ui_fail "TLS handshake failed"
        echo "$out" | grep -iE 'error|refused|timeout|unknown' | head -3 | sed 's/^/    /'
        pause; return
    fi
    # Split chain into individual PEM files
    echo "$out" | awk -v d="$TMP_DIR" '/BEGIN CERT/{n++; f=d"/cert"n".pem"} f{print > f} /END CERT/{f=""}'
    local leaf="$TMP_DIR/cert1.pem"
    local subj issuer nb na serial fp san keyinfo sigalg
    subj="$(openssl x509 -in "$leaf" -noout -subject 2>/dev/null | sed 's/^subject= *//')"
    issuer="$(openssl x509 -in "$leaf" -noout -issuer 2>/dev/null | sed 's/^issuer= *//')"
    nb="$(openssl x509 -in "$leaf" -noout -startdate 2>/dev/null | cut -d= -f2)"
    na="$(openssl x509 -in "$leaf" -noout -enddate 2>/dev/null | cut -d= -f2)"
    serial="$(openssl x509 -in "$leaf" -noout -serial 2>/dev/null | cut -d= -f2)"
    fp="$(openssl x509 -in "$leaf" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)"
    local text; text="$(openssl x509 -in "$leaf" -noout -text 2>/dev/null)"
    san="$(echo "$text" | grep -A1 'Subject Alternative Name' | tail -1 | sed 's/^ *//; s/DNS://g')"
    keyinfo="$(echo "$text" | grep -m1 'Public Key Algorithm' | sed 's/.*: //') $(echo "$text" | grep -m1 -oE '\(([0-9]+) bit\)')"
    sigalg="$(echo "$text" | grep -m1 'Signature Algorithm' | sed 's/.*: //')"

    local now exp days dcol
    now="$(date +%s)"; exp="$(date_to_epoch "$na")"
    if [ -n "$exp" ]; then days=$(((exp - now) / 86400)); else days="?"; fi
    dcol="$C_GRN"
    if is_int "${days#-}"; then
        [ "$days" -lt 30 ] && dcol="$C_YEL"
        [ "$days" -lt 7 ] && dcol="$C_RED"
    fi

    ui_box_top "Certificate"
    ui_box_line "Subject      ${C_B}${subj:0:$((UI_W - 20))}${C_RST}"
    ui_box_line "Issuer       ${issuer:0:$((UI_W - 20))}"
    ui_box_line "Valid from   $nb"
    ui_box_line "Valid until  $na  ${dcol}${C_B}(${days} days left)${C_RST}"
    ui_box_line "Key          $keyinfo"
    ui_box_line "Signature    $sigalg"
    ui_box_line "Serial       ${serial:0:$((UI_W - 20))}"
    ui_box_line "SHA-256      ${C_GRY}${fp:0:$((UI_W - 20))}${C_RST}"
    ui_box_bottom
    if [ -n "$san" ]; then
        ui_section "Subject Alternative Names"
        echo "$san" | tr ',' '\n' | sed 's/^ *//' | head -15 | awk -v w=$((UI_W - 6)) '{ line=(line=="")?$0:line", "$0; if (length(line)>w) { print line; line="" } } END{ if (line!="") print line }' | sed 's/^/    /'
    fi

    # --- Validation --------------------------------------------------------
    ui_section "Validation"
    local findings=0 crit=0
    if [ "$days" != "?" ] && [ "$days" -lt 0 ]; then ui_fail "Certificate EXPIRED $(( -days )) days ago"; crit=1
    elif [ "$days" != "?" ] && [ "$days" -lt 14 ]; then ui_warn "Certificate expires in $days days"; findings=$((findings + 1))
    else ui_ok "Certificate is within its validity period"; fi

    if openssl x509 -in "$leaf" -noout -checkhost "$host" 2>/dev/null | grep -q 'does match'; then
        ui_ok "Hostname '$host' matches the certificate"
    elif openssl x509 -help 2>&1 | grep -q checkhost; then
        ui_fail "Hostname '$host' does NOT match the certificate"; crit=1
    fi

    local vcode; vcode="$(echo "$out" | grep -m1 'Verify return code' | sed 's/.*Verify return code: //')"
    case "$vcode" in
        "0 (ok)") ui_ok "Certificate chain is trusted ($vcode)" ;;
        "") ui_warn "Could not determine chain verification result" ;;
        *) ui_fail "Chain verification failed: $vcode"; crit=1 ;;
    esac
    if [ "$subj" = "$issuer" ]; then ui_fail "Self-signed certificate"; crit=1; fi
    echo "$sigalg" | grep -qiE 'sha1|md5' && { ui_fail "Weak signature algorithm ($sigalg)"; crit=1; }
    local bits; bits="$(echo "$keyinfo" | grep -oE '[0-9]+' | head -1)"
    echo "$keyinfo" | grep -qi rsa && [ -n "$bits" ] && [ "$bits" -lt 2048 ] && { ui_fail "RSA key smaller than 2048 bits"; crit=1; }
    if echo "$out" | grep -q 'OCSP Response Status: successful'; then ui_ok "OCSP stapling enabled"
    else ui_info "No OCSP stapling"; fi

    # --- Chain --------------------------------------------------------------
    ui_section "Certificate chain"
    local c idx=0
    for c in "$TMP_DIR"/cert*.pem; do
        [ -f "$c" ] || continue
        local cs ci ce
        cs="$(openssl x509 -in "$c" -noout -subject 2>/dev/null | sed 's/^subject= *//; s/.*CN *= *//')"
        ci="$(openssl x509 -in "$c" -noout -issuer 2>/dev/null | sed 's/^issuer= *//; s/.*CN *= *//')"
        ce="$(openssl x509 -in "$c" -noout -enddate 2>/dev/null | cut -d= -f2)"
        printf '    %s%s%s %s%s%s\n' "$C_ACC" "$(repeat '  ' "$idx")$([ "$idx" -gt 0 ] && echo "$B_BL$B_H ")" "$C_RST" "$C_B" "${cs:0:50}" "$C_RST"
        printf '    %s   %sissuer: %s  %s expires %s%s\n' "$(repeat '  ' "$idx")" "$C_GRY" "${ci:0:40}" "$G_DOT" "$ce" "$C_RST"
        idx=$((idx + 1))
    done
    [ "$idx" -eq 1 ] && ui_warn "Server sent only the leaf certificate (missing intermediates?)"

    # --- Protocol support ---------------------------------------------------
    ui_section "Protocol support"
    local proto flag res supported="" weak=0
    for proto in "SSLv3:-ssl3" "TLS 1.0:-tls1" "TLS 1.1:-tls1_1" "TLS 1.2:-tls1_2" "TLS 1.3:-tls1_3"; do
        flag="${proto#*:}"; proto="${proto%%:*}"
        if ! openssl s_client -help 2>&1 | grep -q -- "^ *$flag "; then
            printf '    %-9s %s%s%s\n' "$proto" "$C_GRY" "not testable (disabled in local OpenSSL)" "$C_RST"
            continue
        fi
        local extra=""
        case "$flag" in -ssl3|-tls1|-tls1_1) extra="-cipher ALL:@SECLEVEL=0" ;; esac
        # shellcheck disable=SC2086
        res="$(ssl_probe "$host" "$port" "$flag" $extra $starttls)"
        local cipher; cipher="$(echo "$res" | sed -n 's/.*Cipher is \(.*\)$/\1/p; s/^ *Cipher *: \(.*\)$/\1/p' | head -1)"
        if [ -n "$cipher" ] && [ "$cipher" != "(NONE)" ] && [ "$cipher" != "0000" ]; then
            case "$flag" in
                -ssl3|-tls1|-tls1_1) printf '    %-9s %s%s enabled%s   %s%s%s  %s(deprecated, should be disabled)%s\n' "$proto" "$C_RED" "$G_WARN" "$C_RST" "$C_GRY" "$cipher" "$C_RST" "$C_RED" "$C_RST"; weak=1 ;;
                *) printf '    %-9s %s%s enabled%s   %s%s%s\n' "$proto" "$C_GRN" "$G_OK" "$C_RST" "$C_GRY" "$cipher" "$C_RST" ;;
            esac
            supported="$supported $proto"
        else
            case "$flag" in
                -tls1_2|-tls1_3) printf '    %-9s %s%s disabled%s\n' "$proto" "$C_YEL" "$G_FAIL" "$C_RST" ;;
                *) printf '    %-9s %s%s disabled%s\n' "$proto" "$C_GRN" "$G_OK" "$C_RST" ;;
            esac
        fi
    done
    echo "$supported" | grep -q 'TLS 1.3' || findings=$((findings + 1))
    [ "$weak" -eq 1 ] && findings=$((findings + 2))

    # --- Cipher suite analysis ----------------------------------------------
    ui_section "Cipher suite analysis (TLS 1.2 and below)"
    local cls spec weakc=0
    for cls in "NULL / anonymous:aNULL:eNULL" "EXPORT grade:EXPORT" "RC4:RC4" "3DES / DES:3DES:DES" "Static RSA (no forward secrecy):kRSA" "CBC mode:SHA1:SHA256:SHA384:!AESGCM:!CHACHA20" "AEAD + forward secrecy (good):ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM"; do
        local label="${cls%%:*}" cs="${cls#*:}"
        # shellcheck disable=SC2086
        res="$(ssl_probe "$host" "$port" -tls1_2 -cipher "$cs:@SECLEVEL=0" $starttls)"
        local cph; cph="$(echo "$res" | sed -n 's/.*Cipher is \(.*\)$/\1/p' | head -1)"
        [ -z "$cph" ] && cph="$(echo "$res" | sed -n 's/^ *Cipher *: \(.*\)$/\1/p' | head -1)"
        if [ -n "$cph" ] && [ "$cph" != "(NONE)" ] && [ "$cph" != "0000" ]; then
            case "$label" in
                *good*) printf '    %s%s%s %-34s accepted  %s%s%s\n' "$C_GRN" "$G_OK" "$C_RST" "$label" "$C_GRY" "$cph" "$C_RST" ;;
                CBC*) printf '    %s%s%s %-34s accepted  %s%s%s\n' "$C_YEL" "$G_WARN" "$C_RST" "$label" "$C_GRY" "$cph" "$C_RST" ;;
                *) printf '    %s%s%s %-34s %saccepted%s  %s%s%s\n' "$C_RED" "$G_FAIL" "$C_RST" "$label" "$C_RED" "$C_RST" "$C_GRY" "$cph" "$C_RST"; weakc=$((weakc + 1)) ;;
            esac
        else
            case "$label" in
                *good*) printf '    %s%s%s %-34s %snot offered%s\n' "$C_YEL" "$G_WARN" "$C_RST" "$label" "$C_YEL" "$C_RST" ;;
                *) printf '    %s%s%s %-34s rejected\n' "$C_GRN" "$G_OK" "$C_RST" "$label" ;;
            esac
        fi
    done
    [ "$weakc" -gt 0 ] && findings=$((findings + weakc))
    if echo "$supported" | grep -q 'TLS 1.3'; then
        local tls13=""
        for cs in TLS_AES_128_GCM_SHA256 TLS_AES_256_GCM_SHA384 TLS_CHACHA20_POLY1305_SHA256; do
            # shellcheck disable=SC2086
            ssl_probe "$host" "$port" -tls1_3 -ciphersuites "$cs" $starttls | grep -q "$cs" && tls13="$tls13 $cs"
        done
        ui_kv "TLS 1.3 suites" "${tls13:- (could not enumerate)}"
    fi

    # HSTS
    if [ "$port" = "443" ] && have curl; then
        local hsts; hsts="$(curl -sI --max-time 10 "https://$host/" 2>/dev/null | grep -i '^strict-transport-security' | tr -d '\r')"
        if [ -n "$hsts" ]; then ui_ok "HSTS: ${hsts#*: }"; else ui_warn "No HSTS header"; findings=$((findings + 1)); fi
    fi

    # Grade
    local grade="A+"
    [ "$findings" -ge 1 ] && grade="A"
    [ "$findings" -ge 2 ] && grade="B"
    [ "$findings" -ge 4 ] && grade="C"
    [ "$crit" -eq 1 ] && grade="F"
    local gcol="$C_GRN"; case "$grade" in B) gcol="$C_YEL" ;; C|F) gcol="$C_RED" ;; esac
    echo
    ui_box_top
    ui_box_line "Overall grade  ${gcol}${C_B} $grade ${C_RST}   ${C_GRY}(heuristic: validity, chain, protocols, ciphers, HSTS)${C_RST}"
    ui_box_bottom
    write_log "TLS $host:$port grade=$grade days_left=$days protocols=$supported verify=$vcode"
    pause
}

# ============================================================================
#  14. VPN / PROXY / LEAK TEST  (issue #4)
# ============================================================================
# stun_mapped HOST PORT -> prints "ip:port" mapped by the STUN server
stun_mapped() {
    local host="$1" port="$2"
    if have python3; then
        python3 - "$host" "$port" <<'PY' 2>/dev/null
import socket, struct, os, sys
host, port = sys.argv[1], int(sys.argv[2])
tid = os.urandom(12)
req = struct.pack("!HHI", 0x0001, 0, 0x2112A442) + tid
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(3)
s.sendto(req, (socket.gethostbyname(host), port))
data, _ = s.recvfrom(2048)
i = 20
while i + 4 <= len(data):
    t, l = struct.unpack("!HH", data[i:i+4]); v = data[i+4:i+4+l]
    if t in (0x0020, 0x8020) and v[1] == 1:
        p = struct.unpack("!H", v[2:4])[0] ^ 0x2112
        ip = struct.unpack("!I", v[4:8])[0] ^ 0x2112A442
        print("%s:%d" % (socket.inet_ntoa(struct.pack("!I", ip)), p)); break
    if t == 0x0001 and v[1] == 1:
        print("%s:%d" % (socket.inet_ntoa(v[4:8]), struct.unpack("!H", v[2:4])[0])); break
    i += 4 + l + ((4 - l % 4) % 4)
PY
        return
    fi
    have nc || return 1
    local hex
    hex="$(printf '\000\001\000\000\041\022\244\102PingPortTstr' | with_timeout 4 nc -u -w 3 "$host" "$port" 2>/dev/null | od -An -v -tx1 | tr -s ' \n' ' ')"
    [ -z "$hex" ] && return 1
    echo "$hex" | awk '
        function h2d(h,  i, n) { n=0; h=tolower(h); for (i=1;i<=length(h);i++) n=n*16+index("0123456789abcdef", substr(h,i,1))-1; return n }
        function bxor(a, b,  r, bit) { r=0; bit=1; while (a>0 || b>0) { if ((a%2)!=(b%2)) r+=bit; a=int(a/2); b=int(b/2); bit*=2 } return r }
        {
        n=split($0,b," "); i=21
        m[1]=33; m[2]=18; m[3]=164; m[4]=66
        while (i+3<=n) {
            t=b[i] b[i+1]; l=h2d(b[i+2] b[i+3])
            if ((t=="0020" || t=="8020") && b[i+5]=="01") {
                p=bxor(h2d(b[i+6] b[i+7]), 8466)
                ip=""; for (k=0;k<4;k++) ip=ip (k?".":"") bxor(h2d(b[i+8+k]), m[k+1])
                print ip ":" p; exit
            }
            if (t=="0001" && b[i+5]=="01") {
                print h2d(b[i+8]) "." h2d(b[i+9]) "." h2d(b[i+10]) "." h2d(b[i+11]) ":" h2d(b[i+6] b[i+7]); exit
            }
            i+=4+l+((4-l%4)%4)
        }}' 2>/dev/null
}

mode_vpn() {
    ui_header "VPN / Proxy / Leak Test"
    write_log "VPN/proxy test started"
    mk_tmp
    local issues=0

    # --- Proxy detection ----------------------------------------------------
    ui_section "Proxy detection"
    local v found=0
    for v in http_proxy https_proxy all_proxy ftp_proxy socks_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY; do
        eval "local val=\${$v:-}"
        if [ -n "$val" ]; then ui_info "Environment $v=$(trunc "$val" $((UI_W - 20)))"; found=1; fi
    done
    if have gsettings && gsettings get org.gnome.system.proxy mode >/dev/null 2>&1; then
        local gm; gm="$(gsettings get org.gnome.system.proxy mode 2>/dev/null | tr -d "'")"
        [ "$gm" != "none" ] && { ui_info "GNOME system proxy mode: $gm ($(gsettings get org.gnome.system.proxy.http host 2>/dev/null | tr -d "'"):$(gsettings get org.gnome.system.proxy.http port 2>/dev/null))"; found=1; }
    fi
    if [ "$OS" = "Darwin" ] && have scutil; then
        local sp; sp="$(scutil --proxy 2>/dev/null | awk '/(HTTP|HTTPS|SOCKS)Enable : 1/{print $1}' | tr '\n' ' ')"
        [ -n "$sp" ] && { ui_info "macOS system proxy enabled: $sp"; found=1; }
        scutil --proxy 2>/dev/null | grep -q 'ProxyAutoConfigEnable : 1' && { ui_info "macOS proxy auto-config (PAC) enabled"; found=1; }
    fi
    [ -f /etc/apt/apt.conf.d/proxy.conf ] || grep -rqs 'Acquire::http::Proxy' /etc/apt/apt.conf.d/ 2>/dev/null && { ui_info "APT proxy configured"; found=1; }
    [ "$found" -eq 0 ] && ui_ok "No local proxy configuration found"

    local pip; pip="$(public_ip)"
    if [ -z "$pip" ]; then ui_fail "Could not determine public IP - are you online?"; pause; return; fi
    # Transparent proxy: compare the IP seen over plain HTTP vs HTTPS
    local hip; hip="$(curl -s --max-time 6 http://api.ipify.org 2>/dev/null | tr -d '[:space:]')"
    if is_ipv4 "$hip" && [ "$hip" != "$pip" ]; then
        ui_warn "HTTP and HTTPS exit via different IPs ($hip vs $pip) - transparent HTTP proxy likely"; issues=$((issues + 1))
    fi
    local via; via="$(curl -sI --max-time 6 http://example.com 2>/dev/null | grep -iE '^(via|x-cache|x-squid|proxy-)' | tr -d '\r' | head -2)"
    [ -n "$via" ] && ui_warn "Proxy headers injected on plain HTTP: $(echo "$via" | tr '\n' ' ')"

    # --- VPN tunnel -----------------------------------------------------------
    ui_section "VPN tunnel"
    local tunnels="" ifc
    if [ "$OS" = "Darwin" ]; then
        tunnels="$(ifconfig -l 2>/dev/null | tr ' ' '\n' | grep -E '^(utun|ppp|ipsec|tap|tun)' | while read -r ifc; do ifconfig "$ifc" 2>/dev/null | grep -q 'inet ' && echo "$ifc"; done | tr '\n' ' ')"
    else
        tunnels="$(ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -E '^(tun|tap|wg|ppp|ipsec|vti|tailscale|nordlynx|proton|mullvad|zt|gpd|cscotun|nebula|wt)' | tr '\n' ' ')"
    fi
    local egress; egress="$(default_iface)"
    if [ -n "$tunnels" ]; then
        ui_ok "Tunnel interface(s) up: ${C_B}$tunnels${C_RST}"
        case " $tunnels " in
            *" $egress "*) ui_ok "Default route goes through the tunnel ($egress)" ;;
            *) ui_warn "Default route uses '$egress', NOT the tunnel (split tunnel?)"; issues=$((issues + 1)) ;;
        esac
    else
        ui_info "No VPN tunnel interface detected (egress: $egress)"
    fi
    have wg && wg show interfaces >/dev/null 2>&1 && [ -n "$(wg show interfaces 2>/dev/null)" ] && ui_info "WireGuard: $(wg show interfaces 2>/dev/null)"
    local mtu=""
    if [ "$OS" = "Darwin" ]; then mtu="$(ifconfig "$egress" 2>/dev/null | sed -n 's/.*mtu \([0-9]*\).*/\1/p')"
    else mtu="$(cat "/sys/class/net/$egress/mtu" 2>/dev/null)"; fi
    [ -n "$mtu" ] && ui_kv "Egress MTU" "$mtu$([ "$mtu" -lt 1500 ] 2>/dev/null && echo "  (below 1500 - typical for tunnels)")"

    local tor; tor="$(http_get https://check.torproject.org/api/ip 6)"
    [ "$(json_get "$tor" IsTor)" = "true" ] && ui_info "Traffic exits through the Tor network"

    # --- Geo-location consistency ------------------------------------------
    ui_section "Geo-location consistency"
    ui_kv "Public IP" "$pip" "$C_B"
    local c1="" c2="" c3="" tz1="" ccs=""
    if geo_lookup "$pip"; then
        c1="$GEO_CC"; tz1="$GEO_TZ"
        ui_kv "ip-api.com" "$GEO_CITY, $GEO_CC  $G_DOT $GEO_AS"
        [ "$GEO_PROXY" = "true" ] && ui_info "IP is listed as proxy/VPN (expected if you use one)"
        [ "$GEO_HOSTING" = "true" ] && ui_info "IP belongs to a datacenter/hosting provider"
    fi
    local j2; j2="$(http_get "https://ipinfo.io/$pip/json" 6)"
    if [ -n "$j2" ]; then c2="$(json_get "$j2" country)"; ui_kv "ipinfo.io" "$(json_get "$j2" city), $c2  $G_DOT $(json_get "$j2" org)"; [ -z "$tz1" ] && tz1="$(json_get "$j2" timezone)"; fi
    local j3; j3="$(http_get "https://ipwho.is/$pip" 6)"
    if [ -n "$j3" ]; then c3="$(json_get "$j3" country_code)"; ui_kv "ipwho.is" "$(json_get "$j3" city), $c3  $G_DOT $(json_get "$j3" connection.org)"; fi
    ccs="$(printf '%s\n%s\n%s\n' "$c1" "$c2" "$c3" | grep -v '^$' | sort -u | tr '\n' ' ')"
    if [ "$(echo "$ccs" | wc -w)" -le 1 ]; then ui_ok "Providers agree on country: $ccs"
    else ui_warn "Providers disagree on country: $ccs (new/anycast/VPN range)"; fi

    local systz=""
    if have timedatectl; then systz="$(timedatectl show -p Timezone --value 2>/dev/null)"; fi
    [ -z "$systz" ] && systz="$(readlink /etc/localtime 2>/dev/null | sed 's#.*zoneinfo/##')"
    [ -z "$systz" ] && systz="$TZ"
    if [ -n "$tz1" ] && [ -n "$systz" ]; then
        local off_sys off_ip
        off_sys="$(date +%z)"
        off_ip="$(TZ="$tz1" date +%z 2>/dev/null)"
        if [ "$systz" = "$tz1" ] || [ "$off_sys" = "$off_ip" ]; then
            ui_ok "System timezone ($systz, $off_sys) matches IP location ($tz1)"
        else
            ui_warn "System timezone $systz ($off_sys) differs from IP timezone $tz1 ($off_ip) - sites can detect VPN use"
        fi
    fi

    # --- DNS leak test --------------------------------------------------------
    ui_section "DNS leak test"
    ui_kv "Configured DNS" "$(dns_servers)"
    local resolvers=""
    local ak; ak="$(dns_query whoami.akamai.net A | grep -E '^[0-9.]+$' | head -1)"
    [ -z "$ak" ] && have getent && ak="$(getent ahostsv4 whoami.akamai.net 2>/dev/null | awk '{print $1; exit}')"
    [ -n "$ak" ] && resolvers="$ak"
    local gg; gg="$(dns_query o-o.myaddr.l.google.com TXT | tr -d '"' | grep -E '^[0-9.]+$' | head -1)"
    [ -n "$gg" ] && resolvers="$resolvers $gg"
    local gg2; gg2="$(dns_query o-o.myaddr.l.google.com TXT | tr -d '"' | sed -n 's/.*edns0-client-subnet \([0-9.]*\).*/\1/p' | head -1)"
    resolvers="$(echo "$resolvers" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')"
    if [ -z "$resolvers" ]; then
        ui_warn "Could not identify upstream resolvers (install dig/host for best results)"
    else
        local my_as; geo_lookup "$pip"; my_as="${GEO_AS%% *}"; local my_cc="$GEO_CC"
        local r
        for r in $resolvers; do
            geo_lookup "$r"
            local ras="${GEO_AS%% *}"
            local tag="${C_GRN}same network as your public IP${C_RST}"
            if [ "$ras" != "$my_as" ]; then
                case "$GEO_AS" in
                    *Google*|*Cloudflare*|*Quad9*|*OpenDNS*|*Cisco*|*NextDNS*|*AdGuard*) tag="${C_ACC}public DNS provider${C_RST}" ;;
                    *) tag="${C_YEL}different network${C_RST}" ;;
                esac
                if [ -n "$GEO_CC" ] && [ "$GEO_CC" != "$my_cc" ]; then tag="$tag ${C_YEL}(country $GEO_CC != $my_cc)${C_RST}"; fi
            fi
            printf '    %-16s %-36s %s\n' "$r" "${GEO_AS:0:36}" "$tag"
        done
        [ -n "$gg2" ] && ui_info "Resolver forwards your subnet (EDNS client-subnet): $gg2"
        if [ -n "$tunnels" ]; then
            local leak=0
            for r in $resolvers; do geo_lookup "$r"; [ "${GEO_AS%% *}" != "$my_as" ] && [ -n "$GEO_CC" ] && [ "$GEO_CC" != "$my_cc" ] && leak=1; done
            if [ "$leak" -eq 1 ]; then ui_fail "Possible DNS leak: queries resolve outside the VPN exit country"; issues=$((issues + 1))
            else ui_ok "No DNS leak detected - resolvers are consistent with the VPN exit"; fi
        fi
    fi

    # --- WebRTC / UDP leak (STUN) -----------------------------------------------
    ui_section "WebRTC leak test (STUN)"
    ui_note "    Browsers use STUN to discover your address for WebRTC. If it differs from"
    ui_note "    your HTTP exit IP, sites can see your real IP even through a proxy/VPN."
    local s m ok=0
    for s in "stun.l.google.com 19302" "stun.cloudflare.com 3478"; do
        # shellcheck disable=SC2086
        m="$(stun_mapped $s)"
        if [ -n "$m" ]; then
            ok=1
            if [ "${m%:*}" = "$pip" ]; then ui_ok "${s% *}: $m ${C_GRY}(matches HTTP exit IP)${C_RST}"
            else ui_fail "${s% *}: ${C_B}$m${C_RST} differs from HTTP exit $pip ${C_RED}- WebRTC/UDP leak${C_RST}"; issues=$((issues + 1)); fi
        else
            ui_note "    ${s% *}: no STUN response (UDP blocked or no python3/nc)"
        fi
    done
    local lips
    if [ "$OS" = "Darwin" ]; then lips="$(ifconfig 2>/dev/null | awk '/inet /&&$2!="127.0.0.1"{print $2}' | tr '\n' ' ')"
    else lips="$(ip -4 -o addr show 2>/dev/null | awk '$2!="lo"{sub("/.*","",$4); print $4}' | tr '\n' ' ')"; fi
    ui_kv "Local addresses" "$lips ${C_GRY}(hidden by modern browsers via mDNS)${C_RST}"

    echo
    ui_box_top
    if [ "$issues" -eq 0 ]; then ui_box_line "${C_GRN}${C_B}$G_OK No leaks or inconsistencies detected${C_RST}"
    else ui_box_line "${C_YEL}${C_B}$G_WARN $issues potential issue(s) found - see above${C_RST}"; fi
    ui_box_bottom
    write_log "VPN/proxy test: pip=$pip tunnels=${tunnels:-none} resolvers=$resolvers issues=$issues"
    pause
}

# ============================================================================
#  15. LOCAL PORTS & FIREWALL
# ============================================================================
mode_local_ports() {
    local spec
    ui_header "Local Ports & Firewall"
    ui_note "  Leave empty to list every listening port."
    ask spec "Ports to check (e.g. 22,80,443)" ""
    ui_header "Local Ports & Firewall"
    write_log "Local port check: ${spec:-all}"
    local listen
    if have ss; then
        listen="$(ss -H -tulnp 2>/dev/null | awk '{ proto=$1; addr=$5; p=addr; sub(/.*:/,"",p); a=addr; sub(/:[^:]*$/,"",a);
            proc=""; if (match($0, /users:\(\("[^"]+",pid=[0-9]+/)) { proc=substr($0, RSTART+9, RLENGTH-9); gsub(/"/,"",proc); sub(/,pid=/," pid ",proc) }
            print proto, p, a, proc }')"
    elif have lsof; then
        listen="$(lsof -nP -iTCP -sTCP:LISTEN -iUDP 2>/dev/null | awk 'NR>1{ n=$9; p=n; sub(/.*:/,"",p); a=n; sub(/:[^:]*$/,"",a); print tolower($8), p, a, $1" pid "$2 }' | sort -u)"
    elif have netstat; then
        listen="$(netstat -tulnp 2>/dev/null | awk '/^(tcp|udp)/{ addr=$4; p=addr; sub(/.*:/,"",p); a=addr; sub(/:[^:]*$/,"",a); print $1, p, a, $NF }')"
    fi

    ui_section "Listening sockets"
    printf '    %s%-6s %-7s %-22s %-12s %s%s\n' "$C_B" PROTO PORT ADDRESS SERVICE PROCESS "$C_RST"
    local ports=""; [ -n "$spec" ] && ports=" $(expand_ports "$spec" | tr '\n' ' ') "
    echo "$listen" | sort -k2,2n -u | while read -r proto p a proc; do
        [ -z "$p" ] && continue
        [ -n "$ports" ] && case "$ports" in *" $p "*) ;; *) continue ;; esac
        local scope="$C_YEL"
        case "$a" in 127.*|"[::1]"|::1|localhost) scope="$C_GRY" ;; esac
        printf '    %-6s %-7s %s%-22s%s %-12s %s\n' "$proto" "$p" "$scope" "${a:0:22}" "$C_RST" "$(service_name "$p")" "${proc:-${C_GRY}(run as root to see)${C_RST}}"
    done
    ui_note "    Yellow address = reachable from the network, grey = localhost only."
    if [ -n "$ports" ]; then
        for p in $ports; do
            echo "$listen" | awk -v p="$p" '$2==p{f=1} END{exit !f}' || ui_warn "Port $p: nothing listening"
        done
    fi

    ui_section "Firewall"
    local fw=0 SUDO=""
    [ "$(id -u)" -ne 0 ] && have sudo && sudo -n true 2>/dev/null && SUDO="sudo -n"
    if [ "$OS" = "Darwin" ]; then
        local sf=/usr/libexec/ApplicationFirewall/socketfilterfw
        [ -x "$sf" ] && ui_kv "App firewall" "$($sf --getglobalstate 2>/dev/null | sed 's/.*is //')" && fw=1
        $SUDO pfctl -s info 2>/dev/null | grep -q 'Status: Enabled' && { ui_kv "pf" "enabled"; fw=1; }
    fi
    if have ufw; then
        local us; us="$($SUDO ufw status 2>/dev/null)"
        if [ -n "$us" ]; then
            fw=1; ui_kv "UFW" "$(echo "$us" | head -1 | sed 's/Status: //')"
            for p in $ports; do
                if echo "$us" | grep -qE "^$p(/[a-z]+)? .*DENY|^$p(/[a-z]+)? .*REJECT"; then ui_fail "UFW: port $p blocked"
                elif echo "$us" | grep -qE "^$p(/[a-z]+)? .*ALLOW"; then ui_ok "UFW: port $p allowed"
                else ui_info "UFW: no rule for $p (default policy)"; fi
            done
        fi
    fi
    if have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
        fw=1
        local fp; fp="$(firewall-cmd --list-ports 2>/dev/null) $(firewall-cmd --list-services 2>/dev/null)"
        ui_kv "firewalld" "running ${C_GRY}(open: $fp)${C_RST}"
        for p in $ports; do
            case " $fp " in *" $p/"*) ui_ok "firewalld: port $p open" ;; *) ui_info "firewalld: port $p not explicitly opened" ;; esac
        done
    fi
    if have nft; then
        local rs; rs="$($SUDO nft list ruleset 2>/dev/null)"
        if [ -n "$rs" ]; then
            fw=1; ui_kv "nftables" "$(echo "$rs" | grep -c 'chain ') chains"
            for p in $ports; do
                if echo "$rs" | grep -E "dport (\{[^}]*\b$p\b[^}]*\}|$p)\b" | grep -qE 'drop|reject'; then ui_fail "nftables: port $p dropped/rejected"
                elif echo "$rs" | grep -E "dport (\{[^}]*\b$p\b[^}]*\}|$p)\b" | grep -q 'accept'; then ui_ok "nftables: port $p accepted"; fi
            done
        fi
    fi
    if have iptables; then
        local ipt; ipt="$($SUDO iptables -S INPUT 2>/dev/null)"
        if [ -n "$ipt" ]; then
            fw=1; ui_kv "iptables" "INPUT policy $(echo "$ipt" | awk '/^-P INPUT/{print $3}')"
            for p in $ports; do
                if echo "$ipt" | grep -E -- "--dport $p( |$)" | grep -qE 'DROP|REJECT'; then ui_fail "iptables: port $p blocked"
                elif echo "$ipt" | grep -E -- "--dport $p( |$)" | grep -q ACCEPT; then ui_ok "iptables: port $p allowed"; fi
            done
        fi
    fi
    if [ "$fw" -eq 0 ]; then
        if [ "$(id -u)" -ne 0 ]; then ui_warn "Firewall rules need root. Re-run with sudo for full results."
        else ui_info "No active firewall detected"; fi
    fi
    pause
}

# ============================================================================
#  16. SMTP TEST
# ============================================================================
mode_smtp() {
    local server port enc action
    ui_header "SMTP Test"
    ask_required server "SMTP server" "smtp.gmail.com"
    ui_note "    25 = SMTP   465 = implicit TLS   587 = STARTTLS submission"
    ask_int port "Port" "587" 1 65535
    local defenc=3; [ "$port" = "465" ] && defenc=2; [ "$port" = "25" ] && defenc=1
    ask_choice enc "Encryption" "$defenc" "None" "SSL/TLS (implicit, port 465)" "STARTTLS (port 587/25)"
    ask_choice action "Action" 1 "Connection & capability test only (no login)" "Send a test email"

    if [ "$action" = "1" ]; then
        ui_header "SMTP ${G_RIGHT} $server:$port"
        local out
        if [ "$enc" = "1" ]; then
            if have nc; then
                out="$( (sleep 2; printf 'EHLO pingporttester\r\n'; sleep 2; printf 'QUIT\r\n') | with_timeout 8 nc "$server" "$port" 2>&1)"
            else
                out="$(curl -sv --max-time 10 "smtp://$server:$port" -X EHLO 2>&1)"
            fi
        elif have openssl; then
            local st=""; [ "$enc" = "3" ] && st="-starttls smtp"
            # shellcheck disable=SC2086
            out="$( (sleep 2; printf 'EHLO pingporttester\r\n'; sleep 2; printf 'QUIT\r\n') | with_timeout 10 openssl s_client -connect "$server:$port" -servername "$server" -crlf -quiet $st 2>&1)"
        else
            ui_fail "openssl is required for TLS tests"; pause; return
        fi
        local banner; banner="$(echo "$out" | grep -m1 -E '^[<]? ?220' | tr -d '\r')"
        if [ -n "$banner" ]; then ui_ok "Server banner: ${banner#< }"; else ui_fail "No SMTP banner received"; fi
        local caps; caps="$(echo "$out" | grep -E '^[<]? ?250[- ]' | sed 's/^< //; s/^250[- ]//' | tr -d '\r')"
        if [ -n "$caps" ]; then
            ui_section "Capabilities"
            echo "$caps" | sed 's/^/    /'
            echo "$caps" | grep -qi STARTTLS && ui_ok "STARTTLS offered"
            echo "$caps" | grep -qi '^AUTH' && ui_ok "Authentication: $(echo "$caps" | grep -i '^AUTH' | head -1)"
        fi
        [ "$enc" != "1" ] && echo "$out" | grep -q 'verify return:1' && ui_ok "TLS certificate verified"
        write_log "SMTP probe $server:$port: ${banner:-no banner}"
        pause; return
    fi

    local from user pass to subject
    echo
    ask_required from "From address"
    ask user "Username (blank = no auth)" "$from"
    if [ -n "$user" ]; then
        printf '  %s%s%s Password: ' "$C_ACC" "$G_ARROW" "$C_RST"; IFS= read -rs pass; echo
    fi
    ask_required to "To address"
    ask subject "Subject" "Test email from PingPortTester"
    echo
    ui_box_top "Summary"
    ui_box_line "Server  $server:$port  ($(case $enc in 1) echo none;; 2) echo SSL/TLS;; 3) echo STARTTLS;; esac))"
    ui_box_line "From    $from"
    ui_box_line "To      $to"
    ui_box_line "Subject $subject"
    ui_box_bottom
    ask_yn "Send email?" "y" || { ui_warn "Cancelled"; pause; return; }
    mk_tmp
    local msg="$TMP_DIR/mail.txt"
    printf 'From: %s\r\nTo: %s\r\nSubject: %s\r\nDate: %s\r\nMessage-ID: <%s.ppt@%s>\r\n\r\nThis is a test email sent from PingPortTester %s.\r\n\r\nTimestamp: %s\r\nServer: %s:%s\r\n' \
        "$from" "$to" "$subject" "$(LC_ALL=C date -R 2>/dev/null || LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')" "$(date +%s)" "$(hostname 2>/dev/null)" "$PPT_VERSION" "$(date)" "$server" "$port" > "$msg"
    write_log "SMTP send: $server:$port from=$from to=$to"
    local rc out
    if have swaks; then
        local tls=""; [ "$enc" = "2" ] && tls="--tls-on-connect"; [ "$enc" = "3" ] && tls="--tls"
        local auth=""; [ -n "$user" ] && auth="--auth LOGIN --auth-user $user --auth-password $pass"
        # shellcheck disable=SC2086
        out="$(swaks --to "$to" --from "$from" --server "$server" --port "$port" $tls $auth --data "$msg" 2>&1)"; rc=$?
    elif have curl; then
        local scheme="smtp" ssl=""; [ "$enc" = "2" ] && scheme="smtps"; [ "$enc" = "3" ] && ssl="--ssl-reqd"
        local cfg="$TMP_DIR/curl.cfg"
        ( umask 077; [ -n "$user" ] && printf 'user = "%s:%s"\n' "$user" "$(printf '%s' "$pass" | sed 's/\\/\\\\/g; s/"/\\"/g')" > "$cfg" || : > "$cfg" )
        # shellcheck disable=SC2086
        out="$(curl -sS --max-time 30 --url "$scheme://$server:$port" $ssl --mail-from "$from" --mail-rcpt "$to" -K "$cfg" -T "$msg" 2>&1)"; rc=$?
        rm -f "$cfg"
    else
        ui_fail "Neither swaks nor curl is available"; pause; return
    fi
    pass=""
    if [ "$rc" -eq 0 ]; then ui_ok "Email sent to $to"; write_log "SMTP: SUCCESS"
    else ui_fail "Sending failed"; echo "$out" | tail -5 | sed 's/^/    /'; write_log "SMTP: FAILED $(echo "$out" | tail -1)"; fi
    pause
}

# ============================================================================
#  SETTINGS & LOG VIEWER
# ============================================================================
mode_settings() {
    while :; do
        ui_header "Settings"
        ui_box_top "Current settings"
        ui_box_line "1  Logging          $([ "$LOG_ENABLED" = 1 ] && echo "${C_GRN}on${C_RST}" || echo "${C_RED}off${C_RST}")"
        ui_box_line "2  Log file         $(trunc "$LOG_PATH" $((UI_W - 25)))"
        ui_box_line "3  Network timeout  ${NET_TIMEOUT}s"
        ui_box_line "4  Colours          $([ "$USE_COLOR" = 1 ] && echo on || echo off)"
        ui_box_line "5  Unicode glyphs   $([ "$USE_UNICODE" = 1 ] && echo on || echo off)"
        ui_box_sep
        ui_box_line "0  Back"
        ui_box_bottom
        local c; ask c "Change" "0"
        case "$c" in
            1) [ "$LOG_ENABLED" = 1 ] && LOG_ENABLED=0 || { LOG_ENABLED=1; init_log; } ;;
            2) ask LOG_PATH "Log file" "$LOG_PATH"; init_log ;;
            3) ask_int NET_TIMEOUT "Timeout seconds" "$NET_TIMEOUT" 1 30 ;;
            4) [ "$USE_COLOR" = 1 ] && USE_COLOR=0 || USE_COLOR=1; init_ui ;;
            5) [ "$USE_UNICODE" = 1 ] && USE_UNICODE=0 || USE_UNICODE=1; init_ui ;;
            *) return ;;
        esac
    done
}

mode_log() {
    ui_header "Log Viewer"
    if [ "$LOG_ENABLED" != 1 ] || [ ! -s "$LOG_PATH" ]; then ui_info "Log is empty or disabled."; pause; return; fi
    ui_kv "File" "$(trunc "$LOG_PATH" $((UI_W - 24)))"
    ui_kv "Size" "$(awk -v s="$(file_size "$LOG_PATH")" 'BEGIN{printf "%.1f KB", s/1024}')"
    ui_section "Last 30 entries"
    tail -n 30 "$LOG_PATH" | while IFS= read -r l; do
        case "$l" in
            *DROPPED*|*FAIL*|*CLOSED*) printf '    %s%s%s\n' "$C_RED" "${l:0:$((UI_W - 4))}" "$C_RST" ;;
            *) printf '    %s%s%s\n' "$C_GRY" "${l:0:$((UI_W - 4))}" "$C_RST" ;;
        esac
    done
    echo
    ask_yn "Clear the log?" "n" && : > "$LOG_PATH" && ui_ok "Log cleared"
    pause
}

# ============================================================================
#  MAIN MENU
# ============================================================================
# key|label|description|function   (key "-" = section header)
MENU=(
    "-|Connectivity||"
    "1|Ping monitor|Continuous ICMP ping with live stats|mode_ping_monitor"
    "2|Packet loss analysis|Loss, jitter, percentiles, MOS|mode_packet_loss"
    "3|TCP port monitor|Continuous TCP connect latency|mode_tcp_monitor"
    "4|UDP port test|Protocol-aware UDP probe|mode_udp_test"
    "5|Port scanner|Parallel TCP/UDP range scan|mode_port_scan"
    "-|Path & DNS||"
    "6|Traceroute|Trace the network path|mode_traceroute"
    "7|Path analysis (MTR)|Per-hop loss, ASN and geo route|mode_path_analysis"
    "8|DNS lookup|Resolvers, all records, SPF/DMARC|mode_dns"
    "-|Internet||"
    "9|Bandwidth test|Download, upload, latency|mode_bandwidth"
    "i|Public IP & network|Local + public addressing, ISP|mode_public_ip"
    "e|External port check|Reachability from the internet|mode_external_ports"
    "w|Web performance|Timing, waterfall, HTTP/2/3, CDN|mode_web_perf"
    "-|Security||"
    "t|SSL/TLS check|Certificate, chain, protocols, ciphers|mode_ssl"
    "v|VPN / proxy / leaks|Tunnel, geo, DNS & WebRTC leaks|mode_vpn"
    "f|Local ports & firewall|Listeners and firewall rules|mode_local_ports"
    "-|Tools||"
    "m|SMTP test|Probe server or send a test email|mode_smtp"
    "s|Settings|Logging, timeout, display|mode_settings"
    "l|View log|Recent log entries|mode_log"
    "q|Quit||quit"
)

SYS_INFO=""
gather_sys_info() {
    local h ipl gw
    h="$(hostname 2>/dev/null)"; ipl="$(local_ip)"; gw="$(gateway_ip)"
    SYS_INFO="${h:-?}  $G_DOT  ${ipl:-no network}  $G_DOT  gw ${gw:-?}  $G_DOT  $(uname -sr 2>/dev/null)"
}

# Two-column layout for small terminals (e.g. 80x24).
draw_menu_compact() {
    local sel="$1" i=0 sec=-1 entry key label desc fn cw=$(((TERM_COLS - 6) / 2)) seldesc=""
    local -a L R
    for entry in "${MENU[@]}"; do
        IFS='|' read -r key label desc fn <<EOF
$entry
EOF
        local line
        if [ "$key" = "-" ]; then
            sec=$((sec + 1))
            line="${C_ACC2}${C_B}${label}${C_RST}$(printf '%*s' $((cw - ${#label})) '')"
        else
            local txt; txt="$(printf ' [%s] %-*s' "$key" $((cw - 5)) "$label")"
            if [ "$i" -eq "$sel" ]; then line="${C_SEL}${txt}${C_RST}"; seldesc="$desc"
            else line=" ${C_ACC}[$key]${C_RST} $(printf '%-*s' $((cw - 5)) "$label")"; fi
            i=$((i + 1))
        fi
        if [ "$sec" -le 1 ]; then L[${#L[@]}]="$line"; else R[${#R[@]}]="$line"; fi
    done
    clear_screen
    printf '  %s%sPingPortTester%s %sv%s %s %s%s\n\n' "$C_ACC" "$C_B" "$C_RST" "$C_GRY" "$PPT_VERSION" "$G_DOT" "${SYS_INFO:0:$((TERM_COLS - 30))}" "$C_RST"
    local n=${#L[@]}; [ ${#R[@]} -gt "$n" ] && n=${#R[@]}
    local j blank; blank="$(printf '%*s' "$cw" '')"
    for ((j = 0; j < n; j++)); do
        printf '  %s  %s\n' "${L[$j]:-$blank}" "${R[$j]:-}"
    done
    printf '\n  %s%s %s%s\n' "$C_B" "$G_PTR" "${seldesc:-Exit PingPortTester}" "$C_RST"
    printf '  %sarrows move %s Enter select %s hotkey jumps %s q quit%s\n' "$C_GRY" "$G_DOT" "$G_DOT" "$G_DOT" "$C_RST"
}

draw_menu() {
    local sel="$1" i=0 entry key label desc fn
    if [ "$TERM_ROWS" -lt 36 ] && [ "$TERM_COLS" -ge 70 ]; then draw_menu_compact "$sel"; return; fi
    clear_screen
    if [ "$TERM_ROWS" -ge 42 ]; then
        ui_logo
        printf '  %sv%s %s network connectivity toolkit%s\n' "$C_GRY" "$PPT_VERSION" "$G_DOT" "$C_RST"
        ui_box_top
        ui_box_line "${C_GRY}${SYS_INFO:0:$((UI_W - 6))}${C_RST}"
        ui_box_bottom
    else
        printf '  %s%sPingPortTester%s %sv%s %s %s%s\n' "$C_ACC" "$C_B" "$C_RST" "$C_GRY" "$PPT_VERSION" "$G_DOT" "${SYS_INFO:0:$((UI_W - 30))}" "$C_RST"
    fi
    for entry in "${MENU[@]}"; do
        IFS='|' read -r key label desc fn <<EOF
$entry
EOF
        if [ "$key" = "-" ]; then
            [ "$TERM_ROWS" -ge 42 ] && echo
            printf '  %s%s%s\n' "$C_ACC2$C_B" "$label" "$C_RST"
        elif [ "$i" -eq "$sel" ]; then
            printf '  %s %s [%s] %-24s %-40s%s\n' "$C_SEL" "$G_PTR" "$key" "$label" "$desc" "$C_RST"
        else
            printf '     %s[%s]%s %-24s %s%s%s\n' "$C_ACC" "$key" "$C_RST" "$label" "$C_GRY" "$desc" "$C_RST"
        fi
        [ "$key" != "-" ] && i=$((i + 1))
    done
    printf '\n  %s%s/%s move  %s  Enter select  %s  hotkey jumps  %s  q quit%s\n' "$C_GRY" "↑" "↓" "$G_DOT" "$G_DOT" "$G_DOT" "$C_RST" | { [ "$USE_UNICODE" = 1 ] && cat || sed 's/↑/Up/; s/↓/Down/'; }
}

menu_items() { # prints "key fn" for selectable items in order
    local entry key label desc fn
    for entry in "${MENU[@]}"; do
        IFS='|' read -r key label desc fn <<EOF
$entry
EOF
        [ "$key" != "-" ] && echo "$key $fn"
    done
}

main_menu() {
    local sel=0 count items
    items="$(menu_items)"
    count="$(echo "$items" | awk 'END{print NR}')"
    gather_sys_info
    while :; do
        term_size
        draw_menu "$sel"
        read_key
        local run=""
        case "$KEY" in
            UP|k)    sel=$(((sel - 1 + count) % count)) ;;
            DOWN|j)  sel=$(((sel + 1) % count)) ;;
            HOME)    sel=0 ;;
            END)     sel=$((count - 1)) ;;
            ENTER|RIGHT|" ") run="$(echo "$items" | awk -v n=$((sel + 1)) 'NR==n{print $2}')" ;;
            ESC)     ;;
            *)
                local k; k="$(echo "$KEY" | tr '[:upper:]' '[:lower:]')"
                local line; line="$(echo "$items" | awk -v k="$k" '$1==k{print NR" "$2; exit}')"
                if [ -n "$line" ]; then sel=$((${line%% *} - 1)); run="${line#* }"; fi ;;
        esac
        if [ -n "$run" ]; then
            [ "$run" = "quit" ] && return
            "$run"
        fi
    done
}

usage() {
    cat <<EOF
PingPortTester $PPT_VERSION - network connectivity toolkit

Usage: PingPortTester.sh [options]

Options:
  --no-log           Disable logging
  --log FILE         Log file (default: ./NetworkTest.log)
  --timeout SEC      Default network timeout (default: 3)
  --no-color         Disable colours (also honours NO_COLOR)
  --ascii            Use ASCII instead of Unicode glyphs
  -v, --version      Print version
  -h, --help         Show this help

Pass options when piping:  curl -sSL ppt.genius-space.org/PingPortTester.sh | bash -s -- --ascii
EOF
}

check_deps() {
    local missing=""
    have curl || missing="$missing curl"
    have ping || missing="$missing ping"
    dns_tool_available || missing="$missing dig"
    have traceroute || have tracepath || missing="$missing traceroute"
    have openssl || missing="$missing openssl"
    if [ -n "$missing" ]; then
        DEP_NOTE="Missing tools:$missing - some modes will be limited."
    fi
}

main() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-log) LOG_ENABLED=0 ;;
            --log) shift; LOG_PATH="$1" ;;
            --timeout) shift; NET_TIMEOUT="$1" ;;
            --no-color) USE_COLOR=0 ;;
            --ascii) USE_UNICODE=0 ;;
            -v|--version) echo "PingPortTester $PPT_VERSION"; return 0 ;;
            -h|--help) usage; return 0 ;;
            *) echo "Unknown option: $1" >&2; usage >&2; return 1 ;;
        esac
        shift
    done
    is_int "$NET_TIMEOUT" || NET_TIMEOUT=3
    trap cleanup EXIT
    trap 'cleanup; exit 130' TERM
    init_ui
    init_log
    check_deps
    if [ -n "${DEP_NOTE:-}" ]; then
        clear_screen; ui_logo; echo; ui_warn "$DEP_NOTE"
        ui_note "  Debian/Ubuntu: sudo apt install curl iputils-ping dnsutils traceroute openssl python3"
        ui_note "  Fedora/RHEL:   sudo dnf install curl iputils bind-utils traceroute openssl python3"
        ui_note "  macOS:         brew install bind   (others are preinstalled)"
        pause
    fi
    write_log "PingPortTester $PPT_VERSION session started"
    main_menu
    clear_screen
    ui_logo
    echo
    [ "$LOG_ENABLED" = 1 ] && ui_info "Log saved to $LOG_PATH"
    ui_note "  Thanks for using PingPortTester."
    echo
    write_log "Session ended"
}

# When piped (curl ... | bash) stdin is the script itself: read input from the terminal.
if [ -t 0 ] || [ ! -r /dev/tty ]; then main "$@"; else main "$@" < /dev/tty; fi; exit $?
