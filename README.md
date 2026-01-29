# PingPortTester

Network connectivity testing tool for Windows and Linux/macOS.

## Usage

### Windows (PowerShell)

```powershell
iex (irm ppt.genius-space.org/PingPortTester.ps1)
```

### Linux / macOS (Bash)

```bash
curl -sSL ppt.genius-space.org/PingPortTester.sh | bash
```

## Modes

### 1 - ICMP Ping

Continuous ping monitoring to a target host. Logs dropped packets with timestamps.

### 2 - TCP Port Test

Tests if a specific TCP port is open on a remote host. Measures connection latency in milliseconds.

### 3 - UDP Port Test

Tests UDP port connectivity. Useful for DNS, DHCP, NTP, SNMP, and gaming services.

### 4 - Port Range Scan

Scans a range of ports on a target host. Supports TCP and UDP protocols. Identifies common services.

### 5 - Traceroute

Traces the network path to a destination. Shows each hop with IP address and round-trip time.

### 6 - DNS Lookup

Queries DNS records from multiple servers (System Default, Google, Cloudflare, OpenDNS). Shows A, MX, and NS records.

### 7 - Bandwidth Test

Tests download speed using Cloudflare speed test servers (10 MB, 25 MB, or 100 MB).

### 8 - External Port Check

Checks if your ports are reachable from the internet. Useful for verifying port forwarding.

### 9 - Local Blocked Ports Check

Checks firewall rules and listening services for specified ports.

- Windows: Checks Windows Firewall rules
- Linux: Checks iptables and UFW rules

### 10 - SMTP Email Test

Sends a test email via SMTP to verify email server connectivity.

Configuration options:
- SMTP Server
- Port (25, 465, 587)
- Encryption (None, SSL/TLS, STARTTLS)
- Authentication (username/password)
- From/To addresses

Common SMTP Servers:

| Provider | Server | Port | Encryption |
|----------|--------|------|------------|
| Gmail | smtp.gmail.com | 587 | STARTTLS |
| Office 365 | smtp.office365.com | 587 | STARTTLS |
| Outlook | smtp-mail.outlook.com | 587 | STARTTLS |

### 11 - Public IP Info

Shows your public IP address with detailed location and network information:

- IP Address (IPv4 and IPv6)
- City, Region, Country
- Coordinates
- Postal Code
- Timezone
- ISP/Organization
- Hostname

## Common Ports Reference

| Port | Service |
|------|---------|
| 21 | FTP |
| 22 | SSH |
| 25 | SMTP |
| 53 | DNS |
| 80 | HTTP |
| 443 | HTTPS |
| 465 | SMTPS |
| 587 | SMTP (submission) |
| 3306 | MySQL |
| 3389 | RDP |
| 5432 | PostgreSQL |

## Logging

- Log file: ./NetworkTest.log
- Auto-archives when log exceeds 20 MB

## Requirements

### Windows

- PowerShell 5.1 or higher
- Administrator rights for firewall checks (Mode 9)

### Linux

- Bash 4.0 or higher
- curl
- bc
- ss or netstat
- nc/netcat (for UDP tests)
- swaks (optional, for SMTP tests)
- sudo rights for firewall checks (Mode 9)
