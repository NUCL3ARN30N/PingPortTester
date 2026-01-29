<#
.SYNOPSIS
    Network connectivity testing tool with automatic log archiving
.DESCRIPTION
    Tests network connectivity using ICMP ping, TCP/UDP port testing, traceroute,
    DNS lookup, bandwidth test, local blocked ports check, SMTP email test, and public IP check.
#>

# Color Scheme
$Green = "Green"
$Red = "Red"
$Yellow = "Yellow"
$Gray = "DarkGray"
$White = "White"
$Cyan = "Cyan"
$Magenta = "DarkMagenta"

# Configuration
$MaxLogSizeMB = 20
$MaxLogSizeBytes = $MaxLogSizeMB * 1MB
$LogPath = ".\NetworkTest.log"

function Show-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor $Magenta
    Write-Host "  $Title" -ForegroundColor $White
    Write-Host "============================================================" -ForegroundColor $Magenta
    Write-Host ""
}

function Show-Separator {
    Write-Host "------------------------------------------------------------" -ForegroundColor $Gray
}

function Write-LogEntry {
    param([string]$Message, [string]$FilePath)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $FilePath -Value "[$timestamp] $Message"
}

function Test-LogSize {
    param([string]$LogFilePath)
    if (Test-Path $LogFilePath) {
        $fileSize = (Get-Item $LogFilePath).Length
        if ($fileSize -ge $MaxLogSizeBytes) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $archiveName = "NetworkTest_$timestamp.zip"
            Compress-Archive -Path $LogFilePath -DestinationPath $archiveName -Force
            Clear-Content $LogFilePath
            Write-Host "  [ARCHIVED] Log archived to: $archiveName" -ForegroundColor $Yellow
        }
    }
}

# Mode 1: ICMP Ping
function Test-Ping {
    param([string]$Target, [string]$LogFile)
    try {
        $ping = Test-Connection -ComputerName $Target -Count 1 -Quiet -ErrorAction Stop
        if ($ping) {
            Write-Host "  [OK] [$(Get-Date -Format 'HH:mm:ss')] Ping to $Target successful" -ForegroundColor $Green
            return $true
        } else {
            Write-Host "  [FAIL] [$(Get-Date -Format 'HH:mm:ss')] Ping to $Target failed" -ForegroundColor $Red
            Write-LogEntry -Message "DROPPED - Ping to $Target failed" -FilePath $LogFile
            return $false
        }
    } catch {
        Write-Host "  [FAIL] [$(Get-Date -Format 'HH:mm:ss')] Ping error: $($_.Exception.Message)" -ForegroundColor $Red
        Write-LogEntry -Message "ERROR - $($_.Exception.Message)" -FilePath $LogFile
        return $false
    }
}

# Mode 2: TCP Port Test
function Test-TCPPort {
    param([string]$Target, [int]$Port, [string]$LogFile)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $connect = $tcp.BeginConnect($Target, $Port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne(3000, $false)
        
        if ($wait -and $tcp.Connected) {
            $tcp.EndConnect($connect)
            $stopwatch.Stop()
            $latency = $stopwatch.ElapsedMilliseconds
            $tcp.Close()
            
            $color = if ($latency -lt 50) { $Green } elseif ($latency -lt 150) { $Yellow } else { $Red }
            Write-Host "  [OK] [$(Get-Date -Format 'HH:mm:ss')] Port $Port open | Latency: ${latency}ms" -ForegroundColor $color
            Write-LogEntry -Message "Port $Port on $Target - OPEN (${latency}ms)" -FilePath $LogFile
            return @{ Success = $true; Latency = $latency }
        } else {
            $tcp.Close()
            Write-Host "  [FAIL] [$(Get-Date -Format 'HH:mm:ss')] Port $Port closed/filtered" -ForegroundColor $Red
            Write-LogEntry -Message "Port $Port on $Target - CLOSED" -FilePath $LogFile
            return @{ Success = $false; Latency = $null }
        }
    } catch {
        Write-Host "  [FAIL] [$(Get-Date -Format 'HH:mm:ss')] Error: $($_.Exception.Message)" -ForegroundColor $Red
        return @{ Success = $false; Latency = $null }
    }
}

# Mode 3: UDP Port Test
function Test-UDPPort {
    param([string]$Target, [int]$Port, [string]$LogFile)
    try {
        $udp = New-Object System.Net.Sockets.UdpClient
        $udp.Client.ReceiveTimeout = 3000
        $udp.Connect($Target, $Port)
        $bytes = [System.Text.Encoding]::ASCII.GetBytes("test")
        [void]$udp.Send($bytes, $bytes.Length)
        
        try {
            $remoteEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            $udp.Receive([ref]$remoteEP) | Out-Null
            $udp.Close()
            Write-Host "  [OK] [$(Get-Date -Format 'HH:mm:ss')] UDP Port $Port responded" -ForegroundColor $Green
            Write-LogEntry -Message "UDP Port $Port on $Target - OPEN" -FilePath $LogFile
            return @{ Success = $true; Status = "Open" }
        } catch {
            $udp.Close()
            if ($_.Exception.InnerException.SocketErrorCode -eq 'ConnectionReset') {
                Write-Host "  [CLOSED] [$(Get-Date -Format 'HH:mm:ss')] UDP Port $Port closed" -ForegroundColor $Red
                Write-LogEntry -Message "UDP Port $Port on $Target - CLOSED" -FilePath $LogFile
                return @{ Success = $false; Status = "Closed" }
            } else {
                Write-Host "  [OPEN|FILTERED] [$(Get-Date -Format 'HH:mm:ss')] UDP Port $Port open or filtered" -ForegroundColor $Yellow
                Write-LogEntry -Message "UDP Port $Port on $Target - OPEN|FILTERED" -FilePath $LogFile
                return @{ Success = $true; Status = "Open|Filtered" }
            }
        }
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor $Red
        return @{ Success = $false; Status = "Error" }
    }
}

