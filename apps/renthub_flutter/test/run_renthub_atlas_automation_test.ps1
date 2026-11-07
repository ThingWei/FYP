param([switch]$Integration)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tokens = $null; $errors = $null
$tree = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'run-renthub.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Launcher syntax errors.' }
foreach ($function in $tree.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $true)) {
    . ([scriptblock]::Create($function.Extent.Text))
}
. (Join-Path $root 'scripts\atlas-automation.ps1')
function Assert-Automation { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw $Message } }
function Assert-Fails { param([scriptblock]$Action, [string]$Expected); $caught=$false; try { & $Action | Out-Null } catch { $caught=$true; Assert-Automation ($_.Exception.Message.Contains($Expected)) "Expected safe failure: $Expected"; Assert-Automation (-not $_.Exception.Message.Contains('private-test-value')) 'Never print private values.' }; Assert-Automation $caught 'Operation must fail closed.' }

Assert-Automation ((Resolve-RentHubAtlasProfile -WasExplicit $false) -eq 'default') 'Preserve the legacy default.'
Assert-Automation ((Resolve-RentHubAtlasProfile -WasExplicit $false -ConfiguredProfile 'renthub-launcher') -eq 'renthub-launcher') 'Read the private environment profile.'
Assert-Automation ((Resolve-RentHubAtlasProfile -WasExplicit $true -ExplicitProfile 'named' -ConfiguredProfile 'renthub-launcher') -eq 'named') 'An explicit parameter wins.'
foreach ($invalid in @('', '../outside', 'bad profile', '-flag', '.hidden', "bad`nvalue", ('a' * 65))) {
    Assert-Fails { Resolve-RentHubAtlasProfile -WasExplicit $true -ExplicitProfile $invalid } 'ATLAS_PROFILE'
}
foreach ($fixture in @(
    @{raw='401 Unauthorized private-test-value';type='service_account';part='Atlas automation could not authenticate'},
    @{raw='401 Unauthorized private-test-value';type='';part='Atlas automation could not authenticate'},
    @{raw='invalid_client private-test-value';type='service_account';part='invalid, expired or revoked'},
    @{raw='IP_ADDRESS_NOT_ON_ACCESS_LIST private-test-value';type='service_account';part='one-time'},
    @{raw='403 Forbidden private-test-value';type='service_account';part='access was denied'},
    @{raw='TLS timeout private-test-value';type='service_account';part='could not reach Atlas'},
    @{raw='profile does not exist private-test-value';type='service_account';part='Complete setup-renthub-atlas'},
    @{raw="you don't have a profile named private-test-value";type='';part='Complete setup-renthub-atlas'}
)) {
    $message=Get-RentHubAtlasFailureMessage -Output $fixture.raw -Profile renthub-launcher -AuthType $fixture.type
    Assert-Automation ($message.Contains($fixture.part) -and -not $message.Contains('private-test-value')) 'Classify errors without echoing private diagnostics.'
    if($fixture.type -eq 'service_account') { Assert-Automation (-not $message.Contains("Run 'atlas auth login")) 'No personal-login fallback for automation.' }
}
Assert-Automation ((Get-RentHubAtlasFailureMessage -Output '401 Unauthorized' -Profile default -AuthType user_account).Contains('atlas auth login')) 'Legacy personal profiles retain their recovery guidance.'

$savedOverride=$env:MONGODB_ATLAS_CLIENT_SECRET
try { $env:MONGODB_ATLAS_CLIENT_SECRET='private-test-value'; Assert-Fails { Assert-RentHubAtlasEnvironment } 'environment overrides' }
finally { $env:MONGODB_ATLAS_CLIENT_SECRET=$savedOverride }

$personalBlock="[default]`r`n  auth_type = 'user_account'`r`n  project_id = 'personal'`r`n`r`n"
$otherBlock="[another]`r`n  project_id = 'separate'`r`n"
$profileText=$personalBlock+"[renthub-launcher]`r`n  output = 'json'`r`n`r`n"+$otherBlock
$profileUpdated=Set-RentHubAtlasProfileAuthType -Text $profileText -Profile renthub-launcher
Assert-Automation ($profileUpdated.StartsWith($personalBlock) -and $profileUpdated.EndsWith($otherBlock)) 'Unrelated personal/profile metadata remains byte-for-byte unchanged.'
Assert-Automation ($profileUpdated -eq (Set-RentHubAtlasProfileAuthType -Text $profileUpdated -Profile renthub-launcher)) 'Auth-type metadata updates are idempotent.'
Assert-Fails { Set-RentHubAtlasProfileAuthType -Text "[renthub-launcher]`nclient_secret = 'private-test-value'`n" -Profile renthub-launcher } 'plaintext credential'
Assert-Fails { Set-RentHubAtlasProfileAuthType -Text ($profileText+"[renthub-launcher]`n") -Profile renthub-launcher } 'identified safely'
Assert-Fails { Set-RentHubAtlasProfileAuthType -Text $personalBlock -Profile renthub-launcher } 'identified safely'

