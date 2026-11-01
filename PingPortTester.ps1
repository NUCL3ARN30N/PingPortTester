<#
.SYNOPSIS
    PingPortTester - network connectivity toolkit for Windows (PowerShell 5.1+ / 7+).
.DESCRIPTION
    Interactive terminal UI for ping / packet-loss analysis, TCP & UDP port tests,
    port scanning, traceroute & MTR path analysis (ASN + geo), DNS, bandwidth,
    web performance, SSL/TLS inspection, VPN / proxy / leak tests, local firewall
    inspection and SMTP testing.

    Run directly:   iex (irm ppt.genius-space.org/PingPortTester.ps1)
    With options:   & ([scriptblock]::Create((irm ppt.genius-space.org/PingPortTester.ps1))) -Ascii
.PARAMETER Ascii
    Use plain ASCII instead of Unicode box/graph characters.
.PARAMETER NoColor
    Disable colours.
.PARAMETER NoLog
    Disable logging.
.PARAMETER LogPath
    Log file location (default .\NetworkTest.log, falls back to %TEMP%).
.PARAMETER TimeoutSec
    Default network timeout in seconds.
.NOTES
    Copyright (C) NUCL3ARN30N - GPLv3
    https://github.com/NUCL3ARN30N/PingPortTester
#>
param(
    [switch]$Ascii,
    [switch]$NoColor,
    [switch]$NoLog,
    [string]$LogPath = ".\NetworkTest.log",
    [int]$TimeoutSec = 3,
    [switch]$Version
)

$script:PPTVersion = "5.0.0"
if ($Version) { "PingPortTester $script:PPTVersion"; return }

# ============================================================================
#  SETTINGS / STATE
# ============================================================================
$script:LogEnabled = -not $NoLog
$script:LogFile = $LogPath
$script:MaxLogBytes = 20MB
$script:TimeoutMs = [Math]::Max(1, $TimeoutSec) * 1000
$script:UseColor = -not $NoColor
$script:UseUnicode = -not $Ascii
$script:IsConsole = $true
$script:CurlExe = $null

# Modern TLS for Windows PowerShell 5.1 (defaults to SSL3/TLS1.0 on older .NET)
try {
    $proto = [Net.SecurityProtocolType]::Tls12
    try { $proto = $proto -bor [Net.SecurityProtocolType]12288 } catch { }
    [Net.ServicePointManager]::SecurityProtocol = $proto
} catch { }

