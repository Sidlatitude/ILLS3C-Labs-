# OSINT Username Search via Google Dorks
# Opens Google searches for a target username across major social platforms

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,

    [string]$Browser = "default",  # Options: "default", "chrome", "edge", "firefox"
    [int]$DelaySeconds = 2         # Delay between opening each search (to be polite)
)

# Google dork templates — customize these as needed
$Dorks = @(
    # Instagram
    'site:instagram.com "{0}"',
    'site:instagram.com inurl:"{0}"',
    'site:instagram.com "{0}" (bio OR about OR profile)',

    # Facebook
    'site:facebook.com "{0}"',
    'site:facebook.com/people "{0}"',
    'site:facebook.com "{0}" (profile OR page)',

    # LinkedIn
    'site:linkedin.com/in "{0}"',
    'site:linkedin.com "{0}"',
    'site:linkedin.com/pub "{0}"',

    # X / Twitter
    'site:x.com "{0}"',
    'site:twitter.com "{0}"',
    'site:x.com "{0}" (bio OR joined OR from)',
    'site:twitter.com "{0}" (bio OR joined)'
)

function Open-GoogleSearch {
    param(
        [string]$Query,
        [string]$BrowserChoice
    )

    $encodedQuery = [System.Uri]::EscapeDataString($Query)
    $url = "https://www.google.com/search?q=$encodedQuery"

    switch ($BrowserChoice.ToLower()) {
        "chrome"  { Start-Process "chrome" $url }
        "edge"    { Start-Process "msedge" $url }
        "firefox" { Start-Process "firefox" $url }
        default   { Start-Process $url }  # default browser
    }
}

Write-Host "Running OSINT Google dorks for username: $Username" -ForegroundColor Cyan
Write-Host "Browser: $Browser | Delay: ${DelaySeconds}s between searches`n" -ForegroundColor Gray

$i = 1
foreach ($dorkTemplate in $Dorks) {
    $query = $dorkTemplate -f $Username
    Write-Host "[$i/$($Dorks.Count)] $query" -ForegroundColor Yellow

    Open-GoogleSearch -Query $query -BrowserChoice $Browser

    $i++
    if ($i -le $Dorks.Count) {
        Start-Sleep -Seconds $DelaySeconds
    }
}

Write-Host "`nDone. All searches opened." -ForegroundColor Green