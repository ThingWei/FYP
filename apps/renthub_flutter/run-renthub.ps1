[CmdletBinding()]
param(
    [string]$Device = 'windows',
    [switch]$Admin,
    [switch]$SkipAi,
    [switch]$SkipBlockchain,
    [switch]$CheckOnly,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraFlutterArgs
)

$ErrorActionPreference = 'Stop'

function Test-RentHubTcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMilliseconds = 1000
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connection = $client.ConnectAsync($HostName, $Port)
        if (-not $connection.Wait($TimeoutMilliseconds)) {
            return $false
        }
        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Test-RentHubApiReady {
    try {
        $response = Invoke-RestMethod `
            -Uri 'http://localhost:3000/api/v1/ready' `
            -TimeoutSec 2
        return $response.success -eq $true -and `
            $response.data.capabilities -contains 'product-catalog-v1'
    }
    catch {
        return $false
    }
}

function Get-RentHubAiHealth {
    try {
        return Invoke-RestMethod `
            -Uri 'http://localhost:8001/health' `
            -TimeoutSec 3
    }
    catch {
        return $null
    }
}

function Get-RentHubBlockchainHealth {
    param(
        [Parameter(Mandatory = $true)][string]$RpcUrl
    )

    try {
        $body = @{
            jsonrpc = '2.0'
            method = 'eth_chainId'
            params = @()
            id = 1
        } | ConvertTo-Json -Compress
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $RpcUrl `
            -ContentType 'application/json' `
            -Body $body `
            -TimeoutSec 3
        if ($response.result) {
            return $response
        }
        return $null
    }
    catch {
        return $null
    }
}

function Get-RentHubEnvironmentValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$DefaultValue = ''
    )

    $line = Get-Content -LiteralPath $Path | Where-Object {
        $_ -match "^$([regex]::Escape($Name))="
    } | Select-Object -Last 1
    if ($null -eq $line) {
        return $DefaultValue
    }
    return ($line -split '=', 2)[1].Trim().Trim('"').Trim("'")
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$apiDirectory = Join-Path $projectRoot 'services\api'
$aiDirectory = Join-Path $projectRoot 'services\ai'
$blockchainDirectory = Join-Path $projectRoot 'blockchain'
$aiPython = Join-Path $aiDirectory '.venv\Scripts\python.exe'
$apiEnvironment = Join-Path $apiDirectory '.env'
$apiModules = Join-Path $apiDirectory 'node_modules'
$blockchainModules = Join-Path $blockchainDirectory 'node_modules'
$ganacheCli = Join-Path $blockchainModules 'ganache\dist\node\cli.js'
$contractArtifact = Join-Path $blockchainDirectory 'artifacts\contracts\RentalAgreement.sol\RentalAgreement.json'
$logDirectory = Join-Path $apiDirectory '.data\logs'
$standardLog = Join-Path $logDirectory 'launcher-api.log'
$errorLog = Join-Path $logDirectory 'launcher-api-error.log'
$aiLogDirectory = Join-Path $aiDirectory '.data\logs'
$aiStandardLog = Join-Path $aiLogDirectory 'launcher-ai.log'
$aiErrorLog = Join-Path $aiLogDirectory 'launcher-ai-error.log'
$blockchainLogDirectory = Join-Path $blockchainDirectory '.data\logs'
$blockchainStandardLog = Join-Path $blockchainLogDirectory 'launcher-ganache.log'
$blockchainErrorLog = Join-Path $blockchainLogDirectory 'launcher-ganache-error.log'
$blockchainDataDirectory = Join-Path $blockchainDirectory '.data\ganache'
$apiProcess = $null
$aiProcess = $null
$blockchainProcess = $null
$startedApi = $false
$startedAi = $false
$startedBlockchain = $false

