# Setup helpers only. Dot-sourcing this file never contacts Atlas or changes settings.
function Invoke-RentHubAtlasAdminJson {
    param([string]$AtlasPath, [string[]]$Arguments, [string]$Profile, [object]$Body)
    $inputText = if ($null -ne $Body) { ConvertTo-Json -InputObject $Body -Depth 12 -Compress } else { '' }
    $result = Invoke-RentHubNativeCommand -FilePath $AtlasPath -Arguments ($Arguments + @('--profile', $Profile, '--output', 'json')) -InputText $inputText -TimeoutSeconds 30
    if ($result.TimedOut) { throw 'Atlas setup request timed out. No automatic retry was made. Rerun the preview to check what was saved.' }
    if ($result.ExitCode -ne 0) {
        $info = Get-RentHubAtlasProfileInfo -AtlasPath $AtlasPath -Profile $Profile
        throw (Get-RentHubAtlasFailureMessage -Output ($result.Output + $result.Error) -Profile $Profile -AuthType $info.AuthType)
    }
    try { return ($result.Output | ConvertFrom-Json -ErrorAction Stop) }
    catch { throw 'Atlas setup returned an unexpected response. Inspect the setup state before retrying; private output was not printed.' }
}

function Assert-RentHubAtlasEnvironment {
    # These variables override CLI profile credentials/settings. Do not silently
    # use a different account, endpoint or file even when --profile is supplied.
    $conflicting = @(Get-ChildItem Env: | Where-Object {
        $_.Name -match '^(MONGODB_ATLAS|MCLI)_(CLIENT_ID|CLIENT_SECRET|PUBLIC_API_KEY|PRIVATE_API_KEY|ACCESS_TOKEN|REFRESH_TOKEN|ORG_ID|PROJECT_ID|BASE_URL|OPS_MANAGER_URL|AUTH_TYPE|SILENCE_STORAGE_WARNING)$' -and
        -not [string]::IsNullOrWhiteSpace($_.Value)
    })
    if ($conflicting.Count) { throw 'Atlas environment overrides are present. Remove the overriding Atlas authentication/endpoint variables from this terminal before setup; their values were not printed.' }
}

function Get-RentHubAtlasSetupPlan {
    param([string]$AtlasPath, [string]$ClusterHost, [string]$ProjectId, [string]$AdminProfile, [string]$AccountName)
    $resolved = Resolve-RentHubAtlasProject -AtlasPath $AtlasPath -ClusterHost $ClusterHost -ProjectId $ProjectId -Profile $AdminProfile
    $project = Invoke-RentHubAtlasAdminJson -AtlasPath $AtlasPath -Profile $AdminProfile -Arguments @('projects', 'describe', $resolved)
    $orgId = [string]$project.orgId
    if ($orgId -notmatch '^[a-fA-F0-9]{24}$') { throw 'Atlas did not supply a valid organization for this project.' }
    $groups = Invoke-RentHubAtlasAdminJson -AtlasPath $AtlasPath -Profile $AdminProfile -Arguments @('api', 'organizations', 'getOrgGroups', '--orgId', $orgId, '--itemsPerPage', '500')
    if ($groups.totalCount -ne 1 -or @($groups.results).Count -ne 1 -or $groups.results[0].id -ne $resolved) {
        throw 'Setup requires a RentHub-only organization containing exactly the matched project. No policy or credential changes were made.'
    }
    $settings = Invoke-RentHubAtlasAdminJson -AtlasPath $AtlasPath -Profile $AdminProfile -Arguments @('api', 'organizations', 'getOrgSettings', '--orgId', $orgId)
    if ($settings.PSObject.Properties.Name -notcontains 'apiAccessListRequired' -or $settings.apiAccessListRequired -isnot [bool]) {
        throw 'The organization automation-network policy could not be verified. Setup stopped without changing it.'
    }
    $accounts = Invoke-RentHubAtlasAdminJson -AtlasPath $AtlasPath -Profile $AdminProfile -Arguments @('api', 'serviceAccounts', 'listGroupServiceAccounts', '--groupId', $resolved, '--itemsPerPage', '500')
    if ($accounts.totalCount -gt @($accounts.results).Count) { throw 'Too many service accounts to verify safely in this bounded setup. No changes were made.' }
    $matches = @($accounts.results | Where-Object name -eq $AccountName)
    if ($matches.Count -gt 1) { throw 'More than one automation account has this laptop name. Review the duplicates before setup; no winner was chosen.' }
    $existing = if ($matches.Count -eq 1) { $matches[0] } else { $null }
    if ($existing) {
        if ($existing.clientId -notmatch '^mdb_sa_id_[a-fA-F0-9]{24}$' -or
            @($existing.roles).Count -ne 1 -or $existing.roles[0] -ne 'GROUP_NETWORK_ACCESS_MANAGER') {
            throw 'The existing laptop account has unexpected permissions. Setup will not repurpose or broaden it.'
        }
        $access = Invoke-RentHubAtlasAdminJson -AtlasPath $AtlasPath -Profile $AdminProfile -Arguments @('api', 'serviceAccounts', 'listAccessList', '--groupId', $resolved, '--clientId', $existing.clientId, '--itemsPerPage', '500')
        if ($access.totalCount -ne 0 -or @($access.results).Count -ne 0) { throw 'This automation account has administration-API IP restrictions. Review its setup; existing restrictions were not deleted.' }
    }
    return [pscustomobject]@{ ProjectId = $resolved; OrgId = $orgId; Settings = $settings; Existing = $existing; AccountName = $AccountName }
}

