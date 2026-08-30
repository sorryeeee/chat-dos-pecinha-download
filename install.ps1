$ErrorActionPreference = "Stop"

try {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.SecurityProtocolType]::Tls12
    )
}
catch {}

$RepoRaw = "https://raw.githubusercontent.com/sorryeeee/chat-dos-pecinha-download/main"
$ExpectedSha256 = "9040cfb1a68f1bb620a795db26f5a434effe82e3832ec71dcb45677de1ed7b6b"
$Version = "1.3.25.6.8.6.9-online-1"
$ElectronRuntimeVersion = "37.10.3"
$SocketIoClientVersion = "4.8.3"
$SocketIoServerVersion = "4.8.3"
$NodeRuntimeVersion = "24.20.0"
$SocketIoClientSha384 = "9336af8f97e23302cacf30f57fc4bb4dea152048bbb8a1ef6d3037b9e664af362aef9a4d4148948ba0f2f7c4377f16f4"

# Prefer the immutable versioned package, but automatically fall
# back to latest.zip if the versioned file was not uploaded.
$PackageFile = "arena-squad-" + $Version + ".zip"
$PackageUrl = $RepoRaw + "/release/" + $PackageFile
$FallbackUrl = (
    $RepoRaw +
    "/release/latest.zip?x=" +
    [Guid]::NewGuid().ToString("N")
)

$InstallerLog = Join-Path `
    $env:TEMP `
    "arena-squad-install.log"

