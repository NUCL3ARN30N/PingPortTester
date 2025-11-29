<#
.SYNOPSIS
    Network connectivity testing tool with automatic log archiving
.DESCRIPTION
    Tests network connectivity using either ICMP ping or TCP port testing.
    Logs dropped packets with timestamps and auto-archives logs at 20MB.
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
            Write-Host "  📦 " -NoNewline -ForegroundColor $DiscordYellow
            Write-Host "Log archived to: " -NoNewline -ForegroundColor $DiscordYellow
            Write-Host $archiveFullPath -ForegroundColor $DiscordWhite
            Write-Host ""
            
            Clear-Content $LogFilePath -ErrorAction Stop
            Write-LogEntry -Message "=== Log archived to $archiveFileName - New log started ===" -FilePath $LogFilePath
            
            return $true
        }
        catch {
            Write-Host "  ❌ " -NoNewline -ForegroundColor $DiscordRed
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
            Write-Host "  ⚠️  " -NoNewline -ForegroundColor $DiscordYellow
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
            Write-Host "  ❌ " -NoNewline -ForegroundColor $DiscordRed
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
            Write-Host $message -ForegroundColor $DiscordRed
            Write-LogEntry -Message $message -FilePath $LogFile
            return $false
        }
        else {
            Write-Host "  ✅ " -NoNewline -ForegroundColor $DiscordGreen
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
            Write-Host "Ping to " -NoNewline -ForegroundColor $DiscordGreen
            Write-Host $TargetHost -NoNewline -ForegroundColor $DiscordWhite
            Write-Host " successful" -ForegroundColor $DiscordGreen
            return $true
        }
    }
    catch {
        $message = "DROPPED - Ping to $TargetHost failed (Error: $($_.Exception.Message))"
        Write-Host "  ❌ " -NoNewline -ForegroundColor $DiscordRed
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
        Write-Host $message -ForegroundColor $DiscordRed
        Write-LogEntry -Message $message -FilePath $LogFile
        return $false
    }
}

