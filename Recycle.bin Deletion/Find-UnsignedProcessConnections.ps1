#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Finds running processes with unsigned/invalid Authenticode signatures
    and lists their active outbound TCP connections (destination IPs/ports).

.NOTES
    - Must be run elevated (Get-NetTCPConnection requires admin).
    - "Unsigned" here means Status -ne 'Valid' (includes NotSigned, HashMismatch, etc.).
    - System processes without a Path (e.g. System, Idle) are skipped.
    - Local/loopback connections are filtered by default.
#>

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "Enumerating processes and checking signatures..." -ForegroundColor Cyan

# Get processes that have a path and an invalid/unsigned signature
$unsignedProcs = Get-Process | Where-Object {
    $_.Path -and (Get-AuthenticodeSignature -FilePath $_.Path).Status -ne 'Valid'
} | Select-Object Id, ProcessName, Path, 
    @{Name='SignatureStatus'; Expression={(Get-AuthenticodeSignature $_.Path).Status}},
    @{Name='Signer'; Expression={(Get-AuthenticodeSignature $_.Path).SignerCertificate.Subject}}

if (-not $unsignedProcs) {
    Write-Host "No unsigned/invalidly signed processes found." -ForegroundColor Green
    return
}

Write-Host "Found $($unsignedProcs.Count) process(es) with non-Valid signatures.`n" -ForegroundColor Yellow

$results = foreach ($proc in $unsignedProcs) {
    # Active TCP connections owned by this PID
    $tcpConns = Get-NetTCPConnection -OwningProcess $proc.Id -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.State -eq 'Established' -and
                    $_.RemoteAddress -notmatch '^(127\.|::1|0\.0\.0\.0|::)' -and
                    $_.RemoteAddress -ne $null
                } |
                Select-Object RemoteAddress, RemotePort, State

    # Optional: also grab UDP (less useful for "destination" but included)
    $udpConns = Get-NetUDPConnection -OwningProcess $proc.Id -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.RemoteAddress -notmatch '^(127\.|::1|0\.0\.0\.0|::)' -and
                    $_.RemoteAddress -ne $null
                } |
                Select-Object RemoteAddress, RemotePort

    # Build output object
    [PSCustomObject]@{
        PID              = $proc.Id
        ProcessName      = $proc.ProcessName
        Path             = $proc.Path
        SignatureStatus  = $proc.SignatureStatus
        Signer           = $proc.Signer
        TCP_Destinations = ($tcpConns | ForEach-Object { "$($_.RemoteAddress):$($_.RemotePort)" }) -join ', '
        UDP_Destinations = ($udpConns | ForEach-Object { "$($_.RemoteAddress):$($_.RemotePort)" }) -join ', '
        TCP_Count        = @($tcpConns).Count
        UDP_Count        = @($udpConns).Count
    }
}

# Display results
$results | Format-Table -AutoSize -Wrap PID, ProcessName, SignatureStatus, TCP_Count, TCP_Destinations

# Optional: export to CSV
$csvPath = "$env:USERPROFILE\Desktop\UnsignedProcessConnections_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "`nFull results exported to: $csvPath" -ForegroundColor Green

# Optional: show processes with no connections
$noConn = $results | Where-Object { $_.TCP_Count -eq 0 -and $_.UDP_Count -eq 0 }
if ($noConn) {
    Write-Host "`nUnsigned processes with no remote connections:" -ForegroundColor DarkYellow
    $noConn | Select-Object PID, ProcessName, SignatureStatus, Path | Format-Table -AutoSize
}