# ============================================================================
#  UI TOOLKIT
# ============================================================================
function Initialize-UI {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    try { $null = [Console]::KeyAvailable } catch { $script:IsConsole = $false }
    if ($script:UseUnicode) {
        $c = { param($code) [string][char]$code }
        $script:G = @{
            H = & $c 0x2500; V = & $c 0x2502; TL = & $c 0x256D; TR = & $c 0x256E; BL = & $c 0x2570; BR = & $c 0x256F
            LT = & $c 0x251C; RT = & $c 0x2524; OK = & $c 0x2714; FAIL = & $c 0x2718; WARN = & $c 0x25B2; INFO = & $c 0x25CF
            ARROW = & $c 0x203A; PTR = & $c 0x25B6; FULL = & $c 0x2588; EMPTY = & $c 0x2591; DOT = & $c 0x00B7; RIGHT = & $c 0x2192
            UP = & $c 0x2191; DOWN = & $c 0x2193
        }
        $script:Spark = @(0x2581..0x2588 | ForEach-Object { [string][char]$_ })
        $script:Spin = @(0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F | ForEach-Object { [string][char]$_ })
    } else {
        $script:G = @{
            H = '-'; V = '|'; TL = '+'; TR = '+'; BL = '+'; BR = '+'; LT = '+'; RT = '+'; OK = '+'; FAIL = 'x'; WARN = '!'; INFO = '*'
            ARROW = '>'; PTR = '>'; FULL = '#'; EMPTY = '.'; DOT = '.'; RIGHT = '->'; UP = 'Up'; DOWN = 'Down'
        }
        $script:Spark = @('_', '.', '-', '-', '=', '=', '^', '^')
        $script:Spin = @('|', '/', '-', '\')
    }
    Update-TermSize
}

function Update-TermSize {
    $w = 80; $h = 40
    try { $w = $Host.UI.RawUI.WindowSize.Width; $h = $Host.UI.RawUI.WindowSize.Height } catch { }
    if (-not $w -or $w -lt 20) { $w = 80 }
    if (-not $h -or $h -lt 10) { $h = 40 }
    $script:TermW = $w; $script:TermH = $h
    $script:UIW = [Math]::Max(50, [Math]::Min(92, $w - 4))
}

# Write text with optional colours (respects -NoColor)
function W {
    param([string]$Text, [string]$Fg = '', [switch]$NoNewline, [string]$Bg = '')
    $p = @{ Object = $Text; NoNewline = $NoNewline }
    if ($script:UseColor) {
        if ($Fg) { $p.ForegroundColor = $Fg }
        if ($Bg) { $p.BackgroundColor = $Bg }
    }
    Write-Host @p
}

# Write-Segs 'text','Color','text2','' ...   (pairs of text + colour)
function Write-Segs {
    param([object[]]$Segs, [switch]$NoNewline)
    for ($i = 0; $i -lt $Segs.Count; $i += 2) {
        $fg = if ($i + 1 -lt $Segs.Count) { [string]$Segs[$i + 1] } else { '' }
        W ([string]$Segs[$i]) $fg -NoNewline
    }
    if (-not $NoNewline) { Write-Host "" }
}

function Get-SegLen { param([object[]]$Segs) $n = 0; for ($i = 0; $i -lt $Segs.Count; $i += 2) { $n += ([string]$Segs[$i]).Length }; $n }

function Limit-Text { param([string]$Text, [int]$Max) if ($Text.Length -gt $Max) { $Text.Substring(0, [Math]::Max(0, $Max - 3)) + '...' } else { $Text } }

function Write-Logo {
    if ($script:UseUnicode) {
        $lines = @(
            ('  ' + (-join (@(0x250F,0x2501,0x2513,0x257B,0x250F,0x2513,0x257B,0x250F,0x2501,0x2578,0x250F,0x2501,0x2513,0x250F,0x2501,0x2513,0x250F,0x2501,0x2513,0x257A,0x2533,0x2578,0x257A,0x2533,0x2578,0x250F,0x2501,0x2578,0x250F,0x2501,0x2513,0x257A,0x2533,0x2578,0x250F,0x2501,0x2578,0x250F,0x2501,0x2513) | ForEach-Object { [char]$_ }))),
            ('  ' + (-join (@(0x2523,0x2501,0x251B,0x2503,0x2503,0x2517,0x252B,0x2503,0x257A,0x2513,0x2523,0x2501,0x251B,0x2503,0x20,0x2503,0x2523,0x2533,0x251B,0x20,0x2503,0x20,0x20,0x2503,0x20,0x2523,0x2578,0x20,0x2517,0x2501,0x2513,0x20,0x2503,0x20,0x2523,0x2578,0x20,0x2523,0x2533,0x251B) | ForEach-Object { [char]$_ }))),
            ('  ' + (-join (@(0x2579,0x20,0x20,0x2579,0x2579,0x20,0x2579,0x2517,0x2501,0x251B,0x2579,0x20,0x20,0x2517,0x2501,0x251B,0x2579,0x2517,0x2578,0x20,0x2579,0x20,0x20,0x2579,0x20,0x2517,0x2501,0x2578,0x2517,0x2501,0x251B,0x20,0x2579,0x20,0x2517,0x2501,0x2578,0x2579,0x2517,0x2578) | ForEach-Object { [char]$_ })))
        )
    } else {
        $lines = @(
            '   ___ _           ___         _  _____         _',
            '  | _ (_)_ _  __ _| _ \___ _ _| ||_   _|__ ___| |_ ___ _ _',
            "  |  _/ | ' \/ _`` |  _/ _ \ '_|  _|| |/ -_|_-<  _/ -_) '_|"
        )
    }
    W $lines[0] 'Cyan'; W $lines[1] 'Cyan'; W $lines[2] 'Magenta'
}

function Show-Header {
    param([string]$Subtitle)
    Clear-Host
    Update-TermSize
    Write-Logo
    W ("  v{0} {1} {2}" -f $script:PPTVersion, $script:G.DOT, $Subtitle) 'DarkGray'
    Write-Host ""
}

function Write-BoxTop {
    param([string]$Title = '')
    $g = $script:G
    if ($Title) {
        W ("  " + $g.TL + $g.H + " ") 'DarkGray' -NoNewline
        W $Title 'White' -NoNewline
        W (" " + ($g.H * [Math]::Max(0, $script:UIW - $Title.Length - 5)) + $g.TR) 'DarkGray'
    } else {
        W ("  " + $g.TL + ($g.H * ($script:UIW - 2)) + $g.TR) 'DarkGray'
    }
}
function Write-BoxLine {
    param([object[]]$Segs)
    $len = Get-SegLen $Segs
    W ("  " + $script:G.V + " ") 'DarkGray' -NoNewline
    Write-Segs $Segs -NoNewline
    W ((' ' * [Math]::Max(0, $script:UIW - 4 - $len)) + " " + $script:G.V) 'DarkGray'
}
function Write-BoxSep    { W ("  " + $script:G.LT + ($script:G.H * ($script:UIW - 2)) + $script:G.RT) 'DarkGray' }
function Write-BoxBottom { W ("  " + $script:G.BL + ($script:G.H * ($script:UIW - 2)) + $script:G.BR) 'DarkGray' }

function Write-Section {
    param([string]$Title)
    Write-Host ""
    W ("  " + $script:G.H + $script:G.H + " ") 'Cyan' -NoNewline
    W $Title 'White' -NoNewline
    W (" " + ($script:G.H * [Math]::Max(0, $script:UIW - $Title.Length - 4))) 'DarkGray'
}

function Write-KV {
    param([string]$Key, [string]$Value, [string]$Color = '')
    W ("    {0,-18} " -f $Key) 'DarkGray' -NoNewline
    W $Value $Color
}

function Write-Ok   { param([string]$m) W ("  " + $script:G.OK + " ") 'Green' -NoNewline; W $m }
function Write-Fail { param([string]$m) W ("  " + $script:G.FAIL + " ") 'Red' -NoNewline; W $m }
function Write-Warn { param([string]$m) W ("  " + $script:G.WARN + " ") 'Yellow' -NoNewline; W $m }
function Write-Info { param([string]$m) W ("  " + $script:G.INFO + " ") 'Cyan' -NoNewline; W $m }
function Write-Note { param([string]$m) W ("  " + $m) 'DarkGray' }

function Get-LatColor { param([double]$ms) if ($ms -lt 50) { 'Green' } elseif ($ms -lt 150) { 'Yellow' } else { 'Red' } }

function Write-Bar {
    param([double]$Value, [double]$Max, [int]$Width, [string]$Color = 'Cyan', [switch]$NoNewline)
    if ($Max -le 0) { $Max = 1 }
    $f = [int][Math]::Round($Value / $Max * $Width)
    $f = [Math]::Max(0, [Math]::Min($Width, $f))
    W ($script:G.FULL * $f) $Color -NoNewline
    W ($script:G.EMPTY * ($Width - $f)) 'DarkGray' -NoNewline:$NoNewline
}

function Write-Sparkline {
    param([object[]]$Values, [switch]$NoNewline)
    $nums = @($Values | Where-Object { $_ -ne $null -and $_ -ge 0 })
    $max = 1; if ($nums.Count) { $max = [Math]::Max(1, ($nums | Measure-Object -Maximum).Maximum) }
    foreach ($v in $Values) {
        if ($v -eq $null -or $v -lt 0) { W $script:G.FAIL 'Red' -NoNewline; continue }
        $i = [int][Math]::Round($v / $max * 7)
        W $script:Spark[[Math]::Min(7, [Math]::Max(0, $i))] (Get-LatColor $v) -NoNewline
    }
    if (-not $NoNewline) { Write-Host "" }
}

function Write-Progress2 {
    param([int]$Cur, [int]$Total, [string]$Label)
    if ($Total -le 0) { $Total = 1 }
    $pct = [int]($Cur * 100 / $Total)
    W ("`r  ") -NoNewline
    Write-Bar $Cur $Total 30 'Cyan' -NoNewline
    W (" {0,3}% " -f $pct) -NoNewline
    $pad = [Math]::Max(0, $script:TermW - 45 - $Label.Length)
    W ($Label + (' ' * $pad)) 'DarkGray' -NoNewline
}
function Clear-Line { W ("`r" + (' ' * [Math]::Max(1, $script:TermW - 1)) + "`r") -NoNewline }

# ---------------------------------------------------------------------------
#  Input
# ---------------------------------------------------------------------------
function Read-Input {
    param([string]$Prompt, [string]$Default = '')
    W ("  " + $script:G.ARROW + " ") 'Cyan' -NoNewline
    W $Prompt -NoNewline
    if ($Default) { W (" [$Default]") 'DarkGray' -NoNewline }
    if ($script:IsConsole) { W ": " -NoNewline; $a = [Console]::ReadLine() } else { $a = Read-Host " " }
    if ([string]::IsNullOrWhiteSpace($a)) { $a = $Default }
    return $a.Trim()
}
function Read-Required {
    param([string]$Prompt, [string]$Default = '')
    while ($true) {
        $v = Read-Input $Prompt $Default
        if ($v) { return $v }
        Write-Fail "A value is required"
    }
}
function Read-Int {
    param([string]$Prompt, [int]$Default, [int]$Min, [int]$Max)
    while ($true) {
        $v = Read-Input $Prompt "$Default"
        $n = 0
        if ([int]::TryParse($v, [ref]$n) -and $n -ge $Min -and $n -le $Max) { return $n }
        Write-Fail "Enter a whole number between $Min and $Max"
    }
}
function Read-Number {
    param([string]$Prompt, [double]$Default, [double]$Min)
    while ($true) {
        $v = Read-Input $Prompt ([string]$Default)
        $n = 0.0
        if ([double]::TryParse($v.Replace(',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n) -and $n -ge $Min) { return $n }
        Write-Fail "Enter a number >= $Min"
    }
}
function Read-YesNo {
    param([string]$Prompt, [string]$Default = 'n')
    $v = Read-Input "$Prompt (y/n)" $Default
    return ($v -match '^(y|yes)$')
}
function Read-Choice {
    param([string]$Title, [int]$Default, [string[]]$Options)
    W ("  " + $Title) 'White'
    for ($i = 0; $i -lt $Options.Count; $i++) {
        W ("    {0}  " -f ($i + 1)) 'Cyan' -NoNewline; W $Options[$i]
    }
    return (Read-Int "Choice" $Default 1 $Options.Count)
}

# Returns a key token: UP DOWN LEFT RIGHT HOME END ENTER ESC or the character
function Read-MenuKey {
    if (-not $script:IsConsole) {
        $v = Read-Host "  Selection"
        if ([string]::IsNullOrEmpty($v)) { return 'ENTER' }
        return $v.Substring(0, 1)
    }
    $k = [Console]::ReadKey($true)
    switch ($k.Key) {
        'UpArrow' { return 'UP' } 'DownArrow' { return 'DOWN' } 'LeftArrow' { return 'LEFT' } 'RightArrow' { return 'RIGHT' }
        'Home' { return 'HOME' } 'End' { return 'END' } 'Enter' { return 'ENTER' } 'Escape' { return 'ESC' }
        'PageUp' { return 'HOME' } 'PageDown' { return 'END' }
    }
    return [string]$k.KeyChar
}

function Wait-AnyKey {
    Write-Host ""
    W "  Press any key to return to the menu..." 'DarkGray' -NoNewline
    if ($script:IsConsole) {
        while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }
        $null = [Console]::ReadKey($true)
    } else { $null = Read-Host }
    Write-Host ""
}

# Sleep up to $Seconds, returning $true if Q / Esc / Ctrl+C was pressed.
function Wait-StopKey {
    param([double]$Seconds)
    $end = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        if ($script:IsConsole) {
            try {
                while ([Console]::KeyAvailable) {
                    $k = [Console]::ReadKey($true)
                    if ($k.Key -eq 'Q' -or $k.Key -eq 'Escape' -or ($k.Key -eq 'C' -and ($k.Modifiers -band [ConsoleModifiers]::Control))) { return $true }
                }
            } catch { }
        }
        Start-Sleep -Milliseconds 40
    } while ([DateTime]::UtcNow -lt $end)
    return $false
}

function Enter-MonitorMode { if ($script:IsConsole) { try { [Console]::TreatControlCAsInput = $true } catch { } } }
function Exit-MonitorMode  { if ($script:IsConsole) { try { [Console]::TreatControlCAsInput = $false } catch { } } }

# ============================================================================
#  LOGGING
# ============================================================================
function Initialize-Log {
    if (-not $script:LogEnabled) { return }
    try {
        Add-Content -Path $script:LogFile -Value $null -ErrorAction Stop
        $script:LogFile = (Resolve-Path $script:LogFile).ProviderPath
    } catch {
        $script:LogFile = Join-Path $env:TEMP "NetworkTest.log"
        try { Add-Content -Path $script:LogFile -Value $null -ErrorAction Stop } catch { $script:LogEnabled = $false }
    }
}
function Write-LogEntry {
    param([string]$Message)
    if (-not $script:LogEnabled) { return }
    try { Add-Content -Path $script:LogFile -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message) -ErrorAction Stop } catch { }
}
function Test-LogSize {
    if (-not $script:LogEnabled -or -not (Test-Path $script:LogFile)) { return }
    if ((Get-Item $script:LogFile).Length -ge $script:MaxLogBytes) {
        $zip = Join-Path (Split-Path $script:LogFile) ("NetworkTest_{0}.zip" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        try {
            Compress-Archive -Path $script:LogFile -DestinationPath $zip -Force
            Clear-Content $script:LogFile
            Write-Info "Log archived to $zip"
        } catch { }
    }
}

# ============================================================================
#  HELPERS
# ============================================================================
$script:Services = @{
    20 = 'FTP'; 21 = 'FTP'; 22 = 'SSH'; 23 = 'Telnet'; 25 = 'SMTP'; 53 = 'DNS'; 67 = 'DHCP'; 68 = 'DHCP'; 69 = 'TFTP'; 80 = 'HTTP'
    110 = 'POP3'; 111 = 'RPC'; 123 = 'NTP'; 135 = 'MS-RPC'; 137 = 'NetBIOS'; 138 = 'NetBIOS'; 139 = 'NetBIOS'; 143 = 'IMAP'
    161 = 'SNMP'; 162 = 'SNMP'; 389 = 'LDAP'; 443 = 'HTTPS'; 445 = 'SMB'; 465 = 'SMTPS'; 500 = 'IKE'; 514 = 'Syslog'
    587 = 'Submission'; 636 = 'LDAPS'; 853 = 'DoT'; 993 = 'IMAPS'; 995 = 'POP3S'; 1194 = 'OpenVPN'; 1433 = 'MSSQL'
    1521 = 'Oracle'; 1883 = 'MQTT'; 1900 = 'SSDP'; 2049 = 'NFS'; 3000 = 'Dev-HTTP'; 3306 = 'MySQL'; 3389 = 'RDP'
    4500 = 'IPsec-NAT'; 5060 = 'SIP'; 5061 = 'SIP-TLS'; 5353 = 'mDNS'; 5432 = 'PostgreSQL'; 5900 = 'VNC'; 5985 = 'WinRM'
    5986 = 'WinRM-TLS'; 6379 = 'Redis'; 8000 = 'HTTP-Alt'; 8080 = 'HTTP-Alt'; 8443 = 'HTTPS-Alt'; 8888 = 'HTTP-Alt'
    9000 = 'Portainer'; 9200 = 'Elasticsearch'; 11211 = 'Memcached'; 25565 = 'Minecraft'; 27017 = 'MongoDB'; 51820 = 'WireGuard'
}
function Get-ServiceName { param([int]$Port) if ($script:Services.ContainsKey($Port)) { $script:Services[$Port] } else { '' } }

$script:CommonPorts = '21,22,23,25,53,80,110,111,135,139,143,161,389,443,445,465,587,636,993,995,1194,1433,1521,1883,2049,3000,3306,3389,5060,5432,5900,5985,6379,8000,8080,8443,8888,9000,9200,11211,25565,27017,51820'

# "22,80,8000-8010,common" -> sorted unique int[]
function Expand-Ports {
    param([string]$Spec)
    $Spec = ($Spec -replace '\s', '') -replace 'common', $script:CommonPorts
    $set = New-Object 'System.Collections.Generic.SortedSet[int]'
    foreach ($part in $Spec.Split(',')) {
        if ($part -match '^(\d+)-(\d+)$') {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            if ($a -le $b) { for ($p = [Math]::Max(1, $a); $p -le [Math]::Min(65535, $b); $p++) { [void]$set.Add($p) } }
        } elseif ($part -match '^\d+$') {
            $p = [int]$part; if ($p -ge 1 -and $p -le 65535) { [void]$set.Add($p) }
        }
    }
    return , ([int[]]@($set))
}

function Test-PrivateIP {
    param([string]$Ip)
    return ($Ip -match '^(10\.|127\.|192\.168\.|169\.254\.|0\.|172\.(1[6-9]|2\d|3[01])\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.)' -or $Ip -match '^(fe80:|fc|fd|::1$)')
}

function Resolve-IPv4 {
    param([string]$Target)
    $ip = $null
    if ([Net.IPAddress]::TryParse($Target, [ref]$ip)) { return $Target }
    try {
        $a = [Net.Dns]::GetHostAddresses($Target) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
        if ($a) { return $a.IPAddressToString }
        $a = [Net.Dns]::GetHostAddresses($Target) | Select-Object -First 1
        if ($a) { return $a.IPAddressToString }
    } catch { }
    return $null
}

function Invoke-Http {
    param([string]$Url, [int]$TimeoutSec = 10, [string]$Method = 'GET', $Body = $null, [switch]$Raw)
    try {
        $p = @{ Uri = $Url; TimeoutSec = $TimeoutSec; Method = $Method; UserAgent = "PingPortTester/$script:PPTVersion"; ErrorAction = 'Stop' }
        if ($Body) { $p.Body = $Body }
        if ($Raw) { return (Invoke-WebRequest @p -UseBasicParsing).Content }
        return Invoke-RestMethod @p
    } catch { return $null }
}

function Get-PublicIP {
    foreach ($u in @('https://api.ipify.org', 'https://ifconfig.me/ip', 'https://icanhazip.com', 'https://ipv4.icanhazip.com')) {
        $r = Invoke-Http $u 6 -Raw
        if ($r) { $r = ([string]$r).Trim(); if ($r -match '^\d{1,3}(\.\d{1,3}){3}$') { return $r } }
    }
    return $null
}

# Geo / ASN for one or more IPs. Returns hashtable ip -> object(country, countryCode, regionName, city, lat, lon, timezone, isp, as, proxy, hosting)
function Get-GeoInfo {
    param([string[]]$Ips)
    $result = @{}
    $ips = @($Ips | Where-Object { $_ } | Select-Object -Unique)
    if (-not $ips.Count) { return $result }
    $fields = 'status,query,country,countryCode,regionName,city,lat,lon,timezone,isp,as,proxy,hosting'
    for ($i = 0; $i -lt $ips.Count; $i += 100) {
        $chunk = $ips[$i..([Math]::Min($i + 99, $ips.Count - 1))]
        $json = ConvertTo-Json @($chunk) -Compress
        $r = Invoke-Http "http://ip-api.com/batch?fields=$fields" 10 'POST' $json
        foreach ($e in @($r)) { if ($e -and $e.status -eq 'success') { $result[$e.query] = $e } }
    }
    foreach ($ip in $ips) {
        if (-not $result.ContainsKey($ip)) {
            $r = Invoke-Http "https://ipinfo.io/$ip/json" 6
            if ($r -and $r.country) {
                $lat = $null; $lon = $null
                if ($r.loc) { $lat, $lon = $r.loc.Split(',') }
                $result[$ip] = [pscustomobject]@{ query = $ip; country = $r.country; countryCode = $r.country; regionName = $r.region; city = $r.city
                    lat = $lat; lon = $lon; timezone = $r.timezone; isp = $r.org; as = $r.org; proxy = $false; hosting = $false }
            }
        }
    }
    return $result
}

function Get-Stats {
    param([double[]]$Values)
    $n = $Values.Count
    if ($n -eq 0) { return $null }
    $sorted = [double[]]($Values | Sort-Object)
    $avg = ($Values | Measure-Object -Average).Average
    $var = 0.0; foreach ($v in $Values) { $var += ($v - $avg) * ($v - $avg) }
    $jit = 0.0; for ($i = 1; $i -lt $n; $i++) { $jit += [Math]::Abs($Values[$i] - $Values[$i - 1]) }
    $pct = { param($p) $sorted[[int][Math]::Floor(($n - 1) * $p)] }
    return [pscustomobject]@{
        Count = $n; Min = $sorted[0]; Max = $sorted[$n - 1]; Avg = $avg; StdDev = [Math]::Sqrt($var / $n)
        Jitter = $(if ($n -gt 1) { $jit / ($n - 1) } else { 0 })
        P50 = & $pct 0.50; P90 = & $pct 0.90; P95 = & $pct 0.95; P99 = & $pct 0.99
    }
}

function Get-Mos {
    param([double]$Latency, [double]$Jitter, [double]$LossPct)
    $e = $Latency + 2 * $Jitter + 10
    $r = if ($e -lt 160) { 93.2 - $e / 40 } else { 93.2 - ($e - 120) / 10 }
    $r = [Math]::Max(0, [Math]::Min(100, $r - 2.5 * $LossPct))
    $mos = [Math]::Max(1, 1 + 0.035 * $r + 0.000007 * $r * ($r - 60) * (100 - $r))
    $q = if ($mos -ge 4.3) { 'Excellent' } elseif ($mos -ge 4.0) { 'Good' } elseif ($mos -ge 3.6) { 'Fair' } elseif ($mos -ge 3.1) { 'Poor' } else { 'Bad' }
    return [pscustomobject]@{ Mos = [Math]::Round($mos, 2); Quality = $q }
}

function Fmt { param([double]$v, [int]$d = 1) [Math]::Round($v, $d).ToString("F$d", [Globalization.CultureInfo]::InvariantCulture) }

# ============================================================================
#  NETWORK PRIMITIVES
# ============================================================================
function Send-Ping {
    param([string]$Target, [int]$TimeoutMs = $script:TimeoutMs, [int]$Ttl = 0)
    $p = New-Object System.Net.NetworkInformation.Ping
    try {
        if ($Ttl -gt 0) {
            $opt = New-Object System.Net.NetworkInformation.PingOptions($Ttl, $true)
            return $p.Send($Target, $TimeoutMs, (New-Object byte[] 32), $opt)
        }
        return $p.Send($Target, $TimeoutMs)
    } catch { return $null } finally { $p.Dispose() }
}

# Returns connect time in ms or -1
function Test-TcpConnect {
    param([string]$Target, [int]$Port, [int]$TimeoutMs = $script:TimeoutMs)
    $c = New-Object System.Net.Sockets.TcpClient
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $iar = $c.BeginConnect($Target, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            $c.EndConnect($iar)
            return [int]$sw.ElapsedMilliseconds
        }
    } catch { } finally { $c.Close() }
    return -1
}

function Get-UdpPayload {
    param([int]$Port)
    switch ($Port) {
        53   { return [byte[]](0xab,0xcd,0x01,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x02,0x00,0x01) }
        123  { $b = New-Object byte[] 48; $b[0] = 0x1b; return $b }
        161  { return [byte[]](0x30,0x26,0x02,0x01,0x01,0x04,0x06,0x70,0x75,0x62,0x6c,0x69,0x63,0xa0,0x19,0x02,0x04,0x00,0x00,0x00,0x01,0x02,0x01,0x00,0x02,0x01,0x00,0x30,0x0b,0x30,0x09,0x06,0x05,0x2b,0x06,0x01,0x02,0x01,0x05,0x00) }
        1900 { return [Text.Encoding]::ASCII.GetBytes("M-SEARCH * HTTP/1.1`r`nHOST:239.255.255.250:1900`r`nMAN:`"ssdp:discover`"`r`nMX:1`r`nST:ssdp:all`r`n`r`n") }
    }
    return [Text.Encoding]::ASCII.GetBytes("PingPortTester`r`n")
}

function Get-SocketError {
    param($Exception)
    $e = $Exception
    while ($e -and -not ($e -is [Net.Sockets.SocketException])) { $e = $e.InnerException }
    if ($e) { return [string]$e.SocketErrorCode }
    return ''
}

# open | closed | open|filtered | error
function Test-UdpPort {
    param([string]$Target, [int]$Port, [int]$TimeoutMs = $script:TimeoutMs)
    $u = New-Object System.Net.Sockets.UdpClient
    try {
        $u.Client.ReceiveTimeout = $TimeoutMs
        $u.Connect($Target, $Port)
        $data = Get-UdpPayload $Port
        [void]$u.Send($data, $data.Length)
        $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        [void]$u.Receive([ref]$ep)
        return 'open'
    } catch {
        $code = Get-SocketError $_.Exception
        if ($code -eq 'ConnectionReset' -or $code -eq 'ConnectionRefused') { return 'closed' }
        if ($code -eq 'TimedOut') { return 'open|filtered' }
        return 'error'
    } finally { $u.Close() }
}

function Get-DnsRecords {
    param([string]$Name, [string]$Type = 'A', [string]$Server = '')
    try {
        $p = @{ Name = $Name; Type = $Type; DnsOnly = $true; QuickTimeout = $true; ErrorAction = 'Stop' }
        if ($Server) { $p.Server = $Server }
        $r = Resolve-DnsName @p | Where-Object { $_.Section -eq 'Answer' -or -not $_.Section }
        $out = @()
        foreach ($x in $r) {
            switch ($Type) {
                'A'     { if ($x.Type -eq 'A') { $out += $x.IPAddress } }
                'AAAA'  { if ($x.Type -eq 'AAAA') { $out += $x.IPAddress } }
                'MX'    { if ($x.Type -eq 'MX') { $out += ("{0} {1}" -f $x.Preference, $x.NameExchange) } }
                'NS'    { if ($x.Type -eq 'NS') { $out += $x.NameHost } }
                'CNAME' { if ($x.Type -eq 'CNAME') { $out += $x.NameHost } }
                'TXT'   { if ($x.Type -eq 'TXT') { $out += ($x.Strings -join '') } }
                'SOA'   { if ($x.Type -eq 'SOA') { $out += ("{0} {1} serial {2}" -f $x.PrimaryServer, $x.NameAdministrator, $x.SerialNumber) } }
                'PTR'   { if ($x.Type -eq 'PTR') { $out += $x.NameHost } }
                default { $out += ($x | Out-String).Trim() }
            }
        }
        return , $out
    } catch { return , @() }
}

function Get-ReverseDns {
    param([string]$Ip)
    $r = Get-DnsRecords $Ip 'PTR'
    if ($r.Count) { return $r[0] }
    return ''
}

function Get-LocalNetInfo {
    $info = [ordered]@{ Hostname = [Environment]::MachineName; Interface = ''; LocalIP = ''; Gateway = ''; DNS = '' }
    try {
        $cfg = Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
        if ($cfg) {
            $info.Interface = $cfg.InterfaceAlias
            $info.LocalIP = ($cfg.IPv4Address | Select-Object -First 1).IPAddress
            $info.Gateway = ($cfg.IPv4DefaultGateway | Select-Object -First 1).NextHop
            $info.DNS = (($cfg.DNSServer | Where-Object { $_.AddressFamily -eq 2 }).ServerAddresses -join ' ')
        }
    } catch { }
    return $info
}

# ============================================================================
#  1. PING MONITOR
# ============================================================================
function Start-PingMonitor {
    Show-Header "ICMP Ping Monitor"
    $target = Read-Required "Target host" "1.1.1.1"
    $interval = Read-Number "Interval in seconds" 1 0.2
    Show-Header "Ping Monitor $($script:G.RIGHT) $target"
    Write-Note "Press Q, Esc or Ctrl+C to stop."
    Write-Host ""
    Write-LogEntry "Ping monitor started: $target"
    $total = 0; $failed = 0; $streak = 0
    $rtts = New-Object System.Collections.ArrayList
    $spark = New-Object System.Collections.ArrayList
    Enter-MonitorMode
    try {
        while ($true) {
            $total++; Test-LogSize
            $ts = Get-Date -Format 'HH:mm:ss'
            $r = Send-Ping $target
            Clear-Line
            if ($r -and $r.Status -eq 'Success') {
                $streak = 0
                $ms = [double]$r.RoundtripTime
                [void]$rtts.Add($ms); [void]$spark.Add($ms)
                Write-Segs ("  " + $script:G.OK + " "), 'Green', "$ts  ", 'DarkGray', ("reply from {0,-22}" -f $r.Address), '', ("{0,6} ms  " -f $ms), (Get-LatColor $ms) -NoNewline
                Write-Bar $ms 200 20 (Get-LatColor $ms)
            } else {
                $failed++; $streak++
                [void]$spark.Add(-1)
                $why = if ($r) { [string]$r.Status } else { 'unreachable / unknown host' }
                Write-Segs ("  " + $script:G.FAIL + " "), 'Red', "$ts  ", 'DarkGray', "no reply from $target ($why)", 'Red'
                Write-LogEntry "DROPPED - Ping to $target failed ($why)"
            }
            while ($spark.Count -gt 40) { $spark.RemoveAt(0) }
            $avg = '-'; $mn = '-'; $mx = '-'
            if ($rtts.Count) { $m = $rtts | Measure-Object -Average -Minimum -Maximum; $avg = Fmt $m.Average; $mn = $m.Minimum; $mx = $m.Maximum }
            Write-Segs ("  " + $script:G.V + " "), 'Cyan', ("sent {0}  lost {1} ({2}%)  min/avg/max {3}/{4}/{5} ms  " -f $total, $failed, (Fmt ($failed * 100.0 / $total)), $mn, $avg, $mx), '' -NoNewline
            Write-Sparkline $spark.ToArray() -NoNewline
            if ($streak -ge 3) { W ("  " + $script:G.WARN + " outage") 'Red' -NoNewline }
            if (Wait-StopKey $interval) { break }
        }
    } finally { Exit-MonitorMode }
    Write-Host ""; Write-Host ""
    Write-LogEntry "Ping monitor stopped: $target sent=$total lost=$failed"
    Write-Info "Stopped after $total probes."
    Wait-AnyKey
}

# ============================================================================
#  2. PACKET LOSS ANALYSIS (issue #1)
# ============================================================================
function Start-PacketLoss {
    Show-Header "Packet Loss & Jitter Analysis"
    $target = Read-Required "Target host" "1.1.1.1"
    $count = Read-Int "Number of packets" 100 10 10000
    $interval = Read-Number "Interval in seconds" 0.2 0.01
    Show-Header "Packet Loss Analysis $($script:G.RIGHT) $target"
    if (-not (Resolve-IPv4 $target)) { Write-Fail "Could not resolve $target"; Wait-AnyKey; return }
    Write-LogEntry "Packet loss analysis: $target count=$count interval=$interval"
    $seq = New-Object 'System.Collections.Generic.List[double]'      # -1 = lost
    $ok = New-Object 'System.Collections.Generic.List[double]'
    $p = New-Object System.Net.NetworkInformation.Ping
    $stopped = $false
    Enter-MonitorMode
    try {
        for ($i = 1; $i -le $count; $i++) {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $r = $null
            try { $r = $p.Send($target, $script:TimeoutMs) } catch { }
            if ($r -and $r.Status -eq 'Success') { $seq.Add([double]$r.RoundtripTime); $ok.Add([double]$r.RoundtripTime) } else { $seq.Add(-1) }
            Write-Progress2 $i $count ("seq {0}  received {1}  lost {2}" -f $i, $ok.Count, ($i - $ok.Count))
            $rest = $interval - $sw.Elapsed.TotalSeconds
            if (Wait-StopKey ([Math]::Max(0.01, $rest))) { $stopped = $true; break }
        }
    } finally { Exit-MonitorMode; $p.Dispose() }
    Clear-Line
    $sent = $seq.Count
    if ($sent -eq 0) { Write-Fail "No packets sent"; Wait-AnyKey; return }
    $lost = $sent - $ok.Count
    $loss = $lost * 100.0 / $sent
    $burst = 0; $cur = 0
    foreach ($v in $seq) { if ($v -lt 0) { $cur++; if ($cur -gt $burst) { $burst = $cur } } else { $cur = 0 } }
    $st = Get-Stats $ok.ToArray()

    Write-BoxTop "Results"
    Write-BoxLine "Packets      sent ", '', "$sent", 'White', "   received ", '', "$($ok.Count)", 'White', "   lost ", '', "$lost", 'White'
    $lc = if ($loss -ge 5) { 'Red' } elseif ($loss -ge 1) { 'Yellow' } else { 'Green' }
    Write-BoxLine "Packet loss  ", '', ("{0}%" -f (Fmt $loss 2)), $lc, "   longest loss burst: $burst packet(s)", ''
    if ($st) {
        Write-BoxSep
        Write-BoxLine "Latency      min $(Fmt $st.Min)  avg ", '', (Fmt $st.Avg), (Get-LatColor $st.Avg), "  max $(Fmt $st.Max)  stddev $(Fmt $st.StdDev)  (ms)", ''
        Write-BoxLine "Jitter       ", '', ("{0} ms" -f (Fmt $st.Jitter)), (Get-LatColor ($st.Jitter * 5)), "  (mean deviation between consecutive replies)", 'DarkGray'
        Write-BoxLine "Percentiles  p50 $(Fmt $st.P50)  p90 $(Fmt $st.P90)  p95 $(Fmt $st.P95)  p99 $(Fmt $st.P99)  (ms)", ''
    }
    Write-BoxBottom

    if ($st) {
        Write-Section "Latency distribution"
        $buckets = 8
        $w = ($st.Max - $st.Min) / $buckets; if ($w -le 0) { $w = 1 }
        $counts = New-Object int[] $buckets
        foreach ($v in $ok) { $k = [int][Math]::Floor(($v - $st.Min) / $w); if ($k -ge $buckets) { $k = $buckets - 1 }; $counts[$k]++ }
        for ($k = 0; $k -lt $buckets; $k++) {
            $lo = $st.Min + $k * $w; $hi = $lo + $w
            W ("    {0,8} - {1,-8} ms " -f (Fmt $lo), (Fmt $hi)) -NoNewline
            Write-Bar $counts[$k] $ok.Count 30 (Get-LatColor $hi) -NoNewline
            W (" {0,4}  " -f $counts[$k]) -NoNewline
            W ("{0,5}%" -f (Fmt ($counts[$k] * 100.0 / $ok.Count))) 'DarkGray'
        }
        Write-Section "Timeline (each cell = 1 packet, $($script:G.FAIL) = lost)"
        $width = $script:UIW - 6
        for ($i = 0; $i -lt $seq.Count; $i += $width) {
            W "    " -NoNewline
            $slice = $seq.GetRange($i, [Math]::Min($width, $seq.Count - $i)).ToArray()
            Write-Sparkline $slice
        }
    }
    $avgLat = 0; $jit = 0; if ($st) { $avgLat = $st.Avg; $jit = $st.Jitter }
    $mos = Get-Mos $avgLat $jit $loss
    Write-Section "Quality"
    Write-KV "MOS (VoIP est.)" ("{0} / 4.50  {1}" -f $mos.Mos, $mos.Quality) 'White'
    switch ($mos.Quality) {
        { $_ -in 'Excellent', 'Good' } { Write-Ok "Connection is suitable for VoIP, video calls and gaming." }
        'Fair' { Write-Warn "Usable, but calls/gaming may show occasional glitches." }
        default { Write-Fail "Poor quality - expect choppy calls and lag." }
    }
    if ($stopped) { Write-Note "Stopped early after $sent packets." }
    $p95 = '-'; if ($st) { $p95 = Fmt $st.P95 }
    Write-LogEntry ("Packet loss {0}: sent={1} recv={2} loss={3}% avg={4} jitter={5} p95={6} MOS={7}" -f $target, $sent, $ok.Count, (Fmt $loss 2), (Fmt $avgLat), (Fmt $jit), $p95, $mos.Mos)
    Wait-AnyKey
}

# ============================================================================
#  3. TCP PORT MONITOR
# ============================================================================
function Start-TcpMonitor {
    Show-Header "TCP Port Monitor"
    $target = Read-Required "Target host" "example.com"
    Write-Note "  Common: HTTP 80  HTTPS 443  SSH 22  RDP 3389  SMB 445"
    $port = Read-Int "Port" 443 1 65535
    $interval = Read-Number "Interval in seconds" 2 0.2
    $ip = Resolve-IPv4 $target
    Show-Header ("TCP Monitor {0} {1}:{2} {3}" -f $script:G.RIGHT, $target, $port, (Get-ServiceName $port))
    if (-not $ip) { Write-Fail "Could not resolve $target"; Wait-AnyKey; return }
    Write-Note "Resolved to $ip. Press Q, Esc or Ctrl+C to stop."
    Write-Host ""
    Write-LogEntry "TCP monitor started: ${target}:$port"
    $total = 0; $failed = 0
    $lat = New-Object System.Collections.ArrayList
    $spark = New-Object System.Collections.ArrayList
    Enter-MonitorMode
    try {
        while ($true) {
            $total++; Test-LogSize
            $ts = Get-Date -Format 'HH:mm:ss'
            $ms = Test-TcpConnect $ip $port
            Clear-Line
            if ($ms -ge 0) {
                [void]$lat.Add($ms); [void]$spark.Add($ms)
                Write-Segs ("  " + $script:G.OK + " "), 'Green', "$ts  ", 'DarkGray', ("port {0,-6} " -f $port), '', "open     ", 'Green', ("connect {0,6} ms  " -f $ms), (Get-LatColor $ms) -NoNewline
                Write-Bar $ms 300 20 (Get-LatColor $ms)
                Write-LogEntry "Port $port on $target - OPEN (${ms}ms)"
            } else {
                $failed++; [void]$spark.Add(-1)
                Write-Segs ("  " + $script:G.FAIL + " "), 'Red', "$ts  ", 'DarkGray', ("port {0,-6} " -f $port), '', "closed / filtered / timeout", 'Red'
                Write-LogEntry "Port $port on $target - CLOSED"
            }
            while ($spark.Count -gt 40) { $spark.RemoveAt(0) }
            $s = '-/-/-'
            if ($lat.Count) { $m = $lat | Measure-Object -Average -Minimum -Maximum; $s = "{0}/{1}/{2}" -f $m.Minimum, (Fmt $m.Average 0), $m.Maximum }
            Write-Segs ("  " + $script:G.V + " "), 'Cyan', ("tries {0}  failed {1} ({2}%)  min/avg/max {3} ms  " -f $total, $failed, (Fmt ($failed * 100.0 / $total)), $s), '' -NoNewline
            Write-Sparkline $spark.ToArray() -NoNewline
            if (Wait-StopKey $interval) { break }
        }
    } finally { Exit-MonitorMode }
    Write-Host ""; Write-Host ""
    Write-LogEntry "TCP monitor stopped: ${target}:$port tries=$total failed=$failed"
    Wait-AnyKey
}

# ============================================================================
#  4. UDP PORT TEST
# ============================================================================
function Start-UdpTest {
    Show-Header "UDP Port Test"
    $target = Read-Required "Target host" "1.1.1.1"
    Write-Note "  Common: DNS 53  NTP 123  SNMP 161  SSDP 1900  WireGuard 51820"
    $port = Read-Int "Port" 53 1 65535
    $interval = Read-Number "Interval in seconds" 2 0.5
    Show-Header ("UDP Test {0} {1}:{2} {3}" -f $script:G.RIGHT, $target, $port, (Get-ServiceName $port))
    Write-Note "open = got a reply   closed = ICMP port-unreachable   open|filtered = silence"
    Write-Note "Press Q, Esc or Ctrl+C to stop."
    Write-Host ""
    $total = 0; $c = @{ 'open' = 0; 'closed' = 0; 'open|filtered' = 0; 'error' = 0 }
    Enter-MonitorMode
    try {
        while ($true) {
            $total++; Test-LogSize
            $ts = Get-Date -Format 'HH:mm:ss'
            $st = Test-UdpPort $target $port
            $c[$st]++
            Clear-Line
            switch ($st) {
                'open'          { Write-Segs ("  " + $script:G.OK + " "), 'Green', "$ts  ", 'DarkGray', ("udp/{0,-6} " -f $port), '', "open (response received)", 'Green' }
                'closed'        { Write-Segs ("  " + $script:G.FAIL + " "), 'Red', "$ts  ", 'DarkGray', ("udp/{0,-6} " -f $port), '', "closed (ICMP unreachable)", 'Red' }
                'open|filtered' { Write-Segs ("  " + $script:G.WARN + " "), 'Yellow', "$ts  ", 'DarkGray', ("udp/{0,-6} " -f $port), '', "open|filtered (no response)", 'Yellow' }
                default         { Write-Segs ("  " + $script:G.FAIL + " "), 'Red', "$ts  ", 'DarkGray', ("udp/{0,-6} " -f $port), '', "error (unresolvable host?)", 'Red' }
            }
            Write-LogEntry "UDP ${target}:$port - $st"
            Write-Segs ("  " + $script:G.V + " "), 'Cyan', ("probes {0}  open {1}  open|filtered {2}  closed {3}" -f $total, $c['open'], $c['open|filtered'], $c['closed']), '' -NoNewline
            if (Wait-StopKey $interval) { break }
        }
    } finally { Exit-MonitorMode }
    Write-Host ""; Write-Host ""
    Wait-AnyKey
}

# ============================================================================
#  5. PORT SCAN (async, batched)
# ============================================================================
function Start-PortScan {
    Show-Header "Port Scanner"
    $target = Read-Required "Target host" "scanme.nmap.org"
    Write-Note "  Examples: 1-1024   22,80,443   8000-8100   common"
    $spec = Read-Required "Ports" "common"
    $proto = Read-Choice "Protocol" 1 @('TCP', 'UDP')
    $par = Read-Int "Parallel probes" 128 1 1024
    $tmo = [int]((Read-Number "Timeout per port (s)" 1 0.2) * 1000)
    $ip = Resolve-IPv4 $target
    if (-not $ip) { Write-Fail "Could not resolve $target"; Wait-AnyKey; return }
    $ports = Expand-Ports $spec
    if (-not $ports.Count) { Write-Fail "No valid ports in '$spec'"; Wait-AnyKey; return }
    $pname = if ($proto -eq 2) { 'UDP' } else { 'TCP' }
    Show-Header "Port Scan $($script:G.RIGHT) $target ($ip)"
    Write-Info ("Scanning {0} {1} port(s), {2} in parallel..." -f $ports.Count, $pname, $par)
    Write-LogEntry "Port scan started: $target ($spec) $pname"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $found = New-Object System.Collections.ArrayList
    $stopped = $false
    Enter-MonitorMode
    try {
        for ($i = 0; $i -lt $ports.Count; $i += $par) {
            $batch = $ports[$i..([Math]::Min($i + $par, $ports.Count) - 1)]
            if ($pname -eq 'TCP') {
                $jobs = foreach ($p in $batch) {
                    $c = New-Object System.Net.Sockets.TcpClient
                    $t0 = [Diagnostics.Stopwatch]::StartNew()
                    $iar = $null
                    try { $iar = $c.BeginConnect($ip, $p, $null, $null) } catch { }
                    [pscustomobject]@{ Port = $p; Client = $c; Iar = $iar; Sw = $t0; Ms = -1 }
                }
                $deadline = [DateTime]::UtcNow.AddMilliseconds($tmo)
                while ([DateTime]::UtcNow -lt $deadline) {
                    $pending = 0
                    foreach ($j in $jobs) {
                        if ($j.Iar -and $j.Ms -lt 0 -and $j.Iar.IsCompleted) { $j.Ms = [int]$j.Sw.ElapsedMilliseconds }
                        if ($j.Iar -and -not $j.Iar.IsCompleted) { $pending++ }
                    }
                    if ($pending -eq 0) { break }
                    Start-Sleep -Milliseconds 15
                }
                foreach ($j in $jobs) {
                    if ($j.Iar -and $j.Iar.IsCompleted) {
                        try { $j.Client.EndConnect($j.Iar); [void]$found.Add([pscustomobject]@{ Port = $j.Port; State = 'open'; Ms = $j.Ms }) } catch { }
                    }
                    $j.Client.Close()
                }
            } else {
                $jobs = foreach ($p in $batch) {
                    $u = New-Object System.Net.Sockets.UdpClient
                    try { $u.Connect($ip, $p); $d = Get-UdpPayload $p; [void]$u.Send($d, $d.Length) } catch { }
                    [pscustomobject]@{ Port = $p; Client = $u }
                }
                Start-Sleep -Milliseconds $tmo
                foreach ($j in $jobs) {
                    $s = $j.Client.Client
                    $state = 'open|filtered'
                    try {
                        if ($s.Poll(1000, [Net.Sockets.SelectMode]::SelectError)) { $state = 'closed' }   # ICMP unreachable (Linux/macOS)
                        elseif ($s.Poll(1000, [Net.Sockets.SelectMode]::SelectRead)) {                       # data, or ICMP reset (Windows)
                            try { $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0); [void]$j.Client.Receive([ref]$ep); $state = 'open' } catch { $state = 'closed' }
                        }
                    } catch { $state = 'closed' }
                    if ($state -ne 'closed') { [void]$found.Add([pscustomobject]@{ Port = $j.Port; State = $state; Ms = -1 }) }
                    $j.Client.Close()
                }
            }
            $done = [Math]::Min($i + $par, $ports.Count)
            Write-Progress2 $done $ports.Count ("{0}/{1} ports  found {2}" -f $done, $ports.Count, $found.Count)
            if (Wait-StopKey 0) { $stopped = $true; break }
        }
    } finally { Exit-MonitorMode }
    Clear-Line
    Write-BoxTop ("Scan results ({0} ports in {1}s)" -f $ports.Count, (Fmt $sw.Elapsed.TotalSeconds))
    if (-not $found.Count) {
        Write-BoxLine "No open ports found.", 'Yellow'
    } else {
        Write-BoxLine ("{0,-10} {1,-15} {2,-14} {3}" -f 'PORT', 'STATE', 'SERVICE', 'LATENCY'), 'White'
        Write-BoxSep
        foreach ($f in ($found | Sort-Object Port)) {
            $col = if ($f.State -eq 'open') { 'Green' } else { 'Yellow' }
            $lat = if ($f.Ms -ge 0) { "$($f.Ms) ms" } else { '' }
            Write-BoxLine ("{0,-10} " -f "$($f.Port)/$pname"), '', ("{0,-15} " -f $f.State), $col, ("{0,-14} {1}" -f (Get-ServiceName $f.Port), $lat), ''
        }
    }
    Write-BoxBottom
    if ($stopped) { Write-Note "Scan stopped early." }
    if ($pname -eq 'UDP') { Write-Note "UDP 'open|filtered' means no answer; firewalls often silently drop probes." }
    Write-LogEntry ("Port scan {0}: {1}" -f $target, (($found | Sort-Object Port | ForEach-Object { "$($_.Port)($($_.State))" }) -join ' '))
    Wait-AnyKey
}

# ============================================================================
#  6. TRACEROUTE
# ============================================================================
function Get-RouteHops {
    param([string]$Target, [int]$MaxHops, [switch]$Live)
    $hops = New-Object System.Collections.ArrayList
    $dest = Resolve-IPv4 $Target
    for ($ttl = 1; $ttl -le $MaxHops; $ttl++) {
        $ip = '*'; $rtt = -1; $final = $false
        for ($try = 0; $try -lt 2 -and $ip -eq '*'; $try++) {
            $r = Send-Ping $Target 2000 $ttl
            if ($r -and $r.Address -and ($r.Status -eq 'TtlExpired' -or $r.Status -eq 'Success')) {
                $ip = $r.Address.ToString()
                # TtlExpired replies report 0 ms on Windows; measure directly
                if ($r.Status -eq 'Success') { $rtt = [double]$r.RoundtripTime; $final = $true }
                else { $r2 = Send-Ping $ip 1000; if ($r2 -and $r2.Status -eq 'Success') { $rtt = [double]$r2.RoundtripTime } }
            }
        }
        $h = [pscustomobject]@{ Hop = $ttl; IP = $ip; Rtt = $rtt }
        [void]$hops.Add($h)
        if ($Live) { Write-Progress2 $ttl $MaxHops "hop $ttl  $ip" }
        if ($final -or ($dest -and $ip -eq $dest)) { break }
    }
    if ($Live) { Clear-Line }
    return , $hops
}

function Start-Traceroute {
    Show-Header "Traceroute"
    $target = Read-Required "Target host" "1.1.1.1"
    $max = Read-Int "Max hops" 30 1 64
    $rdns = Read-YesNo "Resolve hostnames" "y"
    Show-Header "Traceroute $($script:G.RIGHT) $target"
    Write-LogEntry "Traceroute to $target"
    Write-BoxTop "Route"
    Write-BoxLine ("{0,-4} {1,-50} {2,10}" -f 'HOP', 'HOST', 'RTT'), 'White'
    Write-BoxSep
    $dest = Resolve-IPv4 $target
    $done = $false
    for ($ttl = 1; $ttl -le $max -and -not $done; $ttl++) {
        $ip = '*'; $rtt = -1
        for ($try = 0; $try -lt 2 -and $ip -eq '*'; $try++) {
            $r = Send-Ping $target 2000 $ttl
            if ($r -and $r.Address -and ($r.Status -eq 'TtlExpired' -or $r.Status -eq 'Success')) {
                $ip = $r.Address.ToString()
                if ($r.Status -eq 'Success') { $rtt = $r.RoundtripTime; $done = $true }
                else { $r2 = Send-Ping $ip 1000; if ($r2 -and $r2.Status -eq 'Success') { $rtt = $r2.RoundtripTime } }
            }
        }
        if ($dest -and $ip -eq $dest) { $done = $true }
        if ($ip -eq '*') {
            Write-BoxLine ("{0,-4} {1,-50} {2,10}" -f $ttl, '* (no reply)', '*'), 'DarkGray'
        } else {
            $name = ''
            if ($rdns) { $name = Get-ReverseDns $ip }
            $host1 = $ip; if ($name) { $host1 = "$ip  " }
            $col = if ($rtt -ge 0) { Get-LatColor $rtt } else { 'DarkGray' }
            $rt = if ($rtt -ge 0) { "$rtt ms" } else { '*' }
            $nameShown = Limit-Text $name ([Math]::Max(0, 49 - $host1.Length))
            Write-BoxLine ("{0,-4} " -f $ttl), '', $host1, '', ("{0,-$([Math]::Max(1, 50 - $host1.Length))}" -f $nameShown), 'DarkGray', ("{0,10}" -f $rt), $col
        }
        Write-LogEntry "Hop ${ttl}: $ip ($rtt ms)"
    }
    Write-BoxBottom
    Wait-AnyKey
}

# ============================================================================
#  7. NETWORK PATH ANALYSIS - MTR + ASN + GEO (issue #2)
# ============================================================================
function Get-Distance {
    param([double]$Lat1, [double]$Lon1, [double]$Lat2, [double]$Lon2)
    $r = 6371; $d2r = [Math]::PI / 180
    $dLat = ($Lat2 - $Lat1) * $d2r; $dLon = ($Lon2 - $Lon1) * $d2r
    $a = [Math]::Sin($dLat / 2) * [Math]::Sin($dLat / 2) + [Math]::Cos($Lat1 * $d2r) * [Math]::Cos($Lat2 * $d2r) * [Math]::Sin($dLon / 2) * [Math]::Sin($dLon / 2)
    return [int](2 * $r * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1 - $a)))
}

function Start-PathAnalysis {
    Show-Header "Network Path Analysis (MTR)"
    $target = Read-Required "Target host" "1.1.1.1"
    $rounds = Read-Int "Probe rounds" 10 1 1000
    $max = Read-Int "Max hops" 30 1 64
    Show-Header "Path Analysis $($script:G.RIGHT) $target"
    Write-Info "Discovering route..."
    $hops = Get-RouteHops $target $max -Live
    if (-not ($hops | Where-Object { $_.IP -ne '*' })) { Write-Fail "Could not discover any hops."; Wait-AnyKey; return }
    Write-LogEntry ("Path analysis to {0} ({1} hops, {2} rounds)" -f $target, $hops.Count, $rounds)
    foreach ($h in $hops) {
        $h | Add-Member -NotePropertyName Sent -NotePropertyValue 0
        $h | Add-Member -NotePropertyName Recv -NotePropertyValue 0
        $h | Add-Member -NotePropertyName Samples -NotePropertyValue (New-Object 'System.Collections.Generic.List[double]')
        $h | Add-Member -NotePropertyName Last -NotePropertyValue -1
    }
    $top = 0
    try { $top = [Console]::CursorTop } catch { }
    Enter-MonitorMode
    try {
        for ($r = 1; $r -le $rounds; $r++) {
            $active = @($hops | Where-Object { $_.IP -ne '*' })
            $pingers = @(); $tasks = @()
            foreach ($h in $active) {
                $pg = New-Object System.Net.NetworkInformation.Ping
                $pingers += $pg
                $tasks += $pg.SendPingAsync($h.IP, 1000)
            }
            try { [void][Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$tasks, 3000) } catch { }
            for ($k = 0; $k -lt $active.Count; $k++) {
                $h = $active[$k]; $h.Sent++
                $t = $tasks[$k]
                if ($t.Status -eq 'RanToCompletion' -and $t.Result.Status -eq 'Success') {
                    $v = [double]$t.Result.RoundtripTime
                    $h.Recv++; $h.Samples.Add($v); $h.Last = $v
                }
                $pingers[$k].Dispose()
            }
            try { if ($script:IsConsole) { [Console]::SetCursorPosition(0, $top) } } catch { }
            Write-BoxTop ("Round {0}/{1}  (Q to stop)" -f $r, $rounds)
            Write-BoxLine ("{0,-4}{1,-17}{2,7}{3,5}{4,8}{5,8}{6,8}{7,8}{8,8}" -f 'HOP', 'HOST', 'LOSS%', 'SNT', 'LAST', 'AVG', 'BEST', 'WRST', 'JITTER'), 'White'
            Write-BoxSep
            foreach ($h in $hops) {
                if ($h.IP -eq '*') { Write-BoxLine ("{0,-4}{1,-17}{2,7}{3,5}{4,8}{5,8}{6,8}{7,8}{8,8}" -f $h.Hop, '???', '-', '-', '-', '-', '-', '-', '-'), 'DarkGray'; continue }
                $loss = if ($h.Sent) { ($h.Sent - $h.Recv) * 100.0 / $h.Sent } else { 0 }
                $st = Get-Stats $h.Samples.ToArray()
                $col = if ($loss -ge 20) { 'Red' } elseif ($loss -gt 0) { 'Yellow' } else { 'Green' }
                if ($st) {
                    Write-BoxLine ("{0,-4}{1,-17}{2,7}{3,5}{4,8}{5,8}{6,8}{7,8}{8,8}" -f $h.Hop, (Limit-Text $h.IP 16), (Fmt $loss), $h.Sent, $(if ($h.Last -ge 0) { $h.Last } else { '*' }), (Fmt $st.Avg), $st.Min, $st.Max, (Fmt $st.StdDev)), $col
                } else {
                    Write-BoxLine ("{0,-4}{1,-17}{2,7}{3,5}{4,8}{5,8}{6,8}{7,8}{8,8}" -f $h.Hop, (Limit-Text $h.IP 16), (Fmt $loss), $h.Sent, '*', '-', '-', '-', '-'), $col
                }
            }
            Write-BoxBottom
            if ($r -lt $rounds -and (Wait-StopKey 1)) { break }
        }
    } finally { Exit-MonitorMode }

    Write-Section "ASN & geographic route"
    $public = @($hops | Where-Object { $_.IP -ne '*' -and -not (Test-PrivateIP $_.IP) } | ForEach-Object { $_.IP })
    $geo = Get-GeoInfo $public
    W ("    {0,-4}{1,-17}{2,-10} {3,-32} {4}" -f 'HOP', 'IP', 'ASN', 'OPERATOR', 'LOCATION') 'White'
    $prev = $null; $km = 0; $route = @(); $map = 'https://www.google.com/maps/dir'; $points = 0
    foreach ($h in $hops) {
        if ($h.IP -eq '*') { continue }
        if (Test-PrivateIP $h.IP) { W ("    {0,-4}{1,-17}{2,-10} {3,-32} {4}" -f $h.Hop, $h.IP, '-', 'private / local network', '-') 'DarkGray'; continue }
        $g = $geo[$h.IP]
        if (-not $g) { W ("    {0,-4}{1,-17}{2,-10} {3,-32} {4}" -f $h.Hop, $h.IP, '?', 'lookup failed', '?'); continue }
        $asn = ''; $op = $g.as
        if ($g.as -match '^(AS\d+)\s*(.*)$') { $asn = $Matches[1]; $op = $Matches[2] }
        $loc = (@($g.city, $g.countryCode) | Where-Object { $_ }) -join ', '
        $extra = ''
        if ($prev -and $g.lat -ne $null) {
            $d = Get-Distance $prev.lat $prev.lon $g.lat $g.lon
            $km += $d
            if ($d -gt 50) { $extra = " (+$d km)" }
        }
        W ("    {0,-4}{1,-17}" -f $h.Hop, $h.IP) -NoNewline
        W ("{0,-10} " -f $asn) 'Cyan' -NoNewline
        W ("{0,-32} {1}" -f (Limit-Text $op 32), $loc) -NoNewline
        W $extra 'DarkGray'
        if ($g.lat -ne $null -and (-not $prev -or $prev.lat -ne $g.lat -or $prev.lon -ne $g.lon)) {
            $map += "/$($g.lat),$($g.lon)"; $route += "$($g.city) $($g.countryCode)"; $points++
        }
        if ($g.lat -ne $null) { $prev = $g }
        Write-LogEntry "Hop $($h.Hop) $($h.IP) $($g.as) $loc"
    }
    if ($points) {
        Write-Host ""
        Write-KV "Route" ($route -join " $($script:G.RIGHT) ")
        Write-KV "Distance" "~$km km (great-circle between hops)"
        if ($points -gt 1) { Write-KV "Map" $map }
    }
    Write-Host ""
    Write-Note "Loss on intermediate hops that does not continue to the final hop is usually"
    Write-Note "ICMP rate-limiting on that router, not real packet loss."
    Wait-AnyKey
}

# ============================================================================
#  8. DNS LOOKUP
# ============================================================================
function Start-DnsLookup {
    Show-Header "DNS Lookup"
    $domain = Read-Required "Domain name" "example.com"
    Show-Header "DNS $($script:G.RIGHT) $domain"
    if (-not (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) { Write-Fail "Resolve-DnsName is not available on this system."; Wait-AnyKey; return }
    Write-LogEntry "DNS lookup for $domain"
    Write-Section "Resolver comparison (A record)"
    W ("    {0,-16}{1,-17}{2,9}  {3}" -f 'RESOLVER', 'ADDRESS', 'TIME', 'ANSWER') 'White'
    $servers = @(@('System', ''), @('Google', '8.8.8.8'), @('Cloudflare', '1.1.1.1'), @('Quad9', '9.9.9.9'), @('OpenDNS', '208.67.222.222'))
    foreach ($s in $servers) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $a = Get-DnsRecords $domain 'A' $s[1]
        $ms = $sw.ElapsedMilliseconds
        $addr = if ($s[1]) { $s[1] } else { 'default' }
        W ("    {0,-16}{1,-17}" -f $s[0], $addr) -NoNewline
        if ($a.Count) {
            W ("{0,6} ms  " -f $ms) (Get-LatColor $ms) -NoNewline
            W (($a | Sort-Object) -join ' ') 'Green'
        } else { W ("{0,9}  " -f '-') -NoNewline; W "no answer" 'Yellow' }
    }
    foreach ($t in @('AAAA', 'CNAME', 'MX', 'NS', 'TXT', 'SOA')) {
        Write-Section $t
        $r = Get-DnsRecords $domain $t
        if ($r.Count) { $r | Select-Object -First 12 | ForEach-Object { W ("    " + (Limit-Text $_ ($script:UIW - 6))) 'Green' } }
        else { W "    none" 'DarkGray' }
    }
    Write-Section "Mail security"
    $spf = (Get-DnsRecords $domain 'TXT') | Where-Object { $_ -match 'v=spf1' } | Select-Object -First 1
    $dmarc = (Get-DnsRecords "_dmarc.$domain" 'TXT') | Where-Object { $_ -match 'v=DMARC1' } | Select-Object -First 1
    if ($spf) { Write-Ok ("SPF   " + (Limit-Text $spf 70)) } else { Write-Warn "SPF   not found" }
    if ($dmarc) { Write-Ok ("DMARC " + (Limit-Text $dmarc 70)) } else { Write-Warn "DMARC not found" }
    Write-LogEntry "DNS lookup completed for $domain"
    Wait-AnyKey
}

# ============================================================================
#  9. BANDWIDTH TEST
# ============================================================================
function Measure-Download {
    param([string]$Url, [long]$Bytes)
    $req = [Net.HttpWebRequest]::Create($Url)
    $req.Timeout = 30000; $req.ReadWriteTimeout = 30000; $req.UserAgent = "PingPortTester/$script:PPTVersion"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $resp = $req.GetResponse()
    $stream = $resp.GetResponseStream()
    $buf = New-Object byte[] 65536
    $total = 0L; $lastUi = 0
    try {
        while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
            $total += $n
            if ($sw.ElapsedMilliseconds - $lastUi -gt 150) {
                $lastUi = $sw.ElapsedMilliseconds
                $mbps = ($total * 8 / 1e6) / [Math]::Max(0.001, $sw.Elapsed.TotalSeconds)
                Write-Progress2 ([int]($total / 1024)) ([int]($Bytes / 1024)) ("{0} MB  {1} Mbps" -f (Fmt ($total / 1e6)), (Fmt $mbps))
            }
            if (Wait-StopKey 0) { break }
        }
    } finally { $stream.Close(); $resp.Close() }
    $sw.Stop(); Clear-Line
    return [pscustomobject]@{ Bytes = $total; Seconds = $sw.Elapsed.TotalSeconds; Mbps = ($total * 8 / 1e6) / [Math]::Max(0.001, $sw.Elapsed.TotalSeconds) }
}

function Measure-Upload {
    param([string]$Url, [long]$Bytes)
    $req = [Net.HttpWebRequest]::Create($Url)
    $req.Method = 'POST'; $req.Timeout = 60000; $req.ReadWriteTimeout = 60000; $req.ContentLength = $Bytes
    $req.ContentType = 'application/octet-stream'; $req.AllowWriteStreamBuffering = $false; $req.UserAgent = "PingPortTester/$script:PPTVersion"
    $buf = New-Object byte[] 65536
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $s = $req.GetRequestStream()
    $sent = 0L; $lastUi = 0
    try {
        while ($sent -lt $Bytes) {
            $n = [int][Math]::Min($buf.Length, $Bytes - $sent)
            $s.Write($buf, 0, $n); $sent += $n
            if ($sw.ElapsedMilliseconds - $lastUi -gt 150) {
                $lastUi = $sw.ElapsedMilliseconds
                $mbps = ($sent * 8 / 1e6) / [Math]::Max(0.001, $sw.Elapsed.TotalSeconds)
                Write-Progress2 ([int]($sent / 1024)) ([int]($Bytes / 1024)) ("{0} MB  {1} Mbps" -f (Fmt ($sent / 1e6)), (Fmt $mbps))
            }
        }
    } finally { $s.Close() }
    $resp = $req.GetResponse(); $resp.Close()
    $sw.Stop(); Clear-Line
    return [pscustomobject]@{ Bytes = $sent; Seconds = $sw.Elapsed.TotalSeconds; Mbps = ($sent * 8 / 1e6) / [Math]::Max(0.001, $sw.Elapsed.TotalSeconds) }
}

function Start-Bandwidth {
    Show-Header "Bandwidth Test"
    $c = Read-Choice "Test size" 2 @('Quick     (10 MB down /  5 MB up)', 'Standard  (25 MB down / 10 MB up)', 'Extended (100 MB down / 25 MB up)')
    $down = @(10e6, 25e6, 100e6)[$c - 1]; $up = @(5e6, 10e6, 25e6)[$c - 1]
    Show-Header "Bandwidth Test"
    Write-LogEntry "Bandwidth test started ($($down / 1e6) MB)"

    Write-Section "Latency (Cloudflare)"
    $lat = @()
    for ($i = 0; $i -lt 6; $i++) {
        try {
            $req = [Net.HttpWebRequest]::Create("https://speed.cloudflare.com/__down?bytes=0")
            $req.Timeout = 5000; $req.KeepAlive = $true
            $sw = [Diagnostics.Stopwatch]::StartNew(); $resp = $req.GetResponse(); $sw.Stop(); $resp.Close()
            if ($i -gt 0) { $lat += $sw.Elapsed.TotalMilliseconds }   # first request includes TLS setup
        } catch { }
    }
    $ls = $null
    if ($lat.Count) {
        $ls = Get-Stats ([double[]]$lat)
        Write-KV "Idle latency" ("{0} ms" -f (Fmt $ls.Avg)) (Get-LatColor $ls.Avg)
        Write-KV "Jitter" ("{0} ms" -f (Fmt $ls.Jitter))
    } else { Write-Warn "Could not reach speed.cloudflare.com" }

    Write-Section "Download"
    $d = $null
    try { $d = Measure-Download "https://speed.cloudflare.com/__down?bytes=$([long]$down)" $down } catch { Write-Fail "Download failed: $($_.Exception.Message)" }
    if ($d) {
        Write-KV "Speed" ("{0} Mbps" -f (Fmt $d.Mbps 2)) 'White'
        Write-KV "Transferred" ("{0} MB in {1} s" -f (Fmt ($d.Bytes / 1e6)), (Fmt $d.Seconds 2))
        W "    " -NoNewline; Write-Bar $d.Mbps 1000 40 'Green' -NoNewline; W "  scale 0-1000 Mbps" 'DarkGray'
    }
    Write-Section "Upload"
    $u = $null
    try { $u = Measure-Upload "https://speed.cloudflare.com/__up" ([long]$up) } catch { Write-Fail "Upload failed: $($_.Exception.Message)" }
    if ($u) {
        Write-KV "Speed" ("{0} Mbps" -f (Fmt $u.Mbps 2)) 'White'
        W "    " -NoNewline; Write-Bar $u.Mbps 1000 40 'Magenta' -NoNewline; W "  scale 0-1000 Mbps" 'DarkGray'
    }
    $dm = if ($d) { Fmt $d.Mbps 2 } else { 'n/a' }; $um = if ($u) { Fmt $u.Mbps 2 } else { 'n/a' }; $lm = if ($ls) { Fmt $ls.Avg } else { 'n/a' }
    Write-LogEntry "Bandwidth: down=${dm}Mbps up=${um}Mbps latency=${lm}ms"
    Write-Note "Single-stream test against Cloudflare; results may be lower than multi-stream tests."
    Wait-AnyKey
}

# ============================================================================
#  10. PUBLIC IP & NETWORK INFO
# ============================================================================
function Start-PublicIP {
    Show-Header "Public IP & Network Info"
    Write-LogEntry "Public IP check started"
    Write-Section "Local network"
    $li = Get-LocalNetInfo
    foreach ($k in $li.Keys) { Write-KV $k $li[$k] }
    Write-Section "Public address"
    $pip = Get-PublicIP
    if (-not $pip) { Write-Fail "Could not determine public IPv4 address"; Wait-AnyKey; return }
    Write-KV "IPv4" $pip 'Green'
    $v6 = Invoke-Http "https://api6.ipify.org" 5 -Raw
    if ($v6 -and ([string]$v6).Contains(':')) { Write-KV "IPv6" ([string]$v6).Trim() 'Green' } else { Write-KV "IPv6" "not available" 'DarkGray' }
    $rd = Get-ReverseDns $pip
    if ($rd) { Write-KV "Reverse DNS" $rd }
    $g = (Get-GeoInfo @($pip))[$pip]
    if ($g) {
        Write-Section "Location & provider"
        Write-KV "City" $g.city; Write-KV "Region" $g.regionName; Write-KV "Country" ("{0} ({1})" -f $g.country, $g.countryCode)
        Write-KV "Coordinates" ("{0}, {1}" -f $g.lat, $g.lon); Write-KV "Timezone" $g.timezone
        Write-KV "ISP" $g.isp; Write-KV "ASN" $g.as
        if ($g.proxy) { Write-Warn "This IP is flagged as a proxy / VPN / Tor exit." }
        if ($g.hosting) { Write-Info "This IP belongs to a hosting / datacenter network." }
        Write-LogEntry "Public IP: $pip | $($g.city), $($g.countryCode) | $($g.as)"
    } else {
        Write-Warn "Could not fetch location details"
        Write-LogEntry "Public IP: $pip (no details)"
    }
    Wait-AnyKey
}

# ============================================================================
#  11. EXTERNAL PORT CHECK
# ============================================================================
function Start-ExternalPorts {
    Show-Header "External Port Check"
    Write-Note "Checks whether ports on your public IP are reachable from the internet"
    Write-Note "(e.g. to verify port forwarding)."
    Write-Host ""
    $spec = Read-Required "Ports (e.g. 80,443,25565)" "80,443"
    Show-Header "External Port Check"
    $pip = Get-PublicIP
    if (-not $pip) { Write-Fail "Could not determine public IP"; Wait-AnyKey; return }
    Write-KV "Public IP" $pip 'White'
    Write-Host ""
    Write-LogEntry "External port check on ${pip}: $spec"
    foreach ($p in ((Expand-Ports $spec) | Select-Object -First 50)) {
        $label = "{0,-6} {1,-12} " -f $p, (Get-ServiceName $p)
        $res = Invoke-Http "https://ports.yougetsignal.com/check-port.php" 15 'POST' @{ remoteAddress = $pip; portNumber = $p } -Raw
        if ($res -match 'is open') { Write-Segs ("  " + $script:G.OK + " "), 'Green', $label, '', 'OPEN', 'Green', '  (checked from the internet)', 'DarkGray'; Write-LogEntry "External ${p}: OPEN" }
        elseif ($res -match 'is closed') { Write-Segs ("  " + $script:G.FAIL + " "), 'Red', $label, '', 'CLOSED', 'Red', '  (checked from the internet)', 'DarkGray'; Write-LogEntry "External ${p}: CLOSED" }
        else {
            if ((Test-TcpConnect $pip $p 5000) -ge 0) { Write-Segs ("  " + $script:G.OK + " "), 'Green', $label, '', 'OPEN', 'Green', '  (local hairpin test)', 'Yellow' }
            else { Write-Segs ("  " + $script:G.FAIL + " "), 'Red', $label, '', 'CLOSED/FILTERED', 'Red', '  (local hairpin test)', 'Yellow' }
            Write-LogEntry "External ${p}: hairpin test"
        }
    }
    Write-Host ""
    Write-Note "'hairpin' = remote checker unavailable; tested by connecting to your own public"
    Write-Note "IP, which many routers do not support (NAT loopback). A service must be listening."
    Wait-AnyKey
}

# ============================================================================
#  12. WEB PERFORMANCE (issue #5)
# ============================================================================
$script:CurlFmt = '%{time_namelookup} %{time_connect} %{time_appconnect} %{time_pretransfer} %{time_starttransfer} %{time_total} %{size_download} %{http_code} %{http_version} %{num_redirects} %{remote_ip}'

function ConvertFrom-CurlTiming {
    param([string]$Line)
    $f = $Line.Trim().Split(' ')
    if ($f.Count -lt 11) { return $null }
    $n = { param($s) [double]::Parse($s, [Globalization.CultureInfo]::InvariantCulture) }
    $o = [pscustomobject]@{ Dns = & $n $f[0]; Connect = & $n $f[1]; AppConnect = & $n $f[2]; Pre = & $n $f[3]; Ttfb = & $n $f[4]; Total = & $n $f[5]
        Size = & $n $f[6]; Code = $f[7]; Version = $f[8]; Redirects = $f[9]; RemoteIP = $f[10] }
    if ($o.AppConnect -eq 0) { $o.AppConnect = $o.Connect }
    return $o
}

# Phase durations in ms from a timing object
function Get-Phases {
    param($t)
    return @(($t.Dns * 1000), (($t.Connect - $t.Dns) * 1000), (($t.AppConnect - $t.Connect) * 1000), (($t.Ttfb - $t.Pre) * 1000), (($t.Total - $t.Ttfb) * 1000))
}

function Write-Waterfall {
    param([double]$Offset, [double[]]$Phases, [double]$Scale, [int]$Width)
    if ($Scale -le 0) { $Scale = 1 }
    $colors = @('DarkGray', 'Yellow', 'Magenta', 'Cyan', 'Green')
    $po = [int][Math]::Round($Offset / $Scale * $Width)
    W (' ' * [Math]::Min($Width, $po)) -NoNewline
    $used = $po; $any = $false
    for ($i = 0; $i -lt 5; $i++) {
        $c = [int][Math]::Round($Phases[$i] / $Scale * $Width)
        if ($used + $c -gt $Width) { $c = [Math]::Max(0, $Width - $used) }
        if ($c -gt 0) { W ($script:G.FULL * $c) $colors[$i] -NoNewline; $used += $c; $any = $true }
    }
    if (-not $any -and ($Phases | Measure-Object -Sum).Sum -gt 0 -and $used -lt $Width) { W $script:G.FULL 'Cyan' -NoNewline }
    Write-Host ""
}

function Resolve-Url {
    param([string]$Base, [string]$Ref)
    $Ref = ($Ref -replace '&amp;', '&') -replace '#.*$', ''
    if (-not $Ref -or $Ref -match '^(data|javascript|mailto):') { return $null }
    try { return ([Uri]::new([Uri]$Base, $Ref)).AbsoluteUri } catch { return $null }
}

function Start-WebPerf {
    Show-Header "Web Performance Test"
    $url = Read-Required "URL" "https://example.com"
    if ($url -notmatch '^https?://') { $url = "https://$url" }
    $runs = Read-Int "Timing runs for the main document" 3 1 20
    Show-Header "Web Performance $($script:G.RIGHT) $url"
    Write-LogEntry "Web performance test: $url"
    $curl = $script:CurlExe
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("ppt_" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $pageFile = Join-Path $tmp 'page.html'; $hdrFile = Join-Path $tmp 'headers.txt'
    $nul = if ($env:OS -eq 'Windows_NT') { 'NUL' } else { '/dev/null' }
    $html = ''; $headers = @{}; $finalUrl = $url
    try {
        Write-Section "Page load timing (main document, $runs run(s))"
        $timings = @()
        if ($curl) {
            for ($i = 1; $i -le $runs; $i++) {
                $o = & $curl -s -L -o $pageFile -D $hdrFile -A "Mozilla/5.0 PingPortTester/$script:PPTVersion" --max-time 30 -w $script:CurlFmt $url 2>$null
                $t = ConvertFrom-CurlTiming ([string]$o)
                if ($t -and $t.Code -ne '000') { $timings += $t }
                Write-Progress2 $i $runs "run $i/$runs"
            }
            Clear-Line
            if (-not $timings.Count) { Write-Fail "Could not load $url"; Wait-AnyKey; return }
            $html = [IO.File]::ReadAllText($pageFile)
            # headers of the final response
            $block = ([IO.File]::ReadAllText($hdrFile) -split "`r?`n`r?`n" | Where-Object { $_ -match '^HTTP/' } | Select-Object -Last 1)
            foreach ($l in ($block -split "`r?`n")) { if ($l -match '^([^:]+):\s*(.*)$') { $headers[$Matches[1].ToLower()] = $Matches[2] } }
            $finalUrl = (& $curl -s -o $nul -L -w '%{url_effective}' --max-time 15 $url 2>$null)
            if (-not $finalUrl) { $finalUrl = $url }
        } else {
            # Fallback without curl.exe: measure phases manually
            $uri = [Uri]$url
            for ($i = 1; $i -le $runs; $i++) {
                $sw = [Diagnostics.Stopwatch]::StartNew()
                $ip = Resolve-IPv4 $uri.Host; $tDns = $sw.Elapsed.TotalSeconds
                $port = $uri.Port
                $c = New-Object Net.Sockets.TcpClient; $c.Connect($ip, $port); $tCon = $sw.Elapsed.TotalSeconds
                $tTls = $tCon
                if ($uri.Scheme -eq 'https') { $ss = New-Object Net.Security.SslStream($c.GetStream(), $false); $ss.AuthenticateAsClient($uri.Host); $tTls = $sw.Elapsed.TotalSeconds; $ss.Close() }
                $c.Close()
                $sw2 = [Diagnostics.Stopwatch]::StartNew()
                $req = [Net.HttpWebRequest]::Create($url); $req.UserAgent = "Mozilla/5.0 PingPortTester/$script:PPTVersion"; $req.Timeout = 30000
                $resp = $req.GetResponse(); $tF = $sw2.Elapsed.TotalSeconds
                $rd = New-Object IO.StreamReader($resp.GetResponseStream()); $html = $rd.ReadToEnd(); $rd.Close()
                $tT = $sw2.Elapsed.TotalSeconds
                foreach ($k in $resp.Headers.AllKeys) { $headers[$k.ToLower()] = $resp.Headers[$k] }
                $finalUrl = $resp.ResponseUri.AbsoluteUri
                $timings += [pscustomobject]@{ Dns = $tDns; Connect = $tCon; AppConnect = $tTls; Pre = $tTls; Ttfb = $tTls + $tF; Total = $tTls + $tT
                    Size = $html.Length; Code = [int]$resp.StatusCode; Version = $resp.ProtocolVersion.ToString(); Redirects = '?'; RemoteIP = $ip }
                $resp.Close()
                Write-Progress2 $i $runs "run $i/$runs"
            }
            Clear-Line
        }
        $med = { param($prop) $v = @($timings | ForEach-Object { $_.$prop } | Sort-Object); $v[[int][Math]::Floor(($v.Count - 1) / 2)] }
        $t = [pscustomobject]@{ Dns = & $med 'Dns'; Connect = & $med 'Connect'; AppConnect = & $med 'AppConnect'; Pre = & $med 'Pre'; Ttfb = & $med 'Ttfb'; Total = & $med 'Total' }
        $ph = Get-Phases $t
        $scale = $t.Total * 1000
        $bw = [Math]::Max(20, $script:UIW - 40)
        $names = @('DNS lookup', 'TCP connect', 'TLS handshake', 'Server wait', 'Content download')
        $acc = 0.0
        for ($i = 0; $i -lt 5; $i++) {
            W ("    {0,-16} " -f $names[$i]) -NoNewline
            W ("{0,8} ms  " -f (Fmt $ph[$i])) 'White' -NoNewline
            $only = @(0, 0, 0, 0, 0); $only[$i] = $ph[$i]
            Write-Waterfall $acc $only $scale $bw
            $acc += $ph[$i]
        }
        W ("    {0,-16} " -f 'Total') -NoNewline; W ("{0,8} ms" -f (Fmt $scale)) 'White'
        Write-Host ""
        $last = $timings[-1]
        Write-KV "TTFB" ("{0} ms" -f (Fmt ($t.Ttfb * 1000) 0)) (Get-LatColor ($t.Ttfb * 250))
        Write-KV "HTTP status" ("{0}  (redirects: {1})" -f $last.Code, $last.Redirects)
        Write-KV "Size" ("{0} KB  {1}" -f (Fmt ($last.Size / 1024)), $headers['content-type'])
        Write-KV "Server IP" $last.RemoteIP
        if (-not $curl) { Write-Note "  curl.exe not found - phases measured separately, waterfall simplified." }

        # --- Protocol support -------------------------------------------------
        Write-Section "Protocol support"
        $alt = $headers['alt-svc']
        if ($curl) {
            $features = (& $curl -V 2>$null) -join ' '
            $h1 = & $curl -s -o $nul --http1.1 --max-time 10 -w '%{http_version}' $url 2>$null
            if ($h1 -eq '1.1') { Write-Ok "HTTP/1.1 supported" } elseif ($h1 -eq '1') { Write-Warn "Server only speaks HTTP/1.0" } else { Write-Warn "HTTP/1.1 not confirmed" }
            if ($features -match 'HTTP2') {
                $h2 = & $curl -s -o $nul --http2 --max-time 10 -w '%{http_version}' $url 2>$null
                if ($h2 -eq '2') { Write-Ok "HTTP/2 supported (ALPN h2)" } else { Write-Warn "HTTP/2 not negotiated" }
            } elseif ($PSVersionTable.PSVersion.Major -ge 7) {
                $h2 = Test-Http2 $url
                if ($h2) { Write-Ok "HTTP/2 supported" } else { Write-Warn "HTTP/2 not negotiated" }
            } else { Write-Info "HTTP/2 cannot be verified (local curl.exe lacks HTTP/2; use PowerShell 7)" }
            if ($features -match 'HTTP3') {
                $h3 = & $curl -s -o $nul --http3-only --max-time 10 -w '%{http_version}' $url 2>$null
                if ($h3 -eq '3') { Write-Ok "HTTP/3 (QUIC) supported - verified" }
                elseif ($alt -match 'h3') { Write-Warn "HTTP/3 advertised but QUIC connection failed (UDP 443 blocked?)" }
                else { Write-Warn "HTTP/3 not supported" }
            } elseif ($alt -match 'h3') { Write-Ok "HTTP/3 advertised via Alt-Svc (cannot verify QUIC locally)" }
            else { Write-Warn "HTTP/3 not advertised" }
        } else {
            if ($PSVersionTable.PSVersion.Major -ge 7) { if (Test-Http2 $url) { Write-Ok "HTTP/2 supported" } else { Write-Warn "HTTP/2 not negotiated" } }
            else { Write-Info "HTTP/2 cannot be verified on Windows PowerShell 5.1 without curl.exe" }
            if ($alt -match 'h3') { Write-Ok "HTTP/3 advertised via Alt-Svc" } else { Write-Warn "HTTP/3 not advertised" }
        }

        # --- CDN & caching ----------------------------------------------------
        Write-Section "CDN & caching"
        $h = $headers
        $cdn = $null
        if ($h['cf-ray']) { $cdn = "Cloudflare (POP " + ($h['cf-ray'] -replace '.*-', '') + ")" }
        elseif ($h['x-amz-cf-pop']) { $cdn = "Amazon CloudFront (POP $($h['x-amz-cf-pop']))" }
        elseif ($h['x-served-by'] -match 'cache-') { $cdn = "Fastly ($($h['x-served-by'] -replace '.*cache-',''))" }
        elseif (($h.Keys | Where-Object { $_ -match '^(x-akamai|akamai-)' })) { $cdn = 'Akamai' }
        elseif ($h['x-vercel-id']) { $cdn = "Vercel" }
        elseif ($h['x-nf-request-id']) { $cdn = 'Netlify' }
        elseif ($h['x-azure-ref']) { $cdn = 'Azure Front Door' }
        elseif ($h['server'] -match 'gws|ESF') { $cdn = 'Google' }
        elseif ($h['via'] -match 'varnish') { $cdn = 'Varnish cache' }
        elseif ($h['server'] -match 'bunny') { $cdn = 'BunnyCDN' }
        if ($cdn) { Write-Ok "CDN detected: $cdn" } else { Write-Info "No CDN fingerprint found (origin server: $($h['server']))" }
        $cacheKey = @('cf-cache-status', 'x-cache', 'x-vercel-cache') | Where-Object { $h[$_] } | Select-Object -First 1
        $c1 = if ($cacheKey) { $h[$cacheKey] } else { $null }
        $c2 = $null; $ttfb2 = $null; $enc = $null
        try {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $req = [Net.HttpWebRequest]::Create($finalUrl); $req.UserAgent = "Mozilla/5.0"; $req.Headers.Add('Accept-Encoding', 'gzip, deflate, br'); $req.Timeout = 20000
            $resp = $req.GetResponse(); $ttfb2 = $sw.Elapsed.TotalMilliseconds
            if ($cacheKey) { $c2 = $resp.Headers[$cacheKey] }
            $enc = $resp.Headers['Content-Encoding']
            $resp.Close()
        } catch { }
        Write-KV "Cache status" ("{0} {1} {2} (1st {1} 2nd request)" -f $(if ($c1) { $c1 } else { 'n/a' }), $script:G.RIGHT, $(if ($c2) { $c2 } else { 'n/a' }))
        if ($ttfb2) { Write-KV "TTFB 2nd req" ("{0} ms" -f (Fmt $ttfb2 0)) }
        Write-KV "Cache-Control" $h['cache-control']
        Write-KV "Age" $h['age']
        Write-KV "Compression" $enc
        if ($c2 -match 'HIT') { Write-Ok "Content is served from the CDN cache" }
        elseif ($c2 -match 'MISS|DYNAMIC|BYPASS') { Write-Warn "Content not cached at the edge ($c2)" }
        if (-not $enc) { Write-Warn "Response is not compressed (gzip/br)" }
        if ($h['strict-transport-security']) { Write-Ok "HSTS enabled" } elseif ($url -match '^https') { Write-Warn "No HSTS header" }
        Write-LogEntry ("Web {0}: ttfb={1}ms total={2}ms cdn={3}" -f $url, (Fmt ($t.Ttfb * 1000) 0), (Fmt $scale 0), $cdn)

        # --- Resource waterfall ----------------------------------------------
        Write-Section "Resource waterfall"
        $refs = [regex]::Matches($html, '<(?:script|img|link|source|iframe)\b[^>]*>', 'IgnoreCase') | ForEach-Object {
            $tag = $_.Value
            if ($tag -match 'rel\s*=\s*"?(preconnect|dns-prefetch|canonical|alternate|manifest)') { return }
            $m = [regex]::Match($tag, '\b(?:src|href)\s*=\s*"([^"]+)"', 'IgnoreCase')
            if ($m.Success) { Resolve-Url $finalUrl $m.Groups[1].Value }
        } | Where-Object { $_ } | Select-Object -Unique | Select-Object -First 30
        $refs = @($refs)
        if (-not $refs.Count) {
            Write-Note "  No sub-resources found in the HTML (page may be built by JavaScript)."
        } else {
            $rows = @()
            $t0 = [Diagnostics.Stopwatch]::StartNew()
            if ($curl) {
                # Fetch in parallel batches of 6 (browser-like) using background curl processes
                for ($i = 0; $i -lt $refs.Count; $i += 6) {
                    $procs = @()
                    for ($j = $i; $j -lt [Math]::Min($i + 6, $refs.Count); $j++) {
                        $out = Join-Path $tmp "r$j.txt"
                        $psi = New-Object Diagnostics.ProcessStartInfo
                        $psi.FileName = $curl
                        $psi.Arguments = ('-s -o {0} -A "Mozilla/5.0" --max-time 20 -w "{1}" "{2}"' -f $nul, $script:CurlFmt, $refs[$j])
                        $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
                        $procs += [pscustomobject]@{ Idx = $j; Start = $t0.Elapsed.TotalMilliseconds; P = [Diagnostics.Process]::Start($psi) }
                    }
                    foreach ($pr in $procs) {
                        $o = $pr.P.StandardOutput.ReadToEnd(); $pr.P.WaitForExit()
                        $tm = ConvertFrom-CurlTiming $o
                        if ($tm) { $rows += [pscustomobject]@{ Url = $refs[$pr.Idx]; Offset = $pr.Start; T = $tm } }
                    }
                    Write-Progress2 ([Math]::Min($i + 6, $refs.Count)) $refs.Count "fetching resources"
                }
            } else {
                for ($j = 0; $j -lt $refs.Count; $j++) {
                    $start = $t0.Elapsed.TotalMilliseconds
                    $sw = [Diagnostics.Stopwatch]::StartNew(); $code = '000'; $size = 0; $ttfbR = 0
                    try {
                        $req = [Net.HttpWebRequest]::Create($refs[$j]); $req.UserAgent = "Mozilla/5.0"; $req.Timeout = 20000
                        $resp = $req.GetResponse(); $ttfbR = $sw.Elapsed.TotalSeconds
                        $ms = New-Object IO.MemoryStream; $resp.GetResponseStream().CopyTo($ms); $size = $ms.Length; $code = [int]$resp.StatusCode; $resp.Close()
                    } catch [Net.WebException] { if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode } }
                    $tt = $sw.Elapsed.TotalSeconds
                    $rows += [pscustomobject]@{ Url = $refs[$j]; Offset = $start; T = [pscustomobject]@{ Dns = 0; Connect = 0; AppConnect = 0; Pre = 0; Ttfb = $ttfbR; Total = $tt; Size = $size; Code = $code } }
                    Write-Progress2 ($j + 1) $refs.Count "fetching resources"
                }
            }
            Clear-Line
            $rows = @($rows | Sort-Object Offset)
            $wscale = ($rows | ForEach-Object { $_.Offset + $_.T.Total * 1000 } | Measure-Object -Maximum).Maximum
            $barW = [Math]::Max(16, $script:UIW - 56)
            W ("    {0,-28} {1,4} {2,8} {3,7}  0 {4} {5} ms" -f 'RESOURCE', 'CODE', 'SIZE', 'TIME', $script:G.RIGHT, (Fmt $wscale 0)) 'White'
            $totSize = 0; $slow = $null
            foreach ($r in $rows) {
                $name = ($r.Url -split '\?')[0].TrimEnd('/') -replace '.*/', ''
                if (-not $name) { $name = $r.Url }
                $ms = [int]($r.T.Total * 1000)
                $totSize += $r.T.Size
                if (-not $slow -or $ms -gt $slow.Ms) { $slow = [pscustomobject]@{ Name = $name; Ms = $ms } }
                $code = [string]$r.T.Code
                $cc = if ($code -match '^2') { 'Green' } elseif ($code -match '^3') { 'Yellow' } else { 'Red' }
                W ("    {0,-28} " -f (Limit-Text $name 28)) -NoNewline
                W ("{0,4} " -f $code) $cc -NoNewline
                W ("{0,7}K {1,5} ms  " -f (Fmt ($r.T.Size / 1024)), $ms) -NoNewline
                Write-Waterfall $r.Offset (Get-Phases $r.T) $wscale $barW
            }
            Write-Host ""
            W "    Legend: " 'DarkGray' -NoNewline
            W $script:G.FULL 'DarkGray' -NoNewline; W " dns  " -NoNewline; W $script:G.FULL 'Yellow' -NoNewline; W " connect  " -NoNewline
            W $script:G.FULL 'Magenta' -NoNewline; W " tls  " -NoNewline; W $script:G.FULL 'Cyan' -NoNewline; W " wait  " -NoNewline
            W $script:G.FULL 'Green' -NoNewline; W " download"
            Write-KV "Resources" ("{0}  ({1} KB total)" -f $rows.Count, (Fmt ($totSize / 1024)))
            if ($slow) { Write-KV "Slowest" ("{0} ({1} ms)" -f $slow.Name, $slow.Ms) }
            Write-KV "Est. page load" ("~{0} ms (document + resources)" -f (Fmt ($scale + $wscale) 0))
            Write-LogEntry ("Web {0}: resources={1} size={2}B" -f $url, $rows.Count, $totSize)
        }
    } catch {
        Write-Fail "Error: $($_.Exception.Message)"
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
    Wait-AnyKey
}

function Test-Http2 {
    param([string]$Url)
    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds(10)
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Head, $Url)
        $req.Version = New-Object Version(2, 0)
        $resp = $client.SendAsync($req).GetAwaiter().GetResult()
        $ok = ($resp.Version.Major -ge 2)
        $resp.Dispose(); $client.Dispose()
        return $ok
    } catch { return $false }
}

# ============================================================================
#  13. SSL/TLS CERTIFICATE CHECK (issue #3)
# ============================================================================
function Invoke-TlsHandshake {
    param([string]$HostName, [int]$Port, [int]$Protocols = 0)
    $cap = @{ Cert = $null; Errors = $null; Chain = @(); ChainStatus = @() }
    $tcp = New-Object System.Net.Sockets.TcpClient
    $ssl = $null
    try {
        $iar = $tcp.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(8000, $false)) { throw "Connection timed out" }
        $tcp.EndConnect($iar)
        $tcp.ReceiveTimeout = 8000; $tcp.SendTimeout = 8000
        $cb = [System.Net.Security.RemoteCertificateValidationCallback] {
            param($sender, $certificate, $chain, $errors)
            $cap.Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certificate)
            $cap.Errors = $errors
            $cap.Chain = @($chain.ChainElements | ForEach-Object { [pscustomobject]@{ Subject = $_.Certificate.Subject; Issuer = $_.Certificate.Issuer; NotAfter = $_.Certificate.NotAfter } })
            $cap.ChainStatus = @($chain.ChainStatus | ForEach-Object { $_.StatusInformation.Trim() })
            return $true
        }
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, $cb)
        $ssl.ReadTimeout = 8000; $ssl.WriteTimeout = 8000
        $ssl.AuthenticateAsClient($HostName, $null, [System.Security.Authentication.SslProtocols]$Protocols, $false)
        $suite = $null; try { $suite = [string]$ssl.NegotiatedCipherSuite } catch { }
        return [pscustomobject]@{ Ok = $true; Protocol = [string]$ssl.SslProtocol; Cipher = [string]$ssl.CipherAlgorithm; Strength = $ssl.CipherStrength
            Hash = [string]$ssl.HashAlgorithm; KeyEx = [string]$ssl.KeyExchangeAlgorithm; Suite = $suite; Cert = $cap.Cert; Errors = $cap.Errors
            Chain = $cap.Chain; ChainStatus = $cap.ChainStatus; Error = $null }
    } catch {
        $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }
        $notTestable = ($_.Exception -is [ArgumentException]) -or ($e -is [ArgumentException]) -or ($e -is [NotSupportedException]) -or ($e -is [PlatformNotSupportedException])
        return [pscustomobject]@{ Ok = $false; Error = $e.Message; NotTestable = $notTestable }
    } finally {
        if ($ssl) { $ssl.Dispose() }
        $tcp.Close()
    }
}

function Start-SslCheck {
    Show-Header "SSL/TLS Certificate Check"
    $hostIn = Read-Required "Host" "example.com"
    $hostIn = ($hostIn -replace '^[a-z]+://', '') -replace '/.*$', ''
    $port = 0
    if ($hostIn -match '^(.+):(\d+)$') { $hostIn = $Matches[1]; $port = [int]$Matches[2] }
    if (-not $port) { $port = Read-Int "Port" 443 1 65535 }
    Show-Header "SSL/TLS $($script:G.RIGHT) ${hostIn}:$port"
    Write-LogEntry "TLS check: ${hostIn}:$port"
    Write-Info "Connecting..."
    $main = Invoke-TlsHandshake $hostIn $port 0
    if (-not $main.Ok -or -not $main.Cert) {
        Write-Fail "TLS handshake failed: $($main.Error)"
        if ($port -in 25, 587, 110, 143) { Write-Note "  This port uses STARTTLS - use the SMTP test (capability probe) instead." }
        Wait-AnyKey; return
    }
    $c = $main.Cert
    $days = [int][Math]::Floor(($c.NotAfter - (Get-Date)).TotalDays)
    $dc = if ($days -lt 7) { 'Red' } elseif ($days -lt 30) { 'Yellow' } else { 'Green' }
    $keyAlg = $c.PublicKey.Oid.FriendlyName; $keySize = $null
    try { $keySize = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($c).KeySize } catch { }
    if (-not $keySize) { try { $keySize = $c.PublicKey.Key.KeySize } catch { } }
    if (-not $keySize) { try { $keySize = [Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::GetECDsaPublicKey($c).KeySize } catch { } }
    $san = ($c.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' } | ForEach-Object { $_.Format($false) }) -replace 'DNS Name=', '' -replace 'DNS:', ''

    Write-BoxTop "Certificate"
    $mw = $script:UIW - 20
    Write-BoxLine "Subject      ", '', (Limit-Text $c.Subject $mw), 'White'
    Write-BoxLine ("Issuer       " + (Limit-Text $c.Issuer $mw)), ''
    Write-BoxLine ("Valid from   " + $c.NotBefore.ToString('yyyy-MM-dd HH:mm')), ''
    Write-BoxLine ("Valid until  " + $c.NotAfter.ToString('yyyy-MM-dd HH:mm') + "  "), '', "($days days left)", $dc
    Write-BoxLine ("Key          {0} {1}" -f $keyAlg, $(if ($keySize) { "($keySize bit)" })), ''
    Write-BoxLine ("Signature    " + $c.SignatureAlgorithm.FriendlyName), ''
    Write-BoxLine ("Serial       " + (Limit-Text $c.SerialNumber $mw)), ''
    Write-BoxLine ("SHA-1        " + $c.Thumbprint), 'DarkGray'
    Write-BoxBottom
    if ($san) {
        Write-Section "Subject Alternative Names"
        $line = '    '
        foreach ($s in ($san -split ',\s*' | Select-Object -First 20)) {
            if ($line.Length + $s.Length -gt $script:UIW) { W $line; $line = '    ' }
            $line += "$s, "
        }
        W $line.TrimEnd(', ')
    }

    Write-Section "Validation"
    $findings = 0; $crit = $false
    if ($days -lt 0) { Write-Fail "Certificate EXPIRED $(-$days) days ago"; $crit = $true }
    elseif ($days -lt 14) { Write-Warn "Certificate expires in $days days"; $findings++ }
    else { Write-Ok "Certificate is within its validity period" }
    $err = [string]$main.Errors
    if ($err -match 'RemoteCertificateNameMismatch') { Write-Fail "Hostname '$hostIn' does NOT match the certificate"; $crit = $true }
    else { Write-Ok "Hostname '$hostIn' matches the certificate" }
    if ($err -match 'RemoteCertificateChainErrors') {
        Write-Fail ("Chain is not trusted: " + (($main.ChainStatus | Where-Object { $_ }) -join '; ')); $crit = $true
    } else { Write-Ok "Certificate chain is trusted" }
    if ($c.Subject -eq $c.Issuer) { Write-Fail "Self-signed certificate"; $crit = $true }
    if ($c.SignatureAlgorithm.FriendlyName -match 'sha1|md5') { Write-Fail "Weak signature algorithm ($($c.SignatureAlgorithm.FriendlyName))"; $crit = $true }
    if ($keyAlg -match 'RSA' -and $keySize -and $keySize -lt 2048) { Write-Fail "RSA key smaller than 2048 bits"; $crit = $true }

    Write-Section "Certificate chain"
    $i = 0
    foreach ($e in $main.Chain) {
        $cn = if ($e.Subject -match 'CN=([^,]+)') { $Matches[1] } else { $e.Subject }
        $icn = if ($e.Issuer -match 'CN=([^,]+)') { $Matches[1] } else { $e.Issuer }
        $ind = '  ' * $i
        $pref = if ($i -gt 0) { $script:G.BL + $script:G.H + ' ' } else { '' }
        W ("    $ind") -NoNewline; W $pref 'Cyan' -NoNewline; W (Limit-Text $cn 50) 'White'
        W ("    $ind   issuer: {0}  {1} expires {2}" -f (Limit-Text $icn 40), $script:G.DOT, $e.NotAfter.ToString('yyyy-MM-dd')) 'DarkGray'
        $i++
    }

    Write-Section "Protocol support"
    $supported = @(); $weak = $false
    $protos = @(@('SSL 3.0', 48), @('TLS 1.0', 192), @('TLS 1.1', 768), @('TLS 1.2', 3072), @('TLS 1.3', 12288))
    foreach ($p in $protos) {
        $r = Invoke-TlsHandshake $hostIn $port $p[1]
        W ("    {0,-9} " -f $p[0]) -NoNewline
        if ($r.Ok) {
            $supported += $p[0]
            $suite = if ($r.Suite) { $r.Suite } else { "{0}-{1} {2} / {3}" -f $r.KeyEx, $r.Cipher, $r.Strength, $r.Hash }
            if ($p[1] -le 768) { W ($script:G.WARN + " enabled   ") 'Red' -NoNewline; W $suite 'DarkGray' -NoNewline; W "  (deprecated, should be disabled)" 'Red'; $weak = $true }
            else { W ($script:G.OK + " enabled   ") 'Green' -NoNewline; W $suite 'DarkGray' }
        } elseif ($r.NotTestable) {
            W "not testable (disabled in this Windows/.NET version)" 'DarkGray'
        } else {
            if ($p[1] -ge 3072) { W ($script:G.FAIL + " disabled") 'Yellow' } else { W ($script:G.OK + " disabled") 'Green' }
        }
    }
    if ($supported -notcontains 'TLS 1.3') { $findings++ }
    if ($weak) { $findings += 2 }

    Write-Section "Negotiated cipher (default)"
    $suite = if ($main.Suite) { $main.Suite } else { "{0} {1}-bit / {2} / key exchange {3}" -f $main.Cipher, $main.Strength, $main.Hash, $main.KeyEx }
    Write-KV "Protocol" $main.Protocol
    Write-KV "Cipher suite" $suite
    $pfs = ($main.Protocol -match 'Tls13') -or ($main.Suite -match 'ECDHE|DHE') -or ($main.KeyEx -match 'Ecdh|DiffieHellman|44550|43522')
    if ($pfs) { Write-Ok "Forward secrecy" } else { Write-Warn "Forward secrecy not confirmed"; $findings++ }
    if (($main.Suite -match 'RC4|3DES|DES_|NULL|EXPORT') -or ($main.Cipher -match 'Rc4|Des|None')) { Write-Fail "Weak cipher negotiated"; $findings += 2 }
    Write-Note "  Full cipher-suite enumeration needs OpenSSL; Windows can only report the negotiated suite."

    if ($port -eq 443) {
        try {
            $req = [Net.HttpWebRequest]::Create("https://$hostIn/"); $req.Method = 'HEAD'; $req.Timeout = 10000; $req.AllowAutoRedirect = $false
            $resp = $null
            try { $resp = $req.GetResponse() } catch [Net.WebException] { $resp = $_.Exception.Response }
            $hsts = if ($resp) { $resp.Headers['Strict-Transport-Security'] } else { $null }
            if ($resp) { $resp.Close() }
            if ($hsts) { Write-Ok "HSTS: $hsts" } else { Write-Warn "No HSTS header"; $findings++ }
        } catch { }
    }
    $grade = 'A+'
    if ($findings -ge 1) { $grade = 'A' }
    if ($findings -ge 2) { $grade = 'B' }
    if ($findings -ge 4) { $grade = 'C' }
    if ($crit) { $grade = 'F' }
    $gc = switch ($grade) { 'B' { 'Yellow' } 'C' { 'Red' } 'F' { 'Red' } default { 'Green' } }
    Write-Host ""
    Write-BoxTop
    Write-BoxLine "Overall grade  ", '', " $grade ", $gc, "   (heuristic: validity, chain, protocols, cipher, HSTS)", 'DarkGray'
    Write-BoxBottom
    Write-LogEntry ("TLS {0}:{1} grade={2} days_left={3} protocols={4}" -f $hostIn, $port, $grade, $days, ($supported -join ','))
    Wait-AnyKey
}

# ============================================================================
#  14. VPN / PROXY / LEAK TEST (issue #4)
# ============================================================================
function Get-StunMapped {
    param([string]$Server, [int]$Port)
    $u = New-Object System.Net.Sockets.UdpClient
    try {
        $u.Client.ReceiveTimeout = 3000
        $tid = New-Object byte[] 12; (New-Object Random).NextBytes($tid)
        $req = [byte[]](0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xA4, 0x42) + $tid
        $ip4 = Resolve-IPv4 $Server
        if (-not $ip4) { return $null }
        [void]$u.Send($req, $req.Length, $ip4, $Port)
        $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $d = $u.Receive([ref]$ep)
        $i = 20
        while ($i + 4 -le $d.Length) {
            $type = ($d[$i] -shl 8) -bor $d[$i + 1]; $len = ($d[$i + 2] -shl 8) -bor $d[$i + 3]
            if (($type -eq 0x0020 -or $type -eq 0x8020) -and $d[$i + 5] -eq 1) {
                $port = (($d[$i + 6] -shl 8) -bor $d[$i + 7]) -bxor 0x2112
                $m = @(0x21, 0x12, 0xA4, 0x42)
                $ip = (0..3 | ForEach-Object { $d[$i + 8 + $_] -bxor $m[$_] }) -join '.'
                return "${ip}:$port"
            }
            if ($type -eq 0x0001 -and $d[$i + 5] -eq 1) {
                return ("{0}.{1}.{2}.{3}:{4}" -f $d[$i + 8], $d[$i + 9], $d[$i + 10], $d[$i + 11], (($d[$i + 6] -shl 8) -bor $d[$i + 7]))
            }
            $i += 4 + $len + ((4 - $len % 4) % 4)
        }
    } catch { } finally { $u.Close() }
    return $null
}

function Start-VpnTest {
    Show-Header "VPN / Proxy / Leak Test"
    Write-LogEntry "VPN/proxy test started"
    $issues = 0

    Write-Section "Proxy detection"
    $found = $false
    foreach ($v in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY')) {
        $val = [Environment]::GetEnvironmentVariable($v)
        if ($val) { Write-Info ("Environment {0}={1}" -f $v, (Limit-Text $val ($script:UIW - 20))); $found = $true }
    }
    try {
        $is = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ($is.ProxyEnable -eq 1) { Write-Info "System proxy enabled: $($is.ProxyServer)"; $found = $true }
        if ($is.AutoConfigURL) { Write-Info "Proxy auto-config (PAC): $($is.AutoConfigURL)"; $found = $true }
    } catch { }
    try {
        $wh = (netsh winhttp show proxy) -join ' '
        if ($wh -match 'Proxy Server\(s\)\s*:\s*(\S+)') { Write-Info "WinHTTP proxy: $($Matches[1])"; $found = $true }
    } catch { }
    try {
        $test = [Uri]'https://example.com'
        $sp = [Net.WebRequest]::GetSystemWebProxy().GetProxy($test)
        if ($sp -and $sp.AbsoluteUri -ne $test.AbsoluteUri) { Write-Info "Effective proxy for HTTPS: $($sp.AbsoluteUri)"; $found = $true }
    } catch { }
    if (-not $found) { Write-Ok "No local proxy configuration found" }

    $pip = Get-PublicIP
    if (-not $pip) { Write-Fail "Could not determine public IP - are you online?"; Wait-AnyKey; return }
    $hip = Invoke-Http "http://api.ipify.org" 6 -Raw
    if ($hip) { $hip = ([string]$hip).Trim() }
    if ($hip -match '^\d+\.\d+\.\d+\.\d+$' -and $hip -ne $pip) { Write-Warn "HTTP and HTTPS exit via different IPs ($hip vs $pip) - transparent HTTP proxy likely"; $issues++ }

    Write-Section "VPN tunnel"
    $tunnels = @()
    try {
        $tunnels = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' -and ($_.InterfaceDescription -match 'TAP|TUN|Wintun|WireGuard|VPN|OpenVPN|Fortinet|AnyConnect|PANGP|GlobalProtect|Juniper|Pulse|NordLynx|ProtonVPN|Mullvad|Tailscale|ZeroTier|SonicWall|Check Point|WAN Miniport' -or $_.Name -match 'VPN|WireGuard|Tailscale|ZeroTier|NordLynx|Mullvad') })
    } catch { }
    $egress = $null
    try { $egress = (Find-NetRoute -RemoteIPAddress 1.1.1.1 -ErrorAction Stop | Where-Object { $_.InterfaceAlias } | Select-Object -First 1).InterfaceAlias } catch { }
    if ($tunnels.Count) {
        Write-Ok ("Tunnel adapter(s) up: " + (($tunnels | ForEach-Object { "$($_.Name) [$($_.InterfaceDescription)]" }) -join ', '))
        if ($egress -and ($tunnels.Name -contains $egress)) { Write-Ok "Default route goes through the tunnel ($egress)" }
        elseif ($egress) { Write-Warn "Default route uses '$egress', NOT the tunnel (split tunnel?)"; $issues++ }
    } else { Write-Info ("No VPN adapter detected" + $(if ($egress) { " (egress: $egress)" })) }
    if ($egress) {
        try { $mtu = (Get-NetIPInterface -InterfaceAlias $egress -AddressFamily IPv4 -ErrorAction Stop).NlMtu; Write-KV "Egress MTU" ("$mtu" + $(if ($mtu -lt 1500) { "  (below 1500 - typical for tunnels)" })) } catch { }
    }
    $tor = Invoke-Http "https://check.torproject.org/api/ip" 6
    if ($tor -and $tor.IsTor) { Write-Info "Traffic exits through the Tor network" }

    Write-Section "Geo-location consistency"
    Write-KV "Public IP" $pip 'White'
    $ccs = @(); $ipTz = $null
    $g = (Get-GeoInfo @($pip))[$pip]
    if ($g) {
        $ccs += $g.countryCode; $ipTz = $g.timezone
        Write-KV "ip-api.com" ("{0}, {1}  {2} {3}" -f $g.city, $g.countryCode, $script:G.DOT, $g.as)
        if ($g.proxy) { Write-Info "IP is listed as proxy/VPN (expected if you use one)" }
        if ($g.hosting) { Write-Info "IP belongs to a datacenter/hosting provider" }
    }
    $j2 = Invoke-Http "https://ipinfo.io/$pip/json" 6
    if ($j2 -and $j2.country) { $ccs += $j2.country; if (-not $ipTz) { $ipTz = $j2.timezone }; Write-KV "ipinfo.io" ("{0}, {1}  {2} {3}" -f $j2.city, $j2.country, $script:G.DOT, $j2.org) }
    $j3 = Invoke-Http "https://ipwho.is/$pip" 6
    if ($j3 -and $j3.country_code) { $ccs += $j3.country_code; Write-KV "ipwho.is" ("{0}, {1}  {2} {3}" -f $j3.city, $j3.country_code, $script:G.DOT, $j3.connection.org) }
    $uniq = @($ccs | Where-Object { $_ } | Select-Object -Unique)
    if ($uniq.Count -le 1) { Write-Ok "Providers agree on country: $($uniq -join ' ')" } else { Write-Warn "Providers disagree on country: $($uniq -join ' ') (new/anycast/VPN range)" }
    if ($ipTz) {
        $local = [TimeZoneInfo]::Local
        $sysOff = $local.GetUtcOffset([DateTime]::Now)
        $ipOff = $null
        try { $ipOff = [TimeZoneInfo]::FindSystemTimeZoneById($ipTz).GetUtcOffset([DateTime]::UtcNow) } catch { }
        if (-not $ipOff -and $g -and $j3 -and $j3.timezone.utc) { try { $ipOff = [TimeSpan]::Parse(($j3.timezone.utc -replace '^\+', '')) } catch { } }
        if ($ipOff -ne $null -and $ipOff -eq $sysOff) { Write-Ok "System timezone ($($local.Id), UTC$($sysOff)) matches IP location ($ipTz)" }
        elseif ($ipOff -ne $null) { Write-Warn "System timezone $($local.Id) (UTC$sysOff) differs from IP timezone $ipTz (UTC$ipOff) - sites can detect VPN use" }
        else { Write-Info "IP timezone: $ipTz, system: $($local.Id)" }
    }

    Write-Section "DNS leak test"
    $li = Get-LocalNetInfo
    Write-KV "Configured DNS" $li.DNS
    $resolvers = @()
    $ak = Get-DnsRecords 'whoami.akamai.net' 'A'
    if ($ak.Count) { $resolvers += $ak[0] }
    $gg = Get-DnsRecords 'o-o.myaddr.l.google.com' 'TXT'
    foreach ($t in $gg) {
        if ($t -match '^\d+\.\d+\.\d+\.\d+$') { $resolvers += $t }
        elseif ($t -match 'edns0-client-subnet\s+(\S+)') { Write-Info "Resolver forwards your subnet (EDNS client-subnet): $($Matches[1])" }
    }
    $resolvers = @($resolvers | Select-Object -Unique)
    if (-not $resolvers.Count) {
        Write-Warn "Could not identify upstream resolvers"
    } else {
        $geo = Get-GeoInfo (@($resolvers) + $pip)
        $me = $geo[$pip]
        $myAs = if ($me) { ($me.as -split ' ')[0] } else { '' }
        $myCc = if ($me) { $me.countryCode } else { '' }
        $leak = $false
        foreach ($r in $resolvers) {
            $rg = $geo[$r]
            $ras = if ($rg) { ($rg.as -split ' ')[0] } else { '?' }
            W ("    {0,-16} {1,-36} " -f $r, (Limit-Text $(if ($rg) { $rg.as } else { 'unknown' }) 36)) -NoNewline
            if ($ras -eq $myAs) { W "same network as your public IP" 'Green' }
            else {
                if ($rg -and $rg.as -match 'Google|Cloudflare|Quad9|OpenDNS|Cisco|NextDNS|AdGuard') { W "public DNS provider" 'Cyan' -NoNewline } else { W "different network" 'Yellow' -NoNewline }
                if ($rg -and $myCc -and $rg.countryCode -ne $myCc) { W (" (country {0} != {1})" -f $rg.countryCode, $myCc) 'Yellow'; $leak = $true } else { Write-Host "" }
            }
        }
        if ($tunnels.Count) {
            if ($leak) { Write-Fail "Possible DNS leak: queries resolve outside the VPN exit country"; $issues++ }
            else { Write-Ok "No DNS leak detected - resolvers are consistent with the VPN exit" }
        }
    }

    Write-Section "WebRTC leak test (STUN)"
    Write-Note "  Browsers use STUN to discover your address for WebRTC. If it differs from"
    Write-Note "  your HTTP exit IP, sites can see your real IP even through a proxy/VPN."
    foreach ($s in @(@('stun.l.google.com', 19302), @('stun.cloudflare.com', 3478))) {
        $m = Get-StunMapped $s[0] $s[1]
        if ($m) {
            if (($m -split ':')[0] -eq $pip) { Write-Segs ("  " + $script:G.OK + " "), 'Green', "$($s[0]): $m ", '', "(matches HTTP exit IP)", 'DarkGray' }
            else { Write-Segs ("  " + $script:G.FAIL + " "), 'Red', "$($s[0]): ", '', $m, 'White', " differs from HTTP exit $pip - WebRTC/UDP leak", 'Red'; $issues++ }
        } else { Write-Note "  $($s[0]): no STUN response (UDP blocked?)" }
    }
    try {
        $lips = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.AddressState -eq 'Preferred' }).IPAddress -join ' '
        Write-KV "Local addresses" "$lips (hidden by modern browsers via mDNS)"
    } catch { }

    Write-Host ""
    Write-BoxTop
    if ($issues -eq 0) { Write-BoxLine ($script:G.OK + " No leaks or inconsistencies detected"), 'Green' }
    else { Write-BoxLine ("{0} {1} potential issue(s) found - see above" -f $script:G.WARN, $issues), 'Yellow' }
    Write-BoxBottom
    Write-LogEntry ("VPN/proxy test: pip={0} tunnels={1} resolvers={2} issues={3}" -f $pip, $tunnels.Count, ($resolvers -join ','), $issues)
    Wait-AnyKey
}

# ============================================================================
#  15. LOCAL PORTS & FIREWALL
# ============================================================================
function Start-LocalPorts {
    Show-Header "Local Ports & Firewall"
    Write-Note "Leave empty to list every listening port."
    $spec = Read-Input "Ports to check (e.g. 80,443,3389)" ""
    Show-Header "Local Ports & Firewall"
    Write-LogEntry "Local port check: $(if ($spec) { $spec } else { 'all' })"
    $filter = @(); if ($spec) { $filter = Expand-Ports $spec }
    $procs = @{}; Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $procs[$_.Id] = $_.ProcessName }
    $rows = @()
    try {
        $rows += Get-NetTCPConnection -State Listen -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Proto = 'tcp'; Port = [int]$_.LocalPort; Addr = $_.LocalAddress; Pid = $_.OwningProcess } }
        $rows += Get-NetUDPEndpoint -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Proto = 'udp'; Port = [int]$_.LocalPort; Addr = $_.LocalAddress; Pid = $_.OwningProcess } }
    } catch {
        Write-Warn "Get-NetTCPConnection unavailable - falling back to netstat"
        $ns = @(); try { $ns = @(netstat -ano 2>$null) } catch { Write-Fail "netstat is not available either" }
        foreach ($l in ($ns | Select-String -Pattern '^\s*(TCP|UDP)\s+(\S+):(\d+)\s+\S+\s+(LISTENING\s+)?(\d+)\s*$')) {
            $m = $l.Matches[0].Groups
            if ($m[1].Value -eq 'TCP' -and -not $m[4].Value) { continue }
            $rows += [pscustomobject]@{ Proto = $m[1].Value.ToLower(); Port = [int]$m[3].Value; Addr = $m[2].Value; Pid = [int]$m[5].Value }
        }
    }
    $rows = @($rows | Sort-Object Proto, Port, Addr -Unique)
    if ($filter.Count) { $rows = @($rows | Where-Object { $filter -contains $_.Port }) }
    Write-Section "Listening sockets"
    W ("    {0,-6}{1,-8}{2,-24}{3,-13}{4}" -f 'PROTO', 'PORT', 'ADDRESS', 'SERVICE', 'PROCESS') 'White'
    foreach ($r in $rows) {
        $scope = if ($r.Addr -match '^(127\.|::1$)') { 'DarkGray' } else { 'Yellow' }
        $pn = if ($procs.ContainsKey([int]$r.Pid)) { $procs[[int]$r.Pid] } else { '?' }
        W ("    {0,-6}{1,-8}" -f $r.Proto, $r.Port) -NoNewline
        W ("{0,-24}" -f (Limit-Text $r.Addr 23)) $scope -NoNewline
        W ("{0,-13}{1} (pid {2})" -f (Get-ServiceName $r.Port), $pn, $r.Pid)
    }
    Write-Note "  Yellow address = reachable from the network, grey = localhost only."
    foreach ($p in $filter) { if (-not ($rows | Where-Object { $_.Port -eq $p })) { Write-Warn "Port ${p}: nothing listening" } }

    Write-Section "Windows Firewall"
    $admin = $false
    try { $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { }
    try {
        foreach ($pr in (Get-NetFirewallProfile -ErrorAction Stop)) {
            $st = if ($pr.Enabled) { 'on' } else { 'off' }
            W ("    {0,-10} " -f $pr.Name) -NoNewline
            W ("{0,-4}" -f $st) $(if ($pr.Enabled) { 'Green' } else { 'Red' }) -NoNewline
            W ("  inbound default: {0}  outbound default: {1}" -f $pr.DefaultInboundAction, $pr.DefaultOutboundAction) 'DarkGray'
        }
        if ($filter.Count) {
            Write-Info "Reading firewall rules (this can take a few seconds)..."
            $pf = @(Get-NetFirewallPortFilter -PolicyStore ActiveStore -ErrorAction Stop)
            foreach ($p in $filter) {
                $match = @($pf | Where-Object {
                    $lp = @($_.LocalPort)
                    ($lp -contains [string]$p) -or ($lp | Where-Object { $_ -match '^(\d+)-(\d+)$' -and $p -ge [int]$Matches[1] -and $p -le [int]$Matches[2] })
                })
                $rules = @($match | Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.Direction -eq 'Inbound' -and $_.Enabled -eq 'True' })
                $blk = @($rules | Where-Object { $_.Action -eq 'Block' }); $alw = @($rules | Where-Object { $_.Action -eq 'Allow' })
                if ($blk.Count) { Write-Fail ("Port {0}: BLOCKED by '{1}'" -f $p, $blk[0].DisplayName) }
                elseif ($alw.Count) { Write-Ok ("Port {0}: allowed by '{1}'{2}" -f $p, $alw[0].DisplayName, $(if ($alw.Count -gt 1) { " (+$($alw.Count - 1) more)" })) }
                else { Write-Info "Port ${p}: no explicit rule (default inbound policy applies)" }
            }
        }
    } catch {
        Write-Fail "Could not read firewall configuration: $($_.Exception.Message)"
    }
    if (-not $admin) { Write-Note "  Tip: run PowerShell as Administrator for complete rule and process information." }
    Wait-AnyKey
}

# ============================================================================
#  16. SMTP TEST (own SMTP client: supports none / implicit TLS / STARTTLS)
# ============================================================================
function Invoke-SmtpSession {
    param([string]$Server, [int]$Port, [int]$Enc, [string]$User = '', [string]$Pass = '', $Mail = $null)
    $log = New-Object System.Collections.ArrayList
    $res = [pscustomobject]@{ Ok = $false; Banner = ''; Caps = @(); Tls = ''; CertOk = $null; Error = ''; Log = $log }
    $tcp = New-Object System.Net.Sockets.TcpClient
    $enc8 = New-Object System.Text.UTF8Encoding($false)
    $certErr = @{ E = $null }
    $cb = [System.Net.Security.RemoteCertificateValidationCallback] { param($s, $c, $ch, $e) $certErr.E = $e; return ($e -eq 'None') }
    try {
        $iar = $tcp.BeginConnect($Server, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(10000, $false)) { throw "Connection timed out" }
        $tcp.EndConnect($iar)
        $tcp.ReceiveTimeout = 15000
        $stream = $tcp.GetStream()
        if ($Enc -eq 2) {
            $ssl = New-Object System.Net.Security.SslStream($stream, $false, $cb)
            $ssl.AuthenticateAsClient($Server); $stream = $ssl; $res.Tls = [string]$ssl.SslProtocol
        }
        $rd = New-Object System.IO.StreamReader($stream, $enc8)
        $wr = New-Object System.IO.StreamWriter($stream, $enc8); $wr.NewLine = "`r`n"; $wr.AutoFlush = $true
        $readReply = {
            $lines = @()
            do { $l = $rd.ReadLine(); if ($null -eq $l) { throw "Connection closed by server" }; $lines += $l; [void]$log.Add("S: $l") } while ($l.Length -ge 4 -and $l[3] -eq '-')
            return , $lines
        }
        $send = { param($cmd, [switch]$Secret) if ($Secret) { [void]$log.Add("C: ****") } else { [void]$log.Add("C: $cmd") }; $wr.WriteLine($cmd) }
        $code = { param($lines) [int]($lines[-1].Substring(0, 3)) }

        $r = & $readReply; $res.Banner = $r[0]
        if ((& $code $r) -ne 220) { throw "Unexpected banner: $($r[0])" }
        & $send "EHLO pingporttester"; $r = & $readReply
        if ((& $code $r) -ne 250) { throw "EHLO rejected: $($r[-1])" }
        $res.Caps = @($r | Select-Object -Skip 1 | ForEach-Object { $_.Substring(4) })
        if ($Enc -eq 3) {
            & $send "STARTTLS"; $r = & $readReply
            if ((& $code $r) -ne 220) { throw "STARTTLS not accepted: $($r[-1])" }
            $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, $cb)
            $ssl.AuthenticateAsClient($Server); $res.Tls = [string]$ssl.SslProtocol
            $rd = New-Object System.IO.StreamReader($ssl, $enc8)
            $wr = New-Object System.IO.StreamWriter($ssl, $enc8); $wr.NewLine = "`r`n"; $wr.AutoFlush = $true
            & $send "EHLO pingporttester"; $r = & $readReply
            $res.Caps = @($r | Select-Object -Skip 1 | ForEach-Object { $_.Substring(4) })
        }
        if ($res.Tls) { $res.CertOk = ($certErr.E -eq 'None') }
        if ($Mail) {
            if ($User) {
                $authLine = ($res.Caps | Where-Object { $_ -match '^AUTH' }) -join ' '
                if ($authLine -match 'PLAIN') {
                    $tok = [Convert]::ToBase64String($enc8.GetBytes("`0$User`0$Pass"))
                    & $send "AUTH PLAIN $tok" -Secret; $r = & $readReply
                } else {
                    & $send "AUTH LOGIN"; $r = & $readReply
                    & $send ([Convert]::ToBase64String($enc8.GetBytes($User))) -Secret; $r = & $readReply
                    & $send ([Convert]::ToBase64String($enc8.GetBytes($Pass))) -Secret; $r = & $readReply
                }
                if ((& $code $r) -ne 235) { throw "Authentication failed: $($r[-1])" }
            }
            & $send "MAIL FROM:<$($Mail.From)>"; $r = & $readReply; if ((& $code $r) -ne 250) { throw "MAIL FROM rejected: $($r[-1])" }
            & $send "RCPT TO:<$($Mail.To)>"; $r = & $readReply; if ((& $code $r) -notin 250, 251) { throw "RCPT TO rejected: $($r[-1])" }
            & $send "DATA"; $r = & $readReply; if ((& $code $r) -ne 354) { throw "DATA rejected: $($r[-1])" }
            $date = [DateTime]::Now.ToString('ddd, dd MMM yyyy HH:mm:ss ', [Globalization.CultureInfo]::InvariantCulture) + ([DateTimeOffset]::Now.ToString('zzz') -replace ':', '')
            $msg = @("From: $($Mail.From)", "To: $($Mail.To)", "Subject: $($Mail.Subject)", "Date: $date",
                "Message-ID: <$([Guid]::NewGuid().ToString('N'))@pingporttester>", "MIME-Version: 1.0", "Content-Type: text/plain; charset=utf-8", "")
            $msg += ($Mail.Body -split "`r?`n" | ForEach-Object { if ($_.StartsWith('.')) { ".$_" } else { $_ } })
            foreach ($l in $msg) { $wr.WriteLine($l) }
            [void]$log.Add("C: <message body>")
            & $send "."; $r = & $readReply; if ((& $code $r) -ne 250) { throw "Message rejected: $($r[-1])" }
        }
        & $send "QUIT"; try { $null = & $readReply } catch { }
        $res.Ok = $true
    } catch {
        $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }
        $res.Error = $e.Message
        if ($certErr.E -and $certErr.E -ne 'None') { $res.CertOk = $false; $res.Error += " (TLS certificate: $($certErr.E))" }
    } finally { $tcp.Close() }
    return $res
}

function Start-SmtpTest {
    Show-Header "SMTP Test"
    $server = Read-Required "SMTP server" "smtp.gmail.com"
    Write-Note "  25 = SMTP   465 = implicit TLS   587 = STARTTLS submission"
    $port = Read-Int "Port" 587 1 65535
    $def = 3; if ($port -eq 465) { $def = 2 } elseif ($port -eq 25) { $def = 1 }
    $enc = Read-Choice "Encryption" $def @('None', 'SSL/TLS (implicit, port 465)', 'STARTTLS (port 587/25)')
    $action = Read-Choice "Action" 1 @('Connection & capability test only (no login)', 'Send a test email')
    $encName = @('none', 'SSL/TLS', 'STARTTLS')[$enc - 1]
    if ($action -eq 1) {
        Show-Header "SMTP $($script:G.RIGHT) ${server}:$port"
        $r = Invoke-SmtpSession $server $port $enc
        if ($r.Banner) { Write-Ok "Server banner: $($r.Banner)" }
        if ($r.Caps.Count) {
            Write-Section "Capabilities"
            $r.Caps | ForEach-Object { W "    $_" }
            if ($r.Caps -match '^STARTTLS') { Write-Ok "STARTTLS offered" }
            $auth = $r.Caps | Where-Object { $_ -match '^AUTH' } | Select-Object -First 1
            if ($auth) { Write-Ok "Authentication: $auth" }
        }
        if ($r.Tls) { Write-Ok "TLS: $($r.Tls)" }
        if ($r.CertOk -eq $true) { Write-Ok "TLS certificate verified" } elseif ($r.CertOk -eq $false) { Write-Fail "TLS certificate is NOT valid" }
        if (-not $r.Ok) { Write-Fail "Error: $($r.Error)" }
        Write-LogEntry "SMTP probe ${server}:$port ($encName): $(if ($r.Ok) { 'OK' } else { $r.Error })"
        Wait-AnyKey; return
    }
    Write-Host ""
    $from = Read-Required "From address"
    $user = Read-Input "Username (blank = no auth)" $from
    $plain = ''
    if ($user) {
        $sec = Read-Host "  > Password" -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    $to = Read-Required "To address"
    $subject = Read-Input "Subject" "Test email from PingPortTester"
    $body = "This is a test email sent from PingPortTester $script:PPTVersion.`r`n`r`nTimestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`nServer: ${server}:$port`r`nEncryption: $encName"
    Write-Host ""
    Write-BoxTop "Summary"
    Write-BoxLine "Server  ${server}:$port  ($encName)", ''
    Write-BoxLine "From    $from", ''
    Write-BoxLine "To      $to", ''
    Write-BoxLine "Subject $subject", ''
    Write-BoxBottom
    if (-not (Read-YesNo "Send email?" "y")) { Write-Warn "Cancelled"; Wait-AnyKey; return }
    if ($enc -eq 1 -and $user) { Write-Warn "Sending credentials without encryption!" }
    Write-LogEntry "SMTP send: ${server}:$port ($encName) from=$from to=$to"
    $r = Invoke-SmtpSession $server $port $enc $user $plain ([pscustomobject]@{ From = $from; To = $to; Subject = $subject; Body = $body })
    $plain = $null
    if ($r.Ok) { Write-Ok "Email sent to $to"; Write-LogEntry "SMTP: SUCCESS" }
    else {
        Write-Fail "Sending failed: $($r.Error)"
        Write-Section "Transcript (last lines)"
        $r.Log | Select-Object -Last 8 | ForEach-Object { W "    $_" 'DarkGray' }
        Write-LogEntry "SMTP: FAILED $($r.Error)"
    }
    Wait-AnyKey
}

# ============================================================================
#  SETTINGS & LOG VIEWER
# ============================================================================
function Start-Settings {
    while ($true) {
        Show-Header "Settings"
        Write-BoxTop "Current settings"
        Write-BoxLine "1  Logging          ", '', $(if ($script:LogEnabled) { 'on' } else { 'off' }), $(if ($script:LogEnabled) { 'Green' } else { 'Red' })
        Write-BoxLine ("2  Log file         " + (Limit-Text $script:LogFile ($script:UIW - 25))), ''
        Write-BoxLine ("3  Network timeout  {0}s" -f ($script:TimeoutMs / 1000)), ''
        Write-BoxLine ("4  Colours          " + $(if ($script:UseColor) { 'on' } else { 'off' })), ''
        Write-BoxLine ("5  Unicode glyphs   " + $(if ($script:UseUnicode) { 'on' } else { 'off' })), ''
        Write-BoxSep
        Write-BoxLine "0  Back", ''
        Write-BoxBottom
        switch (Read-Input "Change" "0") {
            '1' { $script:LogEnabled = -not $script:LogEnabled; if ($script:LogEnabled) { Initialize-Log } }
            '2' { $script:LogFile = Read-Input "Log file" $script:LogFile; Initialize-Log }
            '3' { $script:TimeoutMs = (Read-Int "Timeout seconds" ($script:TimeoutMs / 1000) 1 30) * 1000 }
            '4' { $script:UseColor = -not $script:UseColor }
            '5' { $script:UseUnicode = -not $script:UseUnicode; Initialize-UI }
            default { return }
        }
    }
}

function Start-LogViewer {
    Show-Header "Log Viewer"
    if (-not $script:LogEnabled -or -not (Test-Path $script:LogFile) -or (Get-Item $script:LogFile).Length -eq 0) { Write-Info "Log is empty or disabled."; Wait-AnyKey; return }
    Write-KV "File" (Limit-Text $script:LogFile ($script:UIW - 24))
    Write-KV "Size" ("{0} KB" -f (Fmt ((Get-Item $script:LogFile).Length / 1KB)))
    Write-Section "Last 30 entries"
    foreach ($l in (Get-Content $script:LogFile -Tail 30)) {
        $col = if ($l -match 'DROPPED|FAIL|CLOSED') { 'Red' } else { 'DarkGray' }
        W ("    " + (Limit-Text $l ($script:UIW - 4))) $col
    }
    Write-Host ""
    if (Read-YesNo "Clear the log?" "n") { Clear-Content $script:LogFile; Write-Ok "Log cleared" }
    Wait-AnyKey
}

# ============================================================================
#  MAIN MENU
# ============================================================================
$script:Menu = @(
    @{ Section = 'Connectivity' }
    @{ Key = '1'; Label = 'Ping monitor';           Desc = 'Continuous ICMP ping with live stats';  Fn = 'Start-PingMonitor' }
    @{ Key = '2'; Label = 'Packet loss analysis';   Desc = 'Loss, jitter, percentiles, MOS';        Fn = 'Start-PacketLoss' }
    @{ Key = '3'; Label = 'TCP port monitor';       Desc = 'Continuous TCP connect latency';        Fn = 'Start-TcpMonitor' }
    @{ Key = '4'; Label = 'UDP port test';          Desc = 'Protocol-aware UDP probe';              Fn = 'Start-UdpTest' }
    @{ Key = '5'; Label = 'Port scanner';           Desc = 'Parallel TCP/UDP range scan';           Fn = 'Start-PortScan' }
    @{ Section = 'Path & DNS' }
    @{ Key = '6'; Label = 'Traceroute';             Desc = 'Trace the network path';                Fn = 'Start-Traceroute' }
    @{ Key = '7'; Label = 'Path analysis (MTR)';    Desc = 'Per-hop loss, ASN and geo route';       Fn = 'Start-PathAnalysis' }
    @{ Key = '8'; Label = 'DNS lookup';             Desc = 'Resolvers, all records, SPF/DMARC';     Fn = 'Start-DnsLookup' }
    @{ Section = 'Internet' }
    @{ Key = '9'; Label = 'Bandwidth test';         Desc = 'Download, upload, latency';             Fn = 'Start-Bandwidth' }
    @{ Key = 'i'; Label = 'Public IP & network';    Desc = 'Local + public addressing, ISP';        Fn = 'Start-PublicIP' }
    @{ Key = 'e'; Label = 'External port check';    Desc = 'Reachability from the internet';        Fn = 'Start-ExternalPorts' }
    @{ Key = 'w'; Label = 'Web performance';        Desc = 'Timing, waterfall, HTTP/2/3, CDN';      Fn = 'Start-WebPerf' }
    @{ Section = 'Security' }
    @{ Key = 't'; Label = 'SSL/TLS check';          Desc = 'Certificate, chain, protocols, cipher'; Fn = 'Start-SslCheck' }
    @{ Key = 'v'; Label = 'VPN / proxy / leaks';    Desc = 'Tunnel, geo, DNS & WebRTC leaks';       Fn = 'Start-VpnTest' }
    @{ Key = 'f'; Label = 'Local ports & firewall'; Desc = 'Listeners and firewall rules';          Fn = 'Start-LocalPorts' }
    @{ Section = 'Tools' }
    @{ Key = 'm'; Label = 'SMTP test';              Desc = 'Probe server or send a test email';     Fn = 'Start-SmtpTest' }
    @{ Key = 's'; Label = 'Settings';               Desc = 'Logging, timeout, display';             Fn = 'Start-Settings' }
    @{ Key = 'l'; Label = 'View log';               Desc = 'Recent log entries';                    Fn = 'Start-LogViewer' }
    @{ Key = 'q'; Label = 'Quit';                   Desc = 'Exit PingPortTester';                   Fn = 'QUIT' }
)

function Get-SysInfo {
    $li = Get-LocalNetInfo
    $os = [Environment]::OSVersion.VersionString
    try { $os = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption -replace 'Microsoft ', '' } catch { }
    $ip = if ($li.LocalIP) { $li.LocalIP } else { 'no network' }
    $gw = if ($li.Gateway) { $li.Gateway } else { '?' }
    return ("{0}  {1}  {2}  {1}  gw {3}  {1}  {4}  {1}  PS {5}" -f [Environment]::MachineName, $script:G.DOT, $ip, $gw, $os, $PSVersionTable.PSVersion.ToString())
}

function Write-MenuLine {
    param([string]$Text, [string]$Fg = '', [string]$Bg = '', [int]$Used = 0)
    $Text = Limit-Text $Text ([Math]::Max(4, $script:TermW - 1 - $Used))
    $pad = [Math]::Max(0, $script:TermW - 1 - $Used - $Text.Length)
    W ($Text + (' ' * $pad)) $Fg -Bg $Bg
}

function Show-MainMenu {
    param([int]$Sel, [switch]$Full)
    Update-TermSize
    if ($Full -or -not $script:IsConsole) { Clear-Host } else { try { [Console]::SetCursorPosition(0, 0) } catch { Clear-Host } }
    $items = @($script:Menu | Where-Object { $_.Key })
    $compact = $script:TermH -lt 38
    if ($compact) {
        $hdr = "  PingPortTester v{0}  {1}  " -f $script:PPTVersion, $script:G.DOT
        W $hdr 'Cyan' -NoNewline
        Write-MenuLine $script:SysInfo 'DarkGray' -Used $hdr.Length
        Write-MenuLine ""
        # two columns: first two sections left, rest right
        $left = @(); $right = @(); $sec = -1; $idx = 0
        foreach ($m in $script:Menu) {
            if ($m.Section) { $sec++; $o = [pscustomobject]@{ Text = $m.Section; Sel = $false; Section = $true } }
            else { $o = [pscustomobject]@{ Text = (" [{0}] {1}" -f $m.Key, $m.Label); Sel = ($idx -eq $Sel); Section = $false }; $idx++ }
            if ($sec -le 1) { $left += $o } else { $right += $o }
        }
        $cw = [int][Math]::Floor(($script:TermW - 6) / 2)
        for ($r = 0; $r -lt [Math]::Max($left.Count, $right.Count); $r++) {
            W "  " -NoNewline
            foreach ($col in @($left, $right)) {
                if ($r -lt $col.Count) {
                    $o = $col[$r]; $t = $o.Text.PadRight($cw)
                    if ($o.Section) { W $t 'Magenta' -NoNewline }
                    elseif ($o.Sel) { W $t 'White' -Bg 'DarkCyan' -NoNewline }
                    else { W $t -NoNewline }
                } else { W (' ' * $cw) -NoNewline }
                W "  " -NoNewline
            }
            Write-Host ""
        }
        Write-MenuLine ""
        Write-MenuLine ("  " + $script:G.PTR + " " + $items[$Sel].Desc) 'White'
    } else {
        Write-Logo
        Write-MenuLine ("  v{0} {1} network connectivity toolkit" -f $script:PPTVersion, $script:G.DOT) 'DarkGray'
        Write-BoxTop
        Write-BoxLine (Limit-Text $script:SysInfo ($script:UIW - 4)), 'DarkGray'
        Write-BoxBottom
        $idx = 0
        foreach ($m in $script:Menu) {
            if ($m.Section) {
                if ($script:TermH -ge 43) { Write-MenuLine "" }
                Write-MenuLine ("  " + $m.Section) 'Magenta'
                continue
            }
            if ($idx -eq $Sel) {
                Write-MenuLine ("   {0} [{1}] {2,-24} {3}" -f $script:G.PTR, $m.Key, $m.Label, $m.Desc) 'White' 'DarkCyan'
            } else {
                W "     " -NoNewline; W ("[{0}]" -f $m.Key) 'Cyan' -NoNewline
                W (" {0,-24} " -f $m.Label) -NoNewline
                Write-MenuLine $m.Desc 'DarkGray' -Used (9 + 26)
            }
            $idx++
        }
        Write-MenuLine ""
    }
    Write-MenuLine ("  {0}/{1} move  {2}  Enter select  {2}  hotkey jumps  {2}  q quit" -f $script:G.UP, $script:G.DOWN, $script:G.DOT) 'DarkGray'
    if (-not $script:IsConsole) { Write-Note "(Non-interactive host: type a hotkey and press Enter)" }
}

function Start-MainMenu {
    $items = @($script:Menu | Where-Object { $_.Key })
    $sel = 0; $full = $true
    $lastW = $script:TermW; $lastH = $script:TermH
    while ($true) {
        Update-TermSize
        if ($script:TermW -ne $lastW -or $script:TermH -ne $lastH) { $full = $true; $lastW = $script:TermW; $lastH = $script:TermH }
        Show-MainMenu $sel -Full:$full
        $full = $false
        $k = Read-MenuKey
        $run = $null
        switch -CaseSensitive ($k) {
            'UP'    { $sel = ($sel - 1 + $items.Count) % $items.Count; continue }
            'DOWN'  { $sel = ($sel + 1) % $items.Count; continue }
            'HOME'  { $sel = 0; continue }
            'END'   { $sel = $items.Count - 1; continue }
            'ENTER' { $run = $items[$sel].Fn; continue }
            'RIGHT' { $run = $items[$sel].Fn; continue }
            'ESC'   { continue }
            default {
                $kk = ([string]$k).ToLower()
                for ($i = 0; $i -lt $items.Count; $i++) { if ($items[$i].Key -eq $kk) { $sel = $i; $run = $items[$i].Fn; break } }
            }
        }
        if ($run) {
            if ($run -eq 'QUIT') { return }
            try { & $run } catch {
                Write-Host ""
                Write-Fail "Unexpected error: $($_.Exception.Message)"
                Write-LogEntry "ERROR in ${run}: $($_.Exception.Message)"
                Wait-AnyKey
            }
            Exit-MonitorMode
            $full = $true
        }
    }
}

# ============================================================================
#  ENTRY POINT
# ============================================================================
function Start-PingPortTester {
    Initialize-UI
    Initialize-Log
    $cmd = Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $script:CurlExe = $cmd.Source }
    $script:SysInfo = Get-SysInfo
    Write-LogEntry "PingPortTester $script:PPTVersion session started"
    try {
        Start-MainMenu
    } finally {
        Exit-MonitorMode
    }
    Clear-Host
    Write-Logo
    Write-Host ""
    if ($script:LogEnabled) { Write-Info "Log saved to $script:LogFile" }
    Write-Note "Thanks for using PingPortTester."
    Write-Host ""
    Write-LogEntry "Session ended"
}

Start-PingPortTester
