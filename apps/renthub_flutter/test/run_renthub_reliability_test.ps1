# Local helper tests only. Never reads .env, contacts Atlas or starts RentHub.
param([switch]$Integration)
$ErrorActionPreference = 'Stop'
$launcherPath = Join-Path $PSScriptRoot '..\run-renthub.ps1'
$tokens = $null
$errors = $null
$tree = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $launcherPath).Path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Launcher syntax errors.' }
$helpers = $tree.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $true)
foreach ($helper in $helpers) { . ([scriptblock]::Create($helper.Extent.Text)) }
function Assert-Reliability {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
foreach ($version in @('v22.0.0', 'v24.19.0', '22.1.3')) {
    Assert-Reliability (Test-RentHubNodeVersion $version) 'Supported Node runtime passes preflight.'
}
foreach ($version in @('', 'v20.18.0', 'not-a-version', 'v3.12')) {
    Assert-Reliability (-not (Test-RentHubNodeVersion $version)) 'Unsupported or unreadable Node versions fail clearly.'
}

# Exercise the actual health adapter with real JSON-RPC response shapes. Returning
# the response envelope instead of its result formerly rejected valid Ganache.
$script:rpcFixture = '{"jsonrpc":"2.0","id":1,"result":"0x539"}'
function Invoke-RestMethod {
    param($Method, $Uri, $ContentType, $Body, $TimeoutSec)
    Assert-Reliability ($Method -eq 'Post' -and $TimeoutSec -eq 3) 'Blockchain readiness uses a bounded read-only request.'
    $request = $Body | ConvertFrom-Json
    Assert-Reliability ($request.method -eq 'eth_chainId') 'Readiness must not mutate the chain.'
    return $script:rpcFixture | ConvertFrom-Json
}
$chain = Get-RentHubBlockchainHealth -RpcUrl 'http://fixture.invalid'
Assert-Reliability ($chain -is [string] -and $chain -eq '0x539') 'A valid JSON-RPC response must produce the chain ID string, not its envelope.'
foreach ($hex in @('0X539', '0x0539', '0x000539')) {
    $script:rpcFixture = '{"jsonrpc":"2.0","id":1,"result":"' + $hex + '"}'
    Assert-Reliability ((Get-RentHubBlockchainHealth -RpcUrl 'http://fixture.invalid') -eq '0x539') 'Equivalent hex chain IDs normalize consistently.'
}
$script:rpcFixture = '{"jsonrpc":"2.0","id":1,"result":"0x7a69"}'
Assert-Reliability ((Get-RentHubBlockchainHealth -RpcUrl 'http://fixture.invalid') -eq '0x7a69') 'A genuinely different chain remains distinguishable.'
foreach ($invalidRpc in @(
    '{"jsonrpc":"2.0","id":1,"error":{"code":-32601}}',
    '{"jsonrpc":"2.0","id":1,"result":{"value":"0x539"}}',
    '{"jsonrpc":"2.0","id":1,"result":1337}',
    '{"jsonrpc":"2.0","id":1,"result":"invalid"}',
    '{"jsonrpc":"2.0","id":1,"result":"0x539","error":{"code":-1}}'
)) {
    $script:rpcFixture = $invalidRpc
    Assert-Reliability ($null -eq (Get-RentHubBlockchainHealth -RpcUrl 'http://fixture.invalid')) 'Malformed/error RPC responses are not ready.'
}
Remove-Item Function:\Invoke-RestMethod

# Execute the real presentation-mode block, without any service startup.
$presentationBlock = $tree.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.IfStatementAst] -and
    $node.Clauses[0].Item1.Extent.Text -eq '$Presentation'
}, $true) | Select-Object -First 1
$Presentation = $true
$NoAiReload = $false
$NoApiReload = $false
. ([scriptblock]::Create($presentationBlock.Extent.Text))
Assert-Reliability ($NoAiReload -and $NoApiReload) 'Presentation disables both development watchers.'
Assert-Reliability ($tree.Extent.Text.Contains('-not $ServicesOnly -and -not $CheckOnly -and -not (Get-Command flutter')) 'Service-only checks must work without Flutter.'
Assert-Reliability ($tree.Extent.Text.Contains('if ($Device -eq ''windows'' -and -not $ServicesOnly -and -not $CheckOnly)')) 'Service-only recovery must allow an existing desktop app.'

