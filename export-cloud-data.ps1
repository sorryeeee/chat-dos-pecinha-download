$ErrorActionPreference = "Stop"

$serverDir = Join-Path $env:LOCALAPPDATA "ArenaSquad\server"
if (-not (Test-Path $serverDir)) {
    throw "Servidor local nao encontrado em $serverDir"
}

$required = Join-Path $serverDir "profile-auth.json"
if (-not (Test-Path $required)) {
    throw "profile-auth.json nao encontrado. Rode isto no PC que atualmente e o HOST."
}

$temp = Join-Path $env:TEMP ("pecinha-cloud-data-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $temp | Out-Null

$files = @(
    "profile-auth.json",
    "profile-sessions.json",
    "profile-presence.json",
    "profile-activity.json"
)

foreach ($name in $files) {
    $source = Join-Path $serverDir $name
    if (Test-Path $source) {
        Copy-Item -Force $source (Join-Path $temp $name)
    }
}

$out = Join-Path ([Environment]::GetFolderPath("Desktop")) "chat-dos-pecinha-cloud-data.zip"
if (Test-Path $out) { Remove-Item -Force $out }
Compress-Archive -Path (Join-Path $temp "*") -DestinationPath $out -Force
Remove-Item -Recurse -Force $temp

Write-Host ""
Write-Host "Backup CLOUD criado:" -ForegroundColor Green
Write-Host $out
Write-Host ""
Write-Warning "Esse ZIP contem hashes de senha e sessoes. NAO envie para GitHub/Discord. Mande somente para sua VPS via SCP."
