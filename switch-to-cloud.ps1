param(
    [string]$ServerUrl
)

$ErrorActionPreference = "Stop"

if (-not $ServerUrl) {
    $ServerUrl = Read-Host "Cole a URL CLOUD (ex: https://203-0-113-10.sslip.io)"
}

try {
    $uri = [Uri]$ServerUrl.Trim()
}
catch {
    throw "URL invalida."
}

if (
    $uri.Scheme -ne "https" -or
    -not $uri.Host -or
    (-not $uri.IsDefaultPort -and $uri.Port -ne 443) -or
    $uri.UserInfo -or
    $uri.Query -or
    $uri.Fragment -or
    ($uri.AbsolutePath -and $uri.AbsolutePath -ne "/")
) {
    throw "Use uma URL HTTPS simples, sem caminho. Ex: https://203-0-113-10.sslip.io"
}

$origin = "https://" + $uri.Host
$root = Join-Path $env:LOCALAPPDATA "ArenaSquad"
$configPath = Join-Path $root "desktop\config.json"
$hostFlag = Join-Path $root "desktop\host-mode.flag"
$electronExe = Join-Path $root "desktop\node_modules\electron\dist\electron.exe"
$desktopDir = Join-Path $root "desktop"

if (-not (Test-Path $desktopDir)) {
    throw "Chat dos Pecinha nao encontrado em $root"
}

# Stop only this app's Electron processes so config is reloaded cleanly.
if (Test-Path $electronExe) {
    Get-CimInstance Win32_Process -Filter "Name = 'electron.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -eq $electronExe } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

# If this PC used to be the Windows HOST, retire the local server.
$task = Get-ScheduledTask -TaskName "Arena Squad Server" -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName "Arena Squad Server" -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskName "Arena Squad Server" -ErrorAction SilentlyContinue | Out-Null
}

if (Test-Path $hostFlag) {
    Remove-Item -Force $hostFlag
}

@{ serverUrl = $origin } |
    ConvertTo-Json |
    Set-Content -Path $configPath -Encoding UTF8

Write-Host "Cloud configurada: $origin" -ForegroundColor Green
Write-Host "Tailscale nao e mais necessario para o Chat dos Pecinha." -ForegroundColor Green

if (Test-Path $electronExe) {
    Start-Process -FilePath $electronExe -ArgumentList "`"$desktopDir`"" -WorkingDirectory $desktopDir
}
