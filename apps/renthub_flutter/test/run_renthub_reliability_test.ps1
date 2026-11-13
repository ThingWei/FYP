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

$consoleHelper = $helpers | Where-Object Name -eq 'Invoke-RentHubFlutterConsole'
Assert-Reliability ($consoleHelper.Extent.Text.Contains('-NoNewWindow') -and
    -not $consoleHelper.Extent.Text.Contains('-RedirectStandardInput') -and
    -not $consoleHelper.Extent.Text.Contains('-RedirectStandardOutput')) 'Flutter must inherit the console without redirected keyboard/output.'
$backgroundStarts = $tree.FindAll({ param($node)
    $node -is [Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'Start-Process' -and
        $node.Extent.Text.Contains('-RedirectStandardOutput')
}, $true)
Assert-Reliability ($backgroundStarts.Count -eq 3) 'All three background services must be covered.'
foreach ($launch in $backgroundStarts) {
    Assert-Reliability ($launch.Extent.Text.Contains('-RedirectStandardInput $serviceInputPath')) 'Background services cannot compete with Flutter for terminal keys.'
}

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
$script:reverseError = ''
$script:reverseTimedOut = $false
$script:adbException = $null
$script:timedOut = $false
$script:commands = @()
function Invoke-RentHubNativeCommand {
    param($FilePath, [string[]]$Arguments, $TimeoutSeconds, [switch]$PreserveChildProcesses)
    Assert-Reliability ($FilePath -eq 'fixture-adb' -and $TimeoutSeconds -ge 1 -and $TimeoutSeconds -le 5) 'ADB calls use bounded direct process arguments.'
    Assert-Reliability $PreserveChildProcesses 'An ADB client timeout must preserve the shared daemon.'
    $script:commands += ,$Arguments
    if ($script:adbException) { throw $script:adbException }
    if ($Arguments[2] -eq 'get-state') {
        return @{ Output = $script:stateOutput; Error = $script:stateError; ExitCode = $script:stateExit; TimedOut = $script:timedOut }
    }
    Assert-Reliability ($Arguments[2] -eq 'reverse') 'Connection recovery must never kill/restart ADB or alter a booking.'
    return @{ Output = ''; Error = $script:reverseError; ExitCode = $script:reverseExit; TimedOut = ($script:timedOut -or $script:reverseTimedOut) }
}
Assert-Reliability ((Sync-RentHubAndroidConnection -TargetDevice demo -HostPort 3004) -eq 'adb-missing') 'Missing ADB has an explicit state.'
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3004) -eq 'connected') 'An online phone reconnects.'
Assert-Reliability (($script:commands[1] -join ' ') -eq '-s demo reverse tcp:3000 tcp:3004') 'Installed apps retain localhost:3000 when the PC changes API port.'
Assert-Reliability (($script:commands[2] -join ' ') -eq '-s demo reverse tcp:3004 tcp:3004') 'Older custom-port builds also retain forwarding.'
$script:stateExit = 1
$script:stateOutput = ''
$script:stateError = 'device offline'
$before = $script:commands.Count
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'offline') 'Offline phones have a distinct retryable state.'
Assert-Reliability ($script:commands.Count -eq $before + 1) 'Offline devices are not forwarded.'
$script:stateError = 'device unauthorized'
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'unauthorized') 'Debugging approval needs targeted guidance.'
$script:stateExit = 0
$script:stateOutput = 'device'
$script:stateError = ''
$script:reverseExit = 1
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'forwarding-failed') 'Failed forwarding cannot claim connection success.'
$script:timedOut = $true
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'adb-timeout') 'Timed-out ADB checks have targeted guidance and remain recoverable.'
$script:timedOut = $false
$script:reverseExit = 0
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'connected') 'A later retry restores the connection.'
$script:reverseTimedOut = $true
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'forwarding-timeout') 'Forwarding timeouts must be distinct from device-check timeouts.'
$script:reverseTimedOut = $false
$script:reverseExit = 1
$script:reverseError = 'device offline private-test-value'
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'offline') 'A phone disconnecting during forwarding remains retryable.'
$script:reverseExit = 0
$script:reverseError = ''
$script:stateExit = 1
$script:stateError = "error: device 'demo' not found private-test-value"
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'not-found') 'An absent selected device needs specific guidance.'
$script:stateError = 'unrecognized private-test-value C:\private\file'
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'adb-error') 'Unknown ADB output is safely classified.'
$before = $script:commands.Count
foreach ($id in @('', '-flag', 'bad id', "bad`nvalue")) {
    Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice $id -HostPort 3000) -eq 'invalid-device') 'Malformed device IDs fail before invoking ADB.'
}
Assert-Reliability ($before -eq $script:commands.Count) 'Invalid IDs cannot trigger native tools.'
$script:stateExit = 0
$script:stateError = ''
foreach ($id in @('6e5141a', '192.0.2.1:37129', 'adb-demo._adb-tls-connect._tcp', '[::1]:5555', 'emulator-5554')) {
    Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice $id -HostPort 3000) -eq 'connected') 'USB, wireless, mDNS and emulator IDs remain supported.'
}
$script:adbException = [ComponentModel.Win32Exception]::new(2)
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'adb-missing') 'An executable removed after discovery fails clearly.'
$script:adbException = [InvalidOperationException]::new('private-test-value')
Assert-Reliability ((Sync-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3000) -eq 'adb-error') 'Tool startup failures remain classified, without raw exception text.'
$script:adbException = $null
foreach ($state in @('adb-missing', 'invalid-device', 'unauthorized', 'offline', 'not-found', 'adb-timeout', 'adb-discovery-timeout', 'forwarding-timeout', 'forwarding-failed', 'adb-error', 'private-test-value')) {
    $message = Get-RentHubAndroidConnectionMessage -State $state
    Assert-Reliability ($message -and -not $message.Contains('private-test-value')) 'Connection guidance must never dump private raw diagnostics.'
}
Remove-Item Function:\Invoke-RentHubNativeCommand
. ([scriptblock]::Create(($helpers | Where-Object Name -eq 'Invoke-RentHubNativeCommand').Extent.Text))

