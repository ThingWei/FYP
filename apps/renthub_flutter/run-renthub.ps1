[CmdletBinding()]
param(
    [string]$Device = 'windows',
    [ValidateRange(1, 65535)][int]$ApiPort,
    [string]$AtlasProjectId,
    [string]$AtlasProfile = 'default',
    [switch]$SkipAtlasAccess,
    [switch]$Admin,
    [switch]$SkipAi,
    [switch]$NoAiReload,
    [switch]$NoApiReload,
    [switch]$Presentation,
    [ValidateRange(10, 600)][int]$AiStartupTimeoutSeconds = 180,
    [ValidateRange(10, 300)][int]$ApiStartupTimeoutSeconds = 90,
    [switch]$SkipBlockchain,
    [switch]$CheckOnly,
    [switch]$ServicesOnly,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraFlutterArgs
)

$ErrorActionPreference = 'Stop'

if ($CheckOnly -and $ServicesOnly) {
    throw 'Choose CheckOnly for a temporary readiness check or ServicesOnly to keep the services running.'
}
if ($Presentation) {
    $NoAiReload = $true
    $NoApiReload = $true
    Write-Host 'Presentation mode: stable services without development reload.' -ForegroundColor Cyan
}

function ConvertTo-RentHubProcessArguments {
    param([AllowEmptyCollection()][string[]]$Arguments)
    # Start-Process and .NET Framework join arguments into one Windows command line.
    # Quote every argument using the Windows CRT backslash/quote rules.
    return (($Arguments | ForEach-Object {
        '"' + ([regex]::Replace([regex]::Replace($_, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
    }) -join ' ')
}

function Test-RentHubNodeVersion {
    param([string]$Version)
    return $Version.Trim() -match '^v?(?<major>\d+)\.\d+\.\d+(?:[-+].*)?$' -and [int]$Matches.major -ge 22
}

function Invoke-RentHubNativeCommand {
    param([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory,
        [string]$InputText, [ValidateRange(1, 300)][int]$TimeoutSeconds = 30)
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = ConvertTo-RentHubProcessArguments -Arguments $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardInput = $true
    if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $startedAt = $null
    try {
        $null = $process.Start()
        $startedAt = $process.StartTime
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($InputText) { $process.StandardInput.WriteLine($InputText) }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            return [pscustomobject]@{ ExitCode = -1; TimedOut = $true; Output = ''; Error = ''; ProcessId = $process.Id }
        }
        if (-not $stdout.Wait(2000) -or -not $stderr.Wait(2000)) {
            throw 'A launcher tool exited without closing its output. Check the tool installation before retrying.'
        }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; TimedOut = $false;
            Output = $stdout.GetAwaiter().GetResult(); Error = $stderr.GetAwaiter().GetResult(); ProcessId = $process.Id }
    }
    finally {
        if ($startedAt -and -not $process.HasExited) {
            Stop-RentHubOwnedApiProcess -OwnedProcess $process -StartedAt $startedAt
        }
        $process.Dispose()
    }
}

function Wait-RentHubReadiness {
    param([string]$Name, [scriptblock]$Probe, [int]$TimeoutSeconds,
        [System.Diagnostics.Process]$OwnedProcess, [string]$ErrorLogPath)
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $nextProgress = 0
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if ($null -ne $OwnedProcess -and $OwnedProcess.HasExited) {
            throw "$Name stopped before it became ready (exit code $($OwnedProcess.ExitCode)). Check the launcher error log: $ErrorLogPath"
        }
        $result = & $Probe
        if ($result) { return $result }
        if ($timer.Elapsed.TotalSeconds -ge $nextProgress) {
            Write-Host "Waiting for $Name ($([int]$timer.Elapsed.TotalSeconds)/$TimeoutSeconds seconds)..." -ForegroundColor DarkGray
            $nextProgress = $timer.Elapsed.TotalSeconds + 15
        }
        Start-Sleep -Milliseconds 750
    }
    return $null
}

function Sync-RentHubAndroidConnection {
    param([string]$AdbPath, [string]$TargetDevice, [int]$HostPort, [int]$ClientPort = 3000)
    if (-not $AdbPath) { return 'adb-missing' }
    $state = Invoke-RentHubNativeCommand -FilePath $AdbPath -Arguments @('-s', $TargetDevice, 'get-state') -TimeoutSeconds 5
    if ($state.TimedOut) { return 'waiting' }
    if ($state.ExitCode -ne 0 -or $state.Output.Trim() -ne 'device') {
        if (($state.Output + $state.Error) -match 'unauthorized') { return 'unauthorized' }
        return 'waiting'
    }
    $result = Invoke-RentHubNativeCommand -FilePath $AdbPath -Arguments @('-s', $TargetDevice, 'reverse', "tcp:$ClientPort", "tcp:$HostPort") -TimeoutSeconds 5
    if ($result.ExitCode -ne 0 -or $result.TimedOut) { return 'forwarding-failed' }
    # Support older installed builds compiled with an alternate API port too.
    if ($HostPort -ne $ClientPort) {
        $null = Invoke-RentHubNativeCommand -FilePath $AdbPath -Arguments @('-s', $TargetDevice, 'reverse', "tcp:$HostPort", "tcp:$HostPort") -TimeoutSeconds 5
    }
    return 'connected'
}

function Test-RentHubKeepServicesRunning {
    param([string]$TargetDevice, [bool]$StartedApi, [bool]$StartedAi, [bool]$StartedBlockchain)
    return $TargetDevice -notin @('windows', 'chrome', 'edge') -and
        ($StartedApi -or $StartedAi -or $StartedBlockchain)
}

function Get-RentHubAdbPath {
    param(
        [string[]]$CandidatePaths = @(),
        [switch]$SkipPathLookup
    )

    if (-not $SkipPathLookup) {
        $pathCommand = Get-Command adb -ErrorAction SilentlyContinue
        if ($null -ne $pathCommand) { return $pathCommand.Source }
    }

    if (-not $CandidatePaths.Count) {
        if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_SDK_ROOT)) {
            $CandidatePaths += Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe'
        }
        if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
            $CandidatePaths += Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
        }
        if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            $CandidatePaths += Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
        }
    }

    foreach ($candidate in $CandidatePaths | Select-Object -Unique) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Wait-RentHubServiceSession {
    param([string]$AdbPath, [string]$TargetDevice, [int]$HostPort,
        [switch]$MonitorAi, [string]$BlockchainRpcUrl)
    Write-Host 'RentHub services remain running. You can open the app.' -ForegroundColor Green
    Write-Host 'Keep this terminal open. Press Ctrl+C here when you want to stop services started by this launcher.' -ForegroundColor Cyan
    $lastPhoneState = ''
    $lastHealthState = ''
    $nextHealthCheck = [datetime]::MinValue
    while ($true) {
        if ($TargetDevice -and $TargetDevice -notin @('windows', 'chrome', 'edge')) {
            try { $phoneState = Sync-RentHubAndroidConnection -AdbPath $AdbPath -TargetDevice $TargetDevice -HostPort $HostPort }
            catch { $phoneState = 'waiting' }
            if ($phoneState -ne $lastPhoneState) {
                if ($phoneState -eq 'connected') { Write-Host 'Android connection ready; API forwarding restored.' -ForegroundColor Green }
                elseif ($phoneState -eq 'unauthorized') { Write-Warning 'Unlock the phone and allow USB debugging. Services remain running.' }
                elseif ($phoneState -eq 'adb-missing') { Write-Warning 'ADB is missing. Install Android platform-tools or use a LAN-configured app.' }
                else { Write-Warning 'Waiting for Android to reconnect. Keep the same device selected; services remain running.' }
                $lastPhoneState = $phoneState
            }
        }
        if ([datetime]::UtcNow -ge $nextHealthCheck) {
            $unavailable = @()
            if (-not (Test-RentHubApiReady -Port $HostPort)) { $unavailable += 'API/database' }
            if ($MonitorAi -and -not (Test-RentHubAiCompatible -Health (Get-RentHubAiHealth))) { $unavailable += 'AI' }
            if ($BlockchainRpcUrl -and (Get-RentHubBlockchainHealth -RpcUrl $BlockchainRpcUrl) -ne '0x539') { $unavailable += 'rental records' }
            $healthState = $unavailable -join ', '
            if ($healthState -ne $lastHealthState) {
                if ($healthState) { Write-Warning "Needs attention: $healthState. Check the launcher logs; services will not be restarted during a transaction." }
                else { Write-Host 'RentHub service checks recovered.' -ForegroundColor Green }
                $lastHealthState = $healthState
            }
            $nextHealthCheck = [datetime]::UtcNow.AddSeconds(30)
        }
        Start-Sleep -Seconds 5
    }
}

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

