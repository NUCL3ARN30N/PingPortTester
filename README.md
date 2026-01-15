# PingPortTester

<div align="center">

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?style=for-the-badge&logo=powershell)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey?style=for-the-badge&logo=windows)
![Status](https://img.shields.io/badge/Status-Active-success?style=for-the-badge)

**A beautiful Discord-themed network connectivity testing tool with automatic log management**

</div>

---

## Quick Start - Run Instantly!

### One-Line Execution (No Download Required!)

Run the script directly from your PowerShell terminal:

```powershell
iex (irm ppt.genius-space.org)
```

Or use the full command:

```powershell
Invoke-Expression (Invoke-RestMethod https://ppt.genius-space.org)
```

> **That's it!** The script will download and execute immediately - no git clone, no manual downloads needed.

### Alternative Methods

<details>
<summary><b>Click to expand other installation methods</b></summary>

#### Method 2: Direct GitHub URL
```powershell
iex (irm https://raw.githubusercontent.com/NUCL3ARN30N/PingPortTester/refs/heads/main/PingPortTester.ps1)
```

#### Method 3: Traditional Installation
```bash
git clone https://github.com/NUCL3ARN30N/PingPortTester.git
cd PingPortTester
.\PingPortTester.ps1
```

#### Method 4: Download and Save
```powershell
Invoke-WebRequest -Uri "https://ppt.genius-space.org" -OutFile "PingPortTester.ps1"
.\PingPortTester.ps1
```

</details>

---

## Overview

PingPortTester is an interactive PowerShell script that monitors network connectivity using either ICMP ping or TCP port testing. It features a beautiful Discord-inspired terminal UI, real-time statistics, and intelligent log management with automatic archiving.

Perfect for:
- Network troubleshooting and diagnostics
- Monitoring server/service uptime
- Detecting network connectivity issues
- Collecting connectivity statistics over time

---

## Features

### Powerful Testing
- **Dual Testing Modes:**
  - **ICMP Ping Mode** - Standard network layer connectivity testing
  - **TCP Port Test Mode** - Application-level port availability checking
- **Configurable intervals** - Set custom test frequencies
- **Continuous monitoring** - Runs until manually stopped (Ctrl+C)
- **Detailed logging** - Timestamps and failure tracking

### Smart Log Management
- **Automatic archiving** - Logs auto-compress when reaching 20MB
- **Space-efficient** - Only logs failures to save storage
- **Timestamped archives** - Easy identification with `YYYYMMDD_HHMMSS` format
- **Continuous operation** - New log starts seamlessly after archiving

### Statistics & Reporting
- **Real-time metrics** - Total tests, success count, failure count
- **Success rate calculation** - Percentage-based performance indicator
- **Color-coded rates** - Visual feedback (Green >95%, Yellow >80%, Red <80%)
- **Session summaries** - Final statistics displayed on exit

---

## Usage

### Starting the Script

#### Instant Run (Recommended):
```powershell
iex (irm ppt.genius-space.org)
```

#### Or from local file:
```powershell
.\PingPortTester.ps1
```

### Interactive Workflow

#### Step 1: Select Testing Mode
```
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║  🌐 NETWORK CONNECTIVITY TESTING TOOL                    ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝

  Select Testing Mode:

  ┌─ 1 ─────────────────────────────────────────────────┐
  │                                                      │
  │  🔔 ICMP Ping Mode                                   │
  │                                                      │
  │     • Uses ICMP echo requests (standard ping)       │
  │     • Tests if host is reachable on network         │
  │     • Works at network layer (Layer 3)              │
  │     • No port number needed                         │
  │     • Example: google.com or 8.8.8.8                │
  │                                                      │
  └──────────────────────────────────────────────────────┘

  ┌─ 2 ─────────────────────────────────────────────────┐
  │                                                      │
  │  🔌 TCP Port Test Mode                               │
  │                                                      │
  │     • Tests if specific TCP port is open/listening  │
  │     • Checks application-level connectivity         │
  │     • Works at transport layer (Layer 4)            │
  │     • Requires port number (80, 443, 22, etc.)      │
  │     • Example: Test if webserver port 443 is open   │
  │                                                      │
  └──────────────────────────────────────────────────────┘

  ➤ Enter your choice (1 or 2):
```

#### Step 2: Enter Target
```
  ➤ Enter target IP address or hostname: google.com
```

#### Step 3: Configure Port (if Port mode selected)
```
  📋 Common ports:
     HTTP: 80 │ HTTPS: 443 │ SSH: 22 │ RDP: 3389 │ FTP: 21

  ➤ Enter port number (1-65535): 443
```

#### Step 4: Set Test Interval
```
  ➤ Enter test interval in seconds (default: 5): 10
```

#### Step 5: Review Configuration
```
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║  ⚙️  CONFIGURATION SUMMARY                               ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────┐
│  Configuration                                           │
├──────────────────────────────────────────────────────────┤
│  Target:        google.com                               │
│  Mode:          Port                                     │
│  Port:          443                                      │
│  Interval:      10 seconds                               │
│  Log File:      .\NetworkTest.log                        │
│  Max Log Size:  20 MB (auto-archive)                     │
└──────────────────────────────────────────────────────────┘

  🚀 Starting monitoring in 3 seconds...
```

#### Step 6: Monitor Results
```
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║  📡 MONITORING ACTIVE                                    ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝

════════════════════════════════════════════════════════════
  ⚠️  Press Ctrl+C to stop monitoring
════════════════════════════════════════════════════════════

  ✅ [14:23:45] Port 443 on google.com is open
  📊 Total: 1 │ Success: 1 │ Failed: 0 │ Rate: 100.0%

  ✅ [14:23:55] Port 443 on google.com is open
  📊 Total: 2 │ Success: 2 │ Failed: 0 │ Rate: 100.0%
```

### Stopping the Script

Press `Ctrl+C` to stop monitoring. A reminder is displayed every 10 tests.

---

## Configuration

### Modifiable Variables

Edit these variables at the top of the script to customize behavior:

```powershell
# Configuration
$MaxLogSizeMB = 20                    # Maximum log size before archiving
$LogPath = ".\NetworkTest.log"        # Log file location
$ArchivePath = "."                     # Archive destination folder
```

### Log File Format

**Log entries include:**
- Timestamp (YYYY-MM-DD HH:MM:SS)
- Event type (DROPPED, INFO)
- Target details
- Failure reason (if applicable)

**Example log entry:**
```
[2025-01-15 14:23:45] DROPPED - Port 443 on google.com is closed or filtered (Timeout)
```

### Archive Format

Archives are compressed ZIP files with timestamp naming:
```
NetworkTest_20250115_142345.zip
```

---

## Use Cases

### 1. Monitor Web Server Uptime
```powershell
# Test HTTPS availability
Mode: TCP Port Test
Target: yourwebsite.com
Port: 443
Interval: 30 seconds
```

### 2. Check Internet Connectivity
```powershell
# Ping Google DNS
Mode: ICMP Ping
Target: 8.8.8.8
Interval: 5 seconds
```

### 3. Database Connection Monitoring
```powershell
# Test MySQL connection
Mode: TCP Port Test
Target: db.example.com
Port: 3306
Interval: 60 seconds
```

### 4. Remote Desktop Availability
```powershell
# Test RDP port
Mode: TCP Port Test
Target: 192.168.1.100
Port: 3389
Interval: 10 seconds
```

---

## Technical Details

### Testing Methods

#### ICMP Ping Mode
- Uses `Test-Connection` cmdlet
- Sends ICMP echo request packets
- 1-second timeout per test
- Detects network-layer connectivity

#### TCP Port Test Mode
- Uses `System.Net.Sockets.TcpClient`
- Attempts TCP connection to specified port
- 3-second timeout per connection attempt
- Detects application-layer availability

### Color Scheme

Based on Discord's brand colors:
- **Blurple** (#5865F2) - Primary UI elements
- **Green** (#57F287) - Success messages
- **Red** (#ED4245) - Error messages
- **Yellow** (#FEE75C) - Warnings
- **Gray** (#99AAB5) - Secondary info

---

## Security Note

> **Important:** Running scripts directly from the internet should be done with caution. Always review the source code before execution. You can view the script at:
> - **Short URL:** https://ppt.genius-space.org
> - **GitHub Source:** https://github.com/NUCL3ARN30N/PingPortTester/blob/main/PingPortTester.ps1

---

## Known Issues

- ICMP ping may require administrator privileges on some systems
- Some firewalls may block ICMP or specific TCP ports
- Log archiving creates temporary disk usage spike during compression

---

## Contributing

Contributions welcome! Please open an issue or submit a pull request.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

### Quick Access

**Instant Run:** `iex (irm ppt.genius-space.org)`

**[Report Bug](../../issues)** · **[Request Feature](../../issues)**

</div>