$script:secretMarker='private-test-value'
function Invoke-RentHubNativeCommand {
    param($FilePath,$Arguments,$InputText,$TimeoutSeconds)
    $script:arguments=$Arguments; $script:input=$InputText
    if($Arguments[0] -eq 'config'){ return @{ExitCode=0;TimedOut=$false;Output=(@{auth_type='service_account';client_secret=$script:secretMarker;org_id='a';project_id='b'}|ConvertTo-Json);Error=''} }
    return @{ExitCode=0;TimedOut=$false;Output='{"ok":true}';Error=''}
}
$info=Get-RentHubAtlasProfileInfo -AtlasPath fixture -Profile renthub-launcher
Assert-Automation ($info.AuthType -eq 'service_account' -and $info.InsecureCredentials) 'Detect plaintext fallback without returning the secret.'
Assert-Automation (-not (ConvertTo-Json $info).Contains('private-test-value')) 'Profile information is a safe projection.'
$script:secretMarker='[redacted - source: secure storage]'
Assert-Automation (-not (Get-RentHubAtlasProfileInfo -AtlasPath fixture -Profile renthub-launcher).InsecureCredentials) 'Secure redaction markers are not plaintext secrets.'
$script:secretMarker='[redacted - source: config file]'
Assert-Automation (Get-RentHubAtlasProfileInfo -AtlasPath fixture -Profile renthub-launcher).InsecureCredentials 'Insecure redaction markers must fail closed.'
$null=Invoke-RentHubAtlasAdminJson -AtlasPath fixture -Profile personal -Arguments @('api','serviceAccounts','createGroupServiceAccount') -Body @{name='Laptop';secretExpiresAfterHours=8760}
Assert-Automation ($script:arguments -notcontains '--file' -and ($script:input|ConvertFrom-Json).secretExpiresAfterHours -eq 8760) 'JSON requests travel through stdin, not temporary files.'
Remove-Item Function:\Invoke-RentHubNativeCommand