function Is-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Find-ArenaRoot {
    $candidates = New-Object System.Collections.Generic.List[string]

    $localInstall = Join-Path `
        $env:LOCALAPPDATA `
        "ArenaSquad"

    $common = @(
        $localInstall,
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("MyDocuments"),
        (Join-Path $env:USERPROFILE "Downloads"),
        $env:USERPROFILE
    ) | Where-Object { $_ }

    foreach ($folder in $common) {
        if (Test-Path $folder) {
            $candidates.Add($folder)

            Get-ChildItem `
                -Path $folder `
                -Directory `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -match "arena"
                } |
                ForEach-Object {
                    $candidates.Add($_.FullName)
                }
        }
    }

    foreach (
        $candidate in
        $candidates |
        Select-Object -Unique
    ) {
        if (
            (Test-Path (
                Join-Path `
                    $candidate `
                    "desktop\renderer.js"
            )) -and
            (Test-Path (
                Join-Path `
                    $candidate `
                    "desktop\config.json"
            ))
        ) {
            return $candidate
        }
    }

    foreach (
        $folder in
        $common |
        Where-Object { Test-Path $_ } |
        Select-Object -First 4
    ) {
        try {
            $renderer = Get-ChildItem `
                -Path $folder `
                -Filter "renderer.js" `
                -File `
                -Recurse `
                -Depth 5 `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Directory.Name -eq
                        "desktop" -and
                    (Test-Path (
                        Join-Path `
                            $_.Directory.FullName `
                            "config.json"
                    ))
                } |
                Select-Object -First 1

            if ($renderer) {
                return Split-Path `
                    -Parent `
                    $renderer.Directory.FullName
            }
        }
        catch {}
    }

    return $null
}

function Get-TailscaleExe {
    $candidates = @(
        (Join-Path `
            $env:ProgramFiles `
            "Tailscale\tailscale.exe"),
        (Join-Path `
            ${env:ProgramFiles(x86)} `
            "Tailscale\tailscale.exe")
    ) | Where-Object { $_ }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    try {
        return (
            Get-Command `
                tailscale.exe `
                -ErrorAction Stop
        ).Source
    }
    catch {}

    return $null
}

function Test-TailscaleIPv4 {
    param(
        [string]$Address
    )

    if (-not $Address) {
        return $false
    }

    $parsed = $null

    if (
        -not [Net.IPAddress]::TryParse(
            $Address.Trim(),
            [ref]$parsed
        )
    ) {
        return $false
    }

    if (
        $parsed.AddressFamily -ne
        [Net.Sockets.AddressFamily]::InterNetwork
    ) {
        return $false
    }

    $bytes = $parsed.GetAddressBytes()

    return (
        $bytes[0] -eq 100 -and
        $bytes[1] -ge 64 -and
        $bytes[1] -le 127
    )
}

function Normalize-HostInput {
    param(
        [string]$Value
    )

    $text = [string]$Value

    if (-not $text) {
        return $null
    }

    $text = $text.Trim()

    if (
        $text.StartsWith(
            "http://",
            [StringComparison]::OrdinalIgnoreCase
        ) -or
        $text.StartsWith(
            "https://",
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        try {
            return ([Uri]$text).Host
        }
        catch {
            return $null
        }
    }

    if ($text.Contains(":")) {
        try {
            return (
                [Uri](
                    "http://" +
                    $text
                )
            ).Host
        }
        catch {}
    }

    return $text
}

function Ensure-Tailscale {
    $tailscale = Get-TailscaleExe

    if ($tailscale) {
        return $tailscale
    }

    Write-Warning (
        "Tailscale nao foi encontrado neste PC."
    )

    $winget = $null

    try {
        $winget = (
            Get-Command `
                winget.exe `
                -ErrorAction Stop
        ).Source
    }
    catch {}

    if (-not $winget) {
        Write-Warning (
            "winget nao esta disponivel. " +
            "Chat dos Pecinha sera instalado, mas este PC " +
            "precisa do Tailscale para alcancar o HOST."
        )

        return $null
    }

    Write-Host (
        "Tentando instalar Tailscale automaticamente..."
    )

    try {
        & $winget `
            install `
            --id "Tailscale.Tailscale" `
            --exact `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements

        if ($LASTEXITCODE -ne 0) {
            Write-Warning (
                "winget nao conseguiu instalar Tailscale. Codigo: " +
                $LASTEXITCODE
            )
        }
    }
    catch {
        Write-Warning (
            "Falha ao chamar winget para Tailscale: " +
            $_.Exception.Message
        )
    }

    Start-Sleep -Seconds 2

    return Get-TailscaleExe
}


function Copy-WithBackup {
    param(
        [string]$Source,
        [string]$Target,
        [string]$Backup
    )

    $targetDir = Split-Path -Parent $Target
    $backupDir = Split-Path -Parent $Backup

    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    if (Test-Path $Target) {
        Copy-Item -Force $Target $Backup
    }

    Copy-Item -Force $Source $Target
}

if (-not (Is-Admin)) {
    Write-Host "Este instalador precisa ser executado como Administrador." -ForegroundColor Yellow
    Write-Host "Use o comando online oficial que abre esta etapa com UAC."
    Read-Host "Pressione ENTER para fechar"
    exit 1
}

try {
    Start-Transcript `
        -Path $InstallerLog `
        -Force |
        Out-Null
}
catch {}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " CHAT DOS PECINHA - INSTALADOR / UPDATER $Version" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$arenaRoot = Find-ArenaRoot
$freshInstall = $false
$isHost = $false
$freshServerUrl = $null

if (-not $arenaRoot) {
    $freshInstall = $true

    $arenaRoot = Join-Path `
        $env:LOCALAPPDATA `
        "ArenaSquad"

    Write-Host (
        "Nenhuma instalacao antiga encontrada."
    ) -ForegroundColor Yellow

    Write-Host (
        "Instalacao NOVA em:"
    ) -ForegroundColor Green

    Write-Host $arenaRoot
    Write-Host ""

    New-Item `
        -ItemType Directory `
        -Force `
        -Path (Join-Path $arenaRoot "desktop") |
        Out-Null

    $hostAnswer = (
        Read-Host `
            "Este PC sera o HOST? Digite S para HOST ou pressione ENTER para CLIENTE"
    )

    $isHost = (
        [string]$hostAnswer
    ).Trim().ToLowerInvariant() -in @(
        "s",
        "sim",
        "y",
        "yes"
    )

    if ($isHost) {
        $freshServerUrl =
            "http://localhost:3000"
    }
    else {
        $tailscaleExe =
            Ensure-Tailscale

        if ($tailscaleExe) {
            $localTailscaleIP =
                $null

            try {
                $oldErrorPreference =
                    $ErrorActionPreference

                $ErrorActionPreference =
                    "SilentlyContinue"

                $localTailscaleIP = @(
                    & $tailscaleExe `
                        ip `
                        -4 `
                        2>$null
                ) |
                Where-Object {
                    Test-TailscaleIPv4 `
                        ([string]$_).Trim()
                } |
                Select-Object -First 1

                $ErrorActionPreference =
                    $oldErrorPreference
            }
            catch {
                try {
                    $ErrorActionPreference =
                        $oldErrorPreference
                }
                catch {}

                $localTailscaleIP =
                    $null
            }

            if ($localTailscaleIP) {
                Write-Host (
                    "Tailscale local: " +
                    ([string]$localTailscaleIP).Trim()
                ) -ForegroundColor Green
            }
            else {
                Write-Warning (
                    "Tailscale esta instalado, mas ainda nao esta conectado/logado. " +
                    "A instalacao vai continuar normalmente."
                )
            }
        }

        $hostIp = $null

        while (-not $hostIp) {
            $rawHost = Read-Host `
                "Digite o IP Tailscale do HOST (ex: 100.83.252.0)"

            $candidate =
                Normalize-HostInput `
                    $rawHost

            if (
                Test-TailscaleIPv4 `
                    $candidate
            ) {
                $hostIp =
                    $candidate.Trim()
            }
            else {
                Write-Host (
                    "IP invalido. Use o IP Tailscale 100.x do HOST."
                ) -ForegroundColor Yellow
            }
        }

        $freshServerUrl = (
            "http://" +
            $hostIp +
            ":3000"
        )
    }

    @{
        serverUrl = $freshServerUrl
    } |
    ConvertTo-Json |
    Set-Content `
        -Path (
            Join-Path `
                $arenaRoot `
                "desktop\config.json"
        ) `
        -Encoding UTF8
}
else {
    Write-Host (
        "Instalacao existente encontrada:"
    ) -ForegroundColor Green

    Write-Host $arenaRoot
    Write-Host ""

    $configPath = Join-Path `
        $arenaRoot `
        "desktop\config.json"

    $hostFlag = Join-Path `
        $arenaRoot `
        "desktop\host-mode.flag"

    $hasHostFlag =
        Test-Path $hostFlag

    $serverUrl = $null
    $serverHost = $null
    $configNeedsRepair = $false

    if (Test-Path $configPath) {
        try {
            $config = Get-Content `
                $configPath `
                -Raw |
                ConvertFrom-Json

            $serverUrl =
                [string]$config.serverUrl

            $uri =
                [Uri]$serverUrl

            $serverHost =
                [string]$uri.Host

            $validLocalHost =
                (
                    $serverHost -eq "localhost" -or
                    $serverHost -eq "127.0.0.1"
                ) -and
                $uri.Scheme -eq "http" -and
                $uri.Port -eq 3000

            $validTailscaleHost =
                (
                    Test-TailscaleIPv4 `
                        $serverHost
                ) -and
                $uri.Scheme -eq "http" -and
                $uri.Port -eq 3000

            if (
                -not $validLocalHost -and
                -not $validTailscaleHost
            ) {
                $configNeedsRepair =
                    $true
            }
        }
        catch {
            Write-Warning (
                "config.json existente nao pode ser lido. " +
                "O instalador vai reparar a configuracao."
            )

            $configNeedsRepair =
                $true
        }
    }
    else {
        $configNeedsRepair =
            $true
    }

    if ($hasHostFlag) {
        # The host flag is authoritative for an existing HOST.
        # Never depend on Tailscale being logged in just to detect mode.
        $isHost = $true

        if (
            $configNeedsRepair -or
            $serverHost -ne "localhost"
        ) {
            $serverUrl =
                "http://localhost:3000"

            @{
                serverUrl = $serverUrl
            } |
            ConvertTo-Json |
            Set-Content `
                -Path $configPath `
                -Encoding UTF8

            $serverHost =
                "localhost"

            $configNeedsRepair =
                $false

            Write-Host (
                "config.json do HOST reparado para localhost."
            ) -ForegroundColor Green
        }
    }
    else {
        # Existing client: the configured remote Tailscale HOST decides
        # the mode. The client's own Tailscale state is NOT consulted.
        # Tailscale may legitimately be NeedsLogin during install/update.
        $isHost = $false

        if ($configNeedsRepair) {
            Write-Warning (
                "Configuracao do HOST ausente ou invalida."
            )

            $hostIp = $null

            while (-not $hostIp) {
                $rawHost = Read-Host `
                    "Digite o IP Tailscale do HOST (ex: 100.83.252.0)"

                $candidate =
                    Normalize-HostInput `
                        $rawHost

                if (
                    Test-TailscaleIPv4 `
                        $candidate
                ) {
                    $hostIp =
                        $candidate.Trim()
                }
                else {
                    Write-Host (
                        "IP invalido. Use o IP Tailscale 100.x do HOST."
                    ) -ForegroundColor Yellow
                }
            }

            $serverUrl =
                "http://" +
                $hostIp +
                ":3000"

            @{
                serverUrl = $serverUrl
            } |
            ConvertTo-Json |
            Set-Content `
                -Path $configPath `
                -Encoding UTF8

            $serverHost =
                $hostIp

            Write-Host (
                "config.json do CLIENTE reparado."
            ) -ForegroundColor Green
        }

        # Best-effort informational check only.
        # A logged-out Tailscale MUST NOT abort installation/update.
        $tailscaleExe =
            Get-TailscaleExe

        if (-not $tailscaleExe) {
            Write-Warning (
                "Tailscale ainda nao esta instalado. " +
                "O Chat dos Pecinha sera atualizado normalmente, " +
                "mas voce precisara instalar/conectar o Tailscale antes de usar."
            )
        }
        else {
            $tailscaleReady =
                $false

            try {
                $oldErrorPreference =
                    $ErrorActionPreference

                $ErrorActionPreference =
                    "SilentlyContinue"

                $tsOutput = @(
                    & $tailscaleExe `
                        ip `
                        -4 `
                        2>$null
                )

                $ErrorActionPreference =
                    $oldErrorPreference

                $tailscaleReady =
                    !!(
                        $tsOutput |
                        Where-Object {
                            Test-TailscaleIPv4 `
                                ([string]$_).Trim()
                        } |
                        Select-Object -First 1
                    )
            }
            catch {
                try {
                    $ErrorActionPreference =
                        $oldErrorPreference
                }
                catch {}

                $tailscaleReady =
                    $false
            }

            if (-not $tailscaleReady) {
                Write-Warning (
                    "Tailscale esta instalado, mas ainda nao esta conectado/logado. " +
                    "A instalacao vai continuar. Entre no Tailscale antes de abrir o Chat dos Pecinha."
                )
            }
        }
    }
}

