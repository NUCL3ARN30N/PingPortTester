<#
.SYNOPSIS
    Network connectivity testing tool with automatic log archiving
.DESCRIPTION
    Tests network connectivity using either ICMP ping or TCP port testing.
    Logs dropped packets with timestamps and auto-archives logs at 20MB.
    TCP port testing includes latency measurement.
#>

# Discord Color Scheme
$DiscordBlurple = "DarkMagenta"
$DiscordGreen = "Green"
$DiscordRed = "Red"
$DiscordYellow = "Yellow"
$DiscordGray = "DarkGray"
$DiscordWhite = "White"
$DiscordCyan = "Cyan"

# Configuration
$MaxLogSizeMB = 20
$MaxLogSizeBytes = $MaxLogSizeMB * 1MB
$LogPath = ".\NetworkTest.log"
$ArchivePath = Split-Path $LogPath -Parent
if ([string]::IsNullOrEmpty($ArchivePath)) {
    $ArchivePath = "."
}

# Function to draw Discord-style header
function Show-DiscordHeader {
    param([string]$Title)
    
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor $DiscordBlurple
    Write-Host "║                                                          ║" -ForegroundColor $DiscordBlurple
    Write-Host "║  " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host $Title.PadRight(54) -NoNewline -ForegroundColor $DiscordWhite
    Write-Host "  ║" -ForegroundColor $DiscordBlurple
    Write-Host "║                                                          ║" -ForegroundColor $DiscordBlurple
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor $DiscordBlurple
    Write-Host ""
}

# Function to draw Discord-style box
function Show-DiscordBox {
    param(
        [string]$Title,
        [string[]]$Content
    )
    
    $maxLength = 54
    Write-Host ""
    Write-Host "┌──────────────────────────────────────────────────────────┐" -ForegroundColor $DiscordBlurple
    Write-Host "│  " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host $Title.PadRight($maxLength) -NoNewline -ForegroundColor $DiscordCyan
    Write-Host "  │" -ForegroundColor $DiscordBlurple
    Write-Host "├──────────────────────────────────────────────────────────┤" -ForegroundColor $DiscordBlurple
    
    foreach ($line in $Content) {
        Write-Host "│  " -NoNewline -ForegroundColor $DiscordBlurple
        Write-Host $line.PadRight($maxLength) -NoNewline -ForegroundColor $DiscordWhite
        Write-Host "  │" -ForegroundColor $DiscordBlurple
    }
    
    Write-Host "└──────────────────────────────────────────────────────────┘" -ForegroundColor $DiscordBlurple
    Write-Host ""
}

# Function to show separator
function Show-Separator {
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor $DiscordGray
}

# Function to archive log file
function Archive-LogFile {
    param([string]$LogFilePath)
    
    if (Test-Path $LogFilePath) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $logFileName = [System.IO.Path]::GetFileNameWithoutExtension($LogFilePath)
        $archiveFileName = "$logFileName`_$timestamp.zip"
        $archiveFullPath = Join-Path $ArchivePath $archiveFileName
        
        try {
            Compress-Archive -Path $LogFilePath -DestinationPath $archiveFullPath -CompressionLevel Optimal -Force
            Write-Host ""
            Write-Host "  [ARCHIVED] " -NoNewline -ForegroundColor $DiscordYellow
            Write-Host "Log archived to: " -NoNewline -ForegroundColor $DiscordYellow
            Write-Host $archiveFullPath -ForegroundColor $DiscordWhite
            Write-Host ""
            
            Clear-Content $LogFilePath -ErrorAction Stop
            Write-LogEntry -Message "=== Log archived to $archiveFileName - New log started ===" -FilePath $LogFilePath
            
            return $true
        }
        catch {
            Write-Host "  [ERROR] " -NoNewline -ForegroundColor $DiscordRed
            Write-Host "Failed to archive log: $($_.Exception.Message)" -ForegroundColor $DiscordRed
            return $false
        }
    }
}

# Function to check log size and archive if needed
function Test-LogSize {
    param([string]$LogFilePath)
    
    if (Test-Path $LogFilePath) {
        $fileSize = (Get-Item $LogFilePath).Length
        if ($fileSize -ge $MaxLogSizeBytes) {
            Write-Host "  [WARNING] " -NoNewline -ForegroundColor $DiscordYellow
            Write-Host "Log size ($([math]::Round($fileSize/1MB,2)) MB) exceeds $MaxLogSizeMB MB. Archiving..." -ForegroundColor $DiscordYellow
            Archive-LogFile -LogFilePath $LogFilePath
        }
    }
}