$script:group='aaaaaaaaaaaaaaaaaaaaaaaa'; $script:org='bbbbbbbbbbbbbbbbbbbbbbbb'
$script:groupCount=1; $script:policy=$true; $script:existing=@(); $script:restricted=$false; $script:calls=@()
function Resolve-RentHubAtlasProject { param($AtlasPath,$ClusterHost,$ProjectId,$Profile); return $script:group }
function Invoke-RentHubAtlasAdminJson {
    param($AtlasPath,$Arguments,$Profile,$Body)
    $script:calls += ,@{args=$Arguments;body=$Body;profile=$Profile}
    if($Arguments[0] -eq 'projects'){return [pscustomobject]@{id=$script:group;orgId=$script:org}}
    switch($Arguments[2]) {
        getOrgGroups { return [pscustomobject]@{totalCount=$script:groupCount;results=@([pscustomobject]@{id=$script:group})} }
        getOrgSettings { return [pscustomobject]@{apiAccessListRequired=$script:policy;multiFactorAuthRequired=$true} }
        listGroupServiceAccounts { return [pscustomobject]@{totalCount=$script:existing.Count;results=$script:existing} }
        listAccessList { if($script:restricted){return [pscustomobject]@{totalCount=1;results=@(@{ipAddress='203.0.113.7'})}}; return [pscustomobject]@{totalCount=0;results=@()} }
        updateOrgSettings { Assert-Automation ($Body.Keys.Count -eq 1 -and $Body.apiAccessListRequired -eq $false) 'Only the approved policy field is patched.';return [pscustomobject]@{apiAccessListRequired=$false;multiFactorAuthRequired=$true} }
        createGroupServiceAccount { return [pscustomobject]@{clientId=('mdb_sa_id_'+('c'*24));roles=@('GROUP_NETWORK_ACCESS_MANAGER');secrets=@([pscustomobject]@{id=('d'*24);secret='private-test-value';expiresAt='2027-11-06T00:00:00Z'})} }
        createGroupSecret { return [pscustomobject]@{id=('e'*24);secret='private-test-value';expiresAt='2027-11-06T00:00:00Z'} }
    }
    throw 'Unexpected Atlas setup command.'
}
$plan=Get-RentHubAtlasSetupPlan -AtlasPath fixture -ClusterHost demo.mongodb.net -AdminProfile personal -AccountName 'Laptop'
Assert-Automation ($plan.ProjectId -eq $script:group -and -not $plan.Existing) 'Preview identifies the configured project.'
Assert-Automation (-not @($script:calls | Where-Object {$_.args[2] -match 'create|update|delete'}).Count) 'Preview performs no writes.'
$script:groupCount=2
Assert-Fails { Get-RentHubAtlasSetupPlan -AtlasPath fixture -ClusterHost demo.mongodb.net -AdminProfile personal -AccountName 'Laptop' } 'RentHub-only organization'
$script:groupCount=1
Set-RentHubAtlasAutomationPolicy -AtlasPath fixture -AdminProfile personal -Plan $plan
$credential=New-RentHubAtlasAutomationCredential -AtlasPath fixture -AdminProfile personal -Plan $plan
$created=@($script:calls|Where-Object {$_.args[2] -eq 'createGroupServiceAccount'})
Assert-Automation ($created.Count -eq 1 -and $created[0].body.roles.Count -eq 1 -and $created[0].body.roles[0] -eq 'GROUP_NETWORK_ACCESS_MANAGER') 'Use only the network-manager role.'
Assert-Automation ($created[0].body.secretExpiresAfterHours -eq 8760) 'Request 365 days explicitly, without silently lowering it.'
$script:existing=@([pscustomobject]@{name='Laptop';clientId=('mdb_sa_id_'+('c'*24));roles=@('GROUP_NETWORK_ACCESS_MANAGER');secrets=@(@{expiresAt='2027-11-06T00:00:00Z'})})
$plan=Get-RentHubAtlasSetupPlan -AtlasPath fixture -ClusterHost demo.mongodb.net -AdminProfile personal -AccountName 'Laptop'
$script:calls=@()
$reused=New-RentHubAtlasAutomationCredential -AtlasPath fixture -AdminProfile personal -Plan $plan
Assert-Automation ($null -eq $reused.Secret -and $script:calls.Count -eq 0) 'Repeated setup reuses the account without creating another secret.'
$null=New-RentHubAtlasAutomationCredential -AtlasPath fixture -AdminProfile personal -Plan $plan -RenewSecret
Assert-Automation ($script:calls.Count -eq 1 -and $script:calls[0].args[2] -eq 'createGroupSecret') 'Renewal requires the explicit switch and does not delete old secrets.'
$script:restricted=$true
Assert-Fails { Get-RentHubAtlasSetupPlan -AtlasPath fixture -ClusterHost demo.mongodb.net -AdminProfile personal -AccountName 'Laptop' } 'existing restrictions were not deleted'
$script:restricted=$false
$script:existing[0].roles=@('GROUP_OWNER')
Assert-Fails { Get-RentHubAtlasSetupPlan -AtlasPath fixture -ClusterHost demo.mongodb.net -AdminProfile personal -AccountName 'Laptop' } 'unexpected permissions'
$script:existing[0].roles=@('GROUP_NETWORK_ACCESS_MANAGER'); $script:existing += $script:existing[0]
Assert-Fails { Get-RentHubAtlasSetupPlan -AtlasPath fixture -ClusterHost demo.mongodb.net -AdminProfile personal -AccountName 'Laptop' } 'More than one'

$temporary=Join-Path ([IO.Path]::GetTempPath()) ('RentHubAtlasTest-'+[guid]::NewGuid().ToString('N')+'.env')
try {
    [IO.File]::WriteAllText($temporary,"PASSWORD=private-test-value`r`nMONGODB_URI=unchanged`r`nATLAS_PROFILE=old`r`nATLAS_PROJECT_ID=old`r`n")
    Set-RentHubAtlasEnvironmentSettings -Path $temporary -Profile renthub-launcher -ProjectId $script:group
    $first=[IO.File]::ReadAllText($temporary)
    Set-RentHubAtlasEnvironmentSettings -Path $temporary -Profile renthub-launcher -ProjectId $script:group
    Assert-Automation ($first -eq [IO.File]::ReadAllText($temporary)) 'Configuration update is idempotent.'
    Assert-Automation ($first.Contains("PASSWORD=private-test-value`r`nMONGODB_URI=unchanged`r`n")) 'Application secrets and database settings remain byte-for-byte unchanged.'
    Assert-Automation ([regex]::Matches($first,'(?m)^ATLAS_PROFILE=').Count -eq 1) 'Only one selected profile setting is retained.'
}
finally { if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary} }

if($Integration) {
    Test-RentHubAtlasCredentialStore
    Write-Host 'PASS: disposable Windows credential-store probe was saved, found and removed.'
}
Write-Host 'PASS: profile precedence, safe diagnostics, environment isolation, dedicated-organization guards, narrow roles, secret lifetime, reuse/renewal and private configuration preservation.'
