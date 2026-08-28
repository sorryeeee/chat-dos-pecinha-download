$ErrorActionPreference = "Stop"

try {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.SecurityProtocolType]::Tls12
    )
}
catch {}

# Keep bootstrap intentionally tiny/fast. Old clients close Electron only
# ~700 ms after launching this script, so DO NOT download install.ps1 in
# this non-elevated process. Ask Windows for an independent elevated
# PowerShell immediately; that process survives after the old app exits
# and performs the network download itself.
$CacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$InstallerUrl = (
    "https://raw.githubusercontent.com/" +
    "sorryeeee/chat-dos-pecinha-download/main/install.ps1?x=" +
    $CacheBust
)

$InstallerLog = Join-Path `
    $env:TEMP `
    "arena-squad-install.log"

$ElevatedCommand = @'
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}
$InstallerUrl = "__INSTALLER_URL__"
$InstallerFile = Join-Path $env:TEMP ("chat-dos-pecinha-install-" + [Guid]::NewGuid().ToString("N") + ".ps1")
try {
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerFile -UseBasicParsing -Headers @{ "Cache-Control" = "no-cache"; "Pragma" = "no-cache" }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallerFile
    if ($LASTEXITCODE -ne 0) {
        throw ("Instalador terminou com codigo " + $LASTEXITCODE + ".")
    }
}
catch {
    Write-Host ""
    Write-Host "===== ERRO REAL DO ATUALIZADOR =====" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $log = Join-Path $env:TEMP "arena-squad-install.log"
    if (Test-Path $log) {
        Write-Host ""
        Get-Content $log -Tail 80
    }
    Write-Host "====================================" -ForegroundColor Red
    Read-Host "Pressione ENTER para fechar"
    exit 1
}
finally {
    Remove-Item -Force $InstallerFile -ErrorAction SilentlyContinue
}
'@

$ElevatedCommand = $ElevatedCommand.Replace(
    "__INSTALLER_URL__",
    $InstallerUrl.Replace('"', '`"')
)

$Encoded = [Convert]::ToBase64String(
    [Text.Encoding]::Unicode.GetBytes($ElevatedCommand)
)

try {
    Remove-Item `
        -Force `
        $InstallerLog `
        -ErrorAction SilentlyContinue

    # RunAs is intentionally the FIRST expensive action. Once UAC is
    # accepted, the elevated PowerShell is no longer tied to Electron.
    $process = Start-Process `
        -FilePath "powershell.exe" `
        -Verb RunAs `
        -PassThru `
        -ArgumentList @(
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-EncodedCommand", $Encoded
        )

    if (-not $process -or $process.Id -le 0) {
        throw "Nao foi possivel iniciar o atualizador elevado."
    }

    Write-Host (
        "Atualizador elevado iniciado. PID: " +
        $process.Id
    ) -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "Falha ao abrir o atualizador:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
