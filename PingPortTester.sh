#!/bin/bash
#
# Network Connectivity Testing Tool for Linux
# Tests network connectivity using ICMP ping, TCP port testing, or local blocked ports check
# Logs dropped packets with timestamps and auto-archives logs at 20MB
#

# Colors (Discord-style)
BLURPLE='\033[0;35m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
WHITE='\033[1;37m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
MAX_LOG_SIZE_MB=20
MAX_LOG_SIZE_BYTES=$((MAX_LOG_SIZE_MB * 1024 * 1024))
LOG_PATH="./NetworkTest.log"

# Function to draw header
show_header() {
    local title="$1"
    echo ""
    echo -e "${BLURPLE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLURPLE}║                                                          ║${NC}"
    printf "${BLURPLE}║  ${WHITE}%-54s${BLURPLE}  ║${NC}\n" "$title"
    echo -e "${BLURPLE}║                                                          ║${NC}"
    echo -e "${BLURPLE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to draw box
show_box() {
    local title="$1"
    shift
    local content=("$@")
    
    echo ""
    echo -e "${BLURPLE}┌──────────────────────────────────────────────────────────┐${NC}"
    printf "${BLURPLE}│  ${CYAN}%-54s${BLURPLE}  │${NC}\n" "$title"
    echo -e "${BLURPLE}├──────────────────────────────────────────────────────────┤${NC}"
    
    for line in "${content[@]}"; do
        printf "${BLURPLE}│  ${WHITE}%-54s${BLURPLE}  │${NC}\n" "$line"
    done
    
    echo -e "${BLURPLE}└──────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Function to show separator
show_separator() {
    echo -e "${GRAY}════════════════════════════════════════════════════════════${NC}"
}

# Function to write log entry
write_log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_PATH"
}

# Function to archive log file
archive_log() {
    if [[ -f "$LOG_PATH" ]]; then
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local log_name=$(basename "$LOG_PATH" .log)
        local archive_name="${log_name}_${timestamp}.tar.gz"
        
        if tar -czf "$archive_name" "$LOG_PATH" 2>/dev/null; then
            echo ""
            echo -e "  ${YELLOW}[ARCHIVED]${NC} ${YELLOW}Log archived to:${NC} ${WHITE}$archive_name${NC}"
            echo ""
            > "$LOG_PATH"
            write_log "=== Log archived to $archive_name - New log started ==="
            return 0
        else
            echo -e "  ${RED}[ERROR]${NC} ${RED}Failed to archive log${NC}"
            return 1
        fi
    fi
}

# Function to check log size
check_log_size() {
    if [[ -f "$LOG_PATH" ]]; then
        local file_size=$(stat -f%z "$LOG_PATH" 2>/dev/null || stat -c%s "$LOG_PATH" 2>/dev/null)
        if [[ $file_size -ge $MAX_LOG_SIZE_BYTES ]]; then
            local size_mb=$(echo "scale=2; $file_size / 1048576" | bc)
            echo -e "  ${YELLOW}[WARNING]${NC} ${YELLOW}Log size (${size_mb} MB) exceeds ${MAX_LOG_SIZE_MB} MB. Archiving...${NC}"
            archive_log
        fi
    fi
}

# Function to test connectivity using ping
test_ping() {
    local target="$1"
    local timestamp=$(date '+%H:%M:%S')
    
    if ping -c 1 -W 3 "$target" > /dev/null 2>&1; then
        echo -e "  ${GREEN}[OK]${NC} ${GRAY}[$timestamp]${NC} ${GREEN}Ping to${NC} ${WHITE}$target${NC} ${GREEN}successful${NC}"
        return 0
    else
        local message="DROPPED - Ping to $target failed (No response)"
        echo -e "  ${RED}[FAIL]${NC} ${GRAY}[$timestamp]${NC} ${RED}$message${NC}"
        write_log "$message"
        return 1
    fi
}

# Function to test TCP port with latency
test_port() {
    local target="$1"
    local port="$2"
    local timestamp=$(date '+%H:%M:%S')
    
    local start_time=$(date +%s%N)
    
    if timeout 3 bash -c "echo >/dev/tcp/$target/$port" 2>/dev/null; then
        local end_time=$(date +%s%N)
        local latency=$(( (end_time - start_time) / 1000000 ))
        
        echo -ne "  ${GREEN}[OK]${NC} ${GRAY}[$timestamp]${NC} ${GREEN}Port${NC} ${WHITE}$port${NC} ${GREEN}on${NC} ${WHITE}$target${NC} ${GREEN}is open${NC}"
        echo -ne " ${GRAY}|${NC} ${CYAN}Latency:${NC} "
        
        if [[ $latency -lt 50 ]]; then
            echo -e "${GREEN}${latency}ms${NC}"
        elif [[ $latency -lt 150 ]]; then
            echo -e "${YELLOW}${latency}ms${NC}"
        else
            echo -e "${RED}${latency}ms${NC}"
        fi
        
        echo "$latency"
        return 0
    else
        local message="DROPPED - Port $port on $target is closed or filtered"
        echo -e "  ${RED}[FAIL]${NC} ${GRAY}[$timestamp]${NC} ${RED}$message${NC}"
        write_log "$message"
        return 1
    fi
}

# Function to check local blocked ports (Linux)
check_blocked_ports() {
    local ports=("$@")
    local results=()
    
    for port in "${ports[@]}"; do
        echo ""
        echo -e "  ${GRAY}────────────────────────────────────────────────────────${NC}"
        echo -e "  ${CYAN}Checking Port:${NC} ${WHITE}$port${NC}"
        echo -e "  ${GRAY}────────────────────────────────────────────────────────${NC}"
        
        local listening="No"
        local listening_process=""
        local iptables_status="Unknown"
        local ufw_status="Unknown"
        local status="Unknown"
        
        # Check if port is listening
        echo -e "  ${CYAN}[CHECK]${NC} ${GRAY}Checking listening services...${NC}"
        
        local listen_info=$(ss -tlnp 2>/dev/null | grep ":$port " || netstat -tlnp 2>/dev/null | grep ":$port ")
        
        if [[ -n "$listen_info" ]]; then
            listening="Yes"
            listening_process=$(echo "$listen_info" | awk '{print $NF}' | head -1)
            echo -e "  ${GREEN}[OK]${NC} ${WHITE}Port $port is${NC} ${GREEN}LISTENING${NC} ${WHITE}- Process:${NC} ${CYAN}$listening_process${NC}"
        else
            echo -e "  ${YELLOW}[INFO]${NC} ${WHITE}Port $port is${NC} ${YELLOW}NOT LISTENING${NC}"
        fi
        
        # Check iptables rules
        echo -e "  ${CYAN}[CHECK]${NC} ${GRAY}Checking iptables rules...${NC}"
        
        if command -v iptables &> /dev/null; then
            local iptables_drop=$(sudo iptables -L INPUT -n 2>/dev/null | grep -E "DROP.*dpt:$port|REJECT.*dpt:$port")
            local iptables_accept=$(sudo iptables -L INPUT -n 2>/dev/null | grep -E "ACCEPT.*dpt:$port")
            
            if [[ -n "$iptables_drop" ]]; then
                iptables_status="BLOCKED"
                echo -e "  ${RED}[BLOCKED]${NC} ${WHITE}iptables: Port $port is${NC} ${RED}BLOCKED${NC}"
            elif [[ -n "$iptables_accept" ]]; then
                iptables_status="ALLOWED"
                echo -e "  ${GREEN}[OK]${NC} ${WHITE}iptables: Port $port is${NC} ${GREEN}ALLOWED${NC}"
            else
                iptables_status="No specific rule"
                echo -e "  ${YELLOW}[INFO]${NC} ${YELLOW}No specific iptables rule for port $port (default policy applies)${NC}"
            fi
        else
            iptables_status="N/A"
            echo -e "  ${YELLOW}[INFO]${NC} ${YELLOW}iptables not available${NC}"
        fi
        
        # Check UFW status (if available)
        echo -e "  ${CYAN}[CHECK]${NC} ${GRAY}Checking UFW rules...${NC}"
        
        if command -v ufw &> /dev/null; then
            local ufw_output=$(sudo ufw status 2>/dev/null)
            
            if echo "$ufw_output" | grep -q "Status: active"; then
                local ufw_deny=$(echo "$ufw_output" | grep -E "$port.*DENY")
                local ufw_allow=$(echo "$ufw_output" | grep -E "$port.*ALLOW")
                
                if [[ -n "$ufw_deny" ]]; then
                    ufw_status="BLOCKED"
                    echo -e "  ${RED}[BLOCKED]${NC} ${WHITE}UFW: Port $port is${NC} ${RED}BLOCKED${NC}"
                elif [[ -n "$ufw_allow" ]]; then
                    ufw_status="ALLOWED"
                    echo -e "  ${GREEN}[OK]${NC} ${WHITE}UFW: Port $port is${NC} ${GREEN}ALLOWED${NC}"
                else
                    ufw_status="No rule"
                    echo -e "  ${YELLOW}[INFO]${NC} ${YELLOW}No specific UFW rule for port $port${NC}"
                fi
            else
                ufw_status="Inactive"
                echo -e "  ${YELLOW}[INFO]${NC} ${YELLOW}UFW is not active${NC}"
            fi
        else
            ufw_status="N/A"
            echo -e "  ${YELLOW}[INFO]${NC} ${YELLOW}UFW not available${NC}"
        fi
        
        # Check firewalld (if available)
        if command -v firewall-cmd &> /dev/null; then
            echo -e "  ${CYAN}[CHECK]${NC} ${GRAY}Checking firewalld rules...${NC}"
            
            if sudo firewall-cmd --state 2>/dev/null | grep -q "running"; then
                if sudo firewall-cmd --list-ports 2>/dev/null | grep -q "$port/tcp"; then
                    echo -e "  ${GREEN}[OK]${NC} ${WHITE}firewalld: Port $port is${NC} ${GREEN}ALLOWED${NC}"
                else
                    echo -e "  ${YELLOW}[INFO]${NC} ${YELLOW}Port $port not explicitly allowed in firewalld${NC}"
                fi
            fi
        fi
        
        # Determine overall status
        if [[ "$iptables_status" == "BLOCKED" ]] || [[ "$ufw_status" == "BLOCKED" ]]; then
            status="BLOCKED"
        elif [[ "$listening" == "Yes" ]]; then
            status="OPEN & LISTENING"
        elif [[ "$iptables_status" == "ALLOWED" ]] || [[ "$ufw_status" == "ALLOWED" ]]; then
            status="ALLOWED (not listening)"
        else
            status="DEFAULT POLICY"
        fi
        
        # Log result
        write_log "Port $port - Status: $status | Listening: $listening | iptables: $iptables_status | UFW: $ufw_status"
        
        results+=("$port|$status|$listening|$iptables_status|$ufw_status")
    done
    
    # Print results array for parsing
    printf '%s\n' "${results[@]}"
}

# Function to show stats bar
show_stats() {
    local total=$1
    local failed=$2
    local avg_latency=$3
    local min_latency=$4
    local max_latency=$5
    local show_latency=$6
    
    local success=$((total - failed))
    local rate=0
    if [[ $total -gt 0 ]]; then
        rate=$(echo "scale=1; ($success * 100) / $total" | bc)
    fi
    
    echo -ne "  ${CYAN}[STATS]${NC} ${GRAY}Total:${NC} ${WHITE}$total${NC}"
    echo -ne " ${GRAY}|${NC} ${GRAY}Success:${NC} ${GREEN}$success${NC}"
    echo -ne " ${GRAY}|${NC} ${GRAY}Failed:${NC} ${RED}$failed${NC}"
    echo -ne " ${GRAY}|${NC} ${GRAY}Rate:${NC} "
    
    if (( $(echo "$rate >= 95" | bc -l) )); then
        echo -e "${GREEN}${rate}%${NC}"
    elif (( $(echo "$rate >= 80" | bc -l) )); then
        echo -e "${YELLOW}${rate}%${NC}"
    else
        echo -e "${RED}${rate}%${NC}"
    fi
    
    if [[ "$show_latency" == "true" ]] && [[ $avg_latency -gt 0 ]]; then
        echo -ne "  ${CYAN}[LATENCY]${NC} ${GRAY}Avg:${NC} "
        
        if [[ $avg_latency -lt 50 ]]; then
            echo -ne "${GREEN}${avg_latency}ms${NC}"
        elif [[ $avg_latency -lt 150 ]]; then
            echo -ne "${YELLOW}${avg_latency}ms${NC}"
        else
            echo -ne "${RED}${avg_latency}ms${NC}"
        fi
        
        echo -ne " ${GRAY}|${NC} ${GRAY}Min:${NC} ${GREEN}${min_latency}ms${NC}"
        echo -ne " ${GRAY}|${NC} ${GRAY}Max:${NC} "
        
        if [[ $max_latency -lt 100 ]]; then
            echo -e "${GREEN}${max_latency}ms${NC}"
        elif [[ $max_latency -lt 200 ]]; then
            echo -e "${YELLOW}${max_latency}ms${NC}"
        else
            echo -e "${RED}${max_latency}ms${NC}"
        fi
    fi
}

# Function to show abort reminder
show_abort_reminder() {
    echo ""
    show_separator
    echo -e "  ${YELLOW}[INFO]${NC} ${YELLOW}Press${NC} ${WHITE}Ctrl+C${NC} ${YELLOW}to stop monitoring${NC}"
    show_separator
    echo ""
}

# Function to show mode menu
show_mode_menu() {
    clear
    show_header "NETWORK CONNECTIVITY TESTING TOOL"
    
    echo -e "  ${CYAN}Select Testing Mode:${NC}"
    echo ""
    
    echo -e "  ${BLURPLE}┌─${NC} ${WHITE}1${NC} ${BLURPLE}─────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BLURPLE}│                                                        │${NC}"
    echo -e "  ${BLURPLE}│  ${GREEN}ICMP Ping Mode${NC}                                    ${BLURPLE}│${NC}"
    echo -e "  ${BLURPLE}│                                                        │${NC}"
    echo -e "  ${GRAY}│     * Uses ICMP echo requests (standard ping)         │${NC}"
    echo -e "  ${GRAY}│     * Tests if host is reachable on network           │${NC}"
    echo -e "  ${GRAY}│     * Works at network layer (Layer 3)                │${NC}"
    echo -e "  ${GRAY}│     * No port number needed                           │${NC}"
    echo -e "  ${GRAY}│     * Example: google.com or 8.8.8.8                  │${NC}"
    echo -e "  ${BLURPLE}│                                                        │${NC}"
    echo -e "  ${BLURPLE}└────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    echo -e "  ${BLURPLE}┌─${NC} ${WHITE}2${NC} ${BLURPLE}─────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BLURPLE}│                                                        │${NC}"
    echo -e "  ${BLURPLE}│  ${GREEN}TCP Port Test Mode${NC}                                ${BLURPLE}│${NC}"
    echo -e "  ${BLURPLE}│                                                        │${NC}"
    echo -e "  ${GRAY}│     * Tests if specific TCP port is open/listening    │${NC}"
    echo -e "  ${GRAY}│     * Checks application-level connectivity           │${NC}"
    echo -e "  ${GRAY}│     * Works at transport layer (Layer 4)              │${NC}"
    echo -e "  ${GRAY}│     * Requires port number (80, 443, 22, etc.)        │${NC}"
    echo -e "  ${GRAY}│     * Includes latency measurement (connection time)  │${NC}"
    echo -e "  ${BLURPLE}│                                                        │${NC}"
    echo -e "  ${BLURPLE}└────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    echo -e "  ${BLURPLE}┌─${NC} ${WHITE}3${NC} ${BLURPLE}─────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BLURPLE}│                                                        │${NC}"
    echo -e "  ${BLURPLE}│  ${GREEN}Local Blocked Ports Check${NC}                           ${BLURPLE}│${NC}"
    echo -e "  ${BLURPLE}│                                                        │${NC}"
    echo -e "  ${GRAY}│     * Checks if ports are blocked on local system     │${NC}"
    echo -e "  ${GRAY}│     * Tests multiple ports (comma-separated)          │${NC}"
    echo -e "  ${GRAY}│     * Checks iptables/UFW/firewalld rules             │${NC}"
    echo -e "  ${GRAY}│     * Shows listening services on ports               │${NC}"
    echo -e "  ${GRAY}│     * Example: 80,443,3389,22,21                      │${NC}"
    echo -e "  ${BLURPLE}│                                                        │${NC}"
    echo -e "  ${BLURPLE}└────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    show_separator
    echo ""
    
    while true; do
        echo -ne "  ${BLURPLE}>${NC} "
        read -r selection
        if [[ "$selection" =~ ^[123]$ ]]; then
            echo "$selection"
            return
        else
            echo -e "  ${RED}[ERROR] Invalid selection. Please enter 1, 2, or 3.${NC}"
        fi
    done
}

