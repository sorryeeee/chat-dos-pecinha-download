$ErrorActionPreference = "Stop"

$CacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$Url = (
    "https://raw.githubusercontent.com/" +
    "sorryeeee/chat-dos-pecinha-download/main/install.ps1?x=" +
    $CacheBust
)

$File = Join-Path `
    $env:TEMP `
    "arena-squad-online-install.ps1"

$InstallerLog = Join-Path `
    $env:TEMP `
    "arena-squad-install.log"

try {
    Remove-Item `
        -Force `
        $InstallerLog `
        -ErrorAction SilentlyContinue

    Invoke-WebRequest `
        -Uri $Url `
        -OutFile $File `
        -UseBasicParsing `
        -Headers @{
            "Cache-Control" = "no-cache"
            "Pragma" = "no-cache"
        }

    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$File`""
    ) -join " "

    $process = Start-Process `
        powershell.exe `
        -Verb RunAs `
        -Wait `
        -PassThru `
        -ArgumentList $args

    if ($process.ExitCode -ne 0) {
        Write-Host ""
        Write-Host "===== ERRO REAL DO INSTALADOR =====" `
            -ForegroundColor Red

        if (Test-Path $InstallerLog) {
            Get-Content `
                $InstallerLog `
                -Tail 80
        }
        else {
            Write-Host (
                "Log do instalador nao foi criado: " +
                $InstallerLog
            )
        }

        Write-Host "===================================" `
            -ForegroundColor Red

        throw (
            "Instalador terminou com codigo " +
            $process.ExitCode +
            "."
        )
    }
}
finally {
    Remove-Item `
        -Force `
        $File `
        -ErrorAction SilentlyContinue
}