if (-not (Test-Path -LiteralPath $apiEnvironment)) {
    throw "Missing $apiEnvironment. Configure the API .env before running RentHub."
}
if (-not (Test-Path -LiteralPath $apiModules)) {
    throw "API dependencies are missing. Run 'npm.cmd install' in $apiDirectory first."
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw 'Node.js is not available on PATH.'
}
$nodePath = (Get-Command node).Source
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not available on PATH.'
}
if ($Device -eq 'windows') {
    $existingRentHub = Get-Process -Name 'renthub_flutter' -ErrorAction SilentlyContinue
    if ($null -ne $existingRentHub) {
        $processIds = ($existingRentHub.Id | Sort-Object) -join ', '
        throw "RentHub is already running (process $processIds). Close the existing RentHub window, then run this launcher once. This avoids duplicate Auth0 callback ports and disconnected backend sessions."
    }
}
if (-not $SkipAi -and -not (Test-Path -LiteralPath $aiPython)) {
    throw "AI Python environment is missing. Create it at $aiDirectory\.venv and install requirements.txt."
}
$blockchainMode = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'BLOCKCHAIN_MODE' `
    -DefaultValue 'disabled'
$ganacheRpcUrl = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'GANACHE_RPC_URL' `
    -DefaultValue 'http://localhost:8545'
$authMode = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'AUTH_MODE' `
    -DefaultValue 'local'
$auth0Issuer = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'AUTH0_ISSUER_BASE_URL'
$auth0Audience = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'AUTH0_AUDIENCE'
$auth0WindowsClientId = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'AUTH0_WINDOWS_CLIENT_ID'
$auth0WebClientId = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'AUTH0_WEB_CLIENT_ID'
$auth0WindowsCallbackUrl = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'AUTH0_WINDOWS_CALLBACK_URL' `
    -DefaultValue 'http://127.0.0.1:53124/callback'