if (-not $hostFlag) {
    $hostFlag = Join-Path `
        $arenaRoot `
        "desktop\host-mode.flag"
}

Write-Host (
    "Modo: " +
    $(if ($isHost) { "HOST" } else { "CLIENTE" })
)

if ($isHost) {
    Set-Content `
        -Path $hostFlag `
        -Value "HOST" `
        -Encoding ASCII

    Write-Host (
        "Flag HOST criada."
    ) -ForegroundColor Green
}
else {
    if (Test-Path $hostFlag) {
        Remove-Item `
            -Path $hostFlag `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

$tempRoot = Join-Path $env:TEMP (
    "arena-squad-update-" + [Guid]::NewGuid().ToString("N")
)

$zipPath = Join-Path $tempRoot "latest.zip"
$extractPath = Join-Path $tempRoot "package"

New-Item -ItemType Directory -Force -Path $extractPath | Out-Null

try {
    Write-Host "[1/7] Baixando atualizacao..."
    Write-Host ("Pacote preferido: " + $PackageFile)
    Write-Host ("URL preferida: " + $PackageUrl)

    $downloadedFrom = $PackageUrl

    try {
        Invoke-WebRequest `
            -Uri $PackageUrl `
            -OutFile $zipPath `
            -UseBasicParsing `
            -Headers @{
                "Cache-Control" = "no-cache"
                "Pragma" = "no-cache"
            }
    }
    catch {
        Write-Warning (
            "Pacote versionado indisponivel. " +
            "Tentando latest.zip..."
        )

        $downloadedFrom = $FallbackUrl

        Invoke-WebRequest `
            -Uri $FallbackUrl `
            -OutFile $zipPath `
            -UseBasicParsing `
            -Headers @{
                "Cache-Control" = "no-cache"
                "Pragma" = "no-cache"
            }
    }

    Write-Host ("Baixado de: " + $downloadedFrom)

    Write-Host "[2/7] Verificando integridade..."
    $actualHash = (
        Get-FileHash `
            -Path $zipPath `
            -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    if ($actualHash -ne $ExpectedSha256.ToLowerInvariant()) {
        Write-Host (
            "SHA esperado: " +
            $ExpectedSha256.ToLowerInvariant()
        ) -ForegroundColor Yellow

        Write-Host (
            "SHA recebido: " +
            $actualHash
        ) -ForegroundColor Yellow

        throw "SHA-256 invalido. Atualizacao cancelada."
    }

    Write-Host "[3/7] Extraindo..."
    Expand-Archive `
        -Path $zipPath `
        -DestinationPath $extractPath `
        -Force

    # Close only this Arena Squad Electron instance to unlock files.
    $electronExe = Join-Path `
        $arenaRoot `
        "desktop\node_modules\electron\dist\electron.exe"

    if (Test-Path $electronExe) {
        Get-CimInstance Win32_Process `
            -Filter "Name = 'electron.exe'" `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ExecutablePath -eq $electronExe
            } |
            ForEach-Object {
                Stop-Process `
                    -Id $_.ProcessId `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
    }

    # On host, stop only Node that listens on port 3000.
    if ($isHost) {
        try {
            $listeners = Get-NetTCPConnection `
                -LocalPort 3000 `
                -State Listen `
                -ErrorAction SilentlyContinue

            foreach ($listener in $listeners) {
                if ($listener.OwningProcess) {
                    $proc = Get-Process `
                        -Id $listener.OwningProcess `
                        -ErrorAction SilentlyContinue

                    if (
                        $proc -and
                        $proc.ProcessName -in @("node", "electron")
                    ) {
                        Stop-Process `
                            -Id $proc.Id `
                            -Force `
                            -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        catch {}
    }

    Start-Sleep -Milliseconds 900

    if ($isHost) {
        try {
            $stillListening = Get-NetTCPConnection `
                -LocalPort 3000 `
                -State Listen `
                -ErrorAction SilentlyContinue

            foreach ($listener in $stillListening) {
                if ($listener.OwningProcess) {
                    Stop-Process `
                        -Id $listener.OwningProcess `
                        -Force `
                        -ErrorAction SilentlyContinue
                }
            }
        }
        catch {}
    }

    Write-Host "[4/7] Criando backup e atualizando arquivos..."

    $backupRoot = Join-Path $arenaRoot (
        "backup-online-$Version-" +
        (Get-Date -Format "yyyyMMdd-HHmmss")
    )

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $backupRoot |
        Out-Null

    $desktopFiles = @(
        "main.js",
        "preload.js",
        "renderer.js",
        "index.html",
        "styles.css",
        "brand-logo.png",
        "tray-icon.png",
        "app-icon.ico",
        "package.json"
    )

    foreach ($name in $desktopFiles) {
        Copy-WithBackup `
            -Source (Join-Path $extractPath "payload\desktop\$name") `
            -Target (Join-Path $arenaRoot "desktop\$name") `
            -Backup (Join-Path $backupRoot "desktop\$name")
    }

    $brandLogoInstalled = Join-Path `
        $arenaRoot `
        "desktop\brand-logo.png"

    if (-not (Test-Path $brandLogoInstalled)) {
        throw "Falha ao instalar brand-logo.png."
    }

    Write-Host "LOGO oficial instalada: OK" -ForegroundColor Green

    # --------------------------------------------------------
    # Desktop runtime — verified official downloads
    # --------------------------------------------------------
    $desktopDirForDeps = Join-Path `
        $arenaRoot `
        "desktop"

    $targetNodeModules = Join-Path `
        $desktopDirForDeps `
        "node_modules"

    $electronExeCore = Join-Path `
        $targetNodeModules `
        "electron\dist\electron.exe"

    $socketIoCore = Join-Path `
        $targetNodeModules `
        "socket.io-client\dist\socket.io.min.js"

    $runtimeMarker = Join-Path `
        $desktopDirForDeps `
        "arena-runtime-security.json"

    $runtimeNeedsRepair = $true

    if (
        (Test-Path $electronExeCore) -and
        (Test-Path $socketIoCore) -and
        (Test-Path $runtimeMarker)
    ) {
        try {
            $marker = Get-Content `
                $runtimeMarker `
                -Raw |
                ConvertFrom-Json

            $installedClientSha = (
                Get-FileHash `
                    -Path $socketIoCore `
                    -Algorithm SHA384
            ).Hash.ToLowerInvariant()

            if (
                [string]$marker.electron -eq $ElectronRuntimeVersion -and
                [string]$marker.socketIoClient -eq $SocketIoClientVersion -and
                $installedClientSha -eq $SocketIoClientSha384
            ) {
                $runtimeNeedsRepair = $false
            }
        }
        catch {}
    }

    if ($runtimeNeedsRepair) {
        Write-Host (
            "Atualizando runtime seguro Electron/Socket.IO..."
        )

        $runtimeRepairDir = Join-Path `
            $tempRoot `
            "desktop-runtime-secure"

        $electronZip = Join-Path `
            $runtimeRepairDir `
            "electron.zip"

        $electronShasums = Join-Path `
            $runtimeRepairDir `
            "SHASUMS256.txt"

        $electronExtract = Join-Path `
            $runtimeRepairDir `
            "electron-dist"

        $socketIoTemp = Join-Path `
            $runtimeRepairDir `
            "socket.io.min.js"

        New-Item `
            -ItemType Directory `
            -Force `
            -Path $electronExtract |
            Out-Null

        $arch = "x64"

        if (
            $env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or
            $env:PROCESSOR_IDENTIFIER -match "ARM"
        ) {
            $arch = "arm64"
        }

        $electronFileName = (
            "electron-v" +
            $ElectronRuntimeVersion +
            "-win32-" +
            $arch +
            ".zip"
        )

        $electronBase = (
            "https://github.com/electron/electron/releases/download/v" +
            $ElectronRuntimeVersion +
            "/"
        )

        $electronUrl = (
            $electronBase +
            $electronFileName
        )

        $electronShasumsUrl = (
            $electronBase +
            "SHASUMS256.txt"
        )

        $socketIoUrl = (
            "https://cdn.socket.io/" +
            $SocketIoClientVersion +
            "/socket.io.min.js"
        )

        Write-Host (
            "Electron oficial: v" +
            $ElectronRuntimeVersion +
            " / " +
            $arch
        )

        Invoke-WebRequest `
            -Uri $electronUrl `
            -OutFile $electronZip `
            -UseBasicParsing

        Invoke-WebRequest `
            -Uri $electronShasumsUrl `
            -OutFile $electronShasums `
            -UseBasicParsing

        $hashPattern = (
            "^([0-9a-fA-F]{64})\s+\*?" +
            [regex]::Escape($electronFileName) +
            "$"
        )

        $hashLine = Get-Content `
            $electronShasums |
            Where-Object {
                $_ -match $hashPattern
            } |
            Select-Object -First 1

        if (-not $hashLine) {
            throw (
                "Hash oficial do Electron nao foi encontrado."
            )
        }

        $expectedElectronHash = (
            [regex]::Match(
                $hashLine,
                $hashPattern
            ).Groups[1].Value
        ).ToLowerInvariant()

        $actualElectronHash = (
            Get-FileHash `
                -Path $electronZip `
                -Algorithm SHA256
        ).Hash.ToLowerInvariant()

        if (
            $actualElectronHash -ne
            $expectedElectronHash
        ) {
            throw (
                "SHA-256 do Electron nao confere com SHASUMS oficial."
            )
        }

        Write-Host (
            "Electron SHA-256 oficial: OK"
        ) -ForegroundColor Green

        Expand-Archive `
            -Path $electronZip `
            -DestinationPath $electronExtract `
            -Force

        $cleanElectron = Join-Path `
            $electronExtract `
            "electron.exe"

        if (-not (Test-Path $cleanElectron)) {
            throw (
                "electron.exe ausente no ZIP oficial."
            )
        }

        Invoke-WebRequest `
            -Uri $socketIoUrl `
            -OutFile $socketIoTemp `
            -UseBasicParsing

        $actualSocketIoSha = (
            Get-FileHash `
                -Path $socketIoTemp `
                -Algorithm SHA384
        ).Hash.ToLowerInvariant()

        if (
            $actualSocketIoSha -ne
            $SocketIoClientSha384
        ) {
            throw (
                "SHA-384 do Socket.IO Client 4.8.3 nao confere."
            )
        }

        Write-Host (
            "Socket.IO Client SHA-384: OK"
        ) -ForegroundColor Green

        $brokenNodeModulesBackup = Join-Path `
            $backupRoot `
            "desktop\node_modules-before-security"

        if (Test-Path $targetNodeModules) {
            try {
                Move-Item `
                    -Path $targetNodeModules `
                    -Destination $brokenNodeModulesBackup `
                    -Force
            }
            catch {
                Remove-Item `
                    -Path $targetNodeModules `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop
            }
        }

        $targetElectronDist = Join-Path `
            $targetNodeModules `
            "electron\dist"

        $targetSocketIoDist = Join-Path `
            $targetNodeModules `
            "socket.io-client\dist"

        New-Item `
            -ItemType Directory `
            -Force `
            -Path $targetElectronDist |
            Out-Null

        New-Item `
            -ItemType Directory `
            -Force `
            -Path $targetSocketIoDist |
            Out-Null

        Copy-Item `
            -Path (Join-Path $electronExtract "*") `
            -Destination $targetElectronDist `
            -Recurse `
            -Force

        Copy-Item `
            -Path $socketIoTemp `
            -Destination $socketIoCore `
            -Force

        @{
            electron = $ElectronRuntimeVersion
            socketIoClient = $SocketIoClientVersion
            socketIoClientSha384 = $SocketIoClientSha384
        } |
        ConvertTo-Json |
        Set-Content `
            -Path $runtimeMarker `
            -Encoding UTF8
    }

    if (
        -not (Test-Path $electronExeCore) -or
        -not (Test-Path $socketIoCore)
    ) {
        throw (
            "Runtime desktop seguro ficou incompleto."
        )
    }

    Write-Host (
        "Runtime desktop seguro: OK"
    ) -ForegroundColor Green

    # --------------------------------------------------------
    # Bundled Node.js LTS runtime
    # --------------------------------------------------------
    $nodeRuntimeRoot = Join-Path `
        $arenaRoot `
        "runtime\node"

    $nodeExe = Join-Path `
        $nodeRuntimeRoot `
        "node.exe"

    $npmCommand = Join-Path `
        $nodeRuntimeRoot `
        "npm.cmd"

    $nodeMarker = Join-Path `
        $nodeRuntimeRoot `
        "arena-node-runtime.json"

    $nodeNeedsInstall = $true

    if (
        (Test-Path $nodeExe) -and
        (Test-Path $npmCommand) -and
        (Test-Path $nodeMarker)
    ) {
        try {
            $nodeState = Get-Content `
                $nodeMarker `
                -Raw |
                ConvertFrom-Json

            if (
                [string]$nodeState.version -eq
                $NodeRuntimeVersion
            ) {
                $nodeNeedsInstall = $false
            }
        }
        catch {}
    }

    if ($nodeNeedsInstall) {
        Write-Host (
            "Instalando Node.js LTS portatil v" +
            $NodeRuntimeVersion +
            "..."
        )

        $nodeArch = "x64"

        if (
            $env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or
            $env:PROCESSOR_IDENTIFIER -match "ARM"
        ) {
            $nodeArch = "arm64"
        }

        $nodeFileName = (
            "node-v" +
            $NodeRuntimeVersion +
            "-win-" +
            $nodeArch +
            ".zip"
        )

        $nodeBaseUrl = (
            "https://nodejs.org/dist/v" +
            $NodeRuntimeVersion +
            "/"
        )

        $nodeZip = Join-Path `
            $tempRoot `
            $nodeFileName

        $nodeShasums = Join-Path `
            $tempRoot `
            "node-SHASUMS256.txt"

        $nodeExtract = Join-Path `
            $tempRoot `
            "node-runtime-extract"

        Invoke-WebRequest `
            -Uri ($nodeBaseUrl + $nodeFileName) `
            -OutFile $nodeZip `
            -UseBasicParsing

        Invoke-WebRequest `
            -Uri ($nodeBaseUrl + "SHASUMS256.txt") `
            -OutFile $nodeShasums `
            -UseBasicParsing

        $nodeHashPattern = (
            "^([0-9a-fA-F]{64})\s+\*?" +
            [regex]::Escape($nodeFileName) +
            "$"
        )

        $nodeHashLine = Get-Content `
            $nodeShasums |
            Where-Object {
                $_ -match $nodeHashPattern
            } |
            Select-Object -First 1

        if (-not $nodeHashLine) {
            throw (
                "Hash oficial do Node.js nao foi encontrado."
            )
        }

        $expectedNodeHash = (
            [regex]::Match(
                $nodeHashLine,
                $nodeHashPattern
            ).Groups[1].Value
        ).ToLowerInvariant()

        $actualNodeHash = (
            Get-FileHash `
                -Path $nodeZip `
                -Algorithm SHA256
        ).Hash.ToLowerInvariant()

        if (
            $actualNodeHash -ne
            $expectedNodeHash
        ) {
            throw (
                "SHA-256 do Node.js nao confere com SHASUMS oficial."
            )
        }

        Write-Host (
            "Node.js SHA-256 oficial: OK"
        ) -ForegroundColor Green

        Remove-Item `
            -Path $nodeExtract `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue

        Expand-Archive `
            -Path $nodeZip `
            -DestinationPath $nodeExtract `
            -Force

        $nodeSourceDir = Get-ChildItem `
            -Path $nodeExtract `
            -Directory |
            Where-Object {
                Test-Path (
                    Join-Path `
                        $_.FullName `
                        "node.exe"
                )
            } |
            Select-Object -First 1

        if (-not $nodeSourceDir) {
            throw (
                "node.exe nao foi encontrado no ZIP oficial."
            )
        }

        $oldNodeBackup = Join-Path `
            $backupRoot `
            "runtime\node-before-$Version"

        if (Test-Path $nodeRuntimeRoot) {
            New-Item `
                -ItemType Directory `
                -Force `
                -Path (
                    Split-Path `
                        $oldNodeBackup `
                        -Parent
                ) |
                Out-Null

            try {
                Move-Item `
                    -Path $nodeRuntimeRoot `
                    -Destination $oldNodeBackup `
                    -Force
            }
            catch {
                Remove-Item `
                    -Path $nodeRuntimeRoot `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop
            }
        }

        New-Item `
            -ItemType Directory `
            -Force `
            -Path $nodeRuntimeRoot |
            Out-Null

        Copy-Item `
            -Path (
                Join-Path `
                    $nodeSourceDir.FullName `
                    "*"
            ) `
            -Destination $nodeRuntimeRoot `
            -Recurse `
            -Force

        @{
            version = $NodeRuntimeVersion
            source = "nodejs.org official zip"
        } |
        ConvertTo-Json |
        Set-Content `
            -Path $nodeMarker `
            -Encoding UTF8
    }

    if (
        -not (Test-Path $nodeExe) -or
        -not (Test-Path $npmCommand)
    ) {
        throw (
            "Runtime Node.js portatil ficou incompleto."
        )
    }

    $installedNodeVersion = (
        & $nodeExe `
            --version
    )

    Write-Host (
        "Node.js portatil: " +
        ($installedNodeVersion -join "") +
        " / npm incluso"
    ) -ForegroundColor Green

    # --------------------------------------------------------
    # Optional isolated per-window audio
    # --------------------------------------------------------
    # This feature is NEVER allowed to block core app / voice call.
    # It lives in desktop\audio-deps, isolated from the runtime.
    $audioDepsDir = Join-Path `
        $desktopDirForDeps `
        "audio-deps"

    $audioModule = Join-Path `
        $audioDepsDir `
        "node_modules\loopback-capture\dist\index.cjs"

    $audioNative = Join-Path `
        $audioDepsDir `
        "node_modules\loopback-capture\build\Release\loopback_capture_addon.node"

    if (
        -not (Test-Path $audioModule) -or
        -not (Test-Path $audioNative)
    ) {
        Write-Host (
            "Audio isolado por janela: tentando dependencia opcional..."
        )

        try {
            Remove-Item `
                -Path $audioDepsDir `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue

            New-Item `
                -ItemType Directory `
                -Force `
                -Path $audioDepsDir |
                Out-Null

            Push-Location $audioDepsDir

            try {
                @{
                    name = "arena-squad-audio-deps"
                    private = $true
                    version = "1.0.0"
                } |
                ConvertTo-Json |
                Set-Content `
                    -Path "package.json" `
                    -Encoding UTF8

                & $npmCommand `
                    install `
                    "loopback-capture@2.0.0" `
                    --no-save `
                    --package-lock=false `
                    --fund=false `
                    --audit=false

                if ($LASTEXITCODE -ne 0) {
                    throw (
                        "npm install retornou codigo " +
                        $LASTEXITCODE
                    )
                }

                if (-not (Test-Path $audioNative)) {
                    # npm 11.19+ may require explicit approval.
                    try {
                        & $npmCommand `
                            install-scripts `
                            approve `
                            "loopback-capture"

                        & $npmCommand `
                            rebuild `
                            "loopback-capture"
                    }
                    catch {}
                }
            }
            finally {
                Pop-Location
            }

            if (
                (Test-Path $audioModule) -and
                (Test-Path $audioNative)
            ) {
                Write-Host (
                    "Audio isolado por janela: OK"
                ) -ForegroundColor Green
            }
            else {
                throw (
                    "modulo nativo nao ficou disponivel."
                )
            }
        }
        catch {
            Write-Warning (
                "Audio isolado indisponivel por enquanto. " +
                "A SALA DE VOZ e o restante do app continuarao. Motivo: " +
                $_.Exception.Message
            )
        }
    }

    $serverDir = Join-Path $arenaRoot "server"

    if (
        $isHost -or
        (Test-Path $serverDir)
    ) {
        New-Item `
            -ItemType Directory `
            -Force `
            -Path $serverDir |
            Out-Null
        foreach ($name in @(
            "index.js",
            "launcher.js",
            "run-server-hidden.ps1"
        )) {
            Copy-WithBackup `
                -Source (Join-Path $extractPath "payload\server\$name") `
                -Target (Join-Path $arenaRoot "server\$name") `
                -Backup (Join-Path $backupRoot "server\$name")
        }
    }

    # --------------------------------------------------------
    # HOST Socket.IO dependency security update
    # --------------------------------------------------------
    if ($isHost) {
        Write-Host (
            "Atualizando Socket.IO do servidor para versao segura..."
        )

        $serverDepsBuild = Join-Path `
            $tempRoot `
            "server-deps-secure"

        New-Item `
            -ItemType Directory `
            -Force `
            -Path $serverDepsBuild |
            Out-Null

        @{
            name = "arena-squad-server-runtime"
            private = $true
            version = "1.0.0"
        } |
        ConvertTo-Json |
        Set-Content `
            -Path (Join-Path $serverDepsBuild "package.json") `
            -Encoding UTF8

        & $npmCommand `
            install `
            --prefix $serverDepsBuild `
            ("socket.io@" + $SocketIoServerVersion) `
            --no-save `
            --package-lock=false `
            --ignore-scripts `
            --fund=false `
            --audit=false

        if ($LASTEXITCODE -ne 0) {
            throw (
                "npm falhou ao instalar Socket.IO seguro."
            )
        }

        $secureModules = Join-Path `
            $serverDepsBuild `
            "node_modules"

        function Read-PackageVersion {
            param(
                [string]$PackageJson
            )

            if (-not (Test-Path $PackageJson)) {
                return $null
            }

            return [string](
                (
                    Get-Content `
                        $PackageJson `
                        -Raw |
                    ConvertFrom-Json
                ).version
            )
        }

        $socketServerInstalled = Read-PackageVersion (
            Join-Path `
                $secureModules `
                "socket.io\package.json"
        )

        $engineInstalled = Read-PackageVersion (
            Join-Path `
                $secureModules `
                "engine.io\package.json"
        )

        $parserInstalled = Read-PackageVersion (
            Join-Path `
                $secureModules `
                "socket.io-parser\package.json"
        )

        $wsJson = Join-Path `
            $secureModules `
            "ws\package.json"

        if (-not (Test-Path $wsJson)) {
            $wsJson = Join-Path `
                $secureModules `
                "engine.io\node_modules\ws\package.json"
        }

        $wsInstalled = Read-PackageVersion $wsJson

        if (
            $socketServerInstalled -ne $SocketIoServerVersion -or
            -not $engineInstalled -or
            ([version]$engineInstalled) -lt ([version]"6.6.9") -or
            -not $parserInstalled -or
            ([version]$parserInstalled) -lt ([version]"4.2.7") -or
            -not $wsInstalled -or
            ([version]$wsInstalled) -lt ([version]"8.21.0")
        ) {
            throw (
                "Dependencias Socket.IO nao atingiram as versoes seguras. " +
                "socket.io=$socketServerInstalled; " +
                "engine.io=$engineInstalled; " +
                "parser=$parserInstalled; " +
                "ws=$wsInstalled"
            )
        }

        Write-Host (
            "Socket.IO server $socketServerInstalled; " +
            "Engine.IO $engineInstalled; " +
            "parser $parserInstalled; ws $wsInstalled"
        ) -ForegroundColor Green

        $serverDir = Join-Path `
            $arenaRoot `
            "server"

        $targetServerModules = Join-Path `
            $serverDir `
            "node_modules"

        $serverModulesBackup = Join-Path `
            $backupRoot `
            "server\node_modules-before-security"

        if (Test-Path $targetServerModules) {
            try {
                Move-Item `
                    -Path $targetServerModules `
                    -Destination $serverModulesBackup `
                    -Force
            }
            catch {
                Remove-Item `
                    -Path $targetServerModules `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop
            }
        }

        Copy-Item `
            -Path $secureModules `
            -Destination $targetServerModules `
            -Recurse `
            -Force

        @{
            name = "arena-squad-server"
            private = $true
            version = $Version
            dependencies = @{
                "socket.io" = $SocketIoServerVersion
            }
        } |
        ConvertTo-Json -Depth 5 |
        Set-Content `
            -Path (Join-Path $serverDir "package.json") `
            -Encoding UTF8
    }

    # Never download/overwrite password hashes or remembered sessions.
    # If this is a host that has never had passwords configured, create
    # a new auth DB locally so no password hash must be published online.
    if ($isHost) {
        $authFile = Join-Path $arenaRoot "server\profile-auth.json"

        if (-not (Test-Path $authFile)) {
            Write-Host "Criando senhas locais do HOST..."

            $bootstrapAuth = Join-Path $extractPath "tools\bootstrap-auth.js"

            & $nodeExe $bootstrapAuth $arenaRoot

            if ($LASTEXITCODE -ne 0) {
                throw "Nao foi possivel criar profile-auth.json."
            }
        }
    }

    if ($isHost) {
        Write-Host (
            "Protegendo arquivos sensiveis do HOST..."
        )

        $currentIdentity = (
            [System.Security.Principal.WindowsIdentity]::GetCurrent()
        ).Name

        $sensitiveFiles = @(
            (Join-Path $arenaRoot "server\profile-auth.json"),
            (Join-Path $arenaRoot "server\profile-sessions.json"),
            (Join-Path $arenaRoot "server\profile-activity.json"),
            (Join-Path $arenaRoot "server\profile-presence.json"),
            (Join-Path $arenaRoot "SENHAS-ARENA-SQUAD-ADMIN.txt")
        )

        foreach ($sensitiveFile in $sensitiveFiles) {
            if (Test-Path $sensitiveFile) {
                try {
                    & icacls.exe `
                        $sensitiveFile `
                        /inheritance:r `
                        /grant:r `
                        ("${currentIdentity}:(F)") `
                        "SYSTEM:(F)" |
                        Out-Null
                }
                catch {
                    Write-Warning (
                        "Nao foi possivel restringir ACL de: " +
                        $sensitiveFile
                    )
                }
            }
        }
    }

    if ($isHost) {
        Write-Host "[5/7] Configurando servidor HOST invisivel..."

        $taskName = "Arena Squad Server"
        $serverRunner = Join-Path `
            $arenaRoot `
            "server\run-server-hidden.ps1"

        $vbsPath = Join-Path `
            $arenaRoot `
            "server\start-arena-server-hidden.vbs"

        if (-not (Test-Path $serverRunner)) {
            throw "run-server-hidden.ps1 nao encontrado."
        }

        # Wrapper VBS hides PowerShell completely and waits for it.
        # Task Scheduler therefore tracks the real lifetime of the server.
        $escapedRunner = $serverRunner.Replace('"', '""')

        $vbs = @"
Set shell = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & "$escapedRunner" & Chr(34)
code = shell.Run(cmd, 0, True)
WScript.Quit code
"@

        Set-Content `
            -Path $vbsPath `
            -Value $vbs `
            -Encoding ASCII

        # Stop/remove an older task, if it exists.
        Stop-ScheduledTask `
            -TaskName $taskName `
            -ErrorAction SilentlyContinue

        Unregister-ScheduledTask `
            -TaskName $taskName `
            -Confirm:$false `
            -ErrorAction SilentlyContinue

        # Kill anything still bound to port 3000 before starting the new task.
        try {
            $listeners = Get-NetTCPConnection `
                -LocalPort 3000 `
                -State Listen `
                -ErrorAction SilentlyContinue

            foreach ($listener in $listeners) {
                if ($listener.OwningProcess) {
                    Stop-Process `
                        -Id $listener.OwningProcess `
                        -Force `
                        -ErrorAction SilentlyContinue
                }
            }
        }
        catch {}

        Start-Sleep -Milliseconds 500

        $action = New-ScheduledTaskAction `
            -Execute "$env:WINDIR\System32\wscript.exe" `
            -Argument "`"$vbsPath`""

        $trigger = New-ScheduledTaskTrigger -AtLogOn

        $currentUser = (
            [System.Security.Principal.WindowsIdentity]::GetCurrent()
        ).Name

        $principal = New-ScheduledTaskPrincipal `
            -UserId $currentUser `
            -LogonType Interactive `
            -RunLevel Limited

        $settings = New-ScheduledTaskSettingsSet `
            -StartWhenAvailable `
            -MultipleInstances IgnoreNew `
            -RestartCount 5 `
            -RestartInterval (New-TimeSpan -Minutes 1) `
            -ExecutionTimeLimit ([TimeSpan]::Zero)

        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Description "Arena Squad HOST server - hidden background service" `
            -Force |
            Out-Null

        Start-ScheduledTask -TaskName $taskName

        Write-Host "Servidor HOST registrado no Agendador de Tarefas." -ForegroundColor Green
    }

    Write-Host "[6/7] Garantindo Firewall WebRTC/Tailscale..."

    $electronExe = Join-Path `
        $arenaRoot `
        "desktop\node_modules\electron\dist\electron.exe"

    if (Test-Path $electronExe) {
        $udpRule = "Arena Squad WebRTC UDP - Tailscale"
        $tcpRule = "Arena Squad WebRTC TCP - Tailscale"

        Get-NetFirewallRule `
            -DisplayName $udpRule `
            -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule `
                -ErrorAction SilentlyContinue

        Get-NetFirewallRule `
            -DisplayName $tcpRule `
            -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule `
                -ErrorAction SilentlyContinue

        New-NetFirewallRule `
            -DisplayName $udpRule `
            -Direction Inbound `
            -Action Allow `
            -Program $electronExe `
            -Protocol UDP `
            -RemoteAddress "100.64.0.0/10" `
            -Profile Any |
            Out-Null

        New-NetFirewallRule `
            -DisplayName $tcpRule `
            -Direction Inbound `
            -Action Allow `
            -Program $electronExe `
            -Protocol TCP `
            -RemoteAddress "100.64.0.0/10" `
            -Profile Any |
            Out-Null
    }
    else {
        Write-Warning "electron.exe nao encontrado; regra de Firewall nao foi alterada."
    }

    if ($isHost) {
        $serverFirewallRule =
            "Arena Squad Server TCP 3000 - Tailscale"

        Get-NetFirewallRule `
            -DisplayName $serverFirewallRule `
            -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule `
                -ErrorAction SilentlyContinue

        if (
            -not $nodeExe -or
            -not (Test-Path $nodeExe)
        ) {
            throw (
                "Node.js portatil nao encontrado para regra segura do servidor."
            )
        }


        New-NetFirewallRule `
            -DisplayName $serverFirewallRule `
            -Direction Inbound `
            -Action Allow `
            -Program $nodeExe `
            -LocalPort 3000 `
            -Protocol TCP `
            -RemoteAddress "100.64.0.0/10" `
            -Profile Any |
            Out-Null

        Write-Host (
            "Firewall servidor 3000 restrito ao Tailscale: OK"
        ) -ForegroundColor Green
    }

    Write-Host "[6.5/7] Verificando arquivos realmente instalados..."

    $verifyPairs = @(
        @{
            Name = "desktop\main.js"
            Source = Join-Path $extractPath "payload\desktop\main.js"
            Target = Join-Path $arenaRoot "desktop\main.js"
        },
        @{
            Name = "desktop\preload.js"
            Source = Join-Path $extractPath "payload\desktop\preload.js"
            Target = Join-Path $arenaRoot "desktop\preload.js"
        },
        @{
            Name = "desktop\renderer.js"
            Source = Join-Path $extractPath "payload\desktop\renderer.js"
            Target = Join-Path $arenaRoot "desktop\renderer.js"
        },
        @{
            Name = "desktop\index.html"
            Source = Join-Path $extractPath "payload\desktop\index.html"
            Target = Join-Path $arenaRoot "desktop\index.html"
        },
        @{
            Name = "desktop\styles.css"
            Source = Join-Path $extractPath "payload\desktop\styles.css"
            Target = Join-Path $arenaRoot "desktop\styles.css"
        },
        @{
            Name = "desktop\package.json"
            Source = Join-Path $extractPath "payload\desktop\package.json"
            Target = Join-Path $arenaRoot "desktop\package.json"
        }
    )

    if ($isHost) {
        $verifyPairs += @{
            Name = "server\index.js"
            Source = Join-Path $extractPath "payload\server\index.js"
            Target = Join-Path $arenaRoot "server\index.js"
        }
    }

    foreach ($pair in $verifyPairs) {
        if (-not (Test-Path $pair.Target)) {
            throw (
                "Arquivo atualizado nao existe: " +
                $pair.Name
            )
        }

        $sourceHash = (
            Get-FileHash `
                -Path $pair.Source `
                -Algorithm SHA256
        ).Hash

        $targetHash = (
            Get-FileHash `
                -Path $pair.Target `
                -Algorithm SHA256
        ).Hash

        if ($sourceHash -ne $targetHash) {
            throw (
                "Falha ao aplicar atualizacao em " +
                $pair.Name +
                ". SHA do arquivo instalado nao confere."
            )
        }

        Write-Host (
            "OK: " +
            $pair.Name
        ) -ForegroundColor Green
    }

    $installedHtml = Get-Content `
        (Join-Path $arenaRoot "desktop\index.html") `
        -Raw

    $installedRenderer = Get-Content `
        (Join-Path $arenaRoot "desktop\renderer.js") `
        -Raw

    # Do not validate UI by visible copy. Labels can legitimately change
    # (for example, "Sala de voz" became "Voice Call"). Verify the
    # stable DOM/API contract that the voice feature actually needs.
    $requiredVoiceHtmlMarkers = @(
        'id="voiceTab"',
        'id="voiceJoinBtn"',
        'id="voiceMembers"',
        'id="voiceRemoteAudio"'
    )

    foreach ($marker in $requiredVoiceHtmlMarkers) {
        if (
            $installedHtml -notmatch
            [regex]::Escape($marker)
        ) {
            throw (
                "Verificacao funcional falhou: " +
                "estrutura da Voice Call incompleta no index.html. " +
                "Ausente: " + $marker
            )
        }
    }

    $requiredVoiceRendererMarkers = @(
        'voice-join',
        'voice-leave',
        'function joinVoiceCall'
    )

    foreach ($marker in $requiredVoiceRendererMarkers) {
        if (
            $installedRenderer -notmatch
            [regex]::Escape($marker)
        ) {
            throw (
                "Verificacao funcional falhou: " +
                "logica da Voice Call incompleta no renderer.js. " +
                "Ausente: " + $marker
            )
        }
    }

    $installedElectron = Join-Path `
        $arenaRoot `
        "desktop\node_modules\electron\dist\electron.exe"

    $installedSocketIo = Join-Path `
        $arenaRoot `
        "desktop\node_modules\socket.io-client\dist\socket.io.min.js"

    if (-not (Test-Path $installedElectron)) {
        throw (
            "Verificacao de runtime falhou: electron.exe ausente."
        )
    }

    if (-not (Test-Path $installedSocketIo)) {
        throw (
            "Verificacao de runtime falhou: socket.io-client ausente."
        )
    }

    $electronSize = (
        Get-Item $installedElectron
    ).Length

    if ($electronSize -lt 1000000) {
        throw (
            "Verificacao de runtime falhou: " +
            "electron.exe parece incompleto."
        )
    }

    Write-Host (
        "RUNTIME Electron 37.10.3 + Socket.IO 4.8.3: OK"
    ) -ForegroundColor Green

    if ($isHost) {
        $serverSocketPackage = Join-Path `
            $arenaRoot `
            "server\node_modules\socket.io\package.json"

        if (-not (Test-Path $serverSocketPackage)) {
            throw (
                "Verificacao de seguranca falhou: Socket.IO server ausente."
            )
        }

        $serverSocketVersion = [string](
            (
                Get-Content `
                    $serverSocketPackage `
                    -Raw |
                ConvertFrom-Json
            ).version
        )

        if ($serverSocketVersion -ne $SocketIoServerVersion) {
            throw (
                "Verificacao de seguranca falhou: Socket.IO server incorreto."
            )
        }

        Write-Host (
            "RUNTIME Socket.IO server " +
            $serverSocketVersion +
            ": OK"
        ) -ForegroundColor Green
    }

    $installedConfig = Join-Path `
        $arenaRoot `
        "desktop\config.json"

    if (-not (Test-Path $installedConfig)) {
        throw (
            "Verificacao falhou: config.json ausente."
        )
    }

    try {
        $verifiedConfig = Get-Content `
            $installedConfig `
            -Raw |
            ConvertFrom-Json

        $verifiedUri =
            [Uri]([string]$verifiedConfig.serverUrl)

        if (
            $verifiedUri.Scheme -ne "http" -or
            $verifiedUri.Port -ne 3000
        ) {
            throw "serverUrl inesperada."
        }
    }
    catch {
        throw (
            "Verificacao falhou: config.json invalido."
        )
    }

    if (
        -not (Test-Path $nodeExe) -or
        -not (Test-Path $npmCommand)
    ) {
        throw (
            "Verificacao falhou: Node.js portatil ausente."
        )
    }

    Write-Host (
        "CONFIG + Node.js portatil: OK"
    ) -ForegroundColor Green

    $desktopPackageJson = Join-Path `
        $arenaRoot `
        "desktop\package.json"

    $desktopMainJs = Join-Path `
        $arenaRoot `
        "desktop\main.js"

    if (-not (Test-Path $desktopMainJs)) {
        throw (
            "Verificacao falhou: desktop\main.js ausente."
        )
    }

    if (-not (Test-Path $desktopPackageJson)) {
        Write-Warning (
            "desktop\package.json ausente; recriando manifesto do Electron."
        )

        @{
            name = "arena-squad-desktop"
            version = $Version
            private = $true
            main = "main.js"
        } |
        ConvertTo-Json |
        Set-Content `
            -Path $desktopPackageJson `
            -Encoding UTF8
    }

    try {
        $desktopManifest = Get-Content `
            $desktopPackageJson `
            -Raw |
            ConvertFrom-Json

        if (
            [string]$desktopManifest.main -ne
            "main.js"
        ) {
            throw "main invalido"
        }

        if (
            [string]$desktopManifest.version -ne
            $Version
        ) {
            throw (
                "versao instalada incorreta: " +
                [string]$desktopManifest.version
            )
        }
    }
    catch {
        throw (
            "Verificacao falhou: desktop\package.json invalido."
        )
    }

    Write-Host (
        "Electron app manifest (package.json): OK"
    ) -ForegroundColor Green

    Write-Host (
        "VOICE CALL confirmada nos arquivos instalados."
    ) -ForegroundColor Green

    Write-Host "[7/7] Criando atalhos sem CMD..."

    $desktopDir = Join-Path $arenaRoot "desktop"
    $electronExe = Join-Path `
        $desktopDir `
        "node_modules\electron\dist\electron.exe"

    if (Test-Path $electronExe) {
        $shell = New-Object -ComObject WScript.Shell
        $desktopPath = [Environment]::GetFolderPath("Desktop")

        $legacyShortcutNames = @(
            "Arena Squad",
            "Arena Squad HOST"
        )

        foreach ($legacyShortcutName in $legacyShortcutNames) {
            $legacyShortcutPath = Join-Path `
                $desktopPath `
                ($legacyShortcutName + ".lnk")

            Remove-Item `
                $legacyShortcutPath `
                -Force `
                -ErrorAction SilentlyContinue
        }

        $shortcutNames = @("Chat dos Pecinha")

        if ($isHost) {
            $shortcutNames += "Chat dos Pecinha HOST"
        }

        foreach ($shortcutName in $shortcutNames) {
            $shortcutPath = Join-Path `
                $desktopPath `
                ($shortcutName + ".lnk")

            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $electronExe
            $shortcut.Arguments = "`"$desktopDir`""
            $shortcut.WorkingDirectory = $desktopDir
            $appIcon = Join-Path `
                $desktopDir `
                "app-icon.ico"

            if (Test-Path $appIcon) {
                $shortcut.IconLocation =
                    $appIcon
            }
            else {
                $shortcut.IconLocation =
                    "$electronExe,0"
            }
            $shortcut.Description = "Chat dos Pecinha - modo em segundo plano"
            $shortcut.Save()
        }

        Write-Host "Atalho criado sem CMD." -ForegroundColor Green
    }
    else {
        Write-Warning "electron.exe nao encontrado; atalho nao foi recriado."
    }


    $installMarker = Join-Path `
        $arenaRoot `
        $(if ($freshInstall) {
            "FRESH-INSTALL-$Version.txt"
        }
        else {
            "ONLINE-UPDATE-$Version.txt"
        })

    Set-Content `
        -Path $installMarker `
        -Value (
            $(if ($freshInstall) {
                "Instalacao nova concluida em "
            }
            else {
                "Atualizacao online instalada em "
            }) +
            (Get-Date)
        ) `
        -Encoding UTF8

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host (
        " " +
        $(if ($freshInstall) {
            "INSTALACAO CONCLUIDA"
        }
        else {
            "ATUALIZACAO CONCLUIDA"
        }) +
        " - " +
        $Version
    ) -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host ""

    Write-Host "O app agora roda no tray sem CMD aberto."
    if ($isHost) {
        Write-Host "O servidor HOST roda invisivel pelo Agendador de Tarefas."
    }
    Write-Host "Fechar no X apenas esconde o app."
    Write-Host "Para encerrar de verdade: icone do tray > Sair do Chat dos Pecinha."
    Write-Host ""
    if ($freshInstall) {
        Write-Host (
            "Instalacao nova pronta. Runtime Electron + Node.js incluidos."
        )

        if (-not $isHost) {
            Write-Host (
                "HOST configurado em: " +
                $freshServerUrl
            )
        }
    }
    else {
        Write-Host (
            "config.json, senhas, sessoes e ultimo acesso foram preservados."
        )
    }

    if (
        $freshInstall -and
        -not $isHost
    ) {
        $tailscaleAfter =
            Get-TailscaleExe

        if (-not $tailscaleAfter) {
            Write-Warning (
                "Tailscale ainda nao esta instalado. " +
                "Instale/conecte o Tailscale antes de usar o Chat dos Pecinha."
            )
        }
        else {
            try {
                $tsIpAfter = (
                    & $tailscaleAfter `
                        ip `
                        -4 `
                        2>$null |
                    Select-Object -First 1
                )

                if (-not $tsIpAfter) {
                    Write-Warning (
                        "Tailscale esta instalado, mas ainda nao esta conectado. " +
                        "Faca login no Tailscale antes de usar o Chat dos Pecinha."
                    )
                }
            }
            catch {}
        }
    }

    if (Test-Path $electronExe) {
        Start-Process `
            -FilePath $electronExe `
            -ArgumentList "`"$desktopDir`"" `
            -WorkingDirectory $desktopDir

        if ($isHost) {
            Write-Host "Aguardando servidor HOST invisivel..."

            $hostReady = $false

            for ($attempt = 0; $attempt -lt 30; $attempt++) {
                Start-Sleep -Milliseconds 300

                try {
                    $health = Invoke-RestMethod `
                        -Uri "http://localhost:3000/health" `
                        -TimeoutSec 1

                    if ($health.ok) {
                        $hostReady = $true
                        break
                    }
                }
                catch {}
            }

            if ($hostReady) {
                Write-Host (
                    "Servidor HOST online na porta 3000. Versao: " +
                    $health.appVersion
                ) -ForegroundColor Green

                $task = Get-ScheduledTask `
                    -TaskName "Arena Squad Server" `
                    -ErrorAction SilentlyContinue

                if ($task) {
                    Write-Host (
                        "Tarefa Arena Squad Server: " +
                        $task.State
                    ) -ForegroundColor Green
                }
            }
            else {
                Write-Warning "Servidor HOST ainda nao respondeu."

                $taskInfo = Get-ScheduledTaskInfo `
                    -TaskName "Arena Squad Server" `
                    -ErrorAction SilentlyContinue

                if ($taskInfo) {
                    Write-Warning (
                        "Task LastTaskResult: " +
                        $taskInfo.LastTaskResult
                    )
                }

                Write-Warning "Confira server\arena-server.log."
            }
        }
    }
}
finally {
    Remove-Item `
        -Path $tempRoot `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    try {
        Stop-Transcript | Out-Null
    }
    catch {}
}

