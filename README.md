# PingPortTester

[![GitHub stars](https://img.shields.io/github/stars/NUCL3ARN30N/PingPortTester?style=for-the-badge)](https://github.com/NUCL3ARN30N/PingPortTester/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/NUCL3ARN30N/PingPortTester?style=for-the-badge)](https://github.com/NUCL3ARN30N/PingPortTester/network/members)
[![GitHub issues](https://img.shields.io/github/issues/NUCL3ARN30N/PingPortTester?style=for-the-badge)](https://github.com/NUCL3ARN30N/PingPortTester/issues)
[![GitHub license](https://img.shields.io/github/license/NUCL3ARN30N/PingPortTester?style=for-the-badge)](LICENSE)

![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)

> Network connectivity toolkit with an interactive terminal UI, for Windows, Linux & macOS. Single file, no install.

## Quick Start

**Windows (PowerShell 5.1 or 7)**
```powershell
iex (irm ppt.genius-space.org/PingPortTester.ps1)
```

**Linux / macOS**
```bash
curl -sSL ppt.genius-space.org/PingPortTester.sh | bash
```

## Interface

- Full-screen menu: move with the **arrow keys** and press **Enter**, or press a **hotkey** to jump straight to a tool
- Grouped sections, boxed result panels, colour-coded status, progress bars, live sparklines
- Switches to a two-column menu on small terminals (e.g. 80×24)
- `--ascii` / `-Ascii` gives a plain-ASCII mode for legacy consoles; `NO_COLOR` / `-NoColor` turns colour off

## Tools

| Key | Tool                   | What it does                                                                     |
| --- | ---------------------- | -------------------------------------------------------------------------------- |
| `1` | Ping monitor           | Continuous ICMP with RTT, loss %, min/avg/max, sparkline, outage warning         |
| `2` | Packet loss analysis   | N-packet test: loss, loss bursts, jitter, stddev, p50/p90/p95/p99, histogram, timeline, VoIP MOS score |
| `3` | TCP port monitor       | Continuous TCP connect latency                                                   |
| `4` | UDP port test          | Protocol-aware probes (DNS, NTP, SNMP, SSDP…); tells apart open / closed / open\|filtered |
| `5` | Port scanner           | Parallel TCP/UDP scan of ranges, lists or `common`, with service names          |
| `6` | Traceroute             | Hop table with RTT and reverse DNS                                              |
| `7` | Path analysis (MTR)    | Live per-hop loss/latency/jitter, then ASN, operator and geo-location for each hop, total distance and a map link |
| `8` | DNS lookup             | Compares 5 resolvers with timing; AAAA/CNAME/MX/NS/TXT/SOA/CAA; SPF & DMARC check |
| `9` | Bandwidth test         | Download + upload speed, idle latency & jitter (Cloudflare)                     |
| `i` | Public IP & network    | Interface, local IP, gateway, DNS, public IPv4/IPv6, ISP, ASN, location         |
| `e` | External port check    | Checks reachability from the internet (with a local hairpin fallback)           |
| `w` | Web performance        | DNS/TCP/TLS/TTFB/download breakdown, resource waterfall, HTTP/1.1/2/3 support, CDN & cache detection, compression, HSTS |
| `t` | SSL/TLS check          | Certificate details & expiry, SANs, chain, hostname/trust validation, TLS 1.0–1.3 support, cipher analysis, OCSP stapling, HSTS, overall grade |
| `v` | VPN / proxy / leaks    | Proxy detection, VPN tunnel & default-route check, geo-location consistency, DNS leak test, WebRTC/STUN leak test |
| `f` | Local ports & firewall | Listening sockets with process and bind scope, firewall status and per-port rules |
| `m` | SMTP test              | Capability probe (banner, EHLO, STARTTLS, AUTH) or sending a test email over none/SSL/STARTTLS |
| `s` | Settings               | Logging, log path, timeout, colours, glyphs                                     |
| `l` | View log               | Shows recent log entries                                                        |
| `q` | Quit                   |                                                                                 |

## Controls

| Where                         | Keys                                        |
| ----------------------------- | ------------------------------------------- |
| Menu                          | `↑` `↓` / `j` `k`, `Enter`, hotkey, `q`     |
| Continuous / long-running tools | `Q`, `Esc` or `Ctrl+C` stops and shows a summary |
| Result screens                | Any key returns to the menu                 |
| Prompts                       | `Enter` accepts the `[default]`             |

## Options

**PowerShell**
```powershell
& ([scriptblock]::Create((irm ppt.genius-space.org/PingPortTester.ps1))) -Ascii -NoLog
# -Ascii  -NoColor  -NoLog  -LogPath <file>  -TimeoutSec <n>  -Version
```

**Bash**
```bash
curl -sSL ppt.genius-space.org/PingPortTester.sh | bash -s -- --ascii --no-log
# --ascii  --no-color  --no-log  --log <file>  --timeout <n>  --version  --help
```

## Logging

| Setting      | Value                                                               |
| ------------ | ------------------------------------------------------------------- |
| **Log file** | `./NetworkTest.log`, or `%TEMP%` / `$HOME` if the current folder is read-only |
| **Rotation** | Archives automatically at 20 MB (`.zip` on Windows, `.tar.gz` on Linux/macOS) |

## Requirements

**Windows:** PowerShell 5.1+ (Windows 10/11 or Server 2016+). `curl.exe` (built into Windows 10 1803+) adds the full web-performance waterfall.

**Linux / macOS:** bash 3.2+, curl, ping. Recommended: `dig` (dnsutils / bind-utils), `traceroute`, `openssl`, `python3`. The script tells you which tools are missing at startup.

```bash
# Debian/Ubuntu
sudo apt install curl iputils-ping dnsutils traceroute openssl python3
# Fedora/RHEL
sudo dnf install curl iputils bind-utils traceroute openssl python3
# macOS
brew install bind
```

Some checks give fuller results with elevated rights (firewall rules, process names for listening ports).

## Privacy

Some tools call third-party services: ipify / icanhazip (public IP), ip-api.com / ipinfo.io / ipwho.is (geo & ASN), Cloudflare (speed test), Google & Cloudflare STUN, check.torproject.org and ports.yougetsignal.com (external port check). Only your IP address and the targets you enter are sent.

---

Badges from [envoy1084/awesome-badges](https://github.com/envoy1084/awesome-badges)