function Set-RentHubAtlasAutomationPolicy {
    param([string]$AtlasPath, [string]$AdminProfile, [object]$Plan)
    if ($Plan.Settings.apiAccessListRequired) {
        $updated = Invoke-RentHubAtlasAdminJson -AtlasPath $AtlasPath -Profile $AdminProfile -Arguments @('api', 'organizations', 'updateOrgSettings', '--orgId', $Plan.OrgId) -Body @{ apiAccessListRequired = $false }
        if ($updated.apiAccessListRequired -ne $false) { throw 'The automation-network policy change could not be confirmed. Setup stopped.' }
        # PATCH only the one authorized field; verify every returned prior field.
        foreach ($property in $Plan.Settings.PSObject.Properties) {
            if ($property.Name -ne 'apiAccessListRequired' -and
                ($updated.PSObject.Properties.Name -contains $property.Name) -and
                (ConvertTo-Json -InputObject $property.Value -Compress -Depth 8) -ne
                (ConvertTo-Json -InputObject $updated.($property.Name) -Compress -Depth 8)) {
                throw 'An unrelated organization setting changed during setup. Stop and review the organization before continuing.'
            }
        }
    }
}

function New-RentHubAtlasAutomationCredential {
    param([string]$AtlasPath, [string]$AdminProfile, [object]$Plan, [switch]$RenewSecret)
    if ($Plan.Existing) {
        if (-not $RenewSecret) { return [pscustomobject]@{ Account = $Plan.Existing; Secret = $null } }
        $secret = Invoke-RentHubAtlasAdminJson -AtlasPath $AtlasPath -Profile $AdminProfile -Arguments @('api', 'serviceAccounts', 'createGroupSecret', '--groupId', $Plan.ProjectId, '--clientId', $Plan.Existing.clientId) -Body @{ secretExpiresAfterHours = 8760 }
        return [pscustomobject]@{ Account = $Plan.Existing; Secret = $secret }
    }
    $account = Invoke-RentHubAtlasAdminJson -AtlasPath $AtlasPath -Profile $AdminProfile -Arguments @('api', 'serviceAccounts', 'createGroupServiceAccount', '--groupId', $Plan.ProjectId) -Body @{
        name = $Plan.AccountName; description = 'RentHub laptop launcher network registration';
        roles = @('GROUP_NETWORK_ACCESS_MANAGER'); secretExpiresAfterHours = 8760
    }
    if ($account.clientId -notmatch '^mdb_sa_id_[a-fA-F0-9]{24}$' -or
        @($account.roles).Count -ne 1 -or $account.roles[0] -ne 'GROUP_NETWORK_ACCESS_MANAGER' -or
        @($account.secrets).Count -ne 1) { throw 'Atlas returned an unexpected automation account. No credential output was printed; review the account before retrying.' }
    return [pscustomobject]@{ Account = $account; Secret = $account.secrets[0] }
}