function Get-RentHubMongoTarget {
    param([string]$ConnectionString)

    # Do not print the URI: Atlas database credentials belong only in the API.
    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        throw 'MONGODB_URI must be a MongoDB connection string in services/api/.env.'
    }
    $value = $ConnectionString.Trim()
    if ($value -notmatch '^mongodb(?<srv>\+srv)?://(?<authority>[^/?#]+)') {
        throw 'MONGODB_URI must be a MongoDB connection string in services/api/.env.'
    }
    $srv = $Matches['srv']
    $authority = $Matches['authority']
    $authority = $authority.Substring($authority.LastIndexOf('@') + 1)
    if (-not $authority) { throw 'MONGODB_URI must include a database host.' }
    # SRV discovery and multi-host selection are checked by the MongoDB driver.
    if ($srv -or $authority.Contains(',')) { return @{ IsLocal = $false } }
    if ($authority -notmatch '^(?:\[(?<host>[^\]]+)\]|(?<host>[^:]+))(?::(?<port>\d+))?$') {
        throw 'MONGODB_URI contains an invalid database host or port.'
    }
    $mongoHost = $Matches['host'].ToLowerInvariant()
    $mongoPort = 27017
    if ($Matches['port'] -and (-not [int]::TryParse($Matches['port'], [ref]$mongoPort) -or
            $mongoPort -lt 1 -or $mongoPort -gt 65535)) {
        throw 'MONGODB_URI contains an invalid database port.'
    }
    return @{ IsLocal = $mongoHost -in @('localhost', '127.0.0.1', '::1'); HostName = $mongoHost; Port = $mongoPort }
}