# Function to write log entry
function Write-LogEntry {
    param(
        [string]$Message,
        [string]$FilePath
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Add-Content -Path $FilePath -Value $logEntry
}

# Function to test connectivity using Ping
function Test-ConnectivityPing {
    param(
        [string]$TargetHost,
        [string]$LogFile
    )
    
    try {
        $ping = Test-Connection -ComputerName $TargetHost -Count 1 -Quiet -ErrorAction Stop
        
        if (-not $ping) {
            $message = "DROPPED - Ping to $TargetHost failed (No response)"
            Write-Host "  [FAIL] " -NoNewline -ForegroundColor $DiscordRed
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
            Write-Host $message -ForegroundColor $DiscordRed
            Write-LogEntry -Message $message -FilePath $LogFile
            return @{ Success = $false; Latency = $null }
        }
        else {
            Write-Host "  [OK] " -NoNewline -ForegroundColor $DiscordGreen
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
            Write-Host "Ping to " -NoNewline -ForegroundColor $DiscordGreen
            Write-Host $TargetHost -NoNewline -ForegroundColor $DiscordWhite
            Write-Host " successful" -ForegroundColor $DiscordGreen
            return @{ Success = $true; Latency = $null }
        }
    }
    catch {
        $message = "DROPPED - Ping to $TargetHost failed (Error: $($_.Exception.Message))"
        Write-Host "  [FAIL] " -NoNewline -ForegroundColor $DiscordRed
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
        Write-Host $message -ForegroundColor $DiscordRed
        Write-LogEntry -Message $message -FilePath $LogFile
        return @{ Success = $false; Latency = $null }
    }
}

# Function to test connectivity using TCP Port with latency measurement
function Test-ConnectivityPort {
    param(
        [string]$TargetHost,
        [int]$TargetPort,
        [string]$LogFile
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        
        # Start timing for latency measurement
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $connect = $tcpClient.BeginConnect($TargetHost, $TargetPort, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne(3000, $false)
        
        if (!$wait) {
            $stopwatch.Stop()
            $tcpClient.Close()
            $message = "DROPPED - Port $TargetPort on $TargetHost is closed or filtered (Timeout)"
            Write-Host "  [FAIL] " -NoNewline -ForegroundColor $DiscordRed
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
            Write-Host $message -ForegroundColor $DiscordRed
            Write-LogEntry -Message $message -FilePath $LogFile
            return @{ Success = $false; Latency = $null }
        }
        else {
            try {
                $tcpClient.EndConnect($connect)
                $stopwatch.Stop()
                $latencyMs = $stopwatch.ElapsedMilliseconds
                $tcpClient.Close()
                
                Write-Host "  [OK] " -NoNewline -ForegroundColor $DiscordGreen
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
                Write-Host "Port " -NoNewline -ForegroundColor $DiscordGreen
                Write-Host $TargetPort -NoNewline -ForegroundColor $DiscordWhite
                Write-Host " on " -NoNewline -ForegroundColor $DiscordGreen
                Write-Host $TargetHost -NoNewline -ForegroundColor $DiscordWhite
                Write-Host " is open " -NoNewline -ForegroundColor $DiscordGreen
                Write-Host "│ " -NoNewline -ForegroundColor $DiscordGray
                Write-Host "Latency: " -NoNewline -ForegroundColor $DiscordCyan
                
                # Color-code latency based on value
                if ($latencyMs -lt 50) {
                    Write-Host "${latencyMs}ms" -ForegroundColor $DiscordGreen
                }
                elseif ($latencyMs -lt 150) {
                    Write-Host "${latencyMs}ms" -ForegroundColor $DiscordYellow
                }
                else {
                    Write-Host "${latencyMs}ms" -ForegroundColor $DiscordRed
                }
                
                return @{ Success = $true; Latency = $latencyMs }
            }
            catch {
                $stopwatch.Stop()
                $tcpClient.Close()
                $message = "DROPPED - Port $TargetPort on $TargetHost is closed or filtered"
                Write-Host "  [FAIL] " -NoNewline -ForegroundColor $DiscordRed
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
                Write-Host $message -ForegroundColor $DiscordRed
                Write-LogEntry -Message $message -FilePath $LogFile
                return @{ Success = $false; Latency = $null }
            }
        }
    }
    catch {
        $message = "DROPPED - Failed to test port $TargetPort on $TargetHost (Error: $($_.Exception.Message))"
        Write-Host "  [FAIL] " -NoNewline -ForegroundColor $DiscordRed
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
        Write-Host $message -ForegroundColor $DiscordRed
        Write-LogEntry -Message $message -FilePath $LogFile
        return @{ Success = $false; Latency = $null }
    }
}

# Function to show stats bar with latency info
function Show-StatsBar {
    param(
        [int]$Total,
        [int]$Failed,
        [double]$AvgLatency,
        [double]$MinLatency,
        [double]$MaxLatency,
        [bool]$ShowLatency = $false
    )
    
    $success = $Total - $Failed
    $successRate = if ($Total -gt 0) { [math]::Round(($success / $Total) * 100, 1) } else { 0 }
    
    Write-Host "  [STATS] " -NoNewline -ForegroundColor $DiscordCyan
    Write-Host "Total: " -NoNewline -ForegroundColor $DiscordGray
    Write-Host $Total -NoNewline -ForegroundColor $DiscordWhite
    Write-Host " │ " -NoNewline -ForegroundColor $DiscordGray
    Write-Host "Success: " -NoNewline -ForegroundColor $DiscordGray
    Write-Host $success -NoNewline -ForegroundColor $DiscordGreen
    Write-Host " │ " -NoNewline -ForegroundColor $DiscordGray
    Write-Host "Failed: " -NoNewline -ForegroundColor $DiscordGray
    Write-Host $Failed -NoNewline -ForegroundColor $DiscordRed
    Write-Host " │ " -NoNewline -ForegroundColor $DiscordGray
    Write-Host "Rate: " -NoNewline -ForegroundColor $DiscordGray
    
    if ($successRate -ge 95) {
        Write-Host "$successRate%" -ForegroundColor $DiscordGreen
    }
    elseif ($successRate -ge 80) {
        Write-Host "$successRate%" -ForegroundColor $DiscordYellow
    }
    else {
        Write-Host "$successRate%" -ForegroundColor $DiscordRed
    }
    
    # Show latency statistics if enabled and we have data
    if ($ShowLatency -and $AvgLatency -gt 0) {
        Write-Host "  [LATENCY] " -NoNewline -ForegroundColor $DiscordCyan
        Write-Host "Latency - " -NoNewline -ForegroundColor $DiscordGray
        Write-Host "Avg: " -NoNewline -ForegroundColor $DiscordGray
        
        # Color-code average latency
        $avgDisplay = [math]::Round($AvgLatency, 1)
        if ($avgDisplay -lt 50) {
            Write-Host "${avgDisplay}ms" -NoNewline -ForegroundColor $DiscordGreen
        }
        elseif ($avgDisplay -lt 150) {
            Write-Host "${avgDisplay}ms" -NoNewline -ForegroundColor $DiscordYellow
        }
        else {
            Write-Host "${avgDisplay}ms" -NoNewline -ForegroundColor $DiscordRed
        }
        
        Write-Host " │ " -NoNewline -ForegroundColor $DiscordGray
        Write-Host "Min: " -NoNewline -ForegroundColor $DiscordGray
        Write-Host "${MinLatency}ms" -NoNewline -ForegroundColor $DiscordGreen
        Write-Host " │ " -NoNewline -ForegroundColor $DiscordGray
        Write-Host "Max: " -NoNewline -ForegroundColor $DiscordGray
        
        if ($MaxLatency -lt 100) {
            Write-Host "${MaxLatency}ms" -ForegroundColor $DiscordGreen
        }
        elseif ($MaxLatency -lt 200) {
            Write-Host "${MaxLatency}ms" -ForegroundColor $DiscordYellow
        }
        else {
            Write-Host "${MaxLatency}ms" -ForegroundColor $DiscordRed
        }
    }
}

# Function to show abort reminder
function Show-AbortReminder {
    Write-Host ""
    Show-Separator
    Write-Host "  [INFO] " -NoNewline -ForegroundColor $DiscordYellow
    Write-Host "Press " -NoNewline -ForegroundColor $DiscordYellow
    Write-Host "Ctrl+C" -NoNewline -ForegroundColor $DiscordWhite
    Write-Host " to stop monitoring" -ForegroundColor $DiscordYellow
    Show-Separator
    Write-Host ""
}

# Display menu and get mode selection
function Show-ModeMenu {
    Clear-Host
    Show-DiscordHeader "NETWORK CONNECTIVITY TESTING TOOL"
    
    Write-Host "  Select Testing Mode:" -ForegroundColor $DiscordCyan
    Write-Host ""
    
    Write-Host "  ┌─ " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host "1" -NoNewline -ForegroundColor $DiscordWhite
    Write-Host " ─────────────────────────────────────────────────┐" -ForegroundColor $DiscordBlurple
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  │  " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host "ICMP Ping Mode" -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "                                    │" -ForegroundColor $DiscordBlurple
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  │     * Uses ICMP echo requests (standard ping)         │" -ForegroundColor $DiscordGray
    Write-Host "  │     * Tests if host is reachable on network           │" -ForegroundColor $DiscordGray
    Write-Host "  │     * Works at network layer (Layer 3)                │" -ForegroundColor $DiscordGray
    Write-Host "  │     * No port number needed                           │" -ForegroundColor $DiscordGray
    Write-Host "  │     * Example: google.com or 8.8.8.8                  │" -ForegroundColor $DiscordGray
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  └────────────────────────────────────────────────────────┘" -ForegroundColor $DiscordBlurple
    Write-Host ""
    
    Write-Host "  ┌─ " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host "2" -NoNewline -ForegroundColor $DiscordWhite
    Write-Host " ─────────────────────────────────────────────────┐" -ForegroundColor $DiscordBlurple
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  │  " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host "TCP Port Test Mode" -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "                                │" -ForegroundColor $DiscordBlurple
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  │     * Tests if specific TCP port is open/listening    │" -ForegroundColor $DiscordGray
    Write-Host "  │     * Checks application-level connectivity           │" -ForegroundColor $DiscordGray
    Write-Host "  │     * Works at transport layer (Layer 4)              │" -ForegroundColor $DiscordGray
    Write-Host "  │     * Requires port number (80, 443, 22, etc.)        │" -ForegroundColor $DiscordGray
    Write-Host "  │     * Includes latency measurement (connection time)  │" -ForegroundColor $DiscordGray
    Write-Host "  │     * Example: Test if webserver port 443 is open     │" -ForegroundColor $DiscordGray
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  └────────────────────────────────────────────────────────┘" -ForegroundColor $DiscordBlurple
    Write-Host ""
    
    Write-Host "  ┌─ " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host "3" -NoNewline -ForegroundColor $DiscordWhite
    Write-Host " ─────────────────────────────────────────────────┐" -ForegroundColor $DiscordBlurple
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  │  " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host "Local Blocked Ports Check" -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "                           │" -ForegroundColor $DiscordBlurple
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  │     * Checks if ports are blocked on local system     │" -ForegroundColor $DiscordGray
    Write-Host "  │     * Tests multiple ports (comma-separated)          │" -ForegroundColor $DiscordGray
    Write-Host "  │     * Checks Windows Firewall rules                   │" -ForegroundColor $DiscordGray
    Write-Host "  │     * Shows listening services on ports               │" -ForegroundColor $DiscordGray
    Write-Host "  │     * Example: 80,443,3389,22,21                      │" -ForegroundColor $DiscordGray
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  └────────────────────────────────────────────────────────┘" -ForegroundColor $DiscordBlurple
    Write-Host ""
    
    Show-Separator
    Write-Host ""
    
    do {
        Write-Host "  > " -NoNewline -ForegroundColor $DiscordBlurple
        $selection = Read-Host "Enter your choice (1, 2, or 3)"
        if ($selection -notin @('1','2','3')) {
            Write-Host "  [ERROR] Invalid selection. Please enter 1, 2, or 3." -ForegroundColor $DiscordRed
        }
    } while ($selection -notin @('1','2','3'))
    
    return $selection
}

# Function to check local blocked ports
function Test-LocalBlockedPorts {
    param(
        [int[]]$Ports,
        [string]$LogFile
    )
    
    $results = @()
    
    foreach ($port in $Ports) {
        Write-Host ""
        Write-Host "  ────────────────────────────────────────────────────────" -ForegroundColor $DiscordGray
        Write-Host "  Checking Port: " -NoNewline -ForegroundColor $DiscordCyan
        Write-Host $port -ForegroundColor $DiscordWhite
        Write-Host "  ────────────────────────────────────────────────────────" -ForegroundColor $DiscordGray
        
        $portResult = @{
            Port = $port
            Listening = $false
            ListeningProcess = ""
            FirewallInbound = "Unknown"
            FirewallOutbound = "Unknown"
            Status = "Unknown"
        }
        
        # Check if port is listening
        Write-Host "  [CHECK] " -NoNewline -ForegroundColor $DiscordCyan
        Write-Host "Checking listening services..." -ForegroundColor $DiscordGray
        
        try {
            $listening = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | 
                         Where-Object { $_.State -eq 'Listen' }
            
            if ($listening) {
                $processId = $listening[0].OwningProcess
                $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                $processName = if ($process) { $process.ProcessName } else { "Unknown" }
                
                $portResult.Listening = $true
                $portResult.ListeningProcess = "$processName (PID: $processId)"
                
                Write-Host "  [OK] " -NoNewline -ForegroundColor $DiscordGreen
                Write-Host "Port $port is " -NoNewline -ForegroundColor $DiscordWhite
                Write-Host "LISTENING" -NoNewline -ForegroundColor $DiscordGreen
                Write-Host " - Process: " -NoNewline -ForegroundColor $DiscordWhite
                Write-Host $portResult.ListeningProcess -ForegroundColor $DiscordCyan
            }
            else {
                Write-Host "  [INFO] " -NoNewline -ForegroundColor $DiscordYellow
                Write-Host "Port $port is " -NoNewline -ForegroundColor $DiscordWhite
                Write-Host "NOT LISTENING" -ForegroundColor $DiscordYellow
            }
        }
        catch {
            Write-Host "  [INFO] " -NoNewline -ForegroundColor $DiscordYellow
            Write-Host "Port $port is " -NoNewline -ForegroundColor $DiscordWhite
            Write-Host "NOT LISTENING" -ForegroundColor $DiscordYellow
        }
        
        # Check Windows Firewall Inbound Rules
        Write-Host "  [CHECK] " -NoNewline -ForegroundColor $DiscordCyan
        Write-Host "Checking firewall inbound rules..." -ForegroundColor $DiscordGray
        
        try {
            $inboundRules = Get-NetFirewallPortFilter -Protocol TCP -ErrorAction SilentlyContinue | 
                           Where-Object { $_.LocalPort -eq $port } |
                           Get-NetFirewallRule -ErrorAction SilentlyContinue |
                           Where-Object { $_.Direction -eq 'Inbound' }
            
            if ($inboundRules) {
                $allowRules = $inboundRules | Where-Object { $_.Action -eq 'Allow' -and $_.Enabled -eq 'True' }
                $blockRules = $inboundRules | Where-Object { $_.Action -eq 'Block' -and $_.Enabled -eq 'True' }
                
                if ($blockRules) {
                    $portResult.FirewallInbound = "BLOCKED"
                    Write-Host "  [BLOCKED] " -NoNewline -ForegroundColor $DiscordRed
                    Write-Host "Inbound traffic on port $port is " -NoNewline -ForegroundColor $DiscordWhite
                    Write-Host "BLOCKED" -ForegroundColor $DiscordRed
                }
                elseif ($allowRules) {
                    $portResult.FirewallInbound = "ALLOWED"
                    Write-Host "  [OK] " -NoNewline -ForegroundColor $DiscordGreen
                    Write-Host "Inbound traffic on port $port is " -NoNewline -ForegroundColor $DiscordWhite
                    Write-Host "ALLOWED" -ForegroundColor $DiscordGreen
                }
                else {
                    $portResult.FirewallInbound = "No active rules"
                    Write-Host "  [INFO] " -NoNewline -ForegroundColor $DiscordYellow
                    Write-Host "No active inbound rules for port $port" -ForegroundColor $DiscordYellow
                }
            }
            else {
                $portResult.FirewallInbound = "No rules defined"
                Write-Host "  [INFO] " -NoNewline -ForegroundColor $DiscordYellow
                Write-Host "No inbound firewall rules for port $port (default policy applies)" -ForegroundColor $DiscordYellow
            }
        }
        catch {
            $portResult.FirewallInbound = "Check failed"
            Write-Host "  [ERROR] " -NoNewline -ForegroundColor $DiscordRed
            Write-Host "Could not check inbound rules (Admin rights may be required)" -ForegroundColor $DiscordRed
        }
        
        # Check Windows Firewall Outbound Rules
        Write-Host "  [CHECK] " -NoNewline -ForegroundColor $DiscordCyan
        Write-Host "Checking firewall outbound rules..." -ForegroundColor $DiscordGray
        
        try {
            $outboundRules = Get-NetFirewallPortFilter -Protocol TCP -ErrorAction SilentlyContinue | 
                            Where-Object { $_.LocalPort -eq $port } |
                            Get-NetFirewallRule -ErrorAction SilentlyContinue |
                            Where-Object { $_.Direction -eq 'Outbound' }
            
            if ($outboundRules) {
                $allowRules = $outboundRules | Where-Object { $_.Action -eq 'Allow' -and $_.Enabled -eq 'True' }
                $blockRules = $outboundRules | Where-Object { $_.Action -eq 'Block' -and $_.Enabled -eq 'True' }
                
                if ($blockRules) {
                    $portResult.FirewallOutbound = "BLOCKED"
                    Write-Host "  [BLOCKED] " -NoNewline -ForegroundColor $DiscordRed
                    Write-Host "Outbound traffic on port $port is " -NoNewline -ForegroundColor $DiscordWhite
                    Write-Host "BLOCKED" -ForegroundColor $DiscordRed
                }
                elseif ($allowRules) {
                    $portResult.FirewallOutbound = "ALLOWED"
                    Write-Host "  [OK] " -NoNewline -ForegroundColor $DiscordGreen
                    Write-Host "Outbound traffic on port $port is " -NoNewline -ForegroundColor $DiscordWhite
                    Write-Host "ALLOWED" -ForegroundColor $DiscordGreen
                }
                else {
                    $portResult.FirewallOutbound = "No active rules"
                    Write-Host "  [INFO] " -NoNewline -ForegroundColor $DiscordYellow
                    Write-Host "No active outbound rules for port $port" -ForegroundColor $DiscordYellow
                }
            }
            else {
                $portResult.FirewallOutbound = "No rules defined"
                Write-Host "  [INFO] " -NoNewline -ForegroundColor $DiscordYellow
                Write-Host "No outbound firewall rules for port $port (default policy applies)" -ForegroundColor $DiscordYellow
            }
        }
        catch {
            $portResult.FirewallOutbound = "Check failed"
            Write-Host "  [ERROR] " -NoNewline -ForegroundColor $DiscordRed
            Write-Host "Could not check outbound rules (Admin rights may be required)" -ForegroundColor $DiscordRed
        }
        
        # Determine overall status
        if ($portResult.FirewallInbound -eq "BLOCKED" -or $portResult.FirewallOutbound -eq "BLOCKED") {
            $portResult.Status = "BLOCKED"
        }
        elseif ($portResult.Listening) {
            $portResult.Status = "OPEN & LISTENING"
        }
        elseif ($portResult.FirewallInbound -eq "ALLOWED" -or $portResult.FirewallOutbound -eq "ALLOWED") {
            $portResult.Status = "ALLOWED (not listening)"
        }
        else {
            $portResult.Status = "DEFAULT POLICY"
        }
        
        # Log result
        $logMessage = "Port $port - Status: $($portResult.Status) | Listening: $($portResult.Listening) | Inbound: $($portResult.FirewallInbound) | Outbound: $($portResult.FirewallOutbound)"
        if ($portResult.ListeningProcess) {
            $logMessage += " | Process: $($portResult.ListeningProcess)"
        }
        Write-LogEntry -Message $logMessage -FilePath $LogFile
        
        $results += $portResult
    }
    
    return $results
}

# ============================================================================
# MAIN SCRIPT EXECUTION
# ============================================================================

$modeSelection = Show-ModeMenu

# Initialize variables based on selection
$Port = $null
$Target = $null
$LocalPorts = @()

if ($modeSelection -eq '1') {
    $TestMode = "Ping"
    Write-Host ""
    Write-Host "  > " -NoNewline -ForegroundColor $DiscordBlurple
    $Target = Read-Host "Enter target IP address or hostname"
    Write-Host ""
    Write-Host "  [OK] " -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "Mode Selected: " -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "ICMP Ping" -ForegroundColor $DiscordWhite
}
elseif ($modeSelection -eq '2') {
    $TestMode = "Port"
    Write-Host ""
    Write-Host "  > " -NoNewline -ForegroundColor $DiscordBlurple
    $Target = Read-Host "Enter target IP address or hostname"
    Write-Host ""
    Write-Host "  [OK] " -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "Mode Selected: " -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "TCP Port Test (with latency)" -ForegroundColor $DiscordWhite
    Write-Host ""
    Write-Host "  Common ports:" -ForegroundColor $DiscordCyan
    Write-Host "     HTTP: 80 | HTTPS: 443 | SSH: 22 | RDP: 3389 | FTP: 21" -ForegroundColor $DiscordGray
    Write-Host ""
    do {
        Write-Host "  > " -NoNewline -ForegroundColor $DiscordBlurple
        $portInput = Read-Host "Enter port number (1-65535)"
        if ($portInput -match '^\d+$' -and [int]$portInput -ge 1 -and [int]$portInput -le 65535) {
            $Port = [int]$portInput
        }
        else {
            Write-Host "  [ERROR] Invalid port. Enter a number between 1 and 65535." -ForegroundColor $DiscordRed
        }
    } while ($null -eq $Port)
}
elseif ($modeSelection -eq '3') {
    $TestMode = "BlockedPorts"
    Write-Host ""
    Write-Host "  [OK] " -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "Mode Selected: " -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "Local Blocked Ports Check" -ForegroundColor $DiscordWhite
    Write-Host ""
    Write-Host "  Common ports:" -ForegroundColor $DiscordCyan
    Write-Host "     HTTP: 80 | HTTPS: 443 | SSH: 22 | RDP: 3389 | FTP: 21" -ForegroundColor $DiscordGray
    Write-Host "     SMB: 445 | DNS: 53 | SMTP: 25 | MySQL: 3306 | MSSQL: 1433" -ForegroundColor $DiscordGray
    Write-Host ""
    do {
        Write-Host "  > " -NoNewline -ForegroundColor $DiscordBlurple
        $portsInput = Read-Host "Enter ports to check (comma-separated, e.g., 80,443,3389)"
        
        $validPorts = $true
        $parsedPorts = @()
        
        foreach ($p in $portsInput.Split(',')) {
            $trimmedPort = $p.Trim()
            if ($trimmedPort -match '^\d+$' -and [int]$trimmedPort -ge 1 -and [int]$trimmedPort -le 65535) {
                $parsedPorts += [int]$trimmedPort
            }
            else {
                $validPorts = $false
                Write-Host "  [ERROR] Invalid port: '$trimmedPort'. All ports must be numbers between 1-65535." -ForegroundColor $DiscordRed
                break
            }
        }
        
        if ($validPorts -and $parsedPorts.Count -gt 0) {
            $LocalPorts = $parsedPorts
        }
    } while ($LocalPorts.Count -eq 0)
    
    Write-Host ""
    Write-Host "  [INFO] " -NoNewline -ForegroundColor $DiscordCyan
    Write-Host "Will check $($LocalPorts.Count) port(s): " -NoNewline -ForegroundColor $DiscordWhite
    Write-Host ($LocalPorts -join ", ") -ForegroundColor $DiscordCyan
}

# Get test interval (only for ping and port modes)
if ($TestMode -ne "BlockedPorts") {
    Write-Host ""
    Write-Host "  > " -NoNewline -ForegroundColor $DiscordBlurple
    $intervalInput = Read-Host "Enter test interval in seconds (default: 5)"
    if ([string]::IsNullOrWhiteSpace($intervalInput)) {
        $Interval = 5
    }
    else {
        $Interval = [int]$intervalInput
    }
}

# Display configuration
Clear-Host
Show-DiscordHeader "CONFIGURATION SUMMARY"

if ($TestMode -eq "BlockedPorts") {
    $configLines = @(
        "Mode:          Local Blocked Ports Check",
        "Ports:         $($LocalPorts -join ', ')",
        "Log File:      $LogPath",
        "Max Log Size:  $MaxLogSizeMB MB (auto-archive)"
    )
}
else {
    $configLines = @(
        "Target:        $Target",
        "Mode:          $TestMode$(if ($TestMode -eq 'Port') { ' (with latency check)' })",
        $(if ($TestMode -eq 'Port') { "Port:          $Port" } else { "" }),
        "Interval:      $Interval seconds",
        "Log File:      $LogPath",
        "Max Log Size:  $MaxLogSizeMB MB (auto-archive)"
    ) | Where-Object { $_ -ne "" }
}

Show-DiscordBox -Title "Configuration" -Content $configLines

Write-Host "  [START] " -NoNewline -ForegroundColor $DiscordGreen
Write-Host "Starting in " -NoNewline -ForegroundColor $DiscordGreen
Write-Host "3" -NoNewline -ForegroundColor $DiscordWhite
Write-Host " seconds..." -ForegroundColor $DiscordGreen
Start-Sleep -Seconds 1
Write-Host "  [START] " -NoNewline -ForegroundColor $DiscordGreen
Write-Host "Starting in " -NoNewline -ForegroundColor $DiscordGreen
Write-Host "2" -NoNewline -ForegroundColor $DiscordWhite
Write-Host " seconds..." -ForegroundColor $DiscordGreen
Start-Sleep -Seconds 1
Write-Host "  [START] " -NoNewline -ForegroundColor $DiscordGreen
Write-Host "Starting in " -NoNewline -ForegroundColor $DiscordGreen
Write-Host "1" -NoNewline -ForegroundColor $DiscordWhite
Write-Host " second..." -ForegroundColor $DiscordGreen
Start-Sleep -Seconds 1

Clear-Host

# Handle Blocked Ports mode separately (one-time check, not continuous)
if ($TestMode -eq "BlockedPorts") {
    Show-DiscordHeader "LOCAL BLOCKED PORTS CHECK"
    
    # Create log file if it doesn't exist
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType File -Force | Out-Null
        Write-LogEntry -Message "=== Log file created ===" -FilePath $LogPath
    }
    
    Write-LogEntry -Message "=== Local Blocked Ports Check Started - Ports: $($LocalPorts -join ', ') ===" -FilePath $LogPath
    
    $results = Test-LocalBlockedPorts -Ports $LocalPorts -LogFile $LogPath
    
    # Display summary
    Write-Host ""
    Show-Separator
    Show-DiscordHeader "PORT CHECK SUMMARY"
    
    $blockedCount = ($results | Where-Object { $_.Status -eq "BLOCKED" }).Count
    $listeningCount = ($results | Where-Object { $_.Listening -eq $true }).Count
    $allowedCount = ($results | Where-Object { $_.FirewallInbound -eq "ALLOWED" -or $_.FirewallOutbound -eq "ALLOWED" }).Count
    
    $summaryLines = @(
        "Total Ports Checked:  $($results.Count)",
        "Blocked:              $blockedCount",
        "Listening:            $listeningCount",
        "Allowed:              $allowedCount"
    )
    
    Show-DiscordBox -Title "Results Summary" -Content $summaryLines
    
    # Detailed results table
    Write-Host "  Detailed Results:" -ForegroundColor $DiscordCyan
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor $DiscordGray
    Write-Host "  Port    | Status              | Inbound    | Outbound   | Listen" -ForegroundColor $DiscordWhite
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor $DiscordGray
    
    foreach ($result in $results) {
        $portStr = $result.Port.ToString().PadRight(7)
        $statusStr = $result.Status.PadRight(19)
        $inStr = $result.FirewallInbound.PadRight(10)
        $outStr = $result.FirewallOutbound.PadRight(10)
        $listenStr = if ($result.Listening) { "Yes" } else { "No" }
        
        Write-Host "  $portStr | " -NoNewline -ForegroundColor $DiscordWhite
        
        if ($result.Status -eq "BLOCKED") {
            Write-Host $statusStr -NoNewline -ForegroundColor $DiscordRed
        }
        elseif ($result.Status -eq "OPEN & LISTENING") {
            Write-Host $statusStr -NoNewline -ForegroundColor $DiscordGreen
        }
        else {
            Write-Host $statusStr -NoNewline -ForegroundColor $DiscordYellow
        }
        
        Write-Host " | $inStr | $outStr | $listenStr" -ForegroundColor $DiscordGray
    }
    
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor $DiscordGray
    
    Write-LogEntry -Message "=== Check completed ===" -FilePath $LogPath
    
    Write-Host ""
    Write-Host "  [SAVED] " -NoNewline -ForegroundColor $DiscordCyan
    Write-Host "Log file saved to: " -NoNewline -ForegroundColor $DiscordCyan
    Write-Host $LogPath -ForegroundColor $DiscordWhite
    Write-Host ""
    Write-Host "  [BYE] " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host "Thank you for using Network Testing Tool!" -ForegroundColor $DiscordBlurple
    Write-Host ""
    
    exit
}

# Continuous monitoring modes (Ping and Port)
Show-DiscordHeader "MONITORING ACTIVE"
Show-AbortReminder

# Create log file if it doesn't exist
if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType File -Force | Out-Null
    Write-LogEntry -Message "=== Log file created - Monitoring started ===" -FilePath $LogPath
}
else {
    Write-LogEntry -Message "=== Monitoring started ===" -FilePath $LogPath
}