# Refresh discovery with the same ADB executable, without killing the daemon or
# assuming a listed phone has authorized debugging/working port forwarding.
& {
    $script:discoveryCommands = @()
    $script:discoveryTimeout = $false; $script:discoveryExit = 0
    function Invoke-RentHubNativeCommand {
        param($FilePath, [string[]]$Arguments, $TimeoutSeconds, [switch]$PreserveChildProcesses)
        Assert-Reliability ($FilePath -eq 'fixture-adb' -and $TimeoutSeconds -ge 1 -and $TimeoutSeconds -le 10 -and $PreserveChildProcesses) 'Discovery uses bounded calls and preserves other ADB sessions.'
        $script:discoveryCommands += ($Arguments -join ' ')
        return @{ Output = 'private-test-value'; Error = 'private-test-value'; ExitCode = $script:discoveryExit; TimedOut = $script:discoveryTimeout }
    }
    Assert-Reliability ((Initialize-RentHubAndroidDiscovery -AdbPath fixture-adb) -eq 'refreshed') 'Starting/enumerating the daemon can refresh discovery.'
    Assert-Reliability (($script:discoveryCommands -join '|') -eq 'start-server|devices -l') 'Only safe discovery commands run, without kill-server/reconnect or Flutter startup.'
    $script:discoveryTimeout = $true; $script:discoveryCommands = @()
    Assert-Reliability ((Initialize-RentHubAndroidDiscovery -AdbPath fixture-adb) -eq 'adb-discovery-timeout') 'Hung discovery cannot report connection readiness.'
    Assert-Reliability ($script:discoveryCommands.Count -eq 1) 'A timed-out server startup does not start another discovery command.'
    $script:discoveryTimeout = $false; $script:discoveryExit = 1
    Assert-Reliability ((Initialize-RentHubAndroidDiscovery -AdbPath fixture-adb) -eq 'adb-error') 'Discovery failures stay safe and retryable.'
}

