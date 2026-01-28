# PingPortTester

Network connectivity testing tool for Windows and Linux/macOS.

## Features

- ICMP Ping Test - continuous ping monitoring with logging
- TCP Port Test - check if ports are open with latency measurement
- Local Blocked Ports Check - scan multiple ports for firewall rules and listening services

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

Sends ICMP echo requests to a target host. Logs dropped packets with timestamps.

### 2 - TCP Port Test

Tests if a specific TCP port is open on a remote host. Measures connection latency in milliseconds.

### 3 - Local Blocked Ports Check

Checks firewall rules and listening services for multiple ports on your local system.

- Windows: Checks Windows Firewall inbound/outbound rules
- Linux: Checks iptables, UFW, and firewalld

Enter ports comma-separated, e.g.: 80,443,22,3389

## Logging

- Log file: ./NetworkTest.log
- Auto-archives at 20 MB

## Requirements

### Windows

- PowerShell 5.1 or higher
- Administrator rights for firewall checks (Mode 3)

### Linux

- Bash 4.0 or higher
- bc (for calculations)
- ss or netstat
- sudo rights for firewall checks (Mode 3)