# Mode 4: Port Range Scan
function Invoke-PortScan {
    param([string]$Target, [int]$StartPort, [int]$EndPort, [string]$Protocol, [string]$LogFile)
    
    $openPorts = @()
    $total = $EndPort - $StartPort + 1
    
    Write-Host "  Scanning $total ports ($StartPort-$EndPort) on $Target..." -ForegroundColor $Cyan
    Write-LogEntry -Message "Port scan started: $Target ($StartPort-$EndPort) $Protocol" -FilePath $LogFile
    
    for ($port = $StartPort; $port -le $EndPort; $port++) {
        Write-Host "`r  Scanning port $port..." -NoNewline
        
        if ($Protocol -eq "TCP") {
            $tcp = New-Object System.Net.Sockets.TcpClient
            try {
                $connect = $tcp.BeginConnect($Target, $port, $null, $null)
                if ($connect.AsyncWaitHandle.WaitOne(500, $false) -and $tcp.Connected) {
                    $openPorts += $port
                }
            } catch { }
            $tcp.Close()
        } else {
            $udp = New-Object System.Net.Sockets.UdpClient
            try {
                $udp.Client.ReceiveTimeout = 500
                $udp.Connect($Target, $port)
                $openPorts += $port
            } catch { }
            $udp.Close()
        }
    }
    
    Write-Host "`r                                        `r"
    Write-Host ""
    Write-Host "  Open Ports: " -NoNewline -ForegroundColor $Cyan
    if ($openPorts.Count -gt 0) {
        Write-Host ($openPorts -join ", ") -ForegroundColor $Green
        Write-LogEntry -Message "Open ports: $($openPorts -join ', ')" -FilePath $LogFile
    } else {
        Write-Host "None found" -ForegroundColor $Yellow
    }
    
    $services = @{21="FTP";22="SSH";23="Telnet";25="SMTP";53="DNS";80="HTTP";110="POP3";143="IMAP";443="HTTPS";445="SMB";465="SMTPS";587="SMTP-MSA";993="IMAPS";995="POP3S";3306="MySQL";3389="RDP";5432="PostgreSQL";8080="HTTP-Alt"}
    
    if ($openPorts.Count -gt 0) {
        Write-Host ""
        Write-Host "  Services:" -ForegroundColor $Cyan
        foreach ($p in $openPorts) {
            $svc = if ($services.ContainsKey($p)) { $services[$p] } else { "Unknown" }
            Write-Host "    $p - $svc" -ForegroundColor $White
        }
    }
    
    Write-LogEntry -Message "Port scan completed" -FilePath $LogFile
}

# Mode 5: Traceroute
function Invoke-Traceroute {
    param([string]$Target, [int]$MaxHops, [string]$LogFile)
    
    Write-Host "  Tracing route to $Target (max $MaxHops hops)..." -ForegroundColor $Cyan
    Write-Host ""
    Write-Host "  Hop   RTT       IP Address" -ForegroundColor $White
    Show-Separator
    
    Write-LogEntry -Message "Traceroute to $Target started" -FilePath $LogFile
    
    for ($ttl = 1; $ttl -le $MaxHops; $ttl++) {
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $options = New-Object System.Net.NetworkInformation.PingOptions($ttl, $true)
            $buffer = [byte[]]::new(32)
            
            $reply = $ping.Send($Target, 3000, $buffer, $options)
            
            $ip = if ($reply.Address) { $reply.Address.ToString() } else { "*" }
            $rtt = if ($reply.Status -eq 'Success' -or $reply.Status -eq 'TtlExpired') { "$($reply.RoundtripTime)ms" } else { "*" }
            
            $color = if ($reply.RoundtripTime -lt 50) { $Green } elseif ($reply.RoundtripTime -lt 150) { $Yellow } else { $Red }
            if ($rtt -eq "*") { $color = $Gray }
            
            Write-Host "  $($ttl.ToString().PadLeft(3))   $($rtt.PadRight(9)) $ip" -ForegroundColor $color
            Write-LogEntry -Message "Hop $ttl : $ip ($rtt)" -FilePath $LogFile
            
            if ($reply.Status -eq 'Success') {
                Write-Host ""
                Write-Host "  Trace complete." -ForegroundColor $Green
                break
            }
        } catch {
            Write-Host "  $($ttl.ToString().PadLeft(3))   *         Request timed out" -ForegroundColor $Gray
        }
    }
    
    Write-LogEntry -Message "Traceroute completed" -FilePath $LogFile
}

