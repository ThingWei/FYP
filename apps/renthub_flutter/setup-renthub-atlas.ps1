[CmdletBinding()]
param(
    [string]$AdminProfile = 'default',
    [string]$Profile = 'renthub-launcher',
    [switch]$Apply,
    [switch]$RenewSecret
)

$ErrorActionPreference = 'Stop'
# Import functions, not the executable startup section of the launcher.
$tokens = $null; $parseErrors = $null
$tree = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'run-renthub.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'The launcher contains syntax errors; setup was not started.' }
foreach ($helper in $tree.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    . ([scriptblock]::Create($helper.Extent.Text))
}
. (Join-Path $PSScriptRoot 'scripts\atlas-automation.ps1')

$null = Resolve-RentHubAtlasProfile -ExplicitProfile $AdminProfile -WasExplicit $true
if ($Profile -notmatch '^renthub-[a-zA-Z0-9_-]{1,48}$') { throw 'Use a dedicated renthub- automation profile name, without dots.' }
if ($AdminProfile -eq $Profile) { throw 'Use your separate administrator profile for setup; it will not be overwritten.' }
if ($RenewSecret -and -not $Apply) { throw 'Secret renewal requires -Apply. Run without switches for a read-only preview.' }
Assert-RentHubAtlasEnvironment
$atlas = Get-Command atlas -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $atlas) { throw 'Install MongoDB Atlas CLI and sign into an administrator profile once before setup.' }
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$apiDirectory = Join-Path $projectRoot 'services\api'
$environmentPath = Join-Path $apiDirectory '.env'
$uri = if ($env:MONGODB_URI) { $env:MONGODB_URI } else { Get-RentHubEnvironmentValue -Path $environmentPath -Name 'MONGODB_URI' }
$clusterHost = Get-RentHubAtlasHost -ConnectionString $uri
if (-not $clusterHost) { throw 'This setup is only for the existing configured Atlas SRV database. No connection string was displayed.' }
$projectId = Get-RentHubEnvironmentValue -Path $environmentPath -Name 'ATLAS_PROJECT_ID'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$sha = [Security.Cryptography.SHA256]::Create()
try { $tag = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("$env:COMPUTERNAME|$sid")))).Replace('-', '').Substring(0, 12).ToLowerInvariant() }
finally { $sha.Dispose() }
$accountName = "RentHub launcher $env:COMPUTERNAME $tag"
$mutex = [Threading.Mutex]::new($false, "Local\RentHubAtlasSetup_$tag")
$locked = $false
try {
    $locked = $mutex.WaitOne(0)
    if (-not $locked) { throw 'Another Atlas setup is already running for this laptop/Windows account.' }
    Write-Host 'Checking the configured project and RentHub-only organization...' -ForegroundColor Cyan
    $plan = Get-RentHubAtlasSetupPlan -AtlasPath $atlas.Source -ClusterHost $clusterHost -ProjectId $projectId -AdminProfile $AdminProfile -AccountName $accountName
    Write-Host 'Verified one organization project matching the configured RentHub cluster.' -ForegroundColor Green
    Write-Host 'Setup uses a dedicated per-laptop Network Access Manager account, a 365-day secret, and no administration-API IP restriction for that account.'
    Write-Host 'Database access remains limited to individual addresses registered by the launcher. Existing database network entries are preserved.'
    if (-not $Apply) {
        Write-Host 'PREVIEW ONLY: no settings, service accounts, credentials or files were changed. Run again with -Apply to finish the authorized setup.' -ForegroundColor Yellow
        return
    }
    Test-RentHubAtlasCredentialStore
    # Only a verified dedicated organization can reach this authorized mutation.
    Set-RentHubAtlasAutomationPolicy -AtlasPath $atlas.Source -AdminProfile $AdminProfile -Plan $plan
    $credential = New-RentHubAtlasAutomationCredential -AtlasPath $atlas.Source -AdminProfile $AdminProfile -Plan $plan -RenewSecret:$RenewSecret
    try {
        $expiry = if ($credential.Secret) { [datetimeoffset]::Parse($credential.Secret.expiresAt) } else {
            $latest = @($credential.Account.secrets | Sort-Object expiresAt -Descending | Select-Object -First 1)
            if ($latest.Count -ne 1) { throw 'Existing credential expiry could not be verified. Review the dedicated service account.' }
            [datetimeoffset]::Parse($latest[0].expiresAt)
        }
        if ($expiry -le [datetimeoffset]::UtcNow) { throw 'The saved automation secret is expired. Run setup again with -Apply -RenewSecret.' }
        Save-RentHubAtlasCliProfile -AtlasPath $atlas.Source -Profile $Profile -ProjectId $plan.ProjectId -OrgId $plan.OrgId -Credential $credential
    }
    finally {
        if ($credential.Secret) { $credential.Secret.secret = $null }
        foreach ($secret in @($credential.Account.secrets)) { if ($secret.PSObject.Properties.Name -contains 'secret') { $secret.secret = $null } }
    }
    # Verify the actual minimum-privilege credential, not the administrator profile.
    $null = Resolve-RentHubAtlasProject -AtlasPath $atlas.Source -Profile $Profile -ProjectId $plan.ProjectId -ClusterHost $clusterHost
    $null = Invoke-RentHubAtlasJson -AtlasPath $atlas.Source -Profile $Profile -Arguments @('accessLists', 'list', '--projectId', $plan.ProjectId, '--limit', '500')
    $access = Invoke-RentHubAtlasAdminJson -AtlasPath $atlas.Source -Profile $AdminProfile -Arguments @('api', 'serviceAccounts', 'listAccessList', '--groupId', $plan.ProjectId, '--clientId', $credential.Account.clientId, '--itemsPerPage', '500')
    if ($access.totalCount -ne 0 -or @($access.results).Count -ne 0) { throw 'Automation network freedom could not be confirmed. The launcher configuration was not switched.' }
    Set-RentHubAtlasEnvironmentSettings -Path $environmentPath -Profile $Profile -ProjectId $plan.ProjectId
    $receiptDirectory = Join-Path $apiDirectory '.data\atlas-automation'
    $null = New-Item -ItemType Directory -Path $receiptDirectory -Force
    $receipt = [ordered]@{ setupVersion = 1; status = 'configured'; deviceTag = $tag; profile = $Profile;
        projectId = $plan.ProjectId; organizationId = $plan.OrgId; clientId = $credential.Account.clientId;
        secretExpiresAt = $expiry.UtcDateTime.ToString('o'); configuredAt = [datetime]::UtcNow.ToString('o');
        role = 'GROUP_NETWORK_ACCESS_MANAGER'; credentialStorage = 'Windows Credential Manager';
        databaseAccess = 'individual temporary IPv4 entries'; secretsIncluded = $false }
    [IO.File]::WriteAllText((Join-Path $receiptDirectory "setup-$tag.json"), (ConvertTo-Json -InputObject $receipt), [Text.UTF8Encoding]::new($false))
    $expiryLabel = $expiry.ToOffset([timespan]::FromHours(8)).ToString('d MMM yyyy, h:mm tt', [Globalization.CultureInfo]::InvariantCulture)
    Write-Host "Atlas automation is configured on this laptop. Secret renewal due: $expiryLabel MYT." -ForegroundColor Green
    Write-Host 'Use your normal run-renthub.ps1 command. Run this setup separately on the other laptop; do not copy credential files.'
    if ($RenewSecret) { Write-Host 'The new secret is working. Retire the previous secret for this laptop account in Atlas after verifying normal startup.' -ForegroundColor Yellow }
}
finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