# Log the configuration
Write-LogEntry -Message "Target: $Target | Mode: $TestMode $(if($Port){"| Port: $Port"}) | Interval: $Interval seconds" -FilePath $LogPath

# Statistics
$totalTests = 0
$failedTests = 0

# Latency tracking for TCP port mode
$latencyValues = [System.Collections.ArrayList]@()
$minLatency = [double]::MaxValue
$maxLatency = 0
$avgLatency = 0

# Main monitoring loop
try {
    while ($true) {
        $totalTests++
        
        # Check log size before each test
        Test-LogSize -LogFilePath $LogPath
        
        # Perform the appropriate test
        if ($TestMode -eq 'Ping') {
            $result = Test-ConnectivityPing -TargetHost $Target -LogFile $LogPath
        }
        elseif ($TestMode -eq 'Port') {
            $result = Test-ConnectivityPort -TargetHost $Target -TargetPort $Port -LogFile $LogPath
            
            # Track latency if successful
            if ($result.Success -and $null -ne $result.Latency) {
                [void]$latencyValues.Add($result.Latency)
                
                # Update min/max
                if ($result.Latency -lt $minLatency) {
                    $minLatency = $result.Latency
                }
                if ($result.Latency -gt $maxLatency) {
                    $maxLatency = $result.Latency
                }
                
                # Calculate average
                $avgLatency = ($latencyValues | Measure-Object -Average).Average
                
                # Log with latency
                Write-LogEntry -Message "SUCCESS - Port $Port on $Target is open (Latency: $($result.Latency)ms)" -FilePath $LogPath
            }
        }
        
        if (-not $result.Success) {
            $failedTests++
        }
        
        # Display statistics with latency info for Port mode
        if ($TestMode -eq 'Port' -and $latencyValues.Count -gt 0) {
            Show-StatsBar -Total $totalTests -Failed $failedTests -AvgLatency $avgLatency -MinLatency $minLatency -MaxLatency $maxLatency -ShowLatency $true
        }
        else {
            Show-StatsBar -Total $totalTests -Failed $failedTests -AvgLatency 0 -MinLatency 0 -MaxLatency 0 -ShowLatency $false
        }
        Write-Host ""
        
        # Show abort reminder every 10 tests
        if ($totalTests % 10 -eq 0) {
            Show-AbortReminder
        }
        
        # Wait for the specified interval
        Start-Sleep -Seconds $Interval
    }
}
catch {
    Write-Host ""
    Write-Host "  [STOP] " -NoNewline -ForegroundColor $DiscordYellow
    Write-Host "Monitoring stopped by user" -ForegroundColor $DiscordYellow
    Write-LogEntry -Message "=== Monitoring stopped ===" -FilePath $LogPath
}
finally {
    # Final statistics
    Write-Host ""
    Show-Separator
    Show-DiscordHeader "FINAL STATISTICS"
    
    $success = $totalTests - $failedTests
    $finalSuccessRate = if ($totalTests -gt 0) { [math]::Round(($success / $totalTests) * 100, 2) } else { 0 }
    
    $statsLines = @(
        "Total Tests:      $totalTests",
        "Successful:       $success",
        "Failed:           $failedTests",
        "Success Rate:     $finalSuccessRate%"
    )
    
    # Add latency stats for Port mode
    if ($TestMode -eq 'Port' -and $latencyValues.Count -gt 0) {
        $statsLines += ""
        $statsLines += "--- Latency Statistics ---"
        $statsLines += "Average:          $([math]::Round($avgLatency, 2))ms"
        $statsLines += "Minimum:          ${minLatency}ms"
        $statsLines += "Maximum:          ${maxLatency}ms"
        $statsLines += "Samples:          $($latencyValues.Count)"
        
        # Log latency summary
        Write-LogEntry -Message "Latency Summary - Avg: $([math]::Round($avgLatency, 2))ms | Min: ${minLatency}ms | Max: ${maxLatency}ms | Samples: $($latencyValues.Count)" -FilePath $LogPath
    }
    
    Show-DiscordBox -Title "Session Summary" -Content $statsLines
    
    Write-Host "  [SAVED] " -NoNewline -ForegroundColor $DiscordCyan
    Write-Host "Log file saved to: " -NoNewline -ForegroundColor $DiscordCyan
    Write-Host $LogPath -ForegroundColor $DiscordWhite
    Write-Host ""
    Write-Host "  [BYE] " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host "Thank you for using Network Testing Tool!" -ForegroundColor $DiscordBlurple
    Write-Host ""
}