# Mode 6: DNS Lookup
function Invoke-DNSLookup {
    param([string]$Domain, [string]$LogFile)
    
    $dnsServers = @(
        @{Name="System Default"; IP=$null},
        @{Name="Google"; IP="8.8.8.8"},
        @{Name="Cloudflare"; IP="1.1.1.1"},
        @{Name="OpenDNS"; IP="208.67.222.222"}
    )
    
    Write-Host "  DNS Lookup for: $Domain" -ForegroundColor $Cyan
    Show-Separator
    
    Write-LogEntry -Message "DNS Lookup for $Domain" -FilePath $LogFile
    
    foreach ($dns in $dnsServers) {
        Write-Host ""
        Write-Host "  DNS: $($dns.Name)" -NoNewline -ForegroundColor $White
        if ($dns.IP) { Write-Host " ($($dns.IP))" -ForegroundColor $Gray } else { Write-Host "" }
        
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            
            if ($dns.IP) {
                $result = nslookup $Domain $dns.IP 2>$null | Select-String "Address:" | Select-Object -Skip 1
                $sw.Stop()
                if ($result) {
                    $addresses = $result | ForEach-Object { ($_ -replace "Address:\s*", "").Trim() }
                    Write-Host "    $($addresses -join ', ')" -ForegroundColor $Green
                    Write-Host "    Query: $($sw.ElapsedMilliseconds)ms" -ForegroundColor $Gray
                } else {
                    Write-Host "    No results" -ForegroundColor $Yellow
                }
            } else {
                $addresses = [System.Net.Dns]::GetHostAddresses($Domain)
                $sw.Stop()
                Write-Host "    $($addresses.IPAddressToString -join ', ')" -ForegroundColor $Green
                Write-Host "    Query: $($sw.ElapsedMilliseconds)ms" -ForegroundColor $Gray
            }
            
            Write-LogEntry -Message "$($dns.Name): Success" -FilePath $LogFile
        } catch {
            Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor $Red
        }
    }
    
    Write-Host ""
    Show-Separator
    Write-Host ""
    Write-Host "  Additional Records:" -ForegroundColor $Cyan
    
    Write-Host ""
    Write-Host "  MX Records:" -ForegroundColor $White
    try {
        $mx = Resolve-DnsName -Name $Domain -Type MX -ErrorAction Stop
        foreach ($r in $mx | Where-Object {$_.Type -eq 'MX'}) {
            Write-Host "    Priority $($r.Preference): $($r.NameExchange)" -ForegroundColor $Green
        }
    } catch { Write-Host "    None found" -ForegroundColor $Yellow }
    
    Write-Host ""
    Write-Host "  NS Records:" -ForegroundColor $White
    try {
        $ns = Resolve-DnsName -Name $Domain -Type NS -ErrorAction Stop
        foreach ($r in $ns | Where-Object {$_.Type -eq 'NS'}) {
            Write-Host "    $($r.NameHost)" -ForegroundColor $Green
        }
    } catch { Write-Host "    None found" -ForegroundColor $Yellow }
    
    Write-LogEntry -Message "DNS Lookup completed" -FilePath $LogFile
}

# Mode 7: Bandwidth Test
function Test-Bandwidth {
    param([string]$LogFile)
    
    Write-Host "  Bandwidth Test" -ForegroundColor $Cyan
    Write-Host ""
    Write-Host "  Select test size:" -ForegroundColor $White
    Write-Host "    1 - Quick (10 MB)"
    Write-Host "    2 - Standard (25 MB)"
    Write-Host "    3 - Extended (100 MB)"
    Write-Host ""
    
    $choice = Read-Host "  > Choice (1-3)"
    
    $urls = @(
        @{Size=10; Url="https://speed.cloudflare.com/__down?bytes=10000000"},
        @{Size=25; Url="https://speed.cloudflare.com/__down?bytes=25000000"},
        @{Size=100; Url="https://speed.cloudflare.com/__down?bytes=100000000"}
    )
    
    $test = $urls[[int]$choice - 1]
    
    Write-Host ""
    Write-Host "  Downloading $($test.Size) MB test file..." -ForegroundColor $Cyan
    
    Write-LogEntry -Message "Bandwidth test started ($($test.Size) MB)" -FilePath $LogFile
    
    try {
        $wc = New-Object System.Net.WebClient
        $tempFile = [System.IO.Path]::GetTempFileName()
        
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $wc.DownloadFile($test.Url, $tempFile)
        $sw.Stop()
        
        $seconds = $sw.Elapsed.TotalSeconds
        $sizeMB = (Get-Item $tempFile).Length / 1MB
        $speedMbps = [math]::Round(($sizeMB * 8) / $seconds, 2)
        
        Remove-Item $tempFile -Force
        
        Write-Host ""
        Write-Host "  Results:" -ForegroundColor $Cyan
        Write-Host "    Downloaded: $([math]::Round($sizeMB, 2)) MB" -ForegroundColor $White
        Write-Host "    Time: $([math]::Round($seconds, 2)) seconds" -ForegroundColor $White
        Write-Host "    Speed: " -NoNewline -ForegroundColor $White
        
        $color = if ($speedMbps -ge 100) { $Green } elseif ($speedMbps -ge 25) { $Yellow } else { $Red }
        Write-Host "$speedMbps Mbps" -ForegroundColor $color
        
        Write-LogEntry -Message "Download: $speedMbps Mbps" -FilePath $LogFile
        
        Write-Host ""
        Write-Host "  Latency Test:" -ForegroundColor $Cyan
        $latencies = @()
        foreach ($server in @("8.8.8.8", "1.1.1.1")) {
            $ping = Test-Connection -ComputerName $server -Count 3 -ErrorAction SilentlyContinue
            if ($ping) {
                $avg = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 2)
                $latencies += $avg
            }
        }
        
        if ($latencies.Count -gt 0) {
            $avgLatency = [math]::Round(($latencies | Measure-Object -Average).Average, 2)
            $color = if ($avgLatency -lt 30) { $Green } elseif ($avgLatency -lt 100) { $Yellow } else { $Red }
            Write-Host "    Average: ${avgLatency}ms" -ForegroundColor $color
            Write-LogEntry -Message "Latency: ${avgLatency}ms" -FilePath $LogFile
        }
        
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor $Red
    }
    
    Write-LogEntry -Message "Bandwidth test completed" -FilePath $LogFile
}

