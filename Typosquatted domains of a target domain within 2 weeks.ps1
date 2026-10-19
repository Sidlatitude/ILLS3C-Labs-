<#
.SYNOPSIS
    Generates typosquat candidates, keeps only live domains, and filters to those
    registered in the last 2 weeks using free RDAP lookups.

.NOTES
    Pure PowerShell + public RDAP. No API key required.
    Many domains redact creation dates due to privacy — those will be skipped.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetDomain
)

# --- Keyboard + homoglyph maps ---
$keyboard = @{
    'q'=@('w','a'); 'w'=@('q','e','s'); 'e'=@('w','r','d'); 'r'=@('e','t','f')
    't'=@('r','y','g'); 'y'=@('t','u','h'); 'u'=@('y','i','j'); 'i'=@('u','o','k')
    'o'=@('i','p','l'); 'p'=@('o'); 'a'=@('q','s','z'); 's'=@('a','w','d','x')
    'd'=@('s','e','f','c'); 'f'=@('d','r','g','v'); 'g'=@('f','t','h','b')
    'h'=@('g','y','j','n'); 'j'=@('h','u','k','m'); 'k'=@('j','i','l'); 'l'=@('k','o')
    'z'=@('a','x'); 'x'=@('z','s','c'); 'c'=@('x','d','v'); 'v'=@('c','f','b')
    'b'=@('v','g','n'); 'n'=@('b','h','m'); 'm'=@('n','j')
}
$homoglyphs = @{
    'o'=@('0'); '0'=@('o'); 'l'=@('1','i'); '1'=@('l','i'); 'i'=@('l','1')
    's'=@('5'); '5'=@('s'); 'e'=@('3'); '3'=@('e'); 'a'=@('4'); '4'=@('a')
}

function Get-DomainParts($Domain) {
    $parts = $Domain.ToLower() -split '\.'
    if ($parts.Count -lt 2) { throw "Invalid domain format." }
    [PSCustomObject]@{ Name = ($parts[0..($parts.Count-2)] -join '.'); TLD = $parts[-1] }
}

function Add-Variation($Set, $Candidate) {
    if ($Candidate -and $Candidate.Length -ge 3 -and $Candidate -ne $script:baseName) {
        $Set.Add("$Candidate.$script:tld") | Out-Null
    }
}

function Get-DomainCreationDate {
    param([string]$Domain)

    $rdapUrls = @(
        "https://rdap.org/domain/$Domain",
        "https://rdap.verisign.com/com/v1/domain/$Domain",
        "https://rdap.verisign.com/net/v1/domain/$Domain",
        "https://rdap.nic.io/domain/$Domain"
    )

    foreach ($url in $rdapUrls) {
        try {
            $response = Invoke-RestMethod -Uri $url -ErrorAction Stop -TimeoutSec 12
            $event = $response.events | Where-Object { $_.eventAction -eq 'registration' } | Select-Object -First 1
            if ($event -and $event.eventDate) {
                return [DateTime]$event.eventDate
            }
        } catch { }
    }
    return $null
}

# Parse target
$parsed = Get-DomainParts $TargetDomain
$script:baseName = $parsed.Name
$script:tld = $parsed.TLD
$cutoff = (Get-Date).AddDays(-14)

Write-Host "Target: $TargetDomain" -ForegroundColor Cyan
Write-Host "Looking for live typosquats registered after $($cutoff.ToString('yyyy-MM-dd'))`n" -ForegroundColor Cyan

$candidates = [System.Collections.Generic.HashSet[string]]::new()

# Generate candidates
for ($i = 0; $i -lt $script:baseName.Length; $i++) {
    Add-Variation $candidates ($script:baseName.Remove($i, 1))
}
for ($i = 0; $i -lt ($script:baseName.Length - 1); $i++) {
    $chars = $script:baseName.ToCharArray()
    $tmp = $chars[$i]; $chars[$i] = $chars[$i+1]; $chars[$i+1] = $tmp
    Add-Variation $candidates (-join $chars)
}
$extras = @('a','e','i','o','u','s','n','r')
for ($i = 0; $i -le $script:baseName.Length; $i++) {
    foreach ($e in $extras) { Add-Variation $candidates ($script:baseName.Insert($i, $e)) }
}
for ($i = 0; $i -lt $script:baseName.Length; $i++) {
    $c = [string]$script:baseName[$i]
    if ($keyboard.ContainsKey($c)) {
        foreach ($sub in $keyboard[$c]) {
            Add-Variation $candidates ($script:baseName.Remove($i,1).Insert($i, $sub))
        }
    }
    if ($homoglyphs.ContainsKey($c)) {
        foreach ($sub in $homoglyphs[$c]) {
            Add-Variation $candidates ($script:baseName.Remove($i,1).Insert($i, $sub))
        }
    }
}
foreach ($alt in @('com','net','org','info','co','io')) {
    if ($alt -ne $script:tld) { $candidates.Add("$script:baseName.$alt") | Out-Null }
}

Write-Host "Checking $($candidates.Count) candidates (live DNS + RDAP creation date)...`n" -ForegroundColor Yellow

$recentLive = @()

foreach ($domain in ($candidates | Sort-Object)) {
    # Must resolve
    $ip = $null
    try {
        $dns = Resolve-DnsName -Name $domain -Type A -ErrorAction Stop -DnsOnly
        $ip = ($dns | Where-Object Type -eq 'A' | Select-Object -First 1).IPAddress
    } catch { continue }
    if (-not $ip) { continue }

    # Check RDAP registration date
    $created = Get-DomainCreationDate $domain
    if ($created -and $created -ge $cutoff) {
        $recentLive += [PSCustomObject]@{
            Domain     = $domain
            IP         = $ip
            Registered = $created.ToString('yyyy-MM-dd')
            AgeDays    = [math]::Round(((Get-Date) - $created).TotalDays, 1)
        }
    }

    Start-Sleep -Milliseconds 200   # be polite to RDAP servers
}

# Output
if ($recentLive) {
    Write-Host "=== LIVE TYPOSQUATS REGISTERED IN LAST 2 WEEKS ===" -ForegroundColor Green
    $recentLive | Sort-Object Registered -Descending | Format-Table Domain, IP, Registered, AgeDays -AutoSize

    $csv = "$env:USERPROFILE\Desktop\RecentLiveTyposquats_$($script:baseName)_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
    $recentLive | Export-Csv $csv -NoTypeInformation
    Write-Host "`nExported to: $csv" -ForegroundColor Cyan
} else {
    Write-Host "No live typosquat domains found with a registration date in the last 2 weeks." -ForegroundColor Gray
    Write-Host "(Many domains hide creation dates via privacy services.)" -ForegroundColor DarkYellow
}