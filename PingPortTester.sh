#!/bin/bash
#
# Network Connectivity Testing Tool for Linux/macOS
#

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
WHITE='\033[1;37m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
MAX_LOG_SIZE_MB=20
MAX_LOG_SIZE_BYTES=$((MAX_LOG_SIZE_MB * 1024 * 1024))
LOG_PATH="./NetworkTest.log"

show_header() {
    echo ""
    echo -e "${MAGENTA}============================================================${NC}"
    echo -e "${WHITE}  $1${NC}"
    echo -e "${MAGENTA}============================================================${NC}"
    echo ""
}

show_separator() {
    echo -e "${GRAY}------------------------------------------------------------${NC}"
}

write_log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_PATH"
}

check_log_size() {
    if [[ -f "$LOG_PATH" ]]; then
        local size=$(stat -f%z "$LOG_PATH" 2>/dev/null || stat -c%s "$LOG_PATH" 2>/dev/null)
        if [[ $size -ge $MAX_LOG_SIZE_BYTES ]]; then
            local ts=$(date '+%Y%m%d_%H%M%S')
            tar -czf "NetworkTest_${ts}.tar.gz" "$LOG_PATH" 2>/dev/null
            > "$LOG_PATH"
            echo -e "  ${YELLOW}[ARCHIVED] Log archived${NC}"
        fi
    fi
}

test_ping() {
    local target=$1
    local ts=$(date '+%H:%M:%S')
    
    if ping -c 1 -W 3 "$target" > /dev/null 2>&1; then
        echo -e "  ${GREEN}[OK] [$ts] Ping to $target successful${NC}"
        return 0
    else
        echo -e "  ${RED}[FAIL] [$ts] Ping to $target failed${NC}"
        write_log "DROPPED - Ping to $target failed"
        return 1
    fi
}

test_tcp_port() {
    local target=$1
    local port=$2
    local ts=$(date '+%H:%M:%S')
    
    local start=$(date +%s%N)
    
    if timeout 3 bash -c "echo >/dev/tcp/$target/$port" 2>/dev/null; then
        local end=$(date +%s%N)
        local latency=$(( (end - start) / 1000000 ))
        
        local color=$GREEN
        [[ $latency -ge 50 ]] && color=$YELLOW
        [[ $latency -ge 150 ]] && color=$RED
        
        echo -e "  ${color}[OK] [$ts] Port $port open | Latency: ${latency}ms${NC}"
        write_log "Port $port on $target - OPEN (${latency}ms)"
        echo "$latency"
        return 0
    else
        echo -e "  ${RED}[FAIL] [$ts] Port $port closed/filtered${NC}"
        write_log "Port $port on $target - CLOSED"
        return 1
    fi
}

test_udp_port() {
    local target=$1
    local port=$2
    local ts=$(date '+%H:%M:%S')
    
    if command -v nc &> /dev/null; then
        if timeout 3 nc -u -z -w3 "$target" "$port" 2>/dev/null; then
            echo -e "  ${GREEN}[OK] [$ts] UDP Port $port open${NC}"
            write_log "UDP Port $port on $target - OPEN"
            return 0
        else
            echo -e "  ${YELLOW}[OPEN|FILTERED] [$ts] UDP Port $port open or filtered${NC}"
            write_log "UDP Port $port on $target - OPEN|FILTERED"
            return 0
        fi
    else
        echo -e "  ${RED}[ERROR] netcat (nc) not installed${NC}"
        return 1
    fi
}