# Readiness tolerates warming services, preserves the actual health result, and
# stops promptly for exited processes or an explicitly incompatible contract.
$script:probes = 0
function Start-Sleep { param($Seconds, $Milliseconds) }
$result = Wait-RentHubReadiness -Name fixture -TimeoutSeconds 3 -Probe {
    $script:probes++
    if ($script:probes -eq 3) { return @{ status = 'ok'; contract = 'fixture' } }
    return $null
}
Assert-Reliability ($script:probes -eq 3 -and $result.contract -eq 'fixture') 'Slow readiness must be retried without losing health metadata.'
# A real exited fixture is covered in Integration; no fabricated Process object.
$caught = $false
try { Wait-RentHubReadiness -Name fixture -TimeoutSeconds 3 -Probe { throw 'incompatible contract' } | Out-Null }
catch { $caught = $_.Exception.Message -eq 'incompatible contract' }
Assert-Reliability $caught 'An incompatible service must fail without retrying or being killed.'
Remove-Item Function:\Start-Sleep
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$result = Wait-RentHubReadiness -Name fixture -TimeoutSeconds 1 -Probe { $false }
Assert-Reliability ($null -eq $result -and $clock.Elapsed.TotalSeconds -lt 3) 'Unavailable readiness has a wall-clock deadline.'

# Android forwarding is retried safely and always maps the stable device port to
# the chosen host port. No global adb restart, command interpolation or device mutation.
$script:stateOutput = 'device'
$script:stateError = ''
$script:stateExit = 0
$script:reverseExit = 0
$script:timedOut = $false
$script:commands = @()
function Invoke-RentHubNativeCommand {
    param($FilePath, [string[]]$Arguments, $TimeoutSeconds)
    Assert-Reliability ($FilePath -eq 'fixture-adb' -and $TimeoutSeconds -eq 5) 'ADB calls use bounded direct process arguments.'
    $script:commands += ,$Arguments
    if ($Arguments[2] -eq 'get-state') {
        return @{ Output = $script:stateOutput; Error = $script:stateError; ExitCode = $script:stateExit; TimedOut = $script:timedOut }
    }
    Assert-Reliability ($Arguments[2] -eq 'reverse') 'Connection recovery must never kill/restart ADB or alter a booking.'
    return @{ ExitCode = $script:reverseExit; TimedOut = $script:timedOut }
}
Assert-Reliability ((Sync-RentHubAndroidConnection -TargetDevice demo -HostPort 3004) -eq 'adb-missing') 'Missing ADB has an explicit state.'
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3004) -eq 'connected') 'An online phone reconnects.'
Assert-Reliability (($script:commands[1] -join ' ') -eq '-s demo reverse tcp:3000 tcp:3004') 'Installed apps retain localhost:3000 when the PC changes API port.'
Assert-Reliability (($script:commands[2] -join ' ') -eq '-s demo reverse tcp:3004 tcp:3004') 'Older custom-port builds also retain forwarding.'
$script:stateExit = 1
$script:stateOutput = ''
$script:stateError = 'device offline'
$before = $script:commands.Count
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'waiting') 'Offline phones wait for reconnection.'
Assert-Reliability ($script:commands.Count -eq $before + 1) 'Offline devices are not forwarded.'
$script:stateError = 'device unauthorized'
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'unauthorized') 'Debugging approval needs targeted guidance.'
$script:stateExit = 0
$script:stateOutput = 'device'
$script:stateError = ''
$script:reverseExit = 1
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'forwarding-failed') 'Failed forwarding cannot claim connection success.'
$script:timedOut = $true
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'waiting') 'Timed-out ADB calls remain recoverable.'
$script:timedOut = $false
$script:reverseExit = 0
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'connected') 'A later retry restores the connection.'
Remove-Item Function:\Invoke-RentHubNativeCommand
. ([scriptblock]::Create(($helpers | Where-Object Name -eq 'Invoke-RentHubNativeCommand').Extent.Text))

# Exercise one real monitor iteration plus a reconnect. No real health/device calls.
$script:monitorCalls = 0
$script:monitorSleeps = 0
function Sync-RentHubAndroidConnection { param($AdbPath, $TargetDevice, $HostPort)
    $script:monitorCalls++
    if ($script:monitorCalls -eq 1) { return 'waiting' }
    return 'connected'
}
function Test-RentHubApiReady { param($Port); return $true }
function Start-Sleep { param($Seconds)
    $script:monitorSleeps++
    if ($script:monitorSleeps -eq 2) { throw 'end fixture session' }
}
try { Wait-RentHubServiceSession -AdbPath fixture-adb -TargetDevice demo -HostPort 3004 -WarningAction SilentlyContinue }
catch { Assert-Reliability ($_.Exception.Message -eq 'end fixture session') 'Unexpected monitor failure.' }
Assert-Reliability ($script:monitorCalls -eq 2) 'Retained service sessions retry after a device disconnect.'
Remove-Item Function:\Start-Sleep