$auth0DatabaseConnection = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'AUTH0_DATABASE_CONNECTION' `
    -DefaultValue 'Username-Password-Authentication'
if (-not $SkipBlockchain -and $blockchainMode -eq 'ganache' -and -not (Test-Path -LiteralPath $ganacheCli)) {
    throw "Blockchain dependencies are missing. Run 'npm.cmd install' in $blockchainDirectory first."
}
if (-not (Test-RentHubTcpPort -HostName 'localhost' -Port 27017)) {
    throw 'MongoDB is not listening on localhost:27017. Start MongoDB before running RentHub.'
}

try {
    if (-not $SkipBlockchain -and $blockchainMode -eq 'ganache') {
        $blockchainHealth = Get-RentHubBlockchainHealth -RpcUrl $ganacheRpcUrl
        if ($null -ne $blockchainHealth) {
            Write-Host "RentHub blockchain is already ready at $ganacheRpcUrl." -ForegroundColor Green
        }
        else {
            if (-not (Test-Path -LiteralPath $contractArtifact)) {
                Write-Host 'Compiling the RentHub rental agreement contract...' -ForegroundColor Cyan
                & npm.cmd run compile --prefix $blockchainDirectory
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $contractArtifact)) {
                    throw 'The rental agreement contract could not be compiled.'
                }
            }

            New-Item -ItemType Directory -Path $blockchainLogDirectory -Force | Out-Null
            New-Item -ItemType Directory -Path $blockchainDataDirectory -Force | Out-Null
            Write-Host 'Starting the RentHub local blockchain...' -ForegroundColor Cyan
            $blockchainProcess = Start-Process `
                -FilePath $nodePath `
                -ArgumentList @(
                    $ganacheCli,
                    '--server.port', '8545',
                    '--wallet.deterministic',
                    '--chain.chainId', '1337',
                    '--database.dbPath', $blockchainDataDirectory
                ) `
                -WorkingDirectory $blockchainDirectory `
                -WindowStyle Hidden `
                -RedirectStandardOutput $blockchainStandardLog `
                -RedirectStandardError $blockchainErrorLog `
                -PassThru
            $startedBlockchain = $true

            $blockchainReady = $false
            for ($attempt = 0; $attempt -lt 30; $attempt++) {
                if ($blockchainProcess.HasExited) {
                    break
                }
                $blockchainHealth = Get-RentHubBlockchainHealth -RpcUrl $ganacheRpcUrl
                if ($null -ne $blockchainHealth) {
                    $blockchainReady = $true
                    break
                }
                Start-Sleep -Seconds 1
            }

            if (-not $blockchainReady) {
                $details = if (Test-Path -LiteralPath $blockchainErrorLog) {
                    (Get-Content -LiteralPath $blockchainErrorLog -Tail 12) -join [Environment]::NewLine
                }
                else {
                    'No blockchain error log was produced.'
                }
                throw "The local blockchain did not become ready. Review $blockchainErrorLog.`n$details"
            }
            Write-Host 'RentHub local blockchain is ready (chain ID 1337).' -ForegroundColor Green
        }
    }
    elseif ($SkipBlockchain) {
        Write-Host 'Blockchain startup was skipped.' -ForegroundColor DarkGray
    }
    else {
        Write-Host 'Blockchain integration is disabled in the API .env.' -ForegroundColor DarkGray
    }

    if (-not $SkipAi) {
        $aiHealth = Get-RentHubAiHealth
        if ($null -ne $aiHealth -and $aiHealth.status -eq 'ok') {
            Write-Host 'RentHub AI service is already ready on port 8001.' -ForegroundColor Green
        }
        else {
            New-Item -ItemType Directory -Path $aiLogDirectory -Force | Out-Null
            Write-Host 'Starting the RentHub AI service...' -ForegroundColor Cyan
            $aiProcess = Start-Process `
                -FilePath $aiPython `
                -ArgumentList @('-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8001') `
                -WorkingDirectory $aiDirectory `
                -WindowStyle Hidden `
                -RedirectStandardOutput $aiStandardLog `
                -RedirectStandardError $aiErrorLog `
                -PassThru
            $startedAi = $true

            $aiReady = $false
            for ($attempt = 0; $attempt -lt 45; $attempt++) {
                if ($aiProcess.HasExited) {
                    break
                }
                $aiHealth = Get-RentHubAiHealth
                if ($null -ne $aiHealth -and $aiHealth.status -eq 'ok') {
                    $aiReady = $true
                    break
                }
                Start-Sleep -Seconds 1
            }

            if (-not $aiReady) {
                $details = if (Test-Path -LiteralPath $aiErrorLog) {
                    (Get-Content -LiteralPath $aiErrorLog -Tail 12) -join [Environment]::NewLine
                }
                else {
                    'No AI error log was produced.'
                }
                throw "The AI service did not become ready. Review $aiErrorLog.`n$details"
            }
            Write-Host 'RentHub AI service is ready.' -ForegroundColor Green
        }

        if ($aiHealth.artifacts.price_model -eq $true) {
            Write-Host 'AI price-suggestion model is available.' -ForegroundColor Green
        }
        else {
            Write-Warning 'The AI service is running, but the price model artifact is missing.'
        }
    }

    if (Test-RentHubApiReady) {
        Write-Host 'RentHub API is already ready on port 3000.' -ForegroundColor Green
    }
    else {
        if (Test-RentHubTcpPort -HostName 'localhost' -Port 3000) {
            throw 'Port 3000 is occupied by an outdated or unhealthy API process. Stop that process and run this launcher again so the product-catalog routes are loaded.'
        }
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        Write-Host 'Starting the RentHub API...' -ForegroundColor Cyan
        $apiProcess = Start-Process `
            -FilePath $nodePath `
            -ArgumentList 'src/server.js' `
            -WorkingDirectory $apiDirectory `
            -WindowStyle Hidden `
            -RedirectStandardOutput $standardLog `
            -RedirectStandardError $errorLog `
            -PassThru
        $startedApi = $true

        $ready = $false
        for ($attempt = 0; $attempt -lt 30; $attempt++) {
            if ($apiProcess.HasExited) {
                break
            }
            if (Test-RentHubApiReady) {
                $ready = $true
                break
            }
            Start-Sleep -Seconds 1
        }

        if (-not $ready) {
            $details = if (Test-Path -LiteralPath $errorLog) {
                (Get-Content -LiteralPath $errorLog -Tail 12) -join [Environment]::NewLine
            }
            else {
                'No API error log was produced.'
            }
            throw "The API did not become ready. Review $errorLog.`n$details"
        }
        Write-Host 'RentHub API is ready.' -ForegroundColor Green
    }

    if ($CheckOnly) {
        $checkedServices = @('MongoDB', 'the RentHub API')
        if (-not $SkipAi) {
            $checkedServices += 'the AI service'
        }
        if (-not $SkipBlockchain -and $blockchainMode -eq 'ganache') {
            $checkedServices += 'the local blockchain'
        }
        $checkedServices = $checkedServices -join ', '
        Write-Host "$checkedServices passed the launcher checks." -ForegroundColor Green
        return
    }

    $isBrowser = $Device -in @('chrome', 'edge')
    $isDesktop = $Device -in @('windows', 'chrome', 'edge')
    if (-not $isDesktop) {
        $adb = Get-Command adb -ErrorAction SilentlyContinue
        if ($null -ne $adb) {
            & $adb.Source -s $Device reverse tcp:3000 tcp:3000
            if ($LASTEXITCODE -ne 0) {
                Write-Warning 'ADB port forwarding failed. Use your PC LAN address through API_BASE_URL and SOCKET_URL.'
            }
        }
        else {
            Write-Warning 'ADB was not found. The Android device must be able to reach the configured API address.'
        }
    }

    $arguments = @('run', '-d', $Device)
    if ($isBrowser) {
        $arguments += @('--web-port', $(if ($Admin) { '3001' } else { '8080' }))
    }
    if ($Admin) {
        $arguments += @('-t', 'lib/main_admin.dart')
    }
    if ($authMode -in @('auth0', 'hybrid')) {
        if ([string]::IsNullOrWhiteSpace($auth0Issuer)) {
            throw 'AUTH0_ISSUER_BASE_URL is required in the API .env when AUTH_MODE=auth0.'
        }
        if ([string]::IsNullOrWhiteSpace($auth0Audience)) {
            throw 'AUTH0_AUDIENCE is required in the API .env when AUTH_MODE=auth0.'
        }

        $auth0Domain = $auth0Issuer `
            -replace '^https?://', '' `
            -replace '/$', ''
        if ($Device -eq 'windows') {
            $auth0ClientId = $auth0WindowsClientId
            $auth0CallbackUrl = $auth0WindowsCallbackUrl
            $clientSettingName = 'AUTH0_WINDOWS_CLIENT_ID'
        }
        elseif ($isBrowser) {
            $auth0ClientId = $auth0WebClientId
            $auth0CallbackUrl = if ($Admin) {
                'http://localhost:3001'
            }
            else {
                'http://localhost:8080'
            }
            $clientSettingName = 'AUTH0_WEB_CLIENT_ID'
        }
        else {
            throw 'Auth0 mobile startup is not enabled yet. Use Windows/Web or complete the Android Auth0 integration first.'
        }

        if ([string]::IsNullOrWhiteSpace($auth0ClientId)) {
            throw "$clientSettingName is required in the API .env when AUTH_MODE=auth0 and Device=$Device."
        }
        $arguments += @(
            "--dart-define=AUTH0_DOMAIN=$auth0Domain",
            "--dart-define=AUTH0_CLIENT_ID=$auth0ClientId",
            "--dart-define=AUTH0_AUDIENCE=$auth0Audience",
            "--dart-define=AUTH0_CALLBACK_URL=$auth0CallbackUrl",
            "--dart-define=AUTH0_DATABASE_CONNECTION=$auth0DatabaseConnection"
        )
    }
    if ($ExtraFlutterArgs) {
        $arguments += $ExtraFlutterArgs
    }

    Write-Host "Starting RentHub on $Device..." -ForegroundColor Cyan
    & flutter @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter exited with code $LASTEXITCODE."
    }
}
finally {
    if ($startedAi -and $null -ne $aiProcess -and -not $aiProcess.HasExited) {
        Write-Host 'Stopping the AI process started by this launcher...' -ForegroundColor DarkGray
        Stop-Process -Id $aiProcess.Id -Force
    }
    if ($startedApi -and $null -ne $apiProcess -and -not $apiProcess.HasExited) {
        Write-Host 'Stopping the API process started by this launcher...' -ForegroundColor DarkGray
        Stop-Process -Id $apiProcess.Id -Force
    }
    if ($startedBlockchain -and $null -ne $blockchainProcess -and -not $blockchainProcess.HasExited) {
        Write-Host 'Stopping the blockchain process started by this launcher...' -ForegroundColor DarkGray
        Stop-Process -Id $blockchainProcess.Id -Force
    }
}