function Initialize-RentHubAtlasCredentialStore {
    if ('RentHub.AtlasCredentialStore' -as [type]) { return }
    # Uses the official Atlas CLI/go-keyring Windows format:
    # target atlascli_PROFILE:PROPERTY, generic credential, UTF-8 blob.
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace RentHub {
  public static class AtlasCredentialStore {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct Credential {
      public uint Flags, Type;
      public string TargetName, Comment;
      public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
      public uint CredentialBlobSize;
      public IntPtr CredentialBlob;
      public uint Persist, AttributeCount;
      public IntPtr Attributes;
      public string TargetAlias, UserName;
    }
    [DllImport("advapi32.dll", EntryPoint="CredWriteW", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool WriteCredential(ref Credential value, uint flags);
    [DllImport("advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool ReadCredential(string target, uint type, uint flags, out IntPtr value);
    [DllImport("advapi32.dll", EntryPoint="CredDeleteW", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool DeleteCredential(string target, uint type, uint flags);
    [DllImport("advapi32.dll")] static extern void CredFree(IntPtr value);
    static string Target(string profile, string property) {
      if (!System.Text.RegularExpressions.Regex.IsMatch(profile, @"^renthub-[a-zA-Z0-9_-]{1,48}$") ||
          (property != "client_id" && property != "client_secret"))
        throw new InvalidOperationException("Invalid RentHub credential target.");
      return "atlascli_" + profile + ":" + property;
    }
    public static bool Exists(string profile, string property) {
      IntPtr value;
      if (ReadCredential(Target(profile, property), 1, 0, out value)) { CredFree(value); return true; }
      int code=Marshal.GetLastWin32Error();
      if (code==1168) return false;
      throw new InvalidOperationException("Windows credential store is unavailable (code " + code + ").");
    }
    public static void Save(string profile, string property, string secret) {
      byte[] bytes=Encoding.UTF8.GetBytes(secret ?? "");
      if(bytes.Length==0 || bytes.Length>2560) throw new InvalidOperationException("Invalid credential size.");
      IntPtr blob=Marshal.AllocHGlobal(bytes.Length);
      try {
        Marshal.Copy(bytes,0,blob,bytes.Length);
        Credential value=new Credential { Type=1, TargetName=Target(profile,property),
          UserName=property, CredentialBlobSize=(uint)bytes.Length, CredentialBlob=blob, Persist=2 };
        if(!WriteCredential(ref value,0)) throw new InvalidOperationException("Windows credential storage failed (code " + Marshal.GetLastWin32Error() + ").");
      } finally { for(int i=0;i<bytes.Length;i++) Marshal.WriteByte(blob,i,0); Marshal.FreeHGlobal(blob); Array.Clear(bytes,0,bytes.Length); }
    }
    public static void RemoveProbe(string profile, string property) {
      if(!profile.StartsWith("renthub-probe-")) throw new InvalidOperationException("Only disposable probe credentials can be removed.");
      if(!DeleteCredential(Target(profile,property),1,0) && Marshal.GetLastWin32Error()!=1168)
        throw new InvalidOperationException("Credential probe cleanup failed.");
    }
  }
}
'@ -ErrorAction Stop
}

function Test-RentHubAtlasCredentialStore {
    Initialize-RentHubAtlasCredentialStore
    $probe = 'renthub-probe-' + [guid]::NewGuid().ToString('N')
    try {
        [RentHub.AtlasCredentialStore]::Save($probe, 'client_id', 'nonsecret-storage-check')
        if (-not [RentHub.AtlasCredentialStore]::Exists($probe, 'client_id')) { throw 'The Windows credential probe could not be verified.' }
    }
    finally { [RentHub.AtlasCredentialStore]::RemoveProbe($probe, 'client_id') }
}

function Set-RentHubAtlasProfileAuthType {
    param([string]$Text, [string]$Profile)
    if ($Profile -notmatch '^renthub-[a-zA-Z0-9_-]{1,48}$') { throw 'Invalid dedicated automation profile.' }
    $pattern = '(?ms)^\[' + [regex]::Escape($Profile) + '\]\r?\n(?<body>.*?)(?=^\[|\z)'
    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -ne 1) { throw 'The generated Atlas CLI profile block could not be identified safely.' }
    $body = $matches[0].Groups['body'].Value
    if ($body -match '(?m)^\s*(?:client_secret|client_id)\s*=') { throw 'A plaintext credential exists in this profile. Review it before using automation; it was not displayed.' }
    $body = [regex]::Replace($body, '(?m)^\s*auth_type\s*=.*\r?\n?', '')
    $replacement = '[' + $Profile + "]`n  auth_type = 'service_account'`n" + $body
    return $Text.Substring(0, $matches[0].Index) + $replacement + $Text.Substring($matches[0].Index + $matches[0].Length)
}

function Save-RentHubAtlasCliProfile {
    param([string]$AtlasPath, [string]$Profile, [string]$ProjectId, [string]$OrgId, [object]$Credential)
    if ($Profile -notmatch '^renthub-[a-zA-Z0-9_-]{1,48}$') { throw 'Setup requires a dedicated renthub- profile name, without dots.' }
    Initialize-RentHubAtlasCredentialStore
    if ($Credential.Secret) {
        if ([string]::IsNullOrWhiteSpace($Credential.Secret.secret)) { throw 'The new secret is unavailable. It was not printed or saved to disk.' }
        [RentHub.AtlasCredentialStore]::Save($Profile, 'client_id', $Credential.Account.clientId)
        [RentHub.AtlasCredentialStore]::Save($Profile, 'client_secret', $Credential.Secret.secret)
        $Credential.Secret.secret = $null
    }
    if (-not [RentHub.AtlasCredentialStore]::Exists($Profile, 'client_id') -or
        -not [RentHub.AtlasCredentialStore]::Exists($Profile, 'client_secret')) {
        throw 'This laptop has no saved automation credential. Use -Apply -RenewSecret with the one-time administrator profile. Do not copy another laptop credential.'
    }
    # Only non-secret values go through argv. auth_type is not supported by
    # atlas config set, so update that one property in the generated TOML block.
    foreach ($pair in @(@('service', 'cloud'), @('org_id', $OrgId), @('project_id', $ProjectId), @('output', 'json'))) {
        $result = Invoke-RentHubNativeCommand -FilePath $AtlasPath -Arguments @('config', 'set', $pair[0], $pair[1], '--profile', $Profile) -TimeoutSeconds 10
        if ($result.TimedOut -or $result.ExitCode -ne 0 -or $result.Error -match '(?i)insecure storage') { throw 'Atlas CLI metadata could not be saved using secure storage. Credentials were not put in a file.' }
    }
    $path = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'atlascli\config.toml'
    $text = [IO.File]::ReadAllText($path)
    $updated = Set-RentHubAtlasProfileAuthType -Text $text -Profile $Profile
    [IO.File]::WriteAllText($path, $updated, [Text.UTF8Encoding]::new($false))
    $info = Get-RentHubAtlasProfileInfo -AtlasPath $AtlasPath -Profile $Profile
    if ($info.AuthType -ne 'service_account' -or $info.InsecureCredentials -or $info.ProjectId -ne $ProjectId -or $info.OrgId -ne $OrgId) {
        throw 'The dedicated Atlas profile could not be verified. Existing personal profiles were preserved.'
    }
}

function Set-RentHubAtlasEnvironmentSettings {
    param([string]$Path, [string]$Profile, [string]$ProjectId)
    if ($ProjectId -notmatch '^[a-fA-F0-9]{24}$') { throw 'Invalid Atlas project ID.' }
    $null = Resolve-RentHubAtlasProfile -ExplicitProfile $Profile -WasExplicit $true
    $text = [IO.File]::ReadAllText($Path)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    foreach ($key in @('ATLAS_PROFILE', 'ATLAS_PROJECT_ID')) { $text = [regex]::Replace($text, '(?m)^' + $key + '=.*(?:\r?\n|$)', '') }
    $text = $text.TrimEnd("`r", "`n") + $newline + "ATLAS_PROFILE=$Profile" + $newline + "ATLAS_PROJECT_ID=$ProjectId" + $newline
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}