# Function to test connectivity using TCP Port
function Test-ConnectivityPort {
    param(
        [string]$TargetHost,
        [int]$TargetPort,
        [string]$LogFile
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect($TargetHost, $TargetPort, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne(3000, $false)
        
        if (!$wait) {
            $tcpClient.Close()
            $message = "DROPPED - Port $TargetPort on $TargetHost is closed or filtered (Timeout)"
            Write-Host "  ❌ " -NoNewline -ForegroundColor $DiscordRed
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
            Write-Host $message -ForegroundColor $DiscordRed
            Write-LogEntry -Message $message -FilePath $LogFile
            return $false
        }
        else {
            try {
                $tcpClient.EndConnect($connect)
                $tcpClient.Close()
                Write-Host "  ✅ " -NoNewline -ForegroundColor $DiscordGreen
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
                Write-Host "Port " -NoNewline -ForegroundColor $DiscordGreen
                Write-Host $TargetPort -NoNewline -ForegroundColor $DiscordWhite
                Write-Host " on " -NoNewline -ForegroundColor $DiscordGreen
                Write-Host $TargetHost -NoNewline -ForegroundColor $DiscordWhite
                Write-Host " is open" -ForegroundColor $DiscordGreen
                return $true
            }
            catch {
                $tcpClient.Close()
                $message = "DROPPED - Port $TargetPort on $TargetHost is closed or filtered"
                Write-Host "  ❌ " -NoNewline -ForegroundColor $DiscordRed
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
                Write-Host $message -ForegroundColor $DiscordRed
                Write-LogEntry -Message $message -FilePath $LogFile
                return $false
            }
        }
    }
    catch {
        $message = "DROPPED - Failed to test port $TargetPort on $TargetHost (Error: $($_.Exception.Message))"
        Write-Host "  ❌ " -NoNewline -ForegroundColor $DiscordRed
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor $DiscordGray
        Write-Host $message -ForegroundColor $DiscordRed
        Write-LogEntry -Message $message -FilePath $LogFile
        return $false
    }
}

# Function to show stats bar
function Show-StatsBar {
    param(
        [int]$Total,
        [int]$Failed
    )
    
    $success = $Total - $Failed
    $successRate = if ($Total -gt 0) { [math]::Round(($success / $Total) * 100, 1) } else { 0 }
    
    Write-Host "  📊 " -NoNewline -ForegroundColor $DiscordCyan
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
}

# Function to show abort reminder
function Show-AbortReminder {
    Write-Host ""
    Show-Separator
    Write-Host "  ⚠️  " -NoNewline -ForegroundColor $DiscordYellow
    Write-Host "Press " -NoNewline -ForegroundColor $DiscordYellow
    Write-Host "Ctrl+C" -NoNewline -ForegroundColor $DiscordWhite
    Write-Host " to stop monitoring" -ForegroundColor $DiscordYellow
    Show-Separator
    Write-Host ""
}

# Display menu and get mode selection
function Show-ModeMenu {
    Clear-Host
    Show-DiscordHeader "🌐 NETWORK CONNECTIVITY TESTING TOOL"
    
    Write-Host "  Select Testing Mode:" -ForegroundColor $DiscordCyan
    Write-Host ""
    
    Write-Host "  ┌─ " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host "1" -NoNewline -ForegroundColor $DiscordWhite
    Write-Host " ─────────────────────────────────────────────────┐" -ForegroundColor $DiscordBlurple
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  │  " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host "🔔 ICMP Ping Mode" -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "                                  │" -ForegroundColor $DiscordBlurple
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  │     • Uses ICMP echo requests (standard ping)         │" -ForegroundColor $DiscordGray
    Write-Host "  │     • Tests if host is reachable on network           │" -ForegroundColor $DiscordGray
    Write-Host "  │     • Works at network layer (Layer 3)                │" -ForegroundColor $DiscordGray
    Write-Host "  │     • No port number needed                           │" -ForegroundColor $DiscordGray
    Write-Host "  │     • Example: google.com or 8.8.8.8                  │" -ForegroundColor $DiscordGray
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  └────────────────────────────────────────────────────────┘" -ForegroundColor $DiscordBlurple
    Write-Host ""
    
    Write-Host "  ┌─ " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host "2" -NoNewline -ForegroundColor $DiscordWhite
    Write-Host " ─────────────────────────────────────────────────┐" -ForegroundColor $DiscordBlurple
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  │  " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host "🔌 TCP Port Test Mode" -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "                              │" -ForegroundColor $DiscordBlurple
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  │     • Tests if specific TCP port is open/listening    │" -ForegroundColor $DiscordGray
    Write-Host "  │     • Checks application-level connectivity           │" -ForegroundColor $DiscordGray
    Write-Host "  │     • Works at transport layer (Layer 4)              │" -ForegroundColor $DiscordGray
    Write-Host "  │     • Requires port number (80, 443, 22, etc.)        │" -ForegroundColor $DiscordGray
    Write-Host "  │     • Example: Test if webserver port 443 is open     │" -ForegroundColor $DiscordGray
    Write-Host "  │                                                        │" -ForegroundColor $DiscordBlurple
    Write-Host "  └────────────────────────────────────────────────────────┘" -ForegroundColor $DiscordBlurple
    Write-Host ""
    
    Show-Separator
    Write-Host ""
    
    do {
        Write-Host "  ➤ " -NoNewline -ForegroundColor $DiscordBlurple
        $selection = Read-Host "Enter your choice (1 or 2)"
        if ($selection -notin @('1','2')) {
            Write-Host "  ❌ Invalid selection. Please enter 1 or 2." -ForegroundColor $DiscordRed
        }
    } while ($selection -notin @('1','2'))
    
    return $selection
}

# ============================================================================
# MAIN SCRIPT EXECUTION
# ============================================================================

$modeSelection = Show-ModeMenu

# Get target address/IP
Write-Host ""
Write-Host "  ➤ " -NoNewline -ForegroundColor $DiscordBlurple
$Target = Read-Host "Enter target IP address or hostname"

# Initialize variables based on selection
$Port = $null

if ($modeSelection -eq '1') {
    $TestMode = "Ping"
    Write-Host ""
    Write-Host "  ✓ " -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "Mode Selected: " -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "ICMP Ping" -ForegroundColor $DiscordWhite
}
elseif ($modeSelection -eq '2') {
    $TestMode = "Port"
    Write-Host ""
    Write-Host "  ✓ " -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "Mode Selected: " -NoNewline -ForegroundColor $DiscordGreen
    Write-Host "TCP Port Test" -ForegroundColor $DiscordWhite
    Write-Host ""
    Write-Host "  📋 Common ports:" -ForegroundColor $DiscordCyan
    Write-Host "     HTTP: 80 │ HTTPS: 443 │ SSH: 22 │ RDP: 3389 │ FTP: 21" -ForegroundColor $DiscordGray
    Write-Host ""
    do {
        Write-Host "  ➤ " -NoNewline -ForegroundColor $DiscordBlurple
        $portInput = Read-Host "Enter port number (1-65535)"
        if ($portInput -match '^\d+$' -and [int]$portInput -ge 1 -and [int]$portInput -le 65535) {
            $Port = [int]$portInput
        }
        else {
            Write-Host "  ❌ Invalid port. Enter a number between 1 and 65535." -ForegroundColor $DiscordRed
        }
    } while ($null -eq $Port)
}

# Get test interval
Write-Host ""
Write-Host "  ➤ " -NoNewline -ForegroundColor $DiscordBlurple
$intervalInput = Read-Host "Enter test interval in seconds (default: 5)"
if ([string]::IsNullOrWhiteSpace($intervalInput)) {
    $Interval = 5
}
else {
    $Interval = [int]$intervalInput
}

# Display configuration
Clear-Host
Show-DiscordHeader "⚙️  CONFIGURATION SUMMARY"

$configLines = @(
    "Target:        $Target",
    "Mode:          $TestMode",
    $(if ($TestMode -eq 'Port') { "Port:          $Port" } else { "" }),
    "Interval:      $Interval seconds",
    "Log File:      $LogPath",
    "Max Log Size:  $MaxLogSizeMB MB (auto-archive)"
) | Where-Object { $_ -ne "" }

Show-DiscordBox -Title "Configuration" -Content $configLines

Write-Host "  🚀 " -NoNewline -ForegroundColor $DiscordGreen
Write-Host "Starting monitoring in " -NoNewline -ForegroundColor $DiscordGreen
Write-Host "3" -NoNewline -ForegroundColor $DiscordWhite
Write-Host " seconds..." -ForegroundColor $DiscordGreen
Start-Sleep -Seconds 1
Write-Host "  🚀 " -NoNewline -ForegroundColor $DiscordGreen
Write-Host "Starting monitoring in " -NoNewline -ForegroundColor $DiscordGreen
Write-Host "2" -NoNewline -ForegroundColor $DiscordWhite
Write-Host " seconds..." -ForegroundColor $DiscordGreen
Start-Sleep -Seconds 1
Write-Host "  🚀 " -NoNewline -ForegroundColor $DiscordGreen
Write-Host "Starting monitoring in " -NoNewline -ForegroundColor $DiscordGreen
Write-Host "1" -NoNewline -ForegroundColor $DiscordWhite
Write-Host " second..." -ForegroundColor $DiscordGreen
Start-Sleep -Seconds 1

Clear-Host
Show-DiscordHeader "📡 MONITORING ACTIVE"
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
        }
        
        if (-not $result) {
            $failedTests++
        }
        
        # Display statistics
        Show-StatsBar -Total $totalTests -Failed $failedTests
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
    Write-Host "  ⏹️  " -NoNewline -ForegroundColor $DiscordYellow
    Write-Host "Monitoring stopped by user" -ForegroundColor $DiscordYellow
    Write-LogEntry -Message "=== Monitoring stopped ===" -FilePath $LogPath
}
finally {
    # Final statistics
    Write-Host ""
    Show-Separator
    Show-DiscordHeader "📊 FINAL STATISTICS"
    
    $success = $totalTests - $failedTests
    $finalSuccessRate = if ($totalTests -gt 0) { [math]::Round(($success / $totalTests) * 100, 2) } else { 0 }
    
    $statsLines = @(
        "Total Tests:      $totalTests",
        "Successful:       $success",
        "Failed:           $failedTests",
        "Success Rate:     $finalSuccessRate%"
    )
    
    Show-DiscordBox -Title "Session Summary" -Content $statsLines
    
    Write-Host "  💾 " -NoNewline -ForegroundColor $DiscordCyan
    Write-Host "Log file saved to: " -NoNewline -ForegroundColor $DiscordCyan
    Write-Host $LogPath -ForegroundColor $DiscordWhite
    Write-Host ""
    Write-Host "  👋 " -NoNewline -ForegroundColor $DiscordBlurple
    Write-Host "Thank you for using Network Testing Tool!" -ForegroundColor $DiscordBlurple
    Write-Host ""
}