# Mode 8: External Port Check
function Test-ExternalPort {
    param([int[]]$Ports, [string]$LogFile)
    
    Write-Host "  External Port Check" -ForegroundColor $Cyan
    Write-Host "  Checking if ports are reachable from the internet..." -ForegroundColor $Gray
    Write-Host ""
    
    Write-LogEntry -Message "External port check started" -FilePath $LogFile
    
    try {
        $externalIP = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10)
        Write-Host "  Your External IP: $externalIP" -ForegroundColor $Cyan
        Write-Host ""
        Write-LogEntry -Message "External IP: $externalIP" -FilePath $LogFile
    } catch {
        Write-Host "  [ERROR] Could not determine external IP" -ForegroundColor $Red
        return
    }
    
    foreach ($port in $Ports) {
        Write-Host "  Port $port... " -NoNewline
        
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $connect = $tcp.BeginConnect($externalIP, $port, $null, $null)
            if ($connect.AsyncWaitHandle.WaitOne(5000, $false) -and $tcp.Connected) {
                Write-Host "OPEN" -ForegroundColor $Green
                Write-LogEntry -Message "Port $port : OPEN" -FilePath $LogFile
            } else {
                Write-Host "CLOSED/FILTERED" -ForegroundColor $Red
                Write-LogEntry -Message "Port $port : CLOSED" -FilePath $LogFile
            }
        } catch {
            Write-Host "CLOSED/FILTERED" -ForegroundColor $Red
            Write-LogEntry -Message "Port $port : CLOSED" -FilePath $LogFile
        }
        $tcp.Close()
    }
    
    Write-Host ""
    Write-Host "  [INFO] Results depend on router/firewall configuration" -ForegroundColor $Yellow
    Write-Host "  [INFO] Ports may need port forwarding to be accessible" -ForegroundColor $Yellow
    
    Write-LogEntry -Message "External port check completed" -FilePath $LogFile
}

# Mode 9: Local Blocked Ports
function Test-LocalPorts {
    param([int[]]$Ports, [string]$LogFile)
    
    Write-LogEntry -Message "Local port check started" -FilePath $LogFile
    
    foreach ($port in $Ports) {
        Write-Host ""
        Show-Separator
        Write-Host "  Port: $port" -ForegroundColor $Cyan
        Show-Separator
        
        Write-Host "  Checking listening services..." -ForegroundColor $Gray
        try {
            $listen = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Where-Object {$_.State -eq 'Listen'}
            if ($listen) {
                $proc = Get-Process -Id $listen[0].OwningProcess -ErrorAction SilentlyContinue
                $procName = if ($proc) { $proc.ProcessName } else { "Unknown" }
                Write-Host "  [LISTENING] Process: $procName (PID: $($listen[0].OwningProcess))" -ForegroundColor $Green
            } else {
                Write-Host "  [NOT LISTENING]" -ForegroundColor $Yellow
            }
        } catch {
            Write-Host "  [NOT LISTENING]" -ForegroundColor $Yellow
        }
        
        Write-Host "  Checking firewall rules..." -ForegroundColor $Gray
        try {
            $rules = Get-NetFirewallPortFilter -Protocol TCP -ErrorAction SilentlyContinue | 
                     Where-Object {$_.LocalPort -eq $port} |
                     Get-NetFirewallRule -ErrorAction SilentlyContinue
            
            $inbound = $rules | Where-Object {$_.Direction -eq 'Inbound'}
            $blocked = $inbound | Where-Object {$_.Action -eq 'Block' -and $_.Enabled -eq 'True'}
            $allowed = $inbound | Where-Object {$_.Action -eq 'Allow' -and $_.Enabled -eq 'True'}
            
            if ($blocked) {
                Write-Host "  [BLOCKED] Inbound traffic blocked by firewall" -ForegroundColor $Red
            } elseif ($allowed) {
                Write-Host "  [ALLOWED] Inbound traffic allowed" -ForegroundColor $Green
            } else {
                Write-Host "  [DEFAULT] No specific rules (default policy applies)" -ForegroundColor $Yellow
            }
        } catch {
            Write-Host "  [ERROR] Could not check firewall (Admin rights required?)" -ForegroundColor $Red
        }
        
        Write-LogEntry -Message "Port $port checked" -FilePath $LogFile
    }
    
    Write-LogEntry -Message "Local port check completed" -FilePath $LogFile
}