# Trap Ctrl+C
cleanup() {
    echo ""
    echo -e "  ${YELLOW}[STOP]${NC} ${YELLOW}Monitoring stopped by user${NC}"
    write_log "=== Monitoring stopped ==="
    
    # Show final statistics
    echo ""
    show_separator
    show_header "FINAL STATISTICS"
    
    local success=$((total_tests - failed_tests))
    local final_rate=0
    if [[ $total_tests -gt 0 ]]; then
        final_rate=$(echo "scale=2; ($success * 100) / $total_tests" | bc)
    fi
    
    local stats_lines=(
        "Total Tests:      $total_tests"
        "Successful:       $success"
        "Failed:           $failed_tests"
        "Success Rate:     ${final_rate}%"
    )
    
    if [[ "$test_mode" == "Port" ]] && [[ ${#latency_values[@]} -gt 0 ]]; then
        stats_lines+=("")
        stats_lines+=("--- Latency Statistics ---")
        stats_lines+=("Average:          ${avg_latency}ms")
        stats_lines+=("Minimum:          ${min_latency}ms")
        stats_lines+=("Maximum:          ${max_latency}ms")
        stats_lines+=("Samples:          ${#latency_values[@]}")
        
        write_log "Latency Summary - Avg: ${avg_latency}ms | Min: ${min_latency}ms | Max: ${max_latency}ms | Samples: ${#latency_values[@]}"
    fi
    
    show_box "Session Summary" "${stats_lines[@]}"
    
    echo -e "  ${CYAN}[SAVED]${NC} ${CYAN}Log file saved to:${NC} ${WHITE}$LOG_PATH${NC}"
    echo ""
    echo -e "  ${BLURPLE}[BYE]${NC} ${BLURPLE}Thank you for using Network Testing Tool!${NC}"
    echo ""
    
    exit 0
}

trap cleanup SIGINT

# ============================================================================
# MAIN SCRIPT EXECUTION
# ============================================================================

# Initialize variables
total_tests=0
failed_tests=0
latency_values=()
min_latency=999999
max_latency=0
avg_latency=0

# Get mode selection
mode_selection=$(show_mode_menu)

# Handle mode selection
if [[ "$mode_selection" == "1" ]]; then
    test_mode="Ping"
    echo ""
    echo -ne "  ${BLURPLE}>${NC} Enter target IP address or hostname: "
    read -r target
    echo ""
    echo -e "  ${GREEN}[OK]${NC} ${GREEN}Mode Selected:${NC} ${WHITE}ICMP Ping${NC}"
    
elif [[ "$mode_selection" == "2" ]]; then
    test_mode="Port"
    echo ""
    echo -ne "  ${BLURPLE}>${NC} Enter target IP address or hostname: "
    read -r target
    echo ""
    echo -e "  ${GREEN}[OK]${NC} ${GREEN}Mode Selected:${NC} ${WHITE}TCP Port Test (with latency)${NC}"
    echo ""
    echo -e "  ${CYAN}Common ports:${NC}"
    echo -e "  ${GRAY}   HTTP: 80 | HTTPS: 443 | SSH: 22 | RDP: 3389 | FTP: 21${NC}"
    echo ""
    
    while true; do
        echo -ne "  ${BLURPLE}>${NC} Enter port number (1-65535): "
        read -r port
        if [[ "$port" =~ ^[0-9]+$ ]] && [[ $port -ge 1 ]] && [[ $port -le 65535 ]]; then
            break
        else
            echo -e "  ${RED}[ERROR] Invalid port. Enter a number between 1 and 65535.${NC}"
        fi
    done
    
elif [[ "$mode_selection" == "3" ]]; then
    test_mode="BlockedPorts"
    echo ""
    echo -e "  ${GREEN}[OK]${NC} ${GREEN}Mode Selected:${NC} ${WHITE}Local Blocked Ports Check${NC}"
    echo ""
    echo -e "  ${CYAN}Common ports:${NC}"
    echo -e "  ${GRAY}   HTTP: 80 | HTTPS: 443 | SSH: 22 | RDP: 3389 | FTP: 21${NC}"
    echo -e "  ${GRAY}   SMB: 445 | DNS: 53 | SMTP: 25 | MySQL: 3306 | PostgreSQL: 5432${NC}"
    echo ""
    
    while true; do
        echo -ne "  ${BLURPLE}>${NC} Enter ports to check (comma-separated, e.g., 80,443,22): "
        read -r ports_input
        
        valid_ports=true
        IFS=',' read -ra port_array <<< "$ports_input"
        local_ports=()
        
        for p in "${port_array[@]}"; do
            trimmed_port=$(echo "$p" | tr -d ' ')
            if [[ "$trimmed_port" =~ ^[0-9]+$ ]] && [[ $trimmed_port -ge 1 ]] && [[ $trimmed_port -le 65535 ]]; then
                local_ports+=("$trimmed_port")
            else
                valid_ports=false
                echo -e "  ${RED}[ERROR] Invalid port: '$trimmed_port'. All ports must be numbers between 1-65535.${NC}"
                break
            fi
        done
        
        if [[ "$valid_ports" == true ]] && [[ ${#local_ports[@]} -gt 0 ]]; then
            break
        fi
    done
    
    echo ""
    echo -e "  ${CYAN}[INFO]${NC} ${WHITE}Will check ${#local_ports[@]} port(s):${NC} ${CYAN}${local_ports[*]}${NC}"
fi

# Get interval (for Ping and Port modes only)
if [[ "$test_mode" != "BlockedPorts" ]]; then
    echo ""
    echo -ne "  ${BLURPLE}>${NC} Enter test interval in seconds (default: 5): "
    read -r interval_input
    
    if [[ -z "$interval_input" ]]; then
        interval=5
    else
        interval=$interval_input
    fi
fi

# Display configuration
clear
show_header "CONFIGURATION SUMMARY"

if [[ "$test_mode" == "BlockedPorts" ]]; then
    config_lines=(
        "Mode:          Local Blocked Ports Check"
        "Ports:         ${local_ports[*]}"
        "Log File:      $LOG_PATH"
        "Max Log Size:  ${MAX_LOG_SIZE_MB} MB (auto-archive)"
    )
else
    config_lines=(
        "Target:        $target"
        "Mode:          $test_mode"
    )
    if [[ "$test_mode" == "Port" ]]; then
        config_lines+=("Port:          $port")
    fi
    config_lines+=(
        "Interval:      $interval seconds"
        "Log File:      $LOG_PATH"
        "Max Log Size:  ${MAX_LOG_SIZE_MB} MB (auto-archive)"
    )
fi

show_box "Configuration" "${config_lines[@]}"

echo -e "  ${GREEN}[START]${NC} ${GREEN}Starting in${NC} ${WHITE}3${NC} ${GREEN}seconds...${NC}"
sleep 1
echo -e "  ${GREEN}[START]${NC} ${GREEN}Starting in${NC} ${WHITE}2${NC} ${GREEN}seconds...${NC}"
sleep 1
echo -e "  ${GREEN}[START]${NC} ${GREEN}Starting in${NC} ${WHITE}1${NC} ${GREEN}second...${NC}"
sleep 1

clear

# Handle Blocked Ports mode (one-time check)
if [[ "$test_mode" == "BlockedPorts" ]]; then
    show_header "LOCAL BLOCKED PORTS CHECK"
    
    # Create/initialize log file
    touch "$LOG_PATH"
    write_log "=== Local Blocked Ports Check Started - Ports: ${local_ports[*]} ==="
    
    # Run the check and capture results
    mapfile -t results < <(check_blocked_ports "${local_ports[@]}")
    
    # Display summary
    echo ""
    show_separator
    show_header "PORT CHECK SUMMARY"
    
    blocked_count=0
    listening_count=0
    allowed_count=0
    
    for result in "${results[@]}"; do
        IFS='|' read -r p_port p_status p_listening p_iptables p_ufw <<< "$result"
        [[ "$p_status" == "BLOCKED" ]] && ((blocked_count++))
        [[ "$p_listening" == "Yes" ]] && ((listening_count++))
        [[ "$p_iptables" == "ALLOWED" || "$p_ufw" == "ALLOWED" ]] && ((allowed_count++))
    done
    
    summary_lines=(
        "Total Ports Checked:  ${#local_ports[@]}"
        "Blocked:              $blocked_count"
        "Listening:            $listening_count"
        "Allowed:              $allowed_count"
    )
    
    show_box "Results Summary" "${summary_lines[@]}"
    
    # Detailed results table
    echo -e "  ${CYAN}Detailed Results:${NC}"
    echo -e "  ${GRAY}----------------------------------------------------------------${NC}"
    echo -e "  ${WHITE}Port    | Status              | Listening | iptables   | UFW${NC}"
    echo -e "  ${GRAY}----------------------------------------------------------------${NC}"
    
    for result in "${results[@]}"; do
        IFS='|' read -r p_port p_status p_listening p_iptables p_ufw <<< "$result"
        
        printf "  %-7s | " "$p_port"
        
        if [[ "$p_status" == "BLOCKED" ]]; then
            printf "${RED}%-19s${NC}" "$p_status"
        elif [[ "$p_status" == "OPEN & LISTENING" ]]; then
            printf "${GREEN}%-19s${NC}" "$p_status"
        else
            printf "${YELLOW}%-19s${NC}" "$p_status"
        fi
        
        printf " | %-9s | %-10s | %s\n" "$p_listening" "$p_iptables" "$p_ufw"
    done
    
    echo -e "  ${GRAY}----------------------------------------------------------------${NC}"
    
    write_log "=== Check completed ==="
    
    echo ""
    echo -e "  ${CYAN}[SAVED]${NC} ${CYAN}Log file saved to:${NC} ${WHITE}$LOG_PATH${NC}"
    echo ""
    echo -e "  ${BLURPLE}[BYE]${NC} ${BLURPLE}Thank you for using Network Testing Tool!${NC}"
    echo ""
    
    exit 0
fi

# Continuous monitoring modes (Ping and Port)
show_header "MONITORING ACTIVE"
show_abort_reminder

# Create/initialize log file
touch "$LOG_PATH"
write_log "=== Monitoring started ==="
write_log "Target: $target | Mode: $test_mode $(if [[ -n "$port" ]]; then echo "| Port: $port"; fi) | Interval: $interval seconds"

# Main monitoring loop
while true; do
    ((total_tests++))
    
    # Check log size
    check_log_size
    
    # Perform test
    if [[ "$test_mode" == "Ping" ]]; then
        if ! test_ping "$target"; then
            ((failed_tests++))
        fi
    elif [[ "$test_mode" == "Port" ]]; then
        result=$(test_port "$target" "$port")
        exit_code=$?
        
        if [[ $exit_code -ne 0 ]]; then
            ((failed_tests++))
        else
            # Extract latency from result (last line)
            latency=$(echo "$result" | tail -1)
            if [[ "$latency" =~ ^[0-9]+$ ]]; then
                latency_values+=("$latency")
                
                # Update min/max
                [[ $latency -lt $min_latency ]] && min_latency=$latency
                [[ $latency -gt $max_latency ]] && max_latency=$latency
                
                # Calculate average
                sum=0
                for val in "${latency_values[@]}"; do
                    ((sum += val))
                done
                avg_latency=$((sum / ${#latency_values[@]}))
                
                write_log "SUCCESS - Port $port on $target is open (Latency: ${latency}ms)"
            fi
        fi
    fi
    
    # Display statistics
    if [[ "$test_mode" == "Port" ]] && [[ ${#latency_values[@]} -gt 0 ]]; then
        show_stats $total_tests $failed_tests $avg_latency $min_latency $max_latency "true"
    else
        show_stats $total_tests $failed_tests 0 0 0 "false"
    fi
    echo ""
    
    # Show abort reminder every 10 tests
    if (( total_tests % 10 == 0 )); then
        show_abort_reminder
    fi
    
    sleep "$interval"
done
