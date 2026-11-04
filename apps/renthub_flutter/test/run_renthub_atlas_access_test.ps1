# No real Atlas requests, credentials, database access or process startup.
$ErrorActionPreference = 'Stop'
$launcherPath = Join-Path $PSScriptRoot '..\run-renthub.ps1'
$tokens = $null
$parseErrors = $null
$tree = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $launcherPath).Path, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) { throw 'Launcher syntax errors.' }
$helperNames = @('Get-RentHubAtlasHost', 'Invoke-RentHubAtlasJson', 'Resolve-RentHubAtlasProject', 'Get-RentHubPublicIPv4',
    'Sync-RentHubAtlasAccess', 'Test-RentHubAtlasDatabase', 'Wait-RentHubAtlasDatabase')
$helpers = $tree.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $helperNames
}, $true)
if ($helpers.Count -ne $helperNames.Count) { throw 'Missing Atlas helpers.' }
foreach ($helper in $helpers) { . ([scriptblock]::Create($helper.Extent.Text)) }
function Assert-Atlas {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
Assert-Atlas ((Get-RentHubAtlasHost 'mongodb+srv://user:private-test-value@demo.example.mongodb.net/renthub') -eq 'demo.example.mongodb.net') 'Extract only the Atlas hostname.'
Assert-Atlas ((Get-RentHubAtlasHost 'mongodb+srv://demo.example.mongodb.net') -eq 'demo.example.mongodb.net') 'Cluster metadata without credentials matches.'
Assert-Atlas ($null -eq (Get-RentHubAtlasHost 'mongodb://localhost:27017/renthub')) 'Local MongoDB is excluded.'
Assert-Atlas ($null -eq (Get-RentHubAtlasHost 'mongodb+srv://demo.mongodb.net.attacker.test/renthub')) 'A suffix lookalike is excluded.'

# Exercise the native CLI wrapper: private output must never appear in errors.
function Invoke-AtlasFixture {
    $script:nativeArguments = @($args)
    if ($script:nativeFail) { $global:LASTEXITCODE = 1; return 'private-test-value' }
    $global:LASTEXITCODE = 0
    return '{"results":[]}'
}
$script:nativeFail = $false
$null = Invoke-RentHubAtlasJson -AtlasPath Invoke-AtlasFixture -Arguments @('projects', 'list') -Profile fixture
Assert-Atlas (($script:nativeArguments -join ' ') -eq 'projects list --profile fixture --output json') 'CLI uses the requested profile and JSON output.'
$script:nativeFail = $true
$caught = $false
try { Invoke-RentHubAtlasJson -AtlasPath Invoke-AtlasFixture -Arguments @('projects', 'list') | Out-Null }
catch { $caught = $true; Assert-Atlas (-not $_.Exception.Message.Contains('private-test-value')) 'Raw CLI failures stay private.' }
Assert-Atlas $caught 'CLI failure stops registration.'
Remove-Item Function:\Invoke-AtlasFixture

$script:projectId = 'aaaaaaaaaaaaaaaaaaaaaaaa'
$script:clusterHost = 'demo.example.mongodb.net'
$script:currentIp = '203.0.113.7'
$script:entries = @()
$script:cliCalls = @()
$script:createRace = $false
$script:createFail = $false
function Invoke-RentHubAtlasJson {
    param($AtlasPath, [string[]]$Arguments, $Profile)
    $script:cliCalls += ,$Arguments
    switch ($Arguments[0]) {
        projects { return @{ results = @(@{ id = $script:projectId }) } }
        clusters { return @{ results = @(@{ connectionStrings = @{ standardSrv = "mongodb+srv://$script:clusterHost" } }) } }
        accessLists {
            if ($Arguments[1] -eq 'list') { return @{ results = $script:entries } }
            Assert-Atlas ($Arguments[1] -eq 'create') 'No existing entries may be deleted or changed.'
            if ($script:createRace) {
                $script:entries = @(@{ ipAddress = $script:currentIp })
                throw 'Concurrent duplicate registration'
            }
            if ($script:createFail) { throw 'Create failed' }
            $script:entries += @{ ipAddress = $Arguments[2] }
            return @{}
        }
    }
    throw 'Unexpected CLI command.'
}
function Invoke-RestMethod {
    param($Uri, $TimeoutSec, $ErrorAction)
    Assert-Atlas ($Uri -in @('https://checkip.amazonaws.com', 'https://api.ipify.org?format=json')) 'IP discovery sends no database credentials.'
    if ($Uri -eq 'https://checkip.amazonaws.com') {
        if ($script:useLookupFallback) { throw 'First lookup unavailable' }
        return $script:currentIp
    }
    return @{ ip = $script:currentIp }
}
Assert-Atlas ((Get-RentHubPublicIPv4) -eq '203.0.113.7') 'The primary IPv4 lookup is validated.'
$script:useLookupFallback = $true
Assert-Atlas ((Get-RentHubPublicIPv4) -eq '203.0.113.7') 'A second lookup service handles primary outages.'
$script:useLookupFallback = $false
Assert-Atlas ((Resolve-RentHubAtlasProject -AtlasPath fixture -ClusterHost $script:clusterHost) -eq $script:projectId) 'Discover the project owning the configured cluster.'
$script:cliCalls = @()
Assert-Atlas ((Resolve-RentHubAtlasProject -AtlasPath fixture -ClusterHost $script:clusterHost -ProjectId $script:projectId) -eq $script:projectId) 'An explicit project is still matched to the cluster.'
Assert-Atlas (-not @($script:cliCalls | Where-Object { $_[0] -eq 'projects' }).Count) 'Explicit project selection avoids listing all projects.'
$caught = $false
try { Resolve-RentHubAtlasProject -AtlasPath fixture -ClusterHost 'different.mongodb.net' | Out-Null } catch { $caught = $true }
Assert-Atlas $caught 'A different cluster cannot update this project.'
$script:cliCalls = @()
$caught = $false
try { Resolve-RentHubAtlasProject -AtlasPath fixture -ClusterHost $script:clusterHost -ProjectId 'invalid' | Out-Null } catch { $caught = $true }
Assert-Atlas ($caught -and $script:cliCalls.Count -eq 0) 'Reject malformed project IDs before CLI calls.'

$script:entries = @(@{ ipAddress = '198.51.100.4'; comment = 'Other laptop' })
$script:cliCalls = @()
Sync-RentHubAtlasAccess -AtlasPath fixture -ClusterHost $script:clusterHost
$creation = @($script:cliCalls | Where-Object { $_[0] -eq 'accessLists' -and $_[1] -eq 'create' })
Assert-Atlas ($creation.Count -eq 1) 'Register the new network once.'
Assert-Atlas ($creation[0][2] -eq '203.0.113.7') 'Only the current individual address is allowed.'
Assert-Atlas ($creation[0] -notcontains '0.0.0.0/0') 'Registration never creates an unrestricted rule.'
$expiry = [datetime]::Parse($creation[0][[array]::IndexOf($creation[0], '--deleteAfter') + 1]).ToUniversalTime()
Assert-Atlas (($expiry - [datetime]::UtcNow).TotalHours -gt 23.9 -and ($expiry - [datetime]::UtcNow).TotalHours -le 24) 'New access expires after one day.'
Assert-Atlas (@($script:entries | Where-Object ipAddress -eq '198.51.100.4').Count -eq 1) 'The other laptop is preserved.'
$script:cliCalls = @()
Sync-RentHubAtlasAccess -AtlasPath fixture -ClusterHost $script:clusterHost
Assert-Atlas (-not @($script:cliCalls | Where-Object { $_[1] -eq 'create' }).Count) 'Shared public IPs reuse the existing entry.'

$script:entries = @()
$script:createRace = $true
Sync-RentHubAtlasAccess -AtlasPath fixture -ClusterHost $script:clusterHost
Assert-Atlas ($script:entries.Count -eq 1) 'Concurrent registration from the same network is tolerated.'
$script:createRace = $false
$script:createFail = $true
$script:entries = @()
$caught = $false
try { Sync-RentHubAtlasAccess -AtlasPath fixture -ClusterHost $script:clusterHost } catch { $caught = $true }
Assert-Atlas $caught 'A failed registration cannot silently continue.'
$script:createFail = $false
foreach ($invalidIp in @('invalid', '::1', '203.0.113.7/0')) {
    $script:currentIp = $invalidIp
    $script:cliCalls = @()
    $caught = $false
    try { Sync-RentHubAtlasAccess -AtlasPath fixture -ClusterHost $script:clusterHost } catch { $caught = $true }
    Assert-Atlas $caught 'IP discovery must return an individual IPv4 address.'
    Assert-Atlas (-not @($script:cliCalls | Where-Object { $_[0] -eq 'accessLists' }).Count) 'Invalid IPs never reach the access list.'
}

# The real probe must pass JS through stdin safely on Windows PowerShell 5.1.
function Invoke-NodeFixture {
    $script:probeSource = $input -join [Environment]::NewLine
    $global:LASTEXITCODE = $script:probeExitCode
}
$originalLocation = (Get-Location).Path
$script:probeExitCode = 0
Assert-Atlas (Test-RentHubAtlasDatabase -NodePath Invoke-NodeFixture -ApiDirectory $PSScriptRoot) 'Successful database ping is accepted.'
Assert-Atlas ($script:probeSource.Contains('connection.db.command({ping:1})')) 'The preflight pings the database.'
Assert-Atlas ((Get-Location).Path -eq $originalLocation) 'The probe restores the caller directory.'
$script:probeExitCode = 1
Assert-Atlas (-not (Test-RentHubAtlasDatabase -NodePath Invoke-NodeFixture -ApiDirectory $PSScriptRoot)) 'Failed ping stops readiness.'
Remove-Item Function:\Invoke-NodeFixture

$script:probeAttempts = 0
$script:readyAfter = 3
function Test-RentHubAtlasDatabase { param($NodePath, $ApiDirectory); $script:probeAttempts++; return $script:probeAttempts -ge $script:readyAfter }
function Start-Sleep { param($Seconds) }
Wait-RentHubAtlasDatabase -NodePath fixture -ApiDirectory fixture
Assert-Atlas ($script:probeAttempts -eq 3) 'Database access propagation is retried.'
$script:probeAttempts = 0
$script:readyAfter = 99
$caught = $false
try { Wait-RentHubAtlasDatabase -NodePath fixture -ApiDirectory fixture } catch { $caught = $true }
Assert-Atlas ($caught -and $script:probeAttempts -eq 6) 'Unavailable databases have a bounded preflight.'
Assert-Atlas ($tree.Extent.Text.IndexOf('Sync-RentHubAtlasAccess -AtlasPath $atlasCommand.Source') -lt $tree.Extent.Text.IndexOf("Write-Host 'Starting the RentHub local blockchain...")) 'Atlas checks precede service startup.'
Write-Host 'PASS: Atlas project matching, private errors, narrow temporary access, duplicate networks, read-only probes and bounded startup checks.'