# Mode 10: SMTP Email Test
function Send-TestEmail {
    param([string]$LogFile)
    
    Write-Host "  SMTP Email Test" -ForegroundColor $Cyan
    Write-Host ""
    Write-Host "  Enter SMTP configuration:" -ForegroundColor $White
    Write-Host ""
    
    Write-Host "  SMTP Server (e.g., smtp.gmail.com, smtp.office365.com):" -ForegroundColor $Gray
    $smtpServer = Read-Host "  > Server"
    
    Write-Host ""
    Write-Host "  Common ports: 25 (SMTP), 465 (SSL), 587 (STARTTLS)" -ForegroundColor $Gray
    $smtpPort = Read-Host "  > Port (default: 587)"
    if ([string]::IsNullOrWhiteSpace($smtpPort)) { $smtpPort = 587 }
    $smtpPort = [int]$smtpPort
    
    Write-Host ""
    Write-Host "  Encryption:" -ForegroundColor $Gray
    Write-Host "    1 - None"
    Write-Host "    2 - SSL/TLS (port 465)"
    Write-Host "    3 - STARTTLS (port 587)"
    $encChoice = Read-Host "  > Choice (1-3, default: 3)"
    if ([string]::IsNullOrWhiteSpace($encChoice)) { $encChoice = "3" }
    
    $useSSL = $false
    $encryptionType = "None"
    switch ($encChoice) {
        "1" { $useSSL = $false; $encryptionType = "None" }
        "2" { $useSSL = $true; $encryptionType = "SSL/TLS" }
        "3" { $useSSL = $true; $encryptionType = "STARTTLS" }
    }
    
    Write-Host ""
    $fromEmail = Read-Host "  > From Email"
    
    Write-Host ""
    Write-Host "  Authentication:" -ForegroundColor $Gray
    $username = Read-Host "  > Username (usually email address)"
    $passwordSecure = Read-Host "  > Password" -AsSecureString
    
    Write-Host ""
    $toEmail = Read-Host "  > To Email (recipient)"
    
    Write-Host ""
    $subject = Read-Host "  > Subject (default: Test Email from PingPortTester)"
    if ([string]::IsNullOrWhiteSpace($subject)) { $subject = "Test Email from PingPortTester" }
    
    $body = Read-Host "  > Body (default: This is a test email)"
    if ([string]::IsNullOrWhiteSpace($body)) { $body = "This is a test email sent from PingPortTester.`n`nTimestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`nServer: $smtpServer`nPort: $smtpPort`nEncryption: $encryptionType" }
    
    Write-Host ""
    Show-Separator
    Write-Host "  Configuration Summary:" -ForegroundColor $Cyan
    Write-Host "    Server:     $smtpServer" -ForegroundColor $White
    Write-Host "    Port:       $smtpPort" -ForegroundColor $White
    Write-Host "    Encryption: $encryptionType" -ForegroundColor $White
    Write-Host "    From:       $fromEmail" -ForegroundColor $White
    Write-Host "    To:         $toEmail" -ForegroundColor $White
    Write-Host "    Subject:    $subject" -ForegroundColor $White
    Show-Separator
    Write-Host ""
    
    $confirm = Read-Host "  Send email? (y/n)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "  [CANCELLED] Email not sent" -ForegroundColor $Yellow
        return
    }
    
    Write-Host ""
    Write-Host "  Sending email..." -ForegroundColor $Cyan
    
    Write-LogEntry -Message "SMTP Test: $smtpServer`:$smtpPort ($encryptionType) From: $fromEmail To: $toEmail" -FilePath $LogFile
    
    try {
        $credential = New-Object System.Management.Automation.PSCredential($username, $passwordSecure)
        
        $mailParams = @{
            SmtpServer = $smtpServer
            Port = $smtpPort
            UseSsl = $useSSL
            Credential = $credential
            From = $fromEmail
            To = $toEmail
            Subject = $subject
            Body = $body
        }
        
        Send-MailMessage @mailParams -ErrorAction Stop
        
        Write-Host ""
        Write-Host "  [SUCCESS] Email sent successfully!" -ForegroundColor $Green
        Write-Host ""
        Write-Host "  Details:" -ForegroundColor $Cyan
        Write-Host "    Server:     $smtpServer`:$smtpPort" -ForegroundColor $White
        Write-Host "    Encryption: $encryptionType" -ForegroundColor $White
        Write-Host "    From:       $fromEmail" -ForegroundColor $White
        Write-Host "    To:         $toEmail" -ForegroundColor $White
        
        Write-LogEntry -Message "SMTP Test: SUCCESS - Email sent to $toEmail" -FilePath $LogFile
        
    } catch {
        Write-Host ""
        Write-Host "  [FAILED] Could not send email" -ForegroundColor $Red
        Write-Host ""
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor $Red
        Write-Host ""
        Write-Host "  Troubleshooting tips:" -ForegroundColor $Yellow
        Write-Host "    - Verify SMTP server and port are correct" -ForegroundColor $Gray
        Write-Host "    - Check username and password" -ForegroundColor $Gray
        Write-Host "    - Gmail: Enable 'Less secure apps' or use App Password" -ForegroundColor $Gray
        Write-Host "    - Office365: May require App Password with MFA" -ForegroundColor $Gray
        Write-Host "    - Check if firewall blocks outbound SMTP" -ForegroundColor $Gray
        
        Write-LogEntry -Message "SMTP Test: FAILED - $($_.Exception.Message)" -FilePath $LogFile
    }
}

