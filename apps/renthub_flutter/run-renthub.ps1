[CmdletBinding()]
param(
    [string]$Device = 'windows',
    [switch]$Admin,
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
        return $response.success -eq $true
    }
    catch {
        return $false
    }
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$apiDirectory = Join-Path $projectRoot 'services\api'
$apiEnvironment = Join-Path $apiDirectory '.env'
$apiModules = Join-Path $apiDirectory 'node_modules'
$logDirectory = Join-Path $apiDirectory '.data\logs'
$standardLog = Join-Path $logDirectory 'launcher-api.log'
$errorLog = Join-Path $logDirectory 'launcher-api-error.log'
$apiProcess = $null
$startedApi = $false

if (-not (Test-Path -LiteralPath $apiEnvironment)) {
    throw "Missing $apiEnvironment. Configure the API .env before running RentHub."
}
if (-not (Test-Path -LiteralPath $apiModules)) {
    throw "API dependencies are missing. Run 'npm.cmd install' in $apiDirectory first."
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw 'Node.js is not available on PATH.'
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not available on PATH.'
}
if (-not (Test-RentHubTcpPort -HostName 'localhost' -Port 27017)) {
    throw 'MongoDB is not listening on localhost:27017. Start MongoDB before running RentHub.'
}

try {
    if (Test-RentHubApiReady) {
        Write-Host 'RentHub API is already ready on port 3000.' -ForegroundColor Green
    }
    else {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        $nodePath = (Get-Command node).Source
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
        Write-Host 'MongoDB and the RentHub API passed the launcher checks.' -ForegroundColor Green
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
    if ($startedApi -and $null -ne $apiProcess -and -not $apiProcess.HasExited) {
        Write-Host 'Stopping the API process started by this launcher...' -ForegroundColor DarkGray
        Stop-Process -Id $apiProcess.Id -Force
    }
}