function Test-RentHubApiReady {
    param([ValidateRange(1, 65535)][int]$Port = 3000)
    try {
        $response = Invoke-RestMethod `
            -Uri "http://localhost:$Port/api/v1/ready" `
            -TimeoutSec 2
        return $response.success -eq $true -and `
            $response.data.capabilities -contains 'product-catalog-v1' -and `
            $response.data.capabilities -contains 'mykad-capture-validation-v1' -and `
            $response.data.capabilities -contains 'mykad-readability-pair-v1' -and `
            $response.data.capabilities -contains 'mykad-screen-account-binding-v1' -and `
            $response.data.capabilities -contains 'mykad-current-draft-pair-v1' -and `
            $response.data.capabilities -contains 'mykad-bidirectional-capture-pair-v1' -and `
            $response.data.capabilities -contains 'driving-licence-ocr-review-v1' -and `
            $response.data.capabilities -contains 'recommendation-feed-v2' -and `
            $response.data.capabilities -contains 'listing-delivery-fees-v1' -and `
            $response.data.capabilities -contains 'notification-targets-v1' -and `
            $response.data.capabilities -contains 'pricing-daily-baseline-v1' -and `
            $response.data.capabilities -contains 'pricing-suitability-v1' -and `
            $response.data.capabilities -contains 'evidence-led-product-selection-v1' -and `
            $response.data.capabilities -contains 'mandatory-identity-access-v1' -and `
            $response.data.capabilities -contains 'listing-maps-push-status-v1' -and `
            $response.data.capabilities -contains 'precise-locations-v1' -and `
            $response.data.capabilities -contains 'admin-record-details-v1' -and `
            $response.data.capabilities -contains 'trust-profile-v1' -and `
            $response.data.capabilities -contains 'user-records-messaging-v2'
    }
    catch {
        return $false
    }
}

function Test-RentHubApiPortAvailable {
    param([ValidateRange(1, 65535)][int]$Port)

    # A dual-stack bind also detects IPv6 listeners and Windows excluded ports.
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::IPv6Any, $Port)
    try {
        $listener.Server.DualMode = $true
        $listener.ExclusiveAddressUse = $true
        $listener.Start()
        return $true
    }
    catch [System.Net.Sockets.SocketException] { return $false }
    finally { $listener.Stop() }
}

function Resolve-RentHubApiPort {
    param([ValidateRange(1, 65535)][int]$PreferredPort = 3000)

    # Keep the admin/browser, AI and blockchain ports available for their services.
    $reservedPorts = @(3001, 8080, 8001, 8545)
    if ($PreferredPort -notin $reservedPorts) {
        if (Test-RentHubApiReady -Port $PreferredPort) { return $PreferredPort }
        if (Test-RentHubApiPortAvailable -Port $PreferredPort) { return $PreferredPort }
    }
    foreach ($candidate in 3002..3020) {
        if ($candidate -eq $PreferredPort) { continue }
        if (Test-RentHubApiPortAvailable -Port $candidate) { return $candidate }
    }
    throw 'No API port is available in 3002-3020. Choose a free port with -ApiPort <port>.'
}

function Get-RentHubApiClientArguments {
    param([ValidateRange(1, 65535)][int]$Port)
    return @("--dart-define=API_BASE_URL=http://localhost:$Port/api/v1",
        "--dart-define=SOCKET_URL=http://localhost:$Port")
}

function Get-RentHubAiHealth {
    try {
        return Invoke-RestMethod `
            -Uri 'http://127.0.0.1:8001/health' `
            -TimeoutSec 10
    }
    catch {
        return $null
    }
}

function Test-RentHubAiCompatible {
    param([object]$Health)

    return $null -ne $Health -and $Health.status -eq 'ok' -and `
        $Health.document_frame_contract -eq 'opencv-document-yolo-v6' -and `
        $Health.driving_licence_contract -eq 'malaysian-driving-ocr-v1' -and `
        $Health.recommendation_contract -eq 'hybrid-profile-v2' -and `
        $Health.item_verification_contract -eq 'renthub-item-evidence-v4'
}

function Get-RentHubAiArguments {
    param([switch]$DisableReload)

    $aiArguments = @('-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8001')
    if (-not $DisableReload) {
        # Watch code only, not private identity datasets or training/model outputs.
        $aiArguments += @('--reload', '--reload-dir', 'app')
    }
    return $aiArguments
}

function Get-RentHubApiArguments {
    param([switch]$DisableReload)
    if ($DisableReload) { return @('src/server.js') }
    # Restrict watching to source code, excluding private uploads/data and logs.
    return @('--watch', '--watch-path=src', 'src/server.js')
}

function Stop-RentHubOwnedApiProcess {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$OwnedProcess,
        [Parameter(Mandatory = $true)][datetime]$StartedAt
    )
    try {
        if ($OwnedProcess.HasExited) { return }
        $current = Get-Process -Id $OwnedProcess.Id -ErrorAction SilentlyContinue
        if ($null -eq $current) { return }
        if ($current.StartTime -ne $StartedAt) {
            Write-Warning 'API process ID was reused; leaving that unrelated process untouched.'
            return
        }
        # Node watch has a child server. Stop only this launcher's owned tree.
        $ErrorActionPreference = 'Continue'
        & taskkill.exe /PID $OwnedProcess.Id /T /F 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0 -and -not $OwnedProcess.HasExited) {
            Write-Warning 'Could not stop the API process tree owned by this launcher.'
        }
    }
    catch {
        Write-Warning 'API cleanup could not complete. Check the selected API port before starting another server.'
    }
}

function Stop-RentHubOwnedAiProcess {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$OwnedProcess,
        [Parameter(Mandatory = $true)][datetime]$StartedAt
    )

    try {
        if ($OwnedProcess.HasExited) { return }
        $current = Get-Process -Id $OwnedProcess.Id -ErrorAction SilentlyContinue
        if ($null -eq $current) { return }
        if ($current.StartTime -ne $StartedAt) {
            Write-Warning 'AI process ID was reused; leaving that unrelated process untouched.'
            return
        }
        # Uvicorn reload and the Windows venv launcher have child processes.
        # Only this invocation's verified root tree may be stopped, never all Python.
        $ErrorActionPreference = 'Continue'
        & taskkill.exe /PID $OwnedProcess.Id /T /F 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0 -and -not $OwnedProcess.HasExited) {
            Write-Warning "Could not stop the AI tree owned by this launcher (root $($OwnedProcess.Id))."
        }
    }
    catch {
        Write-Warning 'AI cleanup could not complete. Check port 8001 before starting another server.'
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
        if ($null -eq $response.error -and $response.result -is [string] -and
            $response.result -match '^0x[0-9a-f]{1,64}$') {
            # Callers compare the chain ID, not the JSON-RPC response envelope.
            # Normalize case/leading zeros without narrowing a chain ID to Int32.
            $chainHex = $response.result.Substring(2).TrimStart('0').ToLowerInvariant()
            if (-not $chainHex) { $chainHex = '0' }
            return "0x$chainHex"
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

function Get-RentHubAtlasHost {
    param([string]$ConnectionString)
    # Return only the Atlas SRV hostname; never retain credentials in CLI arguments.
    if ($ConnectionString -match '^mongodb\+srv://(?:[^@/]+@)?(?<clusterHost>[a-zA-Z0-9.-]+\.mongodb\.net)(?:[/?]|$)') {
        return $Matches.clusterHost.ToLowerInvariant()
    }
    return $null
}

function Get-RentHubAtlasFailureMessage {
    param([string]$Output, [string]$Profile = 'default')
    # Classify privately captured diagnostics; never repeat account/token/URL text.
    $profileHint = if ($Profile -match '^[a-zA-Z0-9_.-]{1,64}$') { $Profile } else { 'YOUR_PROFILE' }
    if ($Output -match '(?i)unknown (flag|command)|flag provided but not defined|unrecognized (option|argument)') {
        return 'Atlas CLI does not support this command or option. Check atlas --version and update the CLI.'
    }
    if ($Output -match '(?i)not logged|aren.t logged|not authenticated|invalid_grant|(?:token|session|authentication)[^\r\n]*(expired|invalid)|unauthorized|\b401\b') {
        return "Atlas CLI is not signed in, or its session needs renewal. Run 'atlas auth login --profile $profileHint' using the same Windows account, then retry."
    }
    if ($Output -match '(?i)forbidden|\b403\b|not authorized|insufficient[^\r\n]*(permission|role)|permission denied') {
        return 'Atlas CLI access was denied. Check that this account/profile can view the project and manage its Network Access list; signing in again may not resolve missing permissions.'
    }
    if ($Output -match '(?i)profile[^\r\n]*(not found|not exist|missing)|no[^\r\n]*profile') {
        return "The requested Atlas CLI profile is not configured. Run 'atlas auth login --profile $profileHint', or choose your existing profile with -AtlasProfile."
    }
    if ($Output -match '(?i)\b429\b|too many requests|rate.?limit') {
        return 'Atlas is limiting requests. Wait briefly and rerun the launcher.'
    }
    if ($Output -match '(?i)timed? out|timeout|deadline exceeded|no such host|dial tcp|TLS|certificate|connection (refused|reset)|network is unreachable|could not resolve') {
        return 'Atlas CLI could not reach Atlas. Check internet, DNS, VPN/firewall and HTTPS access, then retry. Signing in again is not the first step.'
    }
    if ($Output -match '(?i)keyring|credential[^\r\n]*(vault|store|storage)|secure storage[^\r\n]*(failed|denied|unavailable)') {
        return 'Atlas CLI could not access its saved credentials. Use the same Windows account/profile as the original login and check Windows Credential Manager.'
    }
    return 'Atlas CLI could not complete the network-access check. Verify atlas auth whoami --profile YOUR_PROFILE, project permissions and connectivity. The failure does not necessarily mean your login expired.'
}

function Invoke-RentHubAtlasJson {
    param([string]$AtlasPath, [string[]]$Arguments, [string]$Profile = 'default')
    # Capture native errors too: CLI diagnostics can contain private account details.
    $result = Invoke-RentHubNativeCommand -FilePath $AtlasPath -Arguments ($Arguments + @('--profile', $Profile, '--output', 'json')) -TimeoutSeconds 30
    if ($result.TimedOut) { throw 'Atlas CLI timed out. Check internet/VPN connectivity and retry; no interactive login was started.' }
    if ($result.ExitCode -ne 0) {
        throw (Get-RentHubAtlasFailureMessage -Output ($result.Output + $result.Error) -Profile $Profile)
    }
    try { return $result.Output | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Atlas CLI returned an unexpected response. Check the CLI version and login.' }
}

function Resolve-RentHubAtlasProject {
    param([string]$AtlasPath, [string]$ClusterHost, [string]$ProjectId, [string]$Profile = 'default')
    if ($ProjectId -and $ProjectId -notmatch '^[a-fA-F0-9]{24}$') {
        throw 'ATLAS_PROJECT_ID must be the 24-character Atlas project ID.'
    }
    if ($ProjectId) { $projects = @([pscustomobject]@{ id = $ProjectId }) }
    else {
        $response = Invoke-RentHubAtlasJson -AtlasPath $AtlasPath -Profile $Profile -Arguments @('projects', 'list', '--limit', '500')
        $projects = @($response.results)
    }
    $matchedProjects = @()
    foreach ($project in $projects) {
        $response = Invoke-RentHubAtlasJson -AtlasPath $AtlasPath -Profile $Profile -Arguments @('clusters', 'list', '--projectId', $project.id, '--limit', '500')
        foreach ($cluster in $response.results) {
            $srvHost = Get-RentHubAtlasHost -ConnectionString ([string]$cluster.connectionStrings.standardSrv)
            if ($srvHost -eq $ClusterHost) { $matchedProjects += [string]$project.id }
        }
    }
    $matchedProjects = @($matchedProjects | Select-Object -Unique)
    if ($matchedProjects.Count -ne 1) {
        throw 'Could not uniquely match MONGODB_URI to an Atlas project. Check the CLI account or set ATLAS_PROJECT_ID in services/api/.env.'
    }
    return $matchedProjects[0]
}

function Get-RentHubPublicIPv4 {
    # No credentials are sent to either public address lookup service.
    foreach ($lookupUri in @('https://checkip.amazonaws.com', 'https://api.ipify.org?format=json')) {
        try {
            $ipResponse = Invoke-RestMethod -Uri $lookupUri -TimeoutSec 8 -ErrorAction Stop
            $addressText = if ($lookupUri -like '*ipify.org*') { [string]$ipResponse.ip } else { ([string]$ipResponse).Trim() }
            $publicAddress = $null
            if ([System.Net.IPAddress]::TryParse($addressText, [ref]$publicAddress) -and
                    $publicAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                return $publicAddress.ToString()
            }
        }
        catch { continue }
    }
    throw 'Could not detect the public IPv4 address. Check internet/VPN access and rerun the launcher.'
}

function Sync-RentHubAtlasAccess {
    param([string]$AtlasPath, [string]$ClusterHost, [string]$ProjectId, [string]$Profile = 'default')
    $resolvedProjectId = Resolve-RentHubAtlasProject -AtlasPath $AtlasPath -ClusterHost $ClusterHost -ProjectId $ProjectId -Profile $Profile
    $currentIp = Get-RentHubPublicIPv4
    $entries = Invoke-RentHubAtlasJson -AtlasPath $AtlasPath -Profile $Profile -Arguments @('accessLists', 'list', '--projectId', $resolvedProjectId, '--limit', '500')
    $existing = @($entries.results | Where-Object { $_.ipAddress -eq $currentIp -or $_.cidrBlock -eq "$currentIp/32" })
    if ($existing.Count) {
        Write-Host 'Atlas already allows this public IP. Existing entries were preserved.' -ForegroundColor Green
        return
    }
    $expiresAt = [datetime]::UtcNow.AddDays(1).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    try {
        $null = Invoke-RentHubAtlasJson -AtlasPath $AtlasPath -Profile $Profile -Arguments @(
            'accessLists', 'create', $currentIp, '--type', 'ipAddress', '--projectId', $resolvedProjectId,
            '--deleteAfter', $expiresAt, '--comment', 'RentHub launcher temporary access'
        )
    }
    catch {
        # Two laptops sharing a public IP may register it at the same time.
        $entries = Invoke-RentHubAtlasJson -AtlasPath $AtlasPath -Profile $Profile -Arguments @('accessLists', 'list', '--projectId', $resolvedProjectId, '--limit', '500')
        if (-not @($entries.results | Where-Object { $_.ipAddress -eq $currentIp -or $_.cidrBlock -eq "$currentIp/32" }).Count) { throw }
    }
    Write-Host 'Atlas access registered for this public IP (expires in 24 hours).' -ForegroundColor Green
}

function Test-RentHubAtlasDatabase {
    param([string]$NodePath, [string]$ApiDirectory)
    # No models, schedulers, index creation or application writes: connect/ping only.
    $probe = 'import { connectDatabase, disconnectDatabase } from "./src/config/database.js"; try { const connection = await connectDatabase(); await connection.db.command({ping:1}); } catch { process.exitCode = 1; } finally { await disconnectDatabase(); }'
    $result = Invoke-RentHubNativeCommand -FilePath $NodePath -Arguments @('--input-type=module') -WorkingDirectory $ApiDirectory -InputText $probe -TimeoutSeconds 20
    return -not $result.TimedOut -and $result.ExitCode -eq 0
}

function Wait-RentHubAtlasDatabase {
    param([string]$NodePath, [string]$ApiDirectory)
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        Write-Host "Checking Atlas database access ($attempt/6)..." -ForegroundColor Cyan
        if (Test-RentHubAtlasDatabase -NodePath $NodePath -ApiDirectory $ApiDirectory) {
            Write-Host 'Atlas database connection verified.' -ForegroundColor Green
            return
        }
        if ($attempt -lt 6) { Start-Sleep -Seconds 3 }
    }
    throw 'Atlas access was registered, but the database connection still fails. Check cluster availability, database credentials and VPN/firewall/TLS settings. No RentHub services were started.'
}

function Initialize-RentHubAtlasAccess {
    param([string]$NodePath, [string]$ApiDirectory, [string]$ClusterHost,
        [string]$ProjectId, [string]$Profile = 'default')
    Write-Host 'Checking the existing Atlas database connection...' -ForegroundColor Cyan
    if (Test-RentHubAtlasDatabase -NodePath $NodePath -ApiDirectory $ApiDirectory) {
        Write-Host 'Atlas database is reachable. No Atlas CLI login or network-access update is needed.' -ForegroundColor Green
        return
    }
    $atlasCommand = Get-Command atlas -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $atlasCommand) {
        throw 'Atlas database is not reachable. Install MongoDB Atlas CLI and sign in to register this network, or configure Network Access manually. Use -SkipAtlasAccess only when access is already configured.'
    }
    Write-Host 'Preparing temporary Atlas access for this network...' -ForegroundColor Cyan
    Sync-RentHubAtlasAccess -AtlasPath $atlasCommand.Source -ClusterHost $ClusterHost -ProjectId $ProjectId -Profile $Profile
    Wait-RentHubAtlasDatabase -NodePath $NodePath -ApiDirectory $ApiDirectory
}

# Pure helper: client settings only, never server credentials or private keys.
function Get-RentHubFirebaseDefines {
    param([string]$FcmMode, [string]$TargetDevice, [hashtable]$Settings, [object]$GoogleConfiguration)
    if ($FcmMode -ne 'firebase' -or $TargetDevice -in @('windows', 'chrome', 'edge')) {
        return @('--dart-define=FIREBASE_ENABLED=false')
    }
    $apiKey = $Settings['FIREBASE_ANDROID_API_KEY']
    $appId = $Settings['FIREBASE_ANDROID_APP_ID']
    $sender = $Settings['FIREBASE_MESSAGING_SENDER_ID']
    $project = $Settings['FIREBASE_PROJECT_ID']
    if ($apiKey -match '^(YOUR_|your-|REPLACE|<)') { $apiKey = '' }
    if ($appId -match '^(YOUR_|your-|REPLACE|<)') { $appId = '' }
    if ($sender -match '^(YOUR_|your-|REPLACE|<)') { $sender = '' }
    if ($null -ne $GoogleConfiguration) {
        $androidClient = @($GoogleConfiguration.client | Where-Object {
            $_.client_info.android_client_info.package_name -eq 'com.weith.renthub'
        }) | Select-Object -First 1
        if ($null -eq $androidClient) { throw 'google-services.json must include Android package com.weith.renthub.' }
        if ([string]::IsNullOrWhiteSpace($apiKey)) { $apiKey = $androidClient.api_key[0].current_key }
        if ([string]::IsNullOrWhiteSpace($appId)) { $appId = $androidClient.client_info.mobilesdk_app_id }
        if ([string]::IsNullOrWhiteSpace($sender)) { $sender = $GoogleConfiguration.project_info.project_number }
        if ([string]::IsNullOrWhiteSpace($project) -or $project -eq 'your-project-id') { $project = $GoogleConfiguration.project_info.project_id }
        if ($project -ne $GoogleConfiguration.project_info.project_id -or $sender -ne $GoogleConfiguration.project_info.project_number) {
            throw 'Firebase Android settings and FIREBASE_PROJECT_ID must refer to the same Firebase project.'
        }
    }
    if ([string]::IsNullOrWhiteSpace($apiKey) -or [string]::IsNullOrWhiteSpace($appId) -or
        [string]::IsNullOrWhiteSpace($sender) -or [string]::IsNullOrWhiteSpace($project) -or $project -eq 'your-project-id') {
        throw 'For Android push, configure Firebase Android client settings or add android/app/google-services.json. Keep FCM_MODE=disabled until setup is ready.'
    }
    return @('--dart-define=FIREBASE_ENABLED=true', "--dart-define=FIREBASE_API_KEY=$apiKey",
        "--dart-define=FIREBASE_APP_ID=$appId", "--dart-define=FIREBASE_MESSAGING_SENDER_ID=$sender",
        "--dart-define=FIREBASE_PROJECT_ID=$project")
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
$apiProcessStartedAt = $null
$aiProcess = $null
$aiProcessStartedAt = $null
$blockchainProcess = $null
$blockchainProcessStartedAt = $null
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
$nodeVersion = Invoke-RentHubNativeCommand -FilePath $nodePath -Arguments @('--version') -TimeoutSeconds 5
if ($nodeVersion.TimedOut -or $nodeVersion.ExitCode -ne 0 -or -not (Test-RentHubNodeVersion -Version $nodeVersion.Output)) {
    throw 'RentHub requires Node.js 22 or newer for its current storage SDK. Install a supported Node version, reopen PowerShell and verify node --version.'
}
if (-not $ServicesOnly -and -not $CheckOnly -and -not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not available on PATH.'
}
if ($Device -eq 'windows' -and -not $ServicesOnly -and -not $CheckOnly) {
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
$auth0AndroidClientId = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'AUTH0_ANDROID_CLIENT_ID'
$auth0WebClientId = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'AUTH0_WEB_CLIENT_ID'
$auth0WindowsCallbackUrl = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'AUTH0_WINDOWS_CALLBACK_URL' `
    -DefaultValue 'http://127.0.0.1:53124/callback'
$auth0AndroidCallbackUrl = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'AUTH0_ANDROID_CALLBACK_URL' `
    -DefaultValue 'com.weith.renthub://login-callback'
$auth0DatabaseConnection = Get-RentHubEnvironmentValue `
    -Path $apiEnvironment `
    -Name 'AUTH0_DATABASE_CONNECTION' `
    -DefaultValue 'Username-Password-Authentication'
if (-not $SkipBlockchain -and $blockchainMode -eq 'ganache' -and -not (Test-Path -LiteralPath $ganacheCli)) {
    throw "Blockchain dependencies are missing. Run 'npm.cmd install' in $blockchainDirectory first."
}
$mongoConnection = if (-not [string]::IsNullOrWhiteSpace($env:MONGODB_URI)) { $env:MONGODB_URI }
    else { Get-RentHubEnvironmentValue -Path $apiEnvironment -Name 'MONGODB_URI' -DefaultValue 'mongodb://localhost:27017/renthub' }
$mongoTarget = Get-RentHubMongoTarget -ConnectionString $mongoConnection
if ($mongoTarget.IsLocal) {
    if (-not (Test-RentHubTcpPort -HostName $mongoTarget.HostName -Port $mongoTarget.Port)) {
        throw "MongoDB is not listening on $($mongoTarget.HostName):$($mongoTarget.Port). Start the configured local MongoDB service before running RentHub."
    }
}
else {
    Write-Host 'Using configured cloud/remote MongoDB. API readiness will verify database connectivity.' -ForegroundColor Cyan
}

$atlasHost = Get-RentHubAtlasHost -ConnectionString $mongoConnection
if ($atlasHost -and -not $SkipAtlasAccess) {
    if ([string]::IsNullOrWhiteSpace($AtlasProjectId)) {
        $AtlasProjectId = Get-RentHubEnvironmentValue -Path $apiEnvironment -Name 'ATLAS_PROJECT_ID'
    }
    Initialize-RentHubAtlasAccess -NodePath $nodePath -ApiDirectory $apiDirectory -ClusterHost $atlasHost -ProjectId $AtlasProjectId -Profile $AtlasProfile
}

if (-not $PSBoundParameters.ContainsKey('ApiPort')) {
    $configuredApiPort = if (-not [string]::IsNullOrWhiteSpace($env:PORT)) { $env:PORT }
        else { Get-RentHubEnvironmentValue -Path $apiEnvironment -Name 'PORT' -DefaultValue '3000' }
    if (-not [int]::TryParse($configuredApiPort, [ref]$ApiPort) -or $ApiPort -lt 1 -or $ApiPort -gt 65535) {
        throw 'API PORT must be an integer from 1 to 65535 in the environment or services/api/.env.'
    }
}
$selectedApiPort = Resolve-RentHubApiPort -PreferredPort $ApiPort
if ($selectedApiPort -ne $ApiPort) {
    Write-Warning "API port $ApiPort is occupied, incompatible or reserved. Using port $selectedApiPort for this session."
}
$ApiPort = $selectedApiPort
if ($ApiPort -ne 3000) {
    $standardLog = Join-Path $logDirectory "launcher-api-$ApiPort.log"
    $errorLog = Join-Path $logDirectory "launcher-api-$ApiPort-error.log"
}

try {
    if (-not $SkipBlockchain -and $blockchainMode -eq 'ganache') {
        $blockchainHealth = Get-RentHubBlockchainHealth -RpcUrl $ganacheRpcUrl
        if ($null -ne $blockchainHealth) {
            if ($blockchainHealth -ne '0x539') { throw 'The configured blockchain has the wrong chain ID. RentHub requires chain ID 1337; no existing process was stopped.' }
            Write-Host 'RentHub blockchain is already ready (chain ID 1337).' -ForegroundColor Green
        }
        else {
            $rpcTarget = $null
            if (-not [uri]::TryCreate($ganacheRpcUrl, [System.UriKind]::Absolute, [ref]$rpcTarget) -or
                $rpcTarget.Scheme -ne 'http' -or $rpcTarget.Host -notin @('localhost', '127.0.0.1') -or
                $rpcTarget.Port -ne 8545 -or $rpcTarget.AbsolutePath -ne '/') {
                throw 'The configured blockchain is unavailable. This launcher can start only local Ganache on port 8545; start your custom RPC separately.'
            }
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
                -ArgumentList (ConvertTo-RentHubProcessArguments -Arguments @(
                    $ganacheCli,
                    '--server.port', '8545',
                    '--wallet.deterministic',
                    '--chain.chainId', '1337',
                    '--database.dbPath', $blockchainDataDirectory
                )) `
                -WorkingDirectory $blockchainDirectory `
                -WindowStyle Hidden `
                -RedirectStandardOutput $blockchainStandardLog `
                -RedirectStandardError $blockchainErrorLog `
                -PassThru
            $startedBlockchain = $true
            $blockchainProcessStartedAt = $blockchainProcess.StartTime

            $blockchainReady = Wait-RentHubReadiness -Name 'local blockchain' -TimeoutSeconds 45 -OwnedProcess $blockchainProcess -ErrorLogPath $blockchainErrorLog -Probe {
                $blockchainHealth = Get-RentHubBlockchainHealth -RpcUrl $ganacheRpcUrl
                if ($null -ne $blockchainHealth -and $blockchainHealth -ne '0x539') { throw 'The local blockchain reported the wrong chain ID; expected 1337.' }
                return $blockchainHealth -eq '0x539'
            }

            if (-not $blockchainReady) {
                throw "The local blockchain did not become ready within 45 seconds. Review $blockchainErrorLog."
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
        if (-not (Test-RentHubAiCompatible -Health $aiHealth) -and
            (Test-RentHubTcpPort -HostName '127.0.0.1' -Port 8001) -and ($null -eq $aiHealth -or $aiHealth.status -ne 'ok')) {
            Write-Host 'An AI listener is starting; waiting for its health check before deciding whether it can be reused.' -ForegroundColor Cyan
            $aiHealth = Wait-RentHubReadiness -Name 'existing AI listener' -TimeoutSeconds $AiStartupTimeoutSeconds -Probe {
                $health = Get-RentHubAiHealth
                if ($null -ne $health -and $health.status -eq 'ok') { return $health }
                return $null
            }
        }
        if (Test-RentHubAiCompatible -Health $aiHealth) {
            Write-Host 'RentHub AI service is already ready with current scanner, licence, recommendation and item-photo contracts on port 8001.' -ForegroundColor Green
            Write-Host 'Reusing the existing AI process. Its original owner controls reload and shutdown.' -ForegroundColor DarkGray
        }
        else {
            if (Test-RentHubTcpPort -HostName '127.0.0.1' -Port 8001) {
                if ($null -ne $aiHealth -and $aiHealth.status -eq 'ok') {
                    throw 'The AI service on port 8001 has incompatible service contracts. Stop its original terminal/launcher with Ctrl+C, then rerun this launcher. No existing service was stopped.'
                }
                throw 'Port 8001 is occupied by an unhealthy or different service. Stop the identified owning process before rerunning this launcher. Do not start a second AI server on that port.'
            }
            New-Item -ItemType Directory -Path $aiLogDirectory -Force | Out-Null
            $aiArguments = Get-RentHubAiArguments -DisableReload:$NoAiReload
            if ($NoAiReload) {
                Write-Host 'Starting the RentHub AI service without development reload...' -ForegroundColor Cyan
            }
            else {
                Write-Host 'Starting the RentHub AI service with automatic app-code reload...' -ForegroundColor Cyan
            }
            $aiProcess = Start-Process `
                -FilePath $aiPython `
                -ArgumentList $aiArguments `
                -WorkingDirectory $aiDirectory `
                -WindowStyle Hidden `
                -RedirectStandardOutput $aiStandardLog `
                -RedirectStandardError $aiErrorLog `
                -PassThru
            $startedAi = $true
            $aiProcessStartedAt = $aiProcess.StartTime

            $aiHealth = Wait-RentHubReadiness -Name 'AI service' -TimeoutSeconds $AiStartupTimeoutSeconds -OwnedProcess $aiProcess -ErrorLogPath $aiErrorLog -Probe {
                $health = Get-RentHubAiHealth
                if ($null -ne $health -and $health.status -eq 'ok' -and -not (Test-RentHubAiCompatible -Health $health)) {
                    throw 'The AI service started with incompatible contracts. Check that this checkout and its AI code match.'
                }
                if (Test-RentHubAiCompatible -Health $health) { return $health }
                return $null
            }

            if ($null -eq $aiHealth) {
                throw "The AI service did not become ready within $AiStartupTimeoutSeconds seconds. Review $aiErrorLog. For slower model loading, increase -AiStartupTimeoutSeconds (maximum 600)."
            }
            Write-Host 'RentHub AI service is ready with current scanner, licence, recommendation and item-photo contracts.' -ForegroundColor Green
        }

        if ($aiHealth.item_verification_status.world.available) {
            Write-Host 'Optional YOLO-World item fallback is prepared locally (advisory; administrator review required).' -ForegroundColor DarkGray
        }
        else {
            Write-Warning 'Optional YOLO-World fallback is not prepared/enabled. Existing item checks and manual review remain available; the launcher will not download weights.'
        }

        if ($aiHealth.artifacts.price_model -eq $true) {
            Write-Host 'AI price-suggestion model is available.' -ForegroundColor Green
        }
        else {
            Write-Warning 'The AI service is running, but the price model artifact is missing.'
        }
    }

    if (Test-RentHubApiReady -Port $ApiPort) {
        Write-Host "RentHub API is already ready on port $ApiPort. If you changed .env, restart its original terminal/launcher to load those settings." -ForegroundColor Green
        if ($Presentation) { Write-Host 'Reused services keep their original reload settings; presentation mode controls newly started processes only.' -ForegroundColor DarkGray }
    }
    else {
        if (-not (Test-RentHubApiPortAvailable -Port $ApiPort)) {
            throw "API port $ApiPort became occupied during startup. Run this launcher again to select a free port."
        }
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        Write-Host "Starting the RentHub API on port $ApiPort..." -ForegroundColor Cyan
        $previousApiPort = $env:PORT
        try {
            # The child (including Node watch restarts) inherits this session's port.
            $env:PORT = [string]$ApiPort
            $apiProcess = Start-Process `
                -FilePath $nodePath `
                -ArgumentList (Get-RentHubApiArguments -DisableReload:$NoApiReload) `
                -WorkingDirectory $apiDirectory `
                -WindowStyle Hidden `
                -RedirectStandardOutput $standardLog `
                -RedirectStandardError $errorLog `
                -PassThru
        }
        finally { $env:PORT = $previousApiPort }
        $startedApi = $true
        $apiProcessStartedAt = $apiProcess.StartTime

        $ready = Wait-RentHubReadiness -Name 'API/database' -TimeoutSeconds $ApiStartupTimeoutSeconds -OwnedProcess $apiProcess -ErrorLogPath $errorLog -Probe {
            Test-RentHubApiReady -Port $ApiPort
        }

        if (-not $ready) {
            throw "The API did not become ready within $ApiStartupTimeoutSeconds seconds. Review $errorLog. Check database access and installed API dependencies."
        }
        Write-Host "RentHub API is ready at http://localhost:$ApiPort." -ForegroundColor Green
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
    $clientApiPort = $ApiPort
    $adbPath = $null
    $monitoredRpcUrl = if (-not $SkipBlockchain -and $blockchainMode -eq 'ganache') { $ganacheRpcUrl } else { '' }
    if (-not $isDesktop) {
        # Stable device port keeps an installed APK usable even if the PC needs a fallback port.
        $clientApiPort = 3000
        $adbPath = Get-RentHubAdbPath
        $phoneState = Sync-RentHubAndroidConnection -AdbPath $adbPath -TargetDevice $Device -HostPort $ApiPort
        if ($phoneState -eq 'connected') {
            Write-Host "Forwarded Android localhost:3000 to PC API port $ApiPort." -ForegroundColor Green
        }
        else {
            Write-Warning 'Android is not ready for forwarding. Check USB debugging authorization and the selected device ID. Services-only mode will wait for reconnection.'
            if (-not $ServicesOnly) { throw 'Reconnect/authorize the Android device and rerun, or use -ServicesOnly to keep services running while reconnecting.' }
        }
    }

    if ($ServicesOnly) {
        Wait-RentHubServiceSession -AdbPath $adbPath -TargetDevice $Device -HostPort $ApiPort -MonitorAi:(-not $SkipAi) -BlockchainRpcUrl $monitoredRpcUrl
        return
    }

    $arguments = @('run', '-d', $Device)
    $arguments += @(Get-RentHubApiClientArguments -Port $clientApiPort)
    $firebaseSettings = @{}
    foreach ($setting in @('FIREBASE_ANDROID_API_KEY', 'FIREBASE_ANDROID_APP_ID', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_PROJECT_ID')) {
        $firebaseSettings[$setting] = Get-RentHubEnvironmentValue -Path $apiEnvironment -Name $setting
    }
    $googleConfiguration = $null
    $googleConfigurationPath = Join-Path $PSScriptRoot 'android\app\google-services.json'
    $fcmMode = Get-RentHubEnvironmentValue -Path $apiEnvironment -Name 'FCM_MODE' -DefaultValue 'disabled'
    if (-not $isDesktop -and $fcmMode -ne 'firebase') {
        Write-Warning 'Android phone push is disabled. Configure Firebase Admin credentials and FCM_MODE=firebase in services/api/.env, then restart this launcher. In-app notifications still work.'
    }
    if (-not $isDesktop -and $fcmMode -eq 'firebase' -and (Test-Path -LiteralPath $googleConfigurationPath)) {
        $googleConfiguration = Get-Content -LiteralPath $googleConfigurationPath -Raw | ConvertFrom-Json
    }
    $arguments += @(Get-RentHubFirebaseDefines -FcmMode $fcmMode -TargetDevice $Device -Settings $firebaseSettings -GoogleConfiguration $googleConfiguration)
    if ($isBrowser) {
        $arguments += @('--web-port', $(if ($Admin) { '3001' } else { '8080' }))
    }
    if ($Admin) {
        $arguments += @('-t', 'lib/main_admin.dart')
    }
    if ($authMode -in @('auth0', 'hybrid')) {
        if ([string]::IsNullOrWhiteSpace($auth0Issuer)) {
            throw 'AUTH0_ISSUER_BASE_URL is required in the API .env when AUTH_MODE=auth0 or hybrid.'
        }
        if ([string]::IsNullOrWhiteSpace($auth0Audience)) {
            throw 'AUTH0_AUDIENCE is required in the API .env when AUTH_MODE=auth0 or hybrid.'
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
            $auth0ClientId = $auth0AndroidClientId
            $auth0CallbackUrl = $auth0AndroidCallbackUrl
            $clientSettingName = 'AUTH0_ANDROID_CLIENT_ID'
            try {
                $androidCallback = [System.Uri]::new($auth0CallbackUrl)
            }
            catch {
                throw 'AUTH0_ANDROID_CALLBACK_URL must be a valid custom URI, for example com.weith.renthub://login-callback.'
            }
            if ($androidCallback.Scheme -in @('http', 'https') -or `
                [string]::IsNullOrWhiteSpace($androidCallback.Scheme) -or `
                [string]::IsNullOrWhiteSpace($androidCallback.Host)) {
                throw 'AUTH0_ANDROID_CALLBACK_URL must use a custom scheme and host, for example com.weith.renthub://login-callback.'
            }
            $arguments += @(
                '--android-project-arg',
                "auth0CallbackScheme=$($androidCallback.Scheme)",
                '--android-project-arg',
                "auth0CallbackHost=$($androidCallback.Host)"
            )
        }

        if ([string]::IsNullOrWhiteSpace($auth0ClientId)) {
            throw "$clientSettingName is required in the API .env when AUTH_MODE=auth0 or hybrid and Device=$Device."
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
    Push-Location -LiteralPath $PSScriptRoot
    try {
        & flutter @arguments
        $flutterExitCode = $LASTEXITCODE
    }
    finally { Pop-Location }
    if (Test-RentHubKeepServicesRunning -TargetDevice $Device -StartedApi $startedApi -StartedAi $startedAi -StartedBlockchain $startedBlockchain) {
        Write-Warning 'The Android debug session has ended. This does not stop the local RentHub backend.'
        Wait-RentHubServiceSession -AdbPath $adbPath -TargetDevice $Device -HostPort $ApiPort -MonitorAi:(-not $SkipAi) -BlockchainRpcUrl $monitoredRpcUrl
    }
    if ($flutterExitCode -ne 0) {
        throw "Flutter exited with code $flutterExitCode."
    }
}
finally {
    if ($startedAi -and $null -ne $aiProcess -and $null -ne $aiProcessStartedAt) {
        Write-Host 'Stopping the AI process tree started by this launcher...' -ForegroundColor DarkGray
        Stop-RentHubOwnedAiProcess -OwnedProcess $aiProcess -StartedAt $aiProcessStartedAt
    }
    if ($startedApi -and $null -ne $apiProcess -and $null -ne $apiProcessStartedAt) {
        Write-Host 'Stopping the API process tree started by this launcher...' -ForegroundColor DarkGray
        Stop-RentHubOwnedApiProcess -OwnedProcess $apiProcess -StartedAt $apiProcessStartedAt
    }
    if ($startedBlockchain -and $null -ne $blockchainProcess -and $null -ne $blockchainProcessStartedAt) {
        Write-Host 'Stopping the blockchain process started by this launcher...' -ForegroundColor DarkGray
        Stop-RentHubOwnedApiProcess -OwnedProcess $blockchainProcess -StartedAt $blockchainProcessStartedAt
    }
}
