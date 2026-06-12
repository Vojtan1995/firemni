# Release build skript pro Android APK a Windows EXE
# Použití: .\build-release.ps1 -ApiUrl https://tvoje-api.railway.app [-SentryDsn https://...]
#
# Před spuštěním:
#   - frontend/android/key.properties a release-keystore.jks musí existovat
#   - Railway backend musí být nasazen a URL musí být funkční

param(
    [Parameter(Mandatory=$true)]
    [string]$ApiUrl,

    [Parameter(Mandatory=$false)]
    [string]$SentryDsn = ""
)

$frontendDir = Join-Path $PSScriptRoot "frontend"
$releaseDir = Join-Path $frontendDir "build\windows\x64\runner\Release"

Write-Host "=== Ucpavky Release Build ===" -ForegroundColor Cyan
Write-Host "API URL: $ApiUrl"
if ($SentryDsn) { Write-Host "Sentry DSN: nastaveno" }

Set-Location $frontendDir

# ── Android APK ────────────────────────────────────────────────────────────────
Write-Host "`n[1/2] Android APK..." -ForegroundColor Yellow

$dartDefines = "--dart-define=API_BASE_URL=$ApiUrl"
if ($SentryDsn) { $dartDefines = "$dartDefines --dart-define=SENTRY_DSN=$SentryDsn" }

$buildCmd = "flutter build apk --release $dartDefines"
Write-Host "Spouštím: $buildCmd"
Invoke-Expression $buildCmd

if ($LASTEXITCODE -eq 0) {
    $apkPath = Join-Path $frontendDir "build\app\outputs\flutter-apk\app-release.apk"
    $apkSize = [math]::Round((Get-Item $apkPath).Length / 1MB, 1)
    Write-Host "APK OK: $apkPath ($apkSize MB)" -ForegroundColor Green
} else {
    Write-Host "APK build FAILED (exit $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

# ── Windows EXE ────────────────────────────────────────────────────────────────
Write-Host "`n[2/2] Windows EXE..." -ForegroundColor Yellow

$buildCmd = "flutter build windows --release $dartDefines"
Write-Host "Spouštím: $buildCmd"
Invoke-Expression $buildCmd

if ($LASTEXITCODE -eq 0) {
    $zipPath = Join-Path $PSScriptRoot "ucpavky-windows-release.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath }
    Compress-Archive -Path "$releaseDir\*" -DestinationPath $zipPath
    $zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host "Windows ZIP OK: $zipPath ($zipSize MB)" -ForegroundColor Green
} else {
    Write-Host "Windows build FAILED (exit $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Build dokoncen ===" -ForegroundColor Cyan
Write-Host "Android: frontend\build\app\outputs\flutter-apk\app-release.apk"
Write-Host "Windows: ucpavky-windows-release.zip"
Write-Host ""
Write-Host "Distribuce Windows: rozbalit ZIP na cílovém PC, spustit ucpavky.exe"
Write-Host "Distribuce Android: nainstalovat APK přes USB nebo MDM"
Write-Host ""
Write-Host "=== Update checker (backend env) ===" -ForegroundColor Cyan
$pubspecPath = Join-Path $frontendDir "pubspec.yaml"
$pubspec = Get-Content $pubspecPath -Raw
if ($pubspec -match 'version:\s*([\d.]+)\+(\d+)') {
    $versionName = $matches[1]
    $buildNumber = $matches[2]
    Write-Host "Po nahrani APK na HTTPS nastavte na backendu:"
    Write-Host "  APP_RELEASE_VERSION_NAME=$versionName"
    Write-Host "  APP_RELEASE_BUILD=$buildNumber"
    Write-Host "  APP_RELEASE_MIN_BUILD=<min povoleny build>"
    Write-Host "  APP_RELEASE_APK_URL=https://.../app-release.apk"
    Write-Host "  APP_RELEASE_NOTES=<volitelne poznamky k vydani>"
} else {
    Write-Host "Nepodarilo se precist verzi z pubspec.yaml" -ForegroundColor Yellow
}