if ($Integration) {
    # Disposable native processes only; no ports, dependencies, database or services.
    $node = (Get-Command node -CommandType Application).Source
    $argsFixture = @('ordinary', 'with spaces', 'quote"inside', 'C:\folder with spaces\', '', ('Unicode-' + [char]0x4e2d + [char]0x6587), 'literal-$HOME-`text', 'slash\"quote')
    $native = Invoke-RentHubNativeCommand -FilePath $node -Arguments (@('-e', 'console.log(JSON.stringify(process.argv.slice(1)))') + $argsFixture)
    Assert-Reliability ($native.ExitCode -eq 0 -and -not $native.TimedOut) 'Quoted command must run successfully.'
    $received = $native.Output | ConvertFrom-Json
    Assert-Reliability ($received.Count -eq $argsFixture.Count) 'Every argument, including empty arguments, survives quoting.'
    for ($i = 0; $i -lt $argsFixture.Count; $i++) {
        Assert-Reliability ($received[$i] -ceq $argsFixture[$i]) 'Spaces, quotes, Unicode and backslashes must survive without shell expansion.'
    }
    $native = Invoke-RentHubNativeCommand -FilePath $node -Arguments @('--input-type=module') -InputText 'console.log("stdin-fixture"); console.error("stderr-fixture");'
    Assert-Reliability ($native.Output.Trim() -eq 'stdin-fixture' -and $native.Error.Trim() -eq 'stderr-fixture') 'Stdin works and stderr cannot corrupt JSON output.'
    $native = Invoke-RentHubNativeCommand -FilePath $node -Arguments @('-e', 'process.stdout.write("x".repeat(200000)); process.stderr.write("y".repeat(200000));')
    Assert-Reliability ($native.Output.Length -eq 200000 -and $native.Error.Length -eq 200000) 'Parallel pipe draining must avoid deadlocks.'
    $clock.Restart()
    $native = Invoke-RentHubNativeCommand -FilePath $node -Arguments @('-e', 'setTimeout(()=>{},30000)') -TimeoutSeconds 1
    Assert-Reliability ($native.TimedOut -and $native.ExitCode -eq -1 -and $clock.Elapsed.TotalSeconds -lt 8) 'Hung native tools must terminate within their bound.'
    Assert-Reliability ($null -eq (Get-Process -Id $native.ProcessId -ErrorAction SilentlyContinue)) 'A timed-out owned process must not be left running.'
    $exitFixture = Start-Process -FilePath $node -ArgumentList '-e "process.exit(7)"' -WindowStyle Hidden -PassThru
    $exitFixture.WaitForExit()
    $script:exitProbeCalled = $false
    $caught = $false
    try { Wait-RentHubReadiness -Name fixture -TimeoutSeconds 30 -OwnedProcess $exitFixture -Probe { $script:exitProbeCalled = $true; return $true } | Out-Null }
    catch { $caught = $_.Exception.Message.Contains('stopped before') }
    Assert-Reliability ($caught -and -not $script:exitProbeCalled) 'Exited processes must fail before a misleading health probe.'
    $exitFixture.Dispose()
    Write-Host 'PASS: disposable native quoting, stdin, pipe pressure, timeouts and exited-process integration.'
}

# Run the full executable body against fake service/process boundaries. This
# catches wiring bugs that isolated helper tests miss, without reading .env,
# binding any service port, launching Flutter, or changing database records.
foreach ($helper in $helpers) { . ([scriptblock]::Create($helper.Extent.Text)) }
$fixtureLauncherDirectory = Split-Path (Resolve-Path -LiteralPath $launcherPath).Path
$bodySource = (($tree.EndBlock.Statements | Where-Object {
    $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst]
} | ForEach-Object { $_.Extent.Text }) -join "`n").Replace('$PSScriptRoot', '$fixtureLauncherDirectory')
$body = [scriptblock]::Create($bodySource)
function Test-Path { param($LiteralPath, $PathType); return $true }
function New-Item { param($ItemType, $Path, [switch]$Force) }
function Get-Command { param($Name, $ErrorAction)
    if ($Name -eq 'flutter') { $script:flutterLookups++ }
    return @{ Source = 'fixture-node' }
}
function Get-Process { param($Name, $ErrorAction); return $null }
function Invoke-RentHubNativeCommand { param($FilePath, $Arguments, $TimeoutSeconds)
    Assert-Reliability (($Arguments -join ' ') -eq '--version') 'Full-body fixture cannot execute native service commands.'
    return @{ ExitCode = 0; Output = 'v24.0.0'; TimedOut = $false }
}
function Get-RentHubEnvironmentValue { param($Path, $Name, $DefaultValue = '')
    switch ($Name) {
        BLOCKCHAIN_MODE { return 'ganache' }
        GANACHE_RPC_URL { return 'http://localhost:8545' }
        AUTH_MODE { return 'local' }
        PORT { return '3000' }
        default { return $DefaultValue }
    }
}
function Get-RentHubMongoTarget { param($ConnectionString); return @{ IsLocal = $false } }
function Get-RentHubAtlasHost { param($ConnectionString); return 'fixture.mongodb.net' }
function Initialize-RentHubAtlasAccess { param($NodePath, $ApiDirectory, $ClusterHost, $ProjectId, $Profile); $script:atlasChecked = $true }
function Resolve-RentHubApiPort { param($PreferredPort); return 3004 }
function Invoke-RestMethod { param($Method, $Uri, $ContentType, $Body, $TimeoutSec)
    Assert-Reliability (($Body | ConvertFrom-Json).method -eq 'eth_chainId') 'Full startup fixtures permit read-only chain health only.'
    if ($script:chainStarted -or $script:reuseChain) {
        return ('{"jsonrpc":"2.0","id":1,"result":"' + $script:fixtureChainId + '"}' | ConvertFrom-Json)
    }
    throw 'Fixture chain has not started'
}
function Test-RentHubTcpPort { param($HostName, $Port); return $false }
function Get-RentHubAiHealth {
    if ($script:aiStarted) { return @{ status = 'ok'; document_frame_contract = 'opencv-document-yolo-v6';
        driving_licence_contract = 'malaysian-driving-ocr-v1'; recommendation_contract = 'hybrid-profile-v2';
        item_verification_contract = 'renthub-item-evidence-v4'; artifacts = @{ price_model = $true };
        item_verification_status = @{ world = @{ available = $true } } } }
    return $null
}
function Test-RentHubApiReady { param($Port); return $script:apiStarted }
function Test-RentHubApiPortAvailable { param($Port); return $true }
function Start-Process { param($FilePath, $ArgumentList, $WorkingDirectory, $WindowStyle, $RedirectStandardOutput, $RedirectStandardError, [switch]$PassThru)
    Assert-Reliability $script:atlasChecked 'Database preflight must precede owned service startup.'
    if ($WorkingDirectory -like '*\blockchain') { $script:chainStarted = $true }
    elseif ($WorkingDirectory -like '*\ai') {
        $script:aiStarted = $true
        Assert-Reliability ($ArgumentList -notcontains '--reload') 'Presentation mode must reach real AI startup arguments.'
    }
    elseif ($WorkingDirectory -like '*\api') {
        $script:apiStarted = $true
        Assert-Reliability ($env:PORT -eq '3004') 'API inherits the selected port.'
        Assert-Reliability ($ArgumentList -notcontains '--watch') 'Presentation mode must reach real API startup arguments.'
    }
    else { throw 'Unexpected process directory.' }
    return [pscustomobject]@{ Id = 123; StartTime = $script:fakeStartedAt; HasExited = $false }
}
function Wait-RentHubReadiness { param($Name, $Probe, $TimeoutSeconds, $OwnedProcess, $ErrorLogPath)
    Assert-Reliability ($ErrorLogPath -like '*launcher-*') 'Readiness failures retain a useful private log path.'
    return & $Probe
}
function Stop-RentHubOwnedApiProcess { param($OwnedProcess, $StartedAt); $script:cleanupCalls++ }
function Stop-RentHubOwnedAiProcess { param($OwnedProcess, $StartedAt); $script:cleanupCalls++ }
function Get-RentHubAdbPath { return 'fixture-adb' }
function Sync-RentHubAndroidConnection { param($AdbPath, $TargetDevice, $HostPort)
    Assert-Reliability ($HostPort -eq 3004) 'ADB uses the selected host port.'
    return 'connected'
}
function Wait-RentHubServiceSession { param($AdbPath, $TargetDevice, $HostPort, [switch]$MonitorAi, $BlockchainRpcUrl)
    Assert-Reliability ($HostPort -eq 3004 -and $MonitorAi -and $BlockchainRpcUrl -eq 'http://localhost:8545') 'Retained session receives all monitor settings.'
    $script:sessionEntered = $true
    throw 'fixture session complete'
}
function flutter {
    Assert-Reliability ((Get-Location).Path -eq $fixtureLauncherDirectory) 'Flutter always runs from its app directory, regardless of caller location.'
    $script:flutterArguments = @($args)
    $global:LASTEXITCODE = 0
}
$savedMongo = $env:MONGODB_URI
$savedPort = $env:PORT
try {
    $env:MONGODB_URI = 'mongodb+srv://fixture.mongodb.net/test'
    $env:PORT = $null
    foreach ($scenario in @('check', 'services', 'windows', 'android', 'reuse-chain', 'wrong-chain')) {
        $Device = if ($scenario -in @('check', 'windows', 'reuse-chain', 'wrong-chain')) { 'windows' } else { 'fixture-phone' }
        $Presentation = $true
        $CheckOnly = $scenario -in @('check', 'reuse-chain', 'wrong-chain')
        $ServicesOnly = $scenario -eq 'services'
        $SkipAi = $false; $SkipBlockchain = $false; $SkipAtlasAccess = $false
        $AiStartupTimeoutSeconds = 180; $ApiStartupTimeoutSeconds = 90
        $ApiPort = 0
        $AtlasProfile = 'default'; $AtlasProjectId = ''; $Admin = $false; $ExtraFlutterArgs = @()
        $script:fakeStartedAt = [datetime]::UtcNow
        $script:atlasChecked = $false; $script:chainStarted = $false; $script:aiStarted = $false; $script:apiStarted = $false
        $script:reuseChain = $scenario -in @('reuse-chain', 'wrong-chain')
        $script:fixtureChainId = if ($scenario -eq 'wrong-chain') { '0x7a69' } else { '0x539' }
        $script:flutterLookups = 0; $script:cleanupCalls = 0; $script:sessionEntered = $false; $script:flutterArguments = @()
        $callerDirectory = (Get-Location).Path
        $startupError = $null
        try { & $body }
        catch { $startupError = $_.Exception.Message }
        if ($scenario -eq 'wrong-chain') {
            Assert-Reliability ($startupError -like '*wrong chain ID*') 'A genuinely incompatible chain must fail clearly.'
            Assert-Reliability ($script:cleanupCalls -eq 0 -and -not $script:aiStarted -and -not $script:apiStarted -and -not $script:chainStarted) 'Wrong-chain detection must not stop or replace an existing blockchain.'
            continue
        }
        Assert-Reliability ($null -eq $startupError -or $startupError -eq 'fixture session complete') "Unexpected $scenario startup error: $startupError"
        $expectedCleanup = if ($scenario -eq 'reuse-chain') { 2 } else { 3 }
        Assert-Reliability ($script:cleanupCalls -eq $expectedCleanup) 'Clean up only owned services; never stop a reused blockchain.'
        Assert-Reliability ([string]::IsNullOrEmpty($env:PORT)) 'Full startup restores the caller PORT.'
        Assert-Reliability ((Get-Location).Path -eq $callerDirectory) 'Flutter startup restores the caller directory.'
        if ($scenario -in @('check', 'services', 'reuse-chain')) {
            Assert-Reliability ($script:flutterLookups -eq 0 -and $script:flutterArguments.Count -eq 0) 'Service-only/check mode never needs or launches Flutter.'
        }
        else {
            $expectedPort = if ($scenario -eq 'android') { 3000 } else { 3004 }
            Assert-Reliability ($script:flutterArguments -contains "--dart-define=API_BASE_URL=http://localhost:$expectedPort/api/v1") 'Full startup uses correct desktop/Android client addresses.'
        }
        Assert-Reliability ($script:sessionEntered -eq ($scenario -in @('services', 'android'))) 'Only retained sessions enter the connection monitor.'
    }
}
finally { $env:MONGODB_URI = $savedMongo; $env:PORT = $savedPort }
Write-Host 'PASS: full startup with new/reused chain RPC envelopes, genuine chain mismatch, check-only, services-only, Windows and Android.'
Write-Host 'PASS: presentation mode, bounded readiness, Android stable-port recovery and retained-session monitoring.'