# Exercise the real startup retry loop with state changes, not real ADB calls.
& {
    $script:waitStates = @('connected')
    $script:waitCalls = 0
    $script:waitMessages = @()
    $script:discoveryCalls = 0
    $script:discoveryResult = 'refreshed'
    function Initialize-RentHubAndroidDiscovery {
        param($AdbPath, $TimeoutSeconds)
        Assert-Reliability ($AdbPath -eq 'fixture-adb' -and $TimeoutSeconds -ge 1 -and $TimeoutSeconds -le 10) 'Discovery is included in the remaining startup budget.'
        $script:discoveryCalls++
        return $script:discoveryResult
    }
    function Write-Host { param($Object, $ForegroundColor); $script:waitMessages += [string]$Object }
    function Sync-RentHubAndroidConnection {
        param($AdbPath, $TargetDevice, $HostPort, $TimeoutSeconds)
        Assert-Reliability ($TimeoutSeconds -ge 1 -and $TimeoutSeconds -le 30) 'Each attempt receives only the remaining overall budget.'
        $state = $script:waitStates[[Math]::Min($script:waitCalls, $script:waitStates.Count - 1)]
        $script:waitCalls++
        return $state
    }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $result = Wait-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3004 -RetryIntervalMilliseconds 100
    Assert-Reliability ($result -eq 'connected' -and $script:waitCalls -eq 1 -and $clock.Elapsed.TotalSeconds -lt 1) 'A ready phone must start immediately, without the 30-second delay.'
    Assert-Reliability ($script:discoveryCalls -eq 0) 'A ready phone does not run unnecessary discovery.'
    foreach ($states in @(@('not-found', 'unauthorized', 'connected'), @('offline', 'connected'), @('forwarding-failed', 'connected'), @('adb-timeout', 'connected'))) {
        $script:waitStates = $states
        $script:waitCalls = 0
        $result = Wait-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3004 -RetryIntervalMilliseconds 100
        Assert-Reliability ($result -eq 'connected' -and $script:waitCalls -eq $states.Count) 'Delayed connection, authorization and forwarding must retry to recovery.'
    }
    Assert-Reliability (($script:waitMessages -join ' ').Contains('Unlock your phone')) 'Authorization guidance appears while waiting, not only after failure.'
    $script:waitStates = @('adb-timeout', 'offline', 'connected'); $script:waitCalls = 0; $script:discoveryCalls = 0
    $result = Wait-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3004 -RetryIntervalMilliseconds 100
    Assert-Reliability ($result -eq 'connected' -and $script:discoveryCalls -eq 1 -and $script:waitCalls -eq 3) 'Cold-start recovery refreshes once and still verifies the selected phone and forwarding.'
    $script:discoveryResult = 'adb-discovery-timeout'; $script:waitStates = @('adb-timeout', 'connected'); $script:waitCalls = 0; $script:discoveryCalls = 0
    $result = Wait-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3004 -RetryIntervalMilliseconds 100
    Assert-Reliability ($result -eq 'connected' -and $script:discoveryCalls -eq 1) 'A discovery timeout still permits a later successful selected-device check.'
    $script:discoveryResult = 'refreshed'; $script:waitStates = @('unauthorized', 'connected'); $script:waitCalls = 0; $script:discoveryCalls = 0
    $result = Wait-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3004 -RetryIntervalMilliseconds 100
    Assert-Reliability ($result -eq 'connected' -and $script:discoveryCalls -eq 0) 'Authorization needs the user prompt, not a daemon refresh.'
    foreach ($state in @('adb-missing', 'invalid-device')) {
        $script:waitStates = @($state); $script:waitCalls = 0
        $clock.Restart()
        $result = Wait-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3004
        Assert-Reliability ($result -eq $state -and $script:waitCalls -eq 1 -and $clock.Elapsed.TotalSeconds -lt 1) 'Missing tools and invalid IDs must fail immediately.'
    }
    $script:waitStates = @('offline'); $script:waitCalls = 0
    $clock.Restart()
    $result = Wait-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice demo -HostPort 3004 -TimeoutSeconds 1 -RetryIntervalMilliseconds 100
    Assert-Reliability ($result -eq 'offline' -and $script:waitCalls -ge 2 -and $clock.Elapsed.TotalSeconds -ge 0.9 -and $clock.Elapsed.TotalSeconds -lt 3) 'The retry loop stops at its overall deadline and retains the last actual problem.'
}
Write-Host 'PASS: Android startup retry, authorization recovery, forwarding recovery, deadline, safe diagnostics and fail-fast configuration.'

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
    $node = (Microsoft.PowerShell.Core\Get-Command node -CommandType Application | Select-Object -First 1).Source
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
    $unicodeFixture = 'stdin-' + [char]0x4e2d + [char]0x6587
    $native = Invoke-RentHubNativeCommand -FilePath $node -Arguments @('--input-type=module') -InputText ('console.log("' + $unicodeFixture + '");')
    Assert-Reliability ($native.Output.Trim() -ceq $unicodeFixture) 'UTF-8 stdin and stdout must survive non-interactive Windows PowerShell.'
    $native = Invoke-RentHubNativeCommand -FilePath $node -Arguments @('-e', 'process.stdout.write("x".repeat(200000)); process.stderr.write("y".repeat(200000));')
    Assert-Reliability ($native.Output.Length -eq 200000 -and $native.Error.Length -eq 200000) 'Parallel pipe draining must avoid deadlocks.'
    $clock.Restart()
    $native = Invoke-RentHubNativeCommand -FilePath $node -Arguments @('-e', 'setTimeout(()=>{},30000)') -TimeoutSeconds 1
    Assert-Reliability ($native.TimedOut -and $native.ExitCode -eq -1 -and $clock.Elapsed.TotalSeconds -lt 8) 'Hung native tools must terminate within their bound.'
    Assert-Reliability ($null -eq (Get-Process -Id $native.ProcessId -ErrorAction SilentlyContinue)) 'A timed-out owned process must not be left running.'
    $daemonFixturePath = Join-Path ([IO.Path]::GetTempPath()) ('renthub-adb-daemon-' + [guid]::NewGuid().ToString('N') + '.txt')
    $daemonFixture = $null
    try {
        $parentCode = 'const cp=require("node:child_process"),fs=require("node:fs");const p=cp.spawn(process.execPath,["-e","setTimeout(()=>{},30000)"],{stdio:"ignore",windowsHide:true,detached:true});p.unref();fs.writeFileSync(process.argv[1],String(p.pid));setTimeout(()=>{},30000);'
        $native = Invoke-RentHubNativeCommand -FilePath $node -Arguments @('-e', $parentCode, $daemonFixturePath) -TimeoutSeconds 2 -PreserveChildProcesses
        Assert-Reliability ($native.TimedOut -and (Test-Path -LiteralPath $daemonFixturePath)) 'The disposable ADB-like parent starts a daemon then times out.'
        $daemonFixture = Get-Process -Id ([int][IO.File]::ReadAllText($daemonFixturePath)) -ErrorAction SilentlyContinue
        Assert-Reliability ($null -ne $daemonFixture -and -not $daemonFixture.HasExited) 'ADB client timeout must leave its shared daemon running.'
        Assert-Reliability ($null -eq (Get-Process -Id $native.ProcessId -ErrorAction SilentlyContinue)) 'Preserving the daemon must still terminate the hung client.'
    }
    finally {
        if ($null -ne $daemonFixture) {
            if (-not $daemonFixture.HasExited) { $daemonFixture.Kill(); $daemonFixture.WaitForExit() }
            $daemonFixture.Dispose()
        }
        if (Test-Path -LiteralPath $daemonFixturePath) { Remove-Item -LiteralPath $daemonFixturePath }
    }
    $exitFixture = Start-Process -FilePath $node -ArgumentList '-e "process.exit(7)"' -WindowStyle Hidden -PassThru
    $exitFixture.WaitForExit()
    $script:exitProbeCalled = $false
    $caught = $false
    try { Wait-RentHubReadiness -Name fixture -TimeoutSeconds 30 -OwnedProcess $exitFixture -Probe { $script:exitProbeCalled = $true; return $true } | Out-Null }
    catch { $caught = $_.Exception.Message.Contains('stopped before') }
    Assert-Reliability ($caught -and -not $script:exitProbeCalled) 'Exited processes must fail before a misleading health probe.'
    $exitFixture.Dispose()
    Write-Host 'PASS: disposable native quoting, stdin, pipe pressure, timeouts and exited-process integration.'
    & (Join-Path $PSScriptRoot 'run_renthub_terminal_test.ps1') -Integration
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
    if ($Name -eq 'node') { return @(@{ Source = 'fixture-node' }, @{ Source = 'second-node-on-path' }) }
    return @{ Source = 'fixture-node' }
}
function Get-Process { param($Name, $ErrorAction); return $null }
function Invoke-RentHubNativeCommand { param($FilePath, $Arguments, $TimeoutSeconds)
    Assert-Reliability ($FilePath -eq 'fixture-node') 'Select one executable when PATH contains multiple Node installations.'
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
function Start-Process { param($FilePath, $ArgumentList, $WorkingDirectory, $WindowStyle, $RedirectStandardInput, $RedirectStandardOutput, $RedirectStandardError, [switch]$PassThru)
    Assert-Reliability $script:atlasChecked 'Database preflight must precede owned service startup.'
    Assert-Reliability ($RedirectStandardInput -and [IO.File]::ReadAllBytes($RedirectStandardInput).Length -eq 0) 'Background services receive empty input, never the interactive console.'
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
    if ($script:servicesOffline) { return 'offline' }
    return 'connected'
}
function Wait-RentHubAndroidConnection { param($AdbPath, $TargetDevice, $HostPort)
    Assert-Reliability ($HostPort -eq 3004) 'Startup waiting must use the selected host port.'
    $script:androidWaitCalls++
    return $script:androidStartupState
}
function Wait-RentHubServiceSession { param($AdbPath, $TargetDevice, $HostPort, [switch]$MonitorAi, $BlockchainRpcUrl)
    Assert-Reliability ($HostPort -eq 3004 -and $MonitorAi -and $BlockchainRpcUrl -eq 'http://localhost:8545') 'Retained session receives all monitor settings.'
    $script:sessionEntered = $true
    throw 'fixture session complete'
}
function Invoke-RentHubFlutterConsole {
    param([string[]]$Arguments, [string]$WorkingDirectory)
    Assert-Reliability ((Get-Location).Path -eq $fixtureLauncherDirectory) 'Flutter always runs from its app directory, regardless of caller location.'
    Assert-Reliability ($WorkingDirectory -eq $fixtureLauncherDirectory) 'The native console retains the Flutter app directory.'
    $script:flutterArguments = @($Arguments)
    return 0
}
$savedMongo = $env:MONGODB_URI
$savedPort = $env:PORT
try {
    $env:MONGODB_URI = 'mongodb+srv://fixture.mongodb.net/test'
    $env:PORT = $null
    foreach ($scenario in @('check', 'services', 'windows', 'android', 'reuse-chain', 'wrong-chain', 'android-timeout', 'android-unauthorized', 'android-tools-missing', 'services-offline')) {
        $Device = if ($scenario -in @('check', 'windows', 'reuse-chain', 'wrong-chain')) { 'windows' } else { 'fixture-phone' }
        $Presentation = $true
        $CheckOnly = $scenario -in @('check', 'reuse-chain', 'wrong-chain')
        $ServicesOnly = $scenario -in @('services', 'services-offline')
        $SkipAi = $false; $SkipBlockchain = $false; $SkipAtlasAccess = $false
        $AiStartupTimeoutSeconds = 180; $ApiStartupTimeoutSeconds = 90
        $ApiPort = 0
        $AtlasProfile = 'default'; $AtlasProjectId = ''; $Admin = $false; $ExtraFlutterArgs = @()
        $script:fakeStartedAt = [datetime]::UtcNow
        $script:atlasChecked = $false; $script:chainStarted = $false; $script:aiStarted = $false; $script:apiStarted = $false
        $script:reuseChain = $scenario -in @('reuse-chain', 'wrong-chain')
        $script:fixtureChainId = if ($scenario -eq 'wrong-chain') { '0x7a69' } else { '0x539' }
        $script:flutterLookups = 0; $script:cleanupCalls = 0; $script:sessionEntered = $false; $script:flutterArguments = @()
        $script:androidWaitCalls = 0
        $script:servicesOffline = $scenario -eq 'services-offline'
        $script:androidStartupState = switch ($scenario) {
            'android-timeout' { 'offline' }
            'android-unauthorized' { 'unauthorized' }
            'android-tools-missing' { 'adb-missing' }
            default { 'connected' }
        }
        $callerDirectory = (Get-Location).Path
        $startupError = $null
        try { & $body }
        catch { $startupError = $_.Exception.Message }
        if ($scenario -eq 'wrong-chain') {
            Assert-Reliability ($startupError -like '*wrong chain ID*') 'A genuinely incompatible chain must fail clearly.'
            Assert-Reliability ($script:cleanupCalls -eq 0 -and -not $script:aiStarted -and -not $script:apiStarted -and -not $script:chainStarted) 'Wrong-chain detection must not stop or replace an existing blockchain.'
            continue
        }
        if ($scenario -in @('android-timeout', 'android-unauthorized', 'android-tools-missing')) {
            $problem = Get-RentHubAndroidConnectionMessage -State $script:androidStartupState
            Assert-Reliability ($startupError -and $startupError.Contains($problem)) 'Startup failure must show the specific final connection problem.'
            Assert-Reliability ($script:androidWaitCalls -eq 1 -and $script:flutterArguments.Count -eq 0 -and -not $script:sessionEntered) 'Failed Android readiness must not launch Flutter or enter a normal debug session.'
            Assert-Reliability ($script:cleanupCalls -eq 3) 'Connection failure cleans up only the three owned service trees.'
            Assert-Reliability ([string]::IsNullOrEmpty($env:PORT) -and (Get-Location).Path -eq $callerDirectory) 'Connection failure restores the caller environment and directory.'
            continue
        }
        Assert-Reliability ($null -eq $startupError -or $startupError -eq 'fixture session complete') "Unexpected $scenario startup error: $startupError"
        $expectedCleanup = if ($scenario -eq 'reuse-chain') { 2 } else { 3 }
        Assert-Reliability ($script:cleanupCalls -eq $expectedCleanup) 'Clean up only owned services; never stop a reused blockchain.'
        Assert-Reliability ([string]::IsNullOrEmpty($env:PORT)) 'Full startup restores the caller PORT.'
        Assert-Reliability ((Get-Location).Path -eq $callerDirectory) 'Flutter startup restores the caller directory.'
        if ($scenario -in @('check', 'services', 'services-offline', 'reuse-chain')) {
            Assert-Reliability ($script:flutterLookups -eq 0 -and $script:flutterArguments.Count -eq 0) 'Service-only/check mode never needs or launches Flutter.'
        }
        else {
            $expectedPort = if ($scenario -eq 'android') { 3000 } else { 3004 }
            Assert-Reliability ($script:flutterArguments -contains "--dart-define=API_BASE_URL=http://localhost:$expectedPort/api/v1") 'Full startup uses correct desktop/Android client addresses.'
        }
        Assert-Reliability ($script:sessionEntered -eq ($scenario -in @('services', 'services-offline', 'android'))) 'Only retained sessions enter the connection monitor.'
        Assert-Reliability ($script:androidWaitCalls -eq $(if ($scenario -eq 'android') { 1 } else { 0 })) 'Only normal Android startup uses the bounded wait; services-only still waits continuously.'
    }
}
finally { $env:MONGODB_URI = $savedMongo; $env:PORT = $savedPort }
Write-Host 'PASS: full startup with new/reused chain RPC envelopes, genuine chain mismatch, check-only, services-only, Windows and Android.'
Write-Host 'PASS: presentation mode, bounded readiness, Android stable-port recovery and retained-session monitoring.'