# Mode 11: Public IP Check
function Get-PublicIPInfo {
    param([string]$LogFile)
    
    Write-Host "  Fetching public IP information..." -ForegroundColor $Cyan
    Write-Host ""
    
    Write-LogEntry -Message "Public IP check started" -FilePath $LogFile
    
    $ipServices = @(
        @{Name="ipify"; Url="https://api.ipify.org?format=json"; JsonPath="ip"},
        @{Name="ipinfo.io"; Url="https://ipinfo.io/json"; JsonPath="ip"},
        @{Name="ip-api.com"; Url="http://ip-api.com/json"; JsonPath="query"}
    )
    
    $publicIP = $null
    
    foreach ($service in $ipServices) {
        try {
            $response = Invoke-RestMethod -Uri $service.Url -TimeoutSec 10 -ErrorAction Stop
            $ip = $response.($service.JsonPath)
            if ($ip) {
                $publicIP = $ip
                break
            }
        } catch {
            continue
        }
    }
    
    if (-not $publicIP) {
        Write-Host "  [ERROR] Could not determine public IP" -ForegroundColor $Red
        Write-LogEntry -Message "Public IP check: FAILED" -FilePath $LogFile
        return
    }
    
    Write-Host "  Public IP Address:" -ForegroundColor $Cyan
    Write-Host "  $publicIP" -ForegroundColor $Green
    Write-Host ""
    
    try {
        $details = Invoke-RestMethod -Uri "https://ipinfo.io/$publicIP/json" -TimeoutSec 10 -ErrorAction Stop
        
        Show-Separator
        Write-Host "  Location Information:" -ForegroundColor $Cyan
        Show-Separator
        
        if ($details.city) { Write-Host "    City:         $($details.city)" -ForegroundColor $White }
        if ($details.region) { Write-Host "    Region:       $($details.region)" -ForegroundColor $White }
        if ($details.country) { Write-Host "    Country:      $($details.country)" -ForegroundColor $White }
        if ($details.loc) { Write-Host "    Coordinates:  $($details.loc)" -ForegroundColor $White }
        if ($details.postal) { Write-Host "    Postal Code:  $($details.postal)" -ForegroundColor $White }
        if ($details.timezone) { Write-Host "    Timezone:     $($details.timezone)" -ForegroundColor $White }
        
        Write-Host ""
        Show-Separator
        Write-Host "  Network Information:" -ForegroundColor $Cyan
        Show-Separator
        
        if ($details.org) { Write-Host "    ISP/Org:      $($details.org)" -ForegroundColor $White }
        if ($details.hostname) { Write-Host "    Hostname:     $($details.hostname)" -ForegroundColor $White }
        
        Write-LogEntry -Message "Public IP: $publicIP | Location: $($details.city), $($details.region), $($details.country) | ISP: $($details.org)" -FilePath $LogFile
        
    } catch {
        Write-Host "  [INFO] Could not fetch detailed location info" -ForegroundColor $Yellow
        Write-LogEntry -Message "Public IP: $publicIP (no details)" -FilePath $LogFile
    }
    
    Write-Host ""
    Show-Separator
    Write-Host "  IPv6 Check:" -ForegroundColor $Cyan
    Show-Separator
    
    try {
        $ipv6 = Invoke-RestMethod -Uri "https://api64.ipify.org?format=json" -TimeoutSec 5 -ErrorAction Stop
        if ($ipv6.ip -and $ipv6.ip -ne $publicIP) {
            Write-Host "    IPv6 Address: $($ipv6.ip)" -ForegroundColor $Green
            Write-LogEntry -Message "IPv6: $($ipv6.ip)" -FilePath $LogFile
        } else {
            Write-Host "    No IPv6 connectivity or same as IPv4" -ForegroundColor $Yellow
        }
    } catch {
        Write-Host "    No IPv6 connectivity detected" -ForegroundColor $Yellow
    }
    
    Write-LogEntry -Message "Public IP check completed" -FilePath $LogFile
}