port_scan() {
    local target=$1
    local start_port=$2
    local end_port=$3
    local protocol=$4
    
    local total=$((end_port - start_port + 1))
    local open_ports=()
    
    echo -e "  ${CYAN}Scanning $total ports ($start_port-$end_port) on $target...${NC}"
    write_log "Port scan started: $target ($start_port-$end_port) $protocol"
    
    for ((port=start_port; port<=end_port; port++)); do
        echo -ne "\r  Scanning port $port...     "
        
        if [[ "$protocol" == "TCP" ]]; then
            if timeout 0.5 bash -c "echo >/dev/tcp/$target/$port" 2>/dev/null; then
                open_ports+=($port)
            fi
        else
            if timeout 0.5 nc -u -z -w1 "$target" "$port" 2>/dev/null; then
                open_ports+=($port)
            fi
        fi
    done
    
    echo -ne "\r                              \r"
    echo ""
    echo -e "  ${CYAN}Open Ports:${NC} " 
    
    if [[ ${#open_ports[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}${open_ports[*]}${NC}"
        write_log "Open ports: ${open_ports[*]}"
        
        declare -A services=([21]="FTP" [22]="SSH" [23]="Telnet" [25]="SMTP" [53]="DNS" [80]="HTTP" [110]="POP3" [143]="IMAP" [443]="HTTPS" [445]="SMB" [465]="SMTPS" [587]="SMTP-MSA" [993]="IMAPS" [995]="POP3S" [3306]="MySQL" [3389]="RDP" [5432]="PostgreSQL" [8080]="HTTP-Alt")
        
        echo ""
        echo -e "  ${CYAN}Services:${NC}"
        for p in "${open_ports[@]}"; do
            local svc=${services[$p]:-"Unknown"}
            echo -e "    $p - $svc"
        done
    else
        echo -e "  ${YELLOW}None found${NC}"
    fi
    
    write_log "Port scan completed"
}

do_traceroute() {
    local target=$1
    local max_hops=$2
    
    echo -e "  ${CYAN}Tracing route to $target (max $max_hops hops)...${NC}"
    echo ""
    echo -e "  ${WHITE}Hop   RTT       IP Address${NC}"
    show_separator
    
    write_log "Traceroute to $target started"
    
    if command -v traceroute &> /dev/null; then
        traceroute -m "$max_hops" -w 3 "$target" 2>/dev/null | tail -n +2 | while read line; do
            echo "  $line"
        done
    elif command -v tracepath &> /dev/null; then
        tracepath -m "$max_hops" "$target" 2>/dev/null | while read line; do
            echo "  $line"
        done
    else
        for ((ttl=1; ttl<=max_hops; ttl++)); do
            local result=$(ping -c 1 -t $ttl -W 3 "$target" 2>&1)
            local ip=$(echo "$result" | grep -oE "from [0-9.]+" | cut -d' ' -f2)
            local time=$(echo "$result" | grep -oE "time=[0-9.]+" | cut -d'=' -f2)
            
            if [[ -n "$ip" ]]; then
                printf "  %3d   %-9s %s\n" "$ttl" "${time:-*}ms" "$ip"
                write_log "Hop $ttl: $ip (${time:-*}ms)"
                
                if echo "$result" | grep -q "ttl="; then
                    echo ""
                    echo -e "  ${GREEN}Trace complete.${NC}"
                    break
                fi
            else
                printf "  %3d   *         Request timed out\n" "$ttl"
            fi
        done
    fi
    
    write_log "Traceroute completed"
}

dns_lookup() {
    local domain=$1
    
    echo -e "  ${CYAN}DNS Lookup for: $domain${NC}"
    show_separator
    
    write_log "DNS Lookup for $domain"
    
    local dns_servers=("" "8.8.8.8" "1.1.1.1" "208.67.222.222")
    local dns_names=("System Default" "Google" "Cloudflare" "OpenDNS")
    
    for i in "${!dns_servers[@]}"; do
        echo ""
        echo -e "  ${WHITE}DNS: ${dns_names[$i]}${NC}"
        
        local start=$(date +%s%N)
        
        if [[ -z "${dns_servers[$i]}" ]]; then
            local result=$(host "$domain" 2>/dev/null | grep "has address" | head -3)
        else
            local result=$(host "$domain" "${dns_servers[$i]}" 2>/dev/null | grep "has address" | head -3)
        fi
        
        local end=$(date +%s%N)
        local time=$(( (end - start) / 1000000 ))
        
        if [[ -n "$result" ]]; then
            local ips=$(echo "$result" | awk '{print $NF}' | tr '\n' ', ' | sed 's/,$//')
            echo -e "    ${GREEN}$ips${NC}"
            echo -e "    ${GRAY}Query: ${time}ms${NC}"
            write_log "${dns_names[$i]}: $ips"
        else
            echo -e "    ${YELLOW}No results${NC}"
        fi
    done
    
    echo ""
    show_separator
    echo ""
    echo -e "  ${CYAN}Additional Records:${NC}"
    
    echo ""
    echo -e "  ${WHITE}MX Records:${NC}"
    local mx=$(host -t MX "$domain" 2>/dev/null | grep "mail" | head -3)
    if [[ -n "$mx" ]]; then
        echo "$mx" | while read line; do
            echo -e "    ${GREEN}$line${NC}"
        done
    else
        echo -e "    ${YELLOW}None found${NC}"
    fi
    
    echo ""
    echo -e "  ${WHITE}NS Records:${NC}"
    local ns=$(host -t NS "$domain" 2>/dev/null | grep "name server" | head -3)
    if [[ -n "$ns" ]]; then
        echo "$ns" | while read line; do
            echo -e "    ${GREEN}$line${NC}"
        done
    else
        echo -e "    ${YELLOW}None found${NC}"
    fi
    
    write_log "DNS Lookup completed"
}

bandwidth_test() {
    echo -e "  ${CYAN}Bandwidth Test${NC}"
    echo ""
    echo -e "  ${WHITE}Select test size:${NC}"
    echo "    1 - Quick (10 MB)"
    echo "    2 - Standard (25 MB)"
    echo "    3 - Extended (100 MB)"
    echo ""
    
    read -p "  > Choice (1-3): " choice
    
    local sizes=(10000000 25000000 100000000)
    local names=("10 MB" "25 MB" "100 MB")
    local idx=$((choice - 1))
    
    local url="https://speed.cloudflare.com/__down?bytes=${sizes[$idx]}"
    
    echo ""
    echo -e "  ${CYAN}Downloading ${names[$idx]} test file...${NC}"
    
    write_log "Bandwidth test started (${names[$idx]})"
    
    local temp_file=$(mktemp)
    local start=$(date +%s.%N)
    
    if curl -sS -o "$temp_file" "$url"; then
        local end=$(date +%s.%N)
        local seconds=$(echo "$end - $start" | bc)
        local size_bytes=$(stat -f%z "$temp_file" 2>/dev/null || stat -c%s "$temp_file" 2>/dev/null)
        local size_mb=$(echo "scale=2; $size_bytes / 1048576" | bc)
        local speed_mbps=$(echo "scale=2; ($size_mb * 8) / $seconds" | bc)
        
        rm -f "$temp_file"
        
        echo ""
        echo -e "  ${CYAN}Results:${NC}"
        echo -e "    Downloaded: ${size_mb} MB"
        echo -e "    Time: ${seconds} seconds"
        
        local color=$GREEN
        (( $(echo "$speed_mbps < 100" | bc -l) )) && color=$YELLOW
        (( $(echo "$speed_mbps < 25" | bc -l) )) && color=$RED
        
        echo -e "    Speed: ${color}${speed_mbps} Mbps${NC}"
        
        write_log "Download: ${speed_mbps} Mbps"
        
        echo ""
        echo -e "  ${CYAN}Latency Test:${NC}"
        local latencies=()
        for server in "8.8.8.8" "1.1.1.1"; do
            local lat=$(ping -c 3 "$server" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
            if [[ -n "$lat" ]]; then
                latencies+=("$lat")
            fi
        done
        
        if [[ ${#latencies[@]} -gt 0 ]]; then
            local sum=0
            for l in "${latencies[@]}"; do
                sum=$(echo "$sum + $l" | bc)
            done
            local avg=$(echo "scale=2; $sum / ${#latencies[@]}" | bc)
            
            local color=$GREEN
            (( $(echo "$avg > 30" | bc -l) )) && color=$YELLOW
            (( $(echo "$avg > 100" | bc -l) )) && color=$RED
            
            echo -e "    Average: ${color}${avg}ms${NC}"
            write_log "Latency: ${avg}ms"
        fi
    else
        echo -e "  ${RED}[ERROR] Download failed${NC}"
        rm -f "$temp_file"
    fi
    
    write_log "Bandwidth test completed"
}

external_port_check() {
    local ports=("$@")
    
    echo -e "  ${CYAN}External Port Check${NC}"
    echo -e "  ${GRAY}Checking if ports are reachable from the internet...${NC}"
    echo ""
    
    write_log "External port check started"
    
    local external_ip=$(curl -s https://api.ipify.org 2>/dev/null)
    
    if [[ -z "$external_ip" ]]; then
        echo -e "  ${RED}[ERROR] Could not determine external IP${NC}"
        return
    fi
    
    echo -e "  ${CYAN}Your External IP: $external_ip${NC}"
    echo ""
    write_log "External IP: $external_ip"
    
    for port in "${ports[@]}"; do
        echo -ne "  Port $port... "
        
        if timeout 5 bash -c "echo >/dev/tcp/$external_ip/$port" 2>/dev/null; then
            echo -e "${GREEN}OPEN${NC}"
            write_log "Port $port: OPEN"
        else
            echo -e "${RED}CLOSED/FILTERED${NC}"
            write_log "Port $port: CLOSED"
        fi
    done
    
    echo ""
    echo -e "  ${YELLOW}[INFO] Results depend on router/firewall configuration${NC}"
    echo -e "  ${YELLOW}[INFO] Ports may need port forwarding to be accessible${NC}"
    
    write_log "External port check completed"
}

local_port_check() {
    local ports=("$@")
    
    write_log "Local port check started"
    
    for port in "${ports[@]}"; do
        echo ""
        show_separator
        echo -e "  ${CYAN}Port: $port${NC}"
        show_separator
        
        echo -e "  ${GRAY}Checking listening services...${NC}"
        local listen=$(ss -tlnp 2>/dev/null | grep ":$port " || netstat -tlnp 2>/dev/null | grep ":$port ")
        
        if [[ -n "$listen" ]]; then
            local proc=$(echo "$listen" | awk '{print $NF}' | head -1)
            echo -e "  ${GREEN}[LISTENING] Process: $proc${NC}"
        else
            echo -e "  ${YELLOW}[NOT LISTENING]${NC}"
        fi
        
        echo -e "  ${GRAY}Checking firewall rules...${NC}"
        
        if command -v iptables &> /dev/null; then
            local blocked=$(sudo iptables -L INPUT -n 2>/dev/null | grep -E "DROP.*dpt:$port|REJECT.*dpt:$port")
            local allowed=$(sudo iptables -L INPUT -n 2>/dev/null | grep -E "ACCEPT.*dpt:$port")
            
            if [[ -n "$blocked" ]]; then
                echo -e "  ${RED}[BLOCKED] iptables: Port blocked${NC}"
            elif [[ -n "$allowed" ]]; then
                echo -e "  ${GREEN}[ALLOWED] iptables: Port allowed${NC}"
            else
                echo -e "  ${YELLOW}[DEFAULT] No specific iptables rule${NC}"
            fi
        fi
        
        if command -v ufw &> /dev/null; then
            local ufw_status=$(sudo ufw status 2>/dev/null)
            if echo "$ufw_status" | grep -q "Status: active"; then
                if echo "$ufw_status" | grep -qE "$port.*DENY"; then
                    echo -e "  ${RED}[BLOCKED] UFW: Port blocked${NC}"
                elif echo "$ufw_status" | grep -qE "$port.*ALLOW"; then
                    echo -e "  ${GREEN}[ALLOWED] UFW: Port allowed${NC}"
                else
                    echo -e "  ${YELLOW}[DEFAULT] No specific UFW rule${NC}"
                fi
            fi
        fi
        
        write_log "Port $port checked"
    done
    
    write_log "Local port check completed"
}

send_test_email() {
    echo -e "  ${CYAN}SMTP Email Test${NC}"
    echo ""
    echo -e "  ${WHITE}Enter SMTP configuration:${NC}"
    echo ""
    
    echo -e "  ${GRAY}SMTP Server (e.g., smtp.gmail.com, smtp.office365.com):${NC}"
    read -p "  > Server: " smtp_server
    
    echo ""
    echo -e "  ${GRAY}Common ports: 25 (SMTP), 465 (SSL), 587 (STARTTLS)${NC}"
    read -p "  > Port (default: 587): " smtp_port
    [[ -z "$smtp_port" ]] && smtp_port=587
    
    echo ""
    echo -e "  ${GRAY}Encryption:${NC}"
    echo "    1 - None"
    echo "    2 - SSL/TLS (port 465)"
    echo "    3 - STARTTLS (port 587)"
    read -p "  > Choice (1-3, default: 3): " enc_choice
    [[ -z "$enc_choice" ]] && enc_choice="3"
    
    local encryption_type="None"
    case $enc_choice in
        "1") encryption_type="None" ;;
        "2") encryption_type="SSL/TLS" ;;
        "3") encryption_type="STARTTLS" ;;
    esac
    
    echo ""
    read -p "  > From Email: " from_email
    
    echo ""
    echo -e "  ${GRAY}Authentication:${NC}"
    read -p "  > Username (usually email address): " username
    read -s -p "  > Password: " password
    echo ""
    
    echo ""
    read -p "  > To Email (recipient): " to_email
    
    echo ""
    read -p "  > Subject (default: Test Email from PingPortTester): " subject
    [[ -z "$subject" ]] && subject="Test Email from PingPortTester"
    
    read -p "  > Body (default: This is a test email): " body
    [[ -z "$body" ]] && body="This is a test email sent from PingPortTester.\n\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\nServer: $smtp_server\nPort: $smtp_port\nEncryption: $encryption_type"
    
    echo ""
    show_separator
    echo -e "  ${CYAN}Configuration Summary:${NC}"
    echo -e "    Server:     $smtp_server"
    echo -e "    Port:       $smtp_port"
    echo -e "    Encryption: $encryption_type"
    echo -e "    From:       $from_email"
    echo -e "    To:         $to_email"
    echo -e "    Subject:    $subject"
    show_separator
    echo ""
    
    read -p "  Send email? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "  ${YELLOW}[CANCELLED] Email not sent${NC}"
        return
    fi
    
    echo ""
    echo -e "  ${CYAN}Sending email...${NC}"
    
    write_log "SMTP Test: $smtp_server:$smtp_port ($encryption_type) From: $from_email To: $to_email"
    
    local send_method=""
    
    if command -v swaks &> /dev/null; then
        send_method="swaks"
    elif command -v curl &> /dev/null; then
        send_method="curl"
    fi
    
    case $send_method in
        "swaks")
            local tls_opt=""
            [[ "$enc_choice" == "2" ]] && tls_opt="--tls"
            [[ "$enc_choice" == "3" ]] && tls_opt="--tls-on-connect"
            
            if swaks --to "$to_email" --from "$from_email" --server "$smtp_server" --port "$smtp_port" \
                     --auth LOGIN --auth-user "$username" --auth-password "$password" \
                     --header "Subject: $subject" --body "$body" $tls_opt 2>&1; then
                echo ""
                echo -e "  ${GREEN}[SUCCESS] Email sent successfully!${NC}"
                write_log "SMTP Test: SUCCESS - Email sent to $to_email"
            else
                echo ""
                echo -e "  ${RED}[FAILED] Could not send email${NC}"
                write_log "SMTP Test: FAILED"
            fi
            ;;
            
        "curl")
            local url_scheme="smtp"
            [[ "$enc_choice" == "2" ]] && url_scheme="smtps"
            
            local curl_opts=""
            [[ "$enc_choice" == "3" ]] && curl_opts="--ssl-reqd"
            
            local email_data="From: $from_email\nTo: $to_email\nSubject: $subject\n\n$body"
            
            if echo -e "$email_data" | curl --url "${url_scheme}://${smtp_server}:${smtp_port}" \
                     --mail-from "$from_email" --mail-rcpt "$to_email" \
                     --user "$username:$password" $curl_opts \
                     -T - 2>&1; then
                echo ""
                echo -e "  ${GREEN}[SUCCESS] Email sent successfully!${NC}"
                write_log "SMTP Test: SUCCESS - Email sent to $to_email"
            else
                echo ""
                echo -e "  ${RED}[FAILED] Could not send email${NC}"
                write_log "SMTP Test: FAILED"
            fi
            ;;
            
        *)
            echo ""
            echo -e "  ${RED}[ERROR] No suitable email tool found${NC}"
            echo ""
            echo -e "  ${YELLOW}Please install swaks:${NC}"
            echo -e "    ${GRAY}Ubuntu/Debian: sudo apt install swaks${NC}"
            echo -e "    ${GRAY}macOS:         brew install swaks${NC}"
            
            write_log "SMTP Test: FAILED - No suitable tool found"
            return 1
            ;;
    esac
}

get_public_ip_info() {
    echo -e "  ${CYAN}Fetching public IP information...${NC}"
    echo ""
    
    write_log "Public IP check started"
    
    local public_ip=""
    
    for service in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
        public_ip=$(curl -s --max-time 10 "$service" 2>/dev/null | tr -d '\n')
        if [[ -n "$public_ip" && "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            break
        fi
    done
    
    if [[ -z "$public_ip" ]]; then
        echo -e "  ${RED}[ERROR] Could not determine public IP${NC}"
        write_log "Public IP check: FAILED"
        return
    fi
    
    echo -e "  ${CYAN}Public IP Address:${NC}"
    echo -e "  ${GREEN}$public_ip${NC}"
    echo ""
    
    local details=$(curl -s --max-time 10 "https://ipinfo.io/$public_ip/json" 2>/dev/null)
    
    if [[ -n "$details" ]]; then
        show_separator
        echo -e "  ${CYAN}Location Information:${NC}"
        show_separator
        
        local city=$(echo "$details" | grep -o '"city"[^,]*' | cut -d'"' -f4)
        local region=$(echo "$details" | grep -o '"region"[^,]*' | cut -d'"' -f4)
        local country=$(echo "$details" | grep -o '"country"[^,]*' | cut -d'"' -f4)
        local loc=$(echo "$details" | grep -o '"loc"[^,]*' | cut -d'"' -f4)
        local postal=$(echo "$details" | grep -o '"postal"[^,]*' | cut -d'"' -f4)
        local timezone=$(echo "$details" | grep -o '"timezone"[^,]*' | cut -d'"' -f4)
        local org=$(echo "$details" | grep -o '"org"[^,]*' | cut -d'"' -f4)
        local hostname=$(echo "$details" | grep -o '"hostname"[^,]*' | cut -d'"' -f4)
        
        [[ -n "$city" ]] && echo -e "    City:         $city"
        [[ -n "$region" ]] && echo -e "    Region:       $region"
        [[ -n "$country" ]] && echo -e "    Country:      $country"
        [[ -n "$loc" ]] && echo -e "    Coordinates:  $loc"
        [[ -n "$postal" ]] && echo -e "    Postal Code:  $postal"
        [[ -n "$timezone" ]] && echo -e "    Timezone:     $timezone"
        
        echo ""
        show_separator
        echo -e "  ${CYAN}Network Information:${NC}"
        show_separator
        
        [[ -n "$org" ]] && echo -e "    ISP/Org:      $org"
        [[ -n "$hostname" ]] && echo -e "    Hostname:     $hostname"
        
        write_log "Public IP: $public_ip | Location: $city, $region, $country | ISP: $org"
    else
        write_log "Public IP: $public_ip (no details)"
    fi
    
    echo ""
    show_separator
    echo -e "  ${CYAN}IPv6 Check:${NC}"
    show_separator
    
    local ipv6=$(curl -s --max-time 5 "https://api64.ipify.org" 2>/dev/null)
    if [[ -n "$ipv6" && "$ipv6" != "$public_ip" && "$ipv6" =~ : ]]; then
        echo -e "    IPv6 Address: ${GREEN}$ipv6${NC}"
        write_log "IPv6: $ipv6"
    else
        echo -e "    ${YELLOW}No IPv6 connectivity detected${NC}"
    fi
    
    write_log "Public IP check completed"
}

show_stats() {
    local total=$1
    local failed=$2
    local avg_latency=$3
    local show_latency=$4
    
    local success=$((total - failed))
    local rate=0
    [[ $total -gt 0 ]] && rate=$(echo "scale=1; ($success * 100) / $total" | bc)
    
    local color=$GREEN
    (( $(echo "$rate < 95" | bc -l) )) && color=$YELLOW
    (( $(echo "$rate < 80" | bc -l) )) && color=$RED
    
    echo -e "  [STATS] Total: $total | Success: $success | Failed: $failed | Rate: ${color}${rate}%${NC}"
    
    if [[ "$show_latency" == "true" ]] && (( $(echo "$avg_latency > 0" | bc -l) )); then
        local lat_color=$GREEN
        (( $(echo "$avg_latency > 50" | bc -l) )) && lat_color=$YELLOW
        (( $(echo "$avg_latency > 150" | bc -l) )) && lat_color=$RED
        echo -e "  [LATENCY] Avg: ${lat_color}${avg_latency}ms${NC}"
    fi
}

show_menu() {
    clear
    show_header "NETWORK CONNECTIVITY TESTING TOOL"
    
    echo -e "  ${CYAN}Select Mode:${NC}"
    echo ""
    echo -e "  ${WHITE}1  - ICMP Ping            Continuous ping monitoring${NC}"
    echo -e "  ${WHITE}2  - TCP Port Test        Test single port with latency${NC}"
    echo -e "  ${WHITE}3  - UDP Port Test        Test UDP port${NC}"
    echo -e "  ${WHITE}4  - Port Range Scan      Scan range of ports${NC}"
    echo -e "  ${WHITE}5  - Traceroute           Trace network path${NC}"
    echo -e "  ${WHITE}6  - DNS Lookup           Query DNS records${NC}"
    echo -e "  ${WHITE}7  - Bandwidth Test       Test download speed${NC}"
    echo -e "  ${WHITE}8  - External Port Check  Check if ports reachable from internet${NC}"
    echo -e "  ${WHITE}9  - Local Blocked Ports  Check firewall and listening services${NC}"
    echo -e "  ${WHITE}10 - SMTP Email Test      Send test email via SMTP${NC}"
    echo -e "  ${WHITE}11 - Public IP Info       Show public IP and location${NC}"
    echo ""
    echo -e "  ${RED}0  - Exit${NC}"
    echo ""
    show_separator
    echo ""
    
    while true; do
        read -p "  > Enter choice (0-11): " choice
        if [[ "$choice" =~ ^([0-9]|1[01])$ ]]; then
            echo "$choice"
            return
        fi
        echo -e "  ${RED}Invalid choice${NC}"
    done
}

# ============================================================================
# MAIN
# ============================================================================

touch "$LOG_PATH"

while true; do
    mode=$(show_menu)
    
    if [[ "$mode" == "0" ]]; then
        echo ""
        echo -e "  ${CYAN}[SAVED] Log: $LOG_PATH${NC}"
        echo -e "  ${MAGENTA}[BYE] Thank you for using Network Testing Tool!${NC}"
        echo ""
        exit 0
    fi

    case $mode in
        1)
            echo ""
            read -p "  > Target host: " target
            read -p "  > Interval seconds (default: 5): " interval
            [[ -z "$interval" ]] && interval=5
            
            clear
            show_header "PING MONITORING - $target"
            echo -e "  ${YELLOW}Press Ctrl+C to stop and return to menu${NC}"
            echo ""
            
            write_log "Ping monitoring started: $target"
            total=0
            failed=0
            
            trap 'write_log "Ping monitoring stopped"; break' SIGINT
            
            while true; do
                ((total++))
                check_log_size
                test_ping "$target" || ((failed++))
                show_stats $total $failed 0 "false"
                echo ""
                sleep "$interval"
            done
            
            trap - SIGINT
            ;;
        
        2)
            echo ""
            read -p "  > Target host: " target
            echo -e "  ${GRAY}Common: HTTP(80) HTTPS(443) SSH(22) RDP(3389)${NC}"
            read -p "  > Port: " port
            read -p "  > Interval seconds (default: 5): " interval
            [[ -z "$interval" ]] && interval=5
            
            clear
            show_header "TCP PORT TEST - ${target}:${port}"
            echo -e "  ${YELLOW}Press Ctrl+C to stop and return to menu${NC}"
            echo ""
            
            write_log "TCP port test started: ${target}:${port}"
            total=0
            failed=0
            latency_sum=0
            latency_count=0
            
            trap 'write_log "TCP port test stopped"; break' SIGINT
            
            while true; do
                ((total++))
                check_log_size
                result=$(test_tcp_port "$target" "$port")
                if [[ $? -ne 0 ]]; then
                    ((failed++))
                else
                    latency=$(echo "$result" | tail -1)
                    if [[ "$latency" =~ ^[0-9]+$ ]]; then
                        latency_sum=$((latency_sum + latency))
                        ((latency_count++))
                    fi
                fi
                
                avg=0
                [[ $latency_count -gt 0 ]] && avg=$((latency_sum / latency_count))
                show_stats $total $failed $avg "$([[ $latency_count -gt 0 ]] && echo true || echo false)"
                echo ""
                sleep "$interval"
            done
            
            trap - SIGINT
            ;;
        
        3)
            echo ""
            read -p "  > Target host: " target
            echo -e "  ${GRAY}Common: DNS(53) DHCP(67) NTP(123) SNMP(161)${NC}"
            read -p "  > Port: " port
            read -p "  > Interval seconds (default: 5): " interval
            [[ -z "$interval" ]] && interval=5
            
            clear
            show_header "UDP PORT TEST - ${target}:${port}"
            echo -e "  ${YELLOW}Press Ctrl+C to stop and return to menu${NC}"
            echo ""
            
            write_log "UDP port test started: ${target}:${port}"
            total=0
            failed=0
            
            trap 'write_log "UDP port test stopped"; break' SIGINT
            
            while true; do
                ((total++))
                check_log_size
                test_udp_port "$target" "$port" || ((failed++))
                show_stats $total $failed 0 "false"
                echo ""
                sleep "$interval"
            done
            
            trap - SIGINT
            ;;
        
        4)
            echo ""
            read -p "  > Target host: " target
            read -p "  > Start port: " start_port
            read -p "  > End port: " end_port
            echo -e "  ${WHITE}1 - TCP${NC}"
            echo -e "  ${WHITE}2 - UDP${NC}"
            read -p "  > Protocol (1 or 2): " proto
            protocol="TCP"
            [[ "$proto" == "2" ]] && protocol="UDP"
            
            clear
            show_header "PORT SCAN - $target"
            
            port_scan "$target" "$start_port" "$end_port" "$protocol"
            
            echo ""
            read -p "  Press Enter to return to menu"
            ;;
        
        5)
            echo ""
            read -p "  > Target host: " target
            read -p "  > Max hops (default: 30): " max_hops
            [[ -z "$max_hops" ]] && max_hops=30
            
            clear
            show_header "TRACEROUTE - $target"
            
            do_traceroute "$target" "$max_hops"
            
            echo ""
            read -p "  Press Enter to return to menu"
            ;;
        
        6)
            echo ""
            read -p "  > Domain name: " domain
            
            clear
            show_header "DNS LOOKUP - $domain"
            
            dns_lookup "$domain"
            
            echo ""
            read -p "  Press Enter to return to menu"
            ;;
        
        7)
            clear
            show_header "BANDWIDTH TEST"
            
            bandwidth_test
            
            echo ""
            read -p "  Press Enter to return to menu"
            ;;
        
        8)
            echo ""
            read -p "  > Ports to check (comma-separated, e.g., 80,443,22): " ports_input
            IFS=',' read -ra ports <<< "$ports_input"
            
            clear
            show_header "EXTERNAL PORT CHECK"
            
            external_port_check "${ports[@]}"
            
            echo ""
            read -p "  Press Enter to return to menu"
            ;;
        
        9)
            echo ""
            echo -e "  ${GRAY}Common: HTTP(80) HTTPS(443) SSH(22) RDP(3389) SMB(445)${NC}"
            read -p "  > Ports to check (comma-separated): " ports_input
            IFS=',' read -ra ports <<< "$ports_input"
            
            clear
            show_header "LOCAL BLOCKED PORTS CHECK"
            
            local_port_check "${ports[@]}"
            
            echo ""
            read -p "  Press Enter to return to menu"
            ;;
        
        10)
            clear
            show_header "SMTP EMAIL TEST"
            
            send_test_email
            
            echo ""
            read -p "  Press Enter to return to menu"
            ;;
        
        11)
            clear
            show_header "PUBLIC IP INFORMATION"
            
            get_public_ip_info
            
            echo ""
            read -p "  Press Enter to return to menu"
            ;;
    esac
done
