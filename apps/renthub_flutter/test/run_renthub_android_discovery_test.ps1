# Pure fixtures only: no real Flutter, ADB, device, services, credentials or .env.
param([switch]$Integration)
$ErrorActionPreference = 'Stop'
$launcherPath = (Resolve-Path (Join-Path $PSScriptRoot '..\run-renthub.ps1')).Path
$tokens = $null; $parseErrors = $null
$tree = [Management.Automation.Language.Parser]::ParseFile($launcherPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Launcher syntax errors.' }
foreach ($helper in $tree.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    . ([scriptblock]::Create($helper.Extent.Text))
}
function Assert-Discovery { param([bool]$Value, [string]$Message); if (-not $Value) { throw $Message } }
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('renthub-discovery-' + [guid]::NewGuid().ToString('N'))))
$files = @(); $folders = @()
function New-DiscoveryFixture {
    param([string]$Relative, [string]$Contents = '')
    $file = [IO.Path]::GetFullPath((Join-Path $fixtureRoot $Relative))
    Assert-Discovery ($file.StartsWith($fixtureRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) 'Fixture path stays within its private temporary directory.'
    $folder = Split-Path -Parent $file
    while ($folder -and $folder.StartsWith($fixtureRoot, [StringComparison]::OrdinalIgnoreCase) -and -not [IO.Directory]::Exists($folder)) {
        $script:folders += $folder; $folder = Split-Path -Parent $folder
    }
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $file))
    [IO.File]::WriteAllText($file, $Contents, [Text.UTF8Encoding]::new($false))
    $script:files += $file
    return $file
}
$previousHome = $env:ANDROID_HOME; $previousRoot = $env:ANDROID_SDK_ROOT; $previousLocal = $env:LOCALAPPDATA
try {
    $flutter = New-DiscoveryFixture 'Flutter SDK\bin\flutter.bat'
    Assert-Discovery ($null -eq (Get-RentHubFlutterDiscoveryCommand -FlutterPath $flutter)) 'An unprepared Flutter cache must not trigger downloads/bootstrap.'
    $dart = New-DiscoveryFixture 'Flutter SDK\bin\cache\dart-sdk\bin\dart.exe'
    $snapshot = New-DiscoveryFixture 'Flutter SDK\bin\cache\flutter_tools.snapshot'
    $command = Get-RentHubFlutterDiscoveryCommand -FlutterPath $flutter
    Assert-Discovery ($command.FilePath -eq $dart -and $command.Arguments[0] -eq $snapshot) 'Use the exact installed SDK cache and preserve paths with spaces.'
    Assert-Discovery ($null -eq (Get-RentHubFlutterDiscoveryCommand -FlutterPath 'missing-flutter.bat')) 'Missing Flutter is optional for ADB readiness.'
    $configuredAdb = New-DiscoveryFixture 'configured SDK\platform-tools\adb.exe'
    $homeAdb = New-DiscoveryFixture 'home SDK\platform-tools\adb.exe'
    $rootAdb = New-DiscoveryFixture 'root SDK\platform-tools\adb.exe'
    $pathAdb = New-DiscoveryFixture 'PATH SDK\platform-tools\adb.exe'
    $settings = New-DiscoveryFixture 'flutter-settings.json' (@{'android-sdk' = (Split-Path -Parent (Split-Path -Parent $configuredAdb))} | ConvertTo-Json -Compress)
    $env:ANDROID_HOME = Split-Path -Parent (Split-Path -Parent $homeAdb)
    $env:ANDROID_SDK_ROOT = Split-Path -Parent (Split-Path -Parent $rootAdb)
    $env:LOCALAPPDATA = Join-Path $fixtureRoot 'unused-local'
    & {
        function Get-Command { param($Name, $CommandType, $ErrorAction); return [pscustomobject]@{Source=$pathAdb} }
        Assert-Discovery ((Get-RentHubAdbPath -FlutterSettingsPath $settings) -eq $configuredAdb) 'Flutter SDK selection takes precedence over environment/PATH ADB.'
        [IO.File]::WriteAllText($settings, '{}')
        Assert-Discovery ((Get-RentHubAdbPath -FlutterSettingsPath $settings) -eq $homeAdb) 'ANDROID_HOME has Flutter-compatible precedence over ANDROID_SDK_ROOT.'
        $env:ANDROID_HOME = ''
        Assert-Discovery ((Get-RentHubAdbPath -FlutterSettingsPath $settings) -eq $rootAdb) 'ANDROID_SDK_ROOT remains supported.'
        $env:ANDROID_SDK_ROOT = ''
        [IO.File]::WriteAllText($settings, 'invalid private-test-value')
        Assert-Discovery ((Get-RentHubAdbPath -FlutterSettingsPath $settings) -eq $pathAdb) 'Malformed preferences fall back safely without rewriting user settings.'
        Assert-Discovery ([IO.File]::ReadAllText($settings) -eq 'invalid private-test-value') 'SDK settings are read-only.'
    }
    & {
        $script:toolCalls = @(); $script:toolTimeout = $false; $script:toolExit = 0
        function Invoke-RentHubNativeCommand {
            param($FilePath, [string[]]$Arguments, $TimeoutSeconds, [switch]$PreserveChildProcesses)
            Assert-Discovery ($FilePath -eq $dart -and $PreserveChildProcesses -and $TimeoutSeconds -le 12) 'Only the cached Flutter client runs, bounded and without killing a shared daemon.'
            $script:toolCalls += ,$Arguments
            return @{TimedOut=$script:toolTimeout;ExitCode=$script:toolExit;Output='private-test-value';Error='private-test-value'}
        }
        Assert-Discovery ((Initialize-RentHubFlutterDeviceDiscovery -FlutterPath $flutter) -eq 'flutter-refreshed') 'Flutter discovery can refresh the transport.'
        $receivedArguments = $script:toolCalls[0]
        Assert-Discovery (($receivedArguments[2..($receivedArguments.Length-1)] -join ' ') -eq 'devices --machine --device-timeout 4') 'Discovery runs only a bounded read-only devices command.'
        $script:toolTimeout=$true
        Assert-Discovery ((Initialize-RentHubFlutterDeviceDiscovery -FlutterPath $flutter) -eq 'flutter-discovery-timeout') 'A timed-out Flutter pass never claims readiness.'
        $script:toolTimeout=$false; $script:toolExit=1
        Assert-Discovery ((Initialize-RentHubFlutterDeviceDiscovery -FlutterPath $flutter) -eq 'flutter-discovery-failed') 'Flutter errors are classified without leaking raw output.'
    }
    & {
        $script:states = @('connected'); $script:checks=0; $script:adbRefresh=0; $script:flutterRefresh=0; $script:flutterResult='flutter-refreshed'; $script:flutterBudgets=@()
        function Sync-RentHubAndroidConnection {
            param($AdbPath,$TargetDevice,$HostPort,$TimeoutSeconds)
            Assert-Discovery ($AdbPath -eq 'fixture-adb' -and $TargetDevice -eq 'selected-phone') 'Discovery must never choose a different phone.'
            $state=$script:states[[Math]::Min($script:checks,$script:states.Count-1)];$script:checks++;return $state
        }
        function Initialize-RentHubAndroidDiscovery { param($AdbPath,$TimeoutSeconds);$script:adbRefresh++;return 'refreshed' }
        function Initialize-RentHubFlutterDeviceDiscovery {
            param($FlutterPath,$TimeoutSeconds)
            Assert-Discovery ($FlutterPath -eq $flutter -and $TimeoutSeconds -ge 1 -and $TimeoutSeconds -le 12) 'Warm-up stays within its allocated deadline.'
            $script:flutterRefresh++;$script:flutterBudgets+=$TimeoutSeconds;return $script:flutterResult
        }
        function Write-Host { param($Object,$ForegroundColor) }
        function Run-DiscoveryWait { param([int]$Timeout=30); Wait-RentHubAndroidConnection -AdbPath fixture-adb -TargetDevice selected-phone -HostPort 3004 -FlutterPath $flutter -TimeoutSeconds $Timeout -RetryIntervalMilliseconds 100 }
        Assert-Discovery ((Run-DiscoveryWait) -eq 'connected' -and $script:flutterRefresh -eq 0 -and $script:adbRefresh -eq 0) 'Already-ready phones have no discovery delay.'
        foreach($result in @('flutter-refreshed','flutter-discovery-timeout','flutter-discovery-failed','flutter-discovery-unavailable')) {
            $script:states=@('not-found','not-found','connected');$script:checks=0;$script:adbRefresh=0;$script:flutterRefresh=0;$script:flutterResult=$result
            Assert-Discovery ((Run-DiscoveryWait) -eq 'connected' -and $script:checks -eq 3 -and $script:adbRefresh -eq 1 -and $script:flutterRefresh -eq 1) 'An enumeration pass, including a failed one, must be followed by a successful selected-phone/forwarding check.'
        }
        foreach($state in @('unauthorized','forwarding-failed')) {
            $script:states=@($state,'connected');$script:checks=0;$script:adbRefresh=0;$script:flutterRefresh=0
            Assert-Discovery ((Run-DiscoveryWait) -eq 'connected' -and $script:flutterRefresh -eq 0 -and $script:adbRefresh -eq 0) 'Authorization/forwarding problems are not solved by starting extra discovery tools.'
        }
        $script:states=@('offline','offline','offline','connected');$script:checks=0;$script:flutterRefresh=0;$script:adbRefresh=0
        Assert-Discovery ((Run-DiscoveryWait) -eq 'connected' -and $script:flutterRefresh -eq 1) 'A slow connection runs Flutter discovery at most once.'
        $script:states=@('not-found','not-found','connected');$script:checks=0;$script:flutterRefresh=0;$script:adbRefresh=0;$script:flutterBudgets=@()
        Assert-Discovery ((Run-DiscoveryWait -Timeout 7) -eq 'connected' -and $script:flutterBudgets[0] -le 2) 'Five seconds are reserved for the final exact-device readiness check.'
        $script:states=@('not-found');$script:checks=0;$script:flutterRefresh=0;$script:adbRefresh=0;$script:flutterResult='flutter-refreshed'
        $clock=[Diagnostics.Stopwatch]::StartNew()
        Assert-Discovery ((Run-DiscoveryWait -Timeout 7) -eq 'not-found' -and $script:flutterRefresh -eq 1 -and $clock.Elapsed.TotalSeconds -lt 9) 'Listing other devices or refreshing Flutter never accepts a missing selected phone or exceeds the overall deadline.'
        foreach($state in @('adb-missing','invalid-device')) {
            $script:states=@($state);$script:checks=0;$script:flutterRefresh=0
            Assert-Discovery ((Run-DiscoveryWait) -eq $state -and $script:flutterRefresh -eq 0) 'Missing setup fails before running Flutter.'
        }
    }
    Write-Host 'PASS: SDK alignment, cached Flutter discovery, cold-start recovery, exact-device forwarding, authorization, timeout budgets and safe fallback.'
}
finally {
    $env:ANDROID_HOME=$previousHome;$env:ANDROID_SDK_ROOT=$previousRoot;$env:LOCALAPPDATA=$previousLocal
    foreach($file in $files) {
        Assert-Discovery ([IO.Path]::GetFullPath($file).StartsWith($fixtureRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) 'Cleanup stays within the fixture directory.'
        if([IO.File]::Exists($file)){[IO.File]::Delete($file)}
    }
    foreach($folder in ($folders | Select-Object -Unique | Sort-Object { $_.Length } -Descending)) {
        if([IO.Directory]::Exists($folder)){[IO.Directory]::Delete($folder)}
    }
}
