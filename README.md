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

> Network connectivity testing tool for Windows, Linux & macOS

## Quick Start

**Windows (PowerShell)**
```powershell
iex (irm ppt.genius-space.org/PingPortTester.ps1)
```

**Linux / macOS**
```bash
curl -sSL ppt.genius-space.org/PingPortTester.sh | bash
```

## Features

| #  | Mode                | Description                |
| -- | ------------------- | -------------------------- |
| 1  | ICMP Ping           | Continuous ping monitoring |
| 2  | TCP Port Test       | Test port with latency     |
| 3  | UDP Port Test       | Test UDP connectivity      |
| 4  | Port Range Scan     | Scan TCP/UDP port ranges   |
| 5  | Traceroute          | Trace network path         |
| 6  | DNS Lookup          | Query multiple DNS servers |
| 7  | Bandwidth Test      | Download speed test        |
| 8  | External Port Check | Check ports from internet  |
| 9  | Local Blocked Ports | Check firewall rules       |
| 10 | SMTP Email Test     | Send test email            |
| 11 | Public IP Info      | Show IP & location         |

## Controls

| Control                    | Action                               |
| -------------------------- | ------------------------------------ |
| **Continuous modes (1-3)** | Press `Q` to stop and return to menu |
| **One-time modes (4-11)**  | Press `Enter` to return to menu      |
| **Exit**                   | Select `0` from menu                 |

## Logging

| Setting      | Value                             |
| ------------ | --------------------------------- |
| **Log file** | Auto-saves to `./NetworkTest.log` |
| **Rotation** | Auto-archives at 20MB             |

## Requirements

**Windows:** PowerShell 5.1+  
**Linux/macOS:** bash, curl, bc, nc (netcat)

---

Badges from [envoy1084/awesome-badges](https://github.com/envoy1084/awesome-badges)
