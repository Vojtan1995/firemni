param(
  [Parameter(Mandatory = $true)][string]$BaseUrl,
  [Parameter(Mandatory = $true)][string]$TargetHost,
  [Parameter(Mandatory = $true)][string]$BearerToken,
  [string]$ReportDir = "reports"
)

$ErrorActionPreference = "Stop"
$uri = [Uri]$BaseUrl
if ($env:ALLOW_SECURITY_TEST -ne "YES") { throw "Set ALLOW_SECURITY_TEST=YES after confirming authorization." }
if ($uri.Host.ToLowerInvariant() -ne $TargetHost.ToLowerInvariant()) { throw "TARGET_HOST does not match BASE_URL." }
if ($uri.Host -match "(^|[.-])(prod|production)([.-]|$)") { throw "Production-looking host rejected." }
if ($uri.Scheme -ne "https" -and $uri.Host -notin @("localhost", "127.0.0.1")) { throw "Remote scans require HTTPS." }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker is required for OWASP ZAP." }

New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$resolved = (Resolve-Path $ReportDir).Path
docker run --rm -v "${resolved}:/zap/wrk/:rw" `
  -t ghcr.io/zaproxy/zaproxy:stable zap-full-scan.py `
  -t $BaseUrl `
  -z "-config replacer.full_list(0).description=authorization -config replacer.full_list(0).enabled=true -config replacer.full_list(0).matchtype=REQ_HEADER -config replacer.full_list(0).matchstr=Authorization -config replacer.full_list(0).replacement=Bearer%20$BearerToken" `
  -r zap-report.html -J zap-report.json -w zap-report.md