function Show-Stats {
    param([int]$Total, [int]$Failed, [double]$AvgLatency, [bool]$ShowLatency)
    
    $success = $Total - $Failed
    $rate = if ($Total -gt 0) { [math]::Round(($success / $Total) * 100, 1) } else { 0 }
    
    $rateColor = if ($rate -ge 95) { $Green } elseif ($rate -ge 80) { $Yellow } else { $Red }
    
    Write-Host "  [STATS] Total: $Total | Success: $success | Failed: $Failed | Rate: " -NoNewline
    Write-Host "$rate%" -ForegroundColor $rateColor
    
    if ($ShowLatency -and $AvgLatency -gt 0) {
        $latColor = if ($AvgLatency -lt 50) { $Green } elseif ($AvgLatency -lt 150) { $Yellow } else { $Red }
        Write-Host "  [LATENCY] Avg: " -NoNewline
        Write-Host "$([math]::Round($AvgLatency, 1))ms" -ForegroundColor $latColor
    }
}

function Show-Menu {
    Clear-Host
    Show-Header "NETWORK CONNECTIVITY TESTING TOOL"
    
    Write-Host "  Select Mode:" -ForegroundColor $Cyan
    Write-Host ""
    Write-Host "  1  - ICMP Ping            Continuous ping monitoring" -ForegroundColor $White
    Write-Host "  2  - TCP Port Test        Test single port with latency" -ForegroundColor $White
    Write-Host "  3  - UDP Port Test        Test UDP port" -ForegroundColor $White
    Write-Host "  4  - Port Range Scan      Scan range of ports" -ForegroundColor $White
    Write-Host "  5  - Traceroute           Trace network path" -ForegroundColor $White
    Write-Host "  6  - DNS Lookup           Query DNS records" -ForegroundColor $White
    Write-Host "  7  - Bandwidth Test       Test download speed" -ForegroundColor $White
    Write-Host "  8  - External Port Check  Check if ports reachable from internet" -ForegroundColor $White
    Write-Host "  9  - Local Blocked Ports  Check firewall and listening services" -ForegroundColor $White
    Write-Host "  10 - SMTP Email Test      Send test email via SMTP" -ForegroundColor $White
    Write-Host "  11 - Public IP Info       Show public IP and location" -ForegroundColor $White
    Write-Host ""
    Write-Host "  0  - Exit" -ForegroundColor $Red
    Write-Host ""
    Show-Separator
    Write-Host ""
    
    do {
        $choice = Read-Host "  > Enter choice (0-11)"
    } while ($choice -notmatch '^([0-9]|1[01])$')
    
    return $choice
}

# ============================================================================
# MAIN
# ============================================================================

if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType File -Force | Out-Null
}

while ($true) {
    $mode = Show-Menu
    
    if ($mode -eq '0') {
        Write-Host ""
        Write-Host "  [SAVED] Log: $LogPath" -ForegroundColor $Cyan
        Write-Host "  [BYE] Thank you for using Network Testing Tool!" -ForegroundColor $Magenta
        Write-Host ""
        break
    }

    switch ($mode) {
        '1' {
            Write-Host ""
            $target = Read-Host "  > Target host"
            $interval = Read-Host "  > Interval seconds (default: 5)"
            if ([string]::IsNullOrWhiteSpace($interval)) { $interval = 5 }
            
            Clear-Host
            Show-Header "PING MONITORING - $target"
            Write-Host "  Press Ctrl+C to stop and return to menu" -ForegroundColor $Yellow
            Write-Host ""
            
            Write-LogEntry -Message "Ping monitoring started: $target" -FilePath $LogPath
            $total = 0; $failed = 0
            
            try {
                while ($true) {
                    $total++
                    Test-LogSize -LogFilePath $LogPath
                    if (-not (Test-Ping -Target $target -LogFile $LogPath)) { $failed++ }
                    Show-Stats -Total $total -Failed $failed -AvgLatency 0 -ShowLatency $false
                    Write-Host ""
                    Start-Sleep -Seconds $interval
                }
            } catch {
                Write-LogEntry -Message "Ping monitoring stopped" -FilePath $LogPath
            }
        }
        
        '2' {
            Write-Host ""
            $target = Read-Host "  > Target host"
            Write-Host "  Common: HTTP(80) HTTPS(443) SSH(22) RDP(3389)" -ForegroundColor $Gray
            $port = [int](Read-Host "  > Port")
            $interval = Read-Host "  > Interval seconds (default: 5)"
            if ([string]::IsNullOrWhiteSpace($interval)) { $interval = 5 }
            
            Clear-Host
            Show-Header "TCP PORT TEST - ${target}:${port}"
            Write-Host "  Press Ctrl+C to stop and return to menu" -ForegroundColor $Yellow
            Write-Host ""
            
            Write-LogEntry -Message "TCP port test started: ${target}:${port}" -FilePath $LogPath
            $total = 0; $failed = 0; $latencies = @()
            
            try {
                while ($true) {
                    $total++
                    Test-LogSize -LogFilePath $LogPath
                    $result = Test-TCPPort -Target $target -Port $port -LogFile $LogPath
                    if (-not $result.Success) { $failed++ }
                    elseif ($result.Latency) { $latencies += $result.Latency }
                    
                    $avg = if ($latencies.Count -gt 0) { ($latencies | Measure-Object -Average).Average } else { 0 }
                    Show-Stats -Total $total -Failed $failed -AvgLatency $avg -ShowLatency ($latencies.Count -gt 0)
                    Write-Host ""
                    Start-Sleep -Seconds $interval
                }
            } catch {
                Write-LogEntry -Message "TCP port test stopped" -FilePath $LogPath
            }
        }
        
        '3' {
            Write-Host ""
            $target = Read-Host "  > Target host"
            Write-Host "  Common: DNS(53) DHCP(67) NTP(123) SNMP(161)" -ForegroundColor $Gray
            $port = [int](Read-Host "  > Port")
            $interval = Read-Host "  > Interval seconds (default: 5)"
            if ([string]::IsNullOrWhiteSpace($interval)) { $interval = 5 }
            
            Clear-Host
            Show-Header "UDP PORT TEST - ${target}:${port}"
            Write-Host "  Press Ctrl+C to stop and return to menu" -ForegroundColor $Yellow
            Write-Host ""
            
            Write-LogEntry -Message "UDP port test started: ${target}:${port}" -FilePath $LogPath
            $total = 0; $failed = 0
            
            try {
                while ($true) {
                    $total++
                    Test-LogSize -LogFilePath $LogPath
                    $result = Test-UDPPort -Target $target -Port $port -LogFile $LogPath
                    if (-not $result.Success) { $failed++ }
                    Show-Stats -Total $total -Failed $failed -AvgLatency 0 -ShowLatency $false
                    Write-Host ""
                    Start-Sleep -Seconds $interval
                }
            } catch {
                Write-LogEntry -Message "UDP port test stopped" -FilePath $LogPath
            }
        }
        
        '4' {
            Write-Host ""
            $target = Read-Host "  > Target host"
            $startPort = [int](Read-Host "  > Start port")
            $endPort = [int](Read-Host "  > End port")
            Write-Host "  1 - TCP" -ForegroundColor $White
            Write-Host "  2 - UDP" -ForegroundColor $White
            $proto = Read-Host "  > Protocol (1 or 2)"
            $protocol = if ($proto -eq '2') { "UDP" } else { "TCP" }
            
            Clear-Host
            Show-Header "PORT SCAN - $target"
            
            Invoke-PortScan -Target $target -StartPort $startPort -EndPort $endPort -Protocol $protocol -LogFile $LogPath
            
            Write-Host ""
            Read-Host "  Press Enter to return to menu"
        }
        
        '5' {
            Write-Host ""
            $target = Read-Host "  > Target host"
            $maxHops = Read-Host "  > Max hops (default: 30)"
            if ([string]::IsNullOrWhiteSpace($maxHops)) { $maxHops = 30 }
            
            Clear-Host
            Show-Header "TRACEROUTE - $target"
            
            Invoke-Traceroute -Target $target -MaxHops $maxHops -LogFile $LogPath
            
            Write-Host ""
            Read-Host "  Press Enter to return to menu"
        }
        
        '6' {
            Write-Host ""
            $domain = Read-Host "  > Domain name"
            
            Clear-Host
            Show-Header "DNS LOOKUP - $domain"
            
            Invoke-DNSLookup -Domain $domain -LogFile $LogPath
            
            Write-Host ""
            Read-Host "  Press Enter to return to menu"
        }
        
        '7' {
            Clear-Host
            Show-Header "BANDWIDTH TEST"
            
            Test-Bandwidth -LogFile $LogPath
            
            Write-Host ""
            Read-Host "  Press Enter to return to menu"
        }
        
        '8' {
            Write-Host ""
            $portsInput = Read-Host "  > Ports to check (comma-separated, e.g., 80,443,22)"
            $ports = $portsInput.Split(',') | ForEach-Object { [int]$_.Trim() }
            
            Clear-Host
            Show-Header "EXTERNAL PORT CHECK"
            
            Test-ExternalPort -Ports $ports -LogFile $LogPath
            
            Write-Host ""
            Read-Host "  Press Enter to return to menu"
        }
        
        '9' {
            Write-Host ""
            Write-Host "  Common: HTTP(80) HTTPS(443) SSH(22) RDP(3389) SMB(445)" -ForegroundColor $Gray
            $portsInput = Read-Host "  > Ports to check (comma-separated)"
            $ports = $portsInput.Split(',') | ForEach-Object { [int]$_.Trim() }
            
            Clear-Host
            Show-Header "LOCAL BLOCKED PORTS CHECK"
            
            Test-LocalPorts -Ports $ports -LogFile $LogPath
            
            Write-Host ""
            Read-Host "  Press Enter to return to menu"
        }
        
        '10' {
            Clear-Host
            Show-Header "SMTP EMAIL TEST"
            
            Send-TestEmail -LogFile $LogPath
            
            Write-Host ""
            Read-Host "  Press Enter to return to menu"
        }
        
        '11' {
            Clear-Host
            Show-Header "PUBLIC IP INFORMATION"
            
            Get-PublicIPInfo -LogFile $LogPath
            
            Write-Host ""
            Read-Host "  Press Enter to return to menu"
        }
    }
}
