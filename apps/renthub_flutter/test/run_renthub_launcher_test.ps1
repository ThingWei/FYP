# Standalone PowerShell checks; no .env reads or real service startup/shutdown.
param([switch]$Integration)

$ErrorActionPreference = 'Stop'
$launcherPath = Join-Path $PSScriptRoot '..\run-renthub.ps1'
$tokens = $null
$parseErrors = $null
$tree = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $launcherPath).Path, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) { throw "Launcher syntax errors: $($parseErrors.Count)" }

# Load only these pure/testable helpers, not the launcher's executable body.
$helperNames = @('Test-RentHubAiCompatible', 'Test-RentHubApiReady', 'Get-RentHubAiArguments', 'Stop-RentHubOwnedAiProcess', 'Get-RentHubFirebaseDefines')
$helpers = $tree.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in $helperNames
}, $true)
if ($helpers.Count -ne $helperNames.Count) { throw 'Missing launcher helpers' }
foreach ($helper in $helpers) { . ([scriptblock]::Create($helper.Extent.Text)) }

function Assert-Launcher {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$googleFixture = [pscustomobject]@{
    project_info = [pscustomobject]@{ project_number = '123456'; project_id = 'demo-renthub' }
    client = @([pscustomobject]@{
        client_info = [pscustomobject]@{ mobilesdk_app_id = '1:123456:android:test'; android_client_info = [pscustomobject]@{ package_name = 'com.weith.renthub' } }
        api_key = @([pscustomobject]@{ current_key = 'public-test-client-key' })
    })
}
$firebaseArguments = @(Get-RentHubFirebaseDefines -FcmMode firebase -TargetDevice phone -Settings @{} -GoogleConfiguration $googleFixture)
Assert-Launcher ($firebaseArguments -contains '--dart-define=FIREBASE_ENABLED=true') 'Android FCM should be enabled with complete public settings'
Assert-Launcher ($firebaseArguments -contains '--dart-define=FIREBASE_PROJECT_ID=demo-renthub') 'Android config project'
$placeholderArguments = @(Get-RentHubFirebaseDefines -FcmMode firebase -TargetDevice phone -Settings @{ FIREBASE_ANDROID_API_KEY = 'YOUR_API_KEY'; FIREBASE_ANDROID_APP_ID = 'YOUR_APP_ID'; FIREBASE_MESSAGING_SENDER_ID = 'YOUR_SENDER_ID'; FIREBASE_PROJECT_ID = 'your-project-id' } -GoogleConfiguration $googleFixture)
Assert-Launcher ($placeholderArguments -contains '--dart-define=FIREBASE_APP_ID=1:123456:android:test') 'Android JSON replaces example client placeholders'
Assert-Launcher (-not (($firebaseArguments -join ' ') -match 'private_key|GOOGLE_APPLICATION_CREDENTIALS')) 'No server credentials in Flutter flags'
Assert-Launcher (@(Get-RentHubFirebaseDefines -FcmMode firebase -TargetDevice windows -Settings @{}).Count -eq 1) 'Windows FCM disabled'
Assert-Launcher (@(Get-RentHubFirebaseDefines -FcmMode disabled -TargetDevice phone -Settings @{})[0] -eq '--dart-define=FIREBASE_ENABLED=false') 'Explicit disabled FCM remains disabled'
$caught = $false
try { Get-RentHubFirebaseDefines -FcmMode firebase -TargetDevice phone -Settings @{} | Out-Null } catch { $caught = $true }
Assert-Launcher $caught 'Missing Android configuration should produce setup guidance'
$caught = $false
try { Get-RentHubFirebaseDefines -FcmMode firebase -TargetDevice phone -Settings @{ FIREBASE_PROJECT_ID = 'different-project' } -GoogleConfiguration $googleFixture | Out-Null } catch { $caught = $true }
Assert-Launcher $caught 'Mismatched Firebase project must fail clearly'

Assert-Launcher (-not (Test-RentHubAiCompatible $null)) 'Null health must fail'
Assert-Launcher (-not (Test-RentHubAiCompatible @{ status = 'ok' })) 'Old health must fail'
Assert-Launcher (-not (Test-RentHubAiCompatible @{
    status = 'ok'; document_frame_contract = 'opencv-document-yolo-v1'
})) 'Old contract must fail'
Assert-Launcher (-not (Test-RentHubAiCompatible @{
    status = 'error'; document_frame_contract = 'opencv-document-yolo-v6'
})) 'Unhealthy service must fail'
Assert-Launcher (Test-RentHubAiCompatible @{
    status = 'ok'; document_frame_contract = 'opencv-document-yolo-v6'; driving_licence_contract = 'malaysian-driving-ocr-v1'; recommendation_contract = 'hybrid-profile-v2'
}) 'Current contract must pass'

Assert-Launcher (-not (Test-RentHubAiCompatible @{
    status = 'ok'; document_frame_contract = 'opencv-document-yolo-v3'
})) 'Old heading-only scanner contract must fail'
Assert-Launcher (-not (Test-RentHubAiCompatible @{
    status = 'ok'; document_frame_contract = 'opencv-document-yolo-v4'
})) 'Scanner without enclosing-phone checks must fail'
Assert-Launcher (-not (Test-RentHubAiCompatible @{
    status = 'ok'; document_frame_contract = 'opencv-document-yolo-v5'
})) 'Scanner without replacement-front comparison must fail'

# Verify compatibility against the actual service constant, without importing models.
$contractSource = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot '..\..\..\services\ai\app\services\image_intelligence.py')
$serviceContract = [regex]::Match($contractSource, "DOCUMENT_FRAME_CONTRACT = '([^']+)'").Groups[1].Value
Assert-Launcher (-not [string]::IsNullOrWhiteSpace($serviceContract)) 'Service scanner contract must be discoverable'
$licenceSource = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot '..\..\..\services\ai\app\services\driving_licence.py')
$licenceContract = [regex]::Match($licenceSource, "CONTRACT = '([^']+)'").Groups[1].Value
$recommendationSource = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot '..\..\..\services\ai\app\services\recommendation.py')
$recommendationContract = [regex]::Match($recommendationSource, "CONTRACT = '([^']+)'").Groups[1].Value
Assert-Launcher (Test-RentHubAiCompatible @{ status = 'ok'; document_frame_contract = $serviceContract; driving_licence_contract = $licenceContract; recommendation_contract = $recommendationContract }) 'Launcher must accept current Python scanner, licence and recommendation contracts'
Assert-Launcher (-not (Test-RentHubAiCompatible @{ status = 'ok'; document_frame_contract = $serviceContract; driving_licence_contract = $licenceContract })) 'Missing profile-aware recommendation service must fail'
Assert-Launcher (-not (Test-RentHubAiCompatible @{ status = 'ok'; document_frame_contract = $serviceContract })) 'Missing licence contract must fail'
Assert-Launcher (-not (Test-RentHubAiCompatible @{ status = 'ok'; document_frame_contract = $serviceContract; driving_licence_contract = 'old' })) 'Old licence contract must fail'

Assert-Launcher (-not (Test-RentHubAiCompatible @{
    status = 'ok'; document_frame_contract = 'opencv-document-yolo-v2'
})) 'Geometry-only contract must fail'

# Mock readiness: these checks do not call the running API or read credentials.
$script:apiHealthFixture = @{ success = $true; data = @{ capabilities = @('product-catalog-v1') } }
function Invoke-RestMethod { param($Uri, $TimeoutSec); return $script:apiHealthFixture }
Assert-Launcher (-not (Test-RentHubApiReady)) 'Old API without capture validation must fail'
$script:apiHealthFixture.data.capabilities += 'mykad-capture-validation-v1'
Assert-Launcher (-not (Test-RentHubApiReady)) 'Old API without mandatory identity must fail'
$script:apiHealthFixture.data.capabilities += 'mandatory-identity-access-v1'
Assert-Launcher (-not (Test-RentHubApiReady)) 'Old API without listing maps and push status must fail'
$script:apiHealthFixture.data.capabilities += 'listing-maps-push-status-v1'
$script:apiHealthFixture.data.capabilities += 'precise-locations-v1'
Assert-Launcher (-not (Test-RentHubApiReady)) 'API without mandatory MyKad readability/pair checks must fail'
$script:apiHealthFixture.data.capabilities += 'mykad-readability-pair-v1'
Assert-Launcher (-not (Test-RentHubApiReady)) 'API without account binding and visual screening must fail'
$script:apiHealthFixture.data.capabilities += 'mykad-screen-account-binding-v1'
Assert-Launcher (-not (Test-RentHubApiReady)) 'API without current uploaded-pair checks must fail'
$script:apiHealthFixture.data.capabilities += 'mykad-current-draft-pair-v1'
Assert-Launcher (-not (Test-RentHubApiReady)) 'API without replacement-front scanner comparison must fail'
$script:apiHealthFixture.data.capabilities += 'mykad-bidirectional-capture-pair-v1'
Assert-Launcher (-not (Test-RentHubApiReady)) 'API without licence OCR review must fail'
$script:apiHealthFixture.data.capabilities += 'driving-licence-ocr-review-v1'
Assert-Launcher (-not (Test-RentHubApiReady)) 'API without recommendation feed must fail'
$script:apiHealthFixture.data.capabilities += 'recommendation-feed-v2'
Assert-Launcher (-not (Test-RentHubApiReady)) 'API without saved listing delivery fees must fail'
$script:apiHealthFixture.data.capabilities += 'listing-delivery-fees-v1'
Assert-Launcher (-not (Test-RentHubApiReady)) 'API without authorized notification targets must fail'
$script:apiHealthFixture.data.capabilities += 'notification-targets-v1'
Assert-Launcher (Test-RentHubApiReady) 'Current API must pass'
$script:apiHealthFixture.success = $false
Assert-Launcher (-not (Test-RentHubApiReady)) 'Unready API must fail'
Remove-Item Function:\Invoke-RestMethod

$reloadArguments = @(Get-RentHubAiArguments)
Assert-Launcher (($reloadArguments -join ' ') -eq
    '-m uvicorn app.main:app --host 127.0.0.1 --port 8001 --reload --reload-dir app') 'Default reload arguments'
$stableArguments = @(Get-RentHubAiArguments -DisableReload)
Assert-Launcher (($stableArguments -join ' ') -eq
    '-m uvicorn app.main:app --host 127.0.0.1 --port 8001') 'No-reload arguments'

if ($Integration) {
    # Disposable sleeping Python tree; never launches RentHub or binds its ports.
    $fixturePython = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\services\ai\.venv\Scripts\python.exe')).Path
    $ownedTree = Start-Process -FilePath $fixturePython -ArgumentList @(
        '-c', '"import subprocess,sys,time; subprocess.Popen([sys.executable, ''-c'', ''import time; time.sleep(90)'']); time.sleep(90)"'
    ) -WindowStyle Hidden -PassThru
    $ownedTreeStartedAt = $ownedTree.StartTime
    try {
        $fixtureIds = @($ownedTree.Id)
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            foreach ($parentId in @($fixtureIds)) {
                $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $parentId"
                foreach ($child in $children) {
                    if ($child.ProcessId -notin $fixtureIds) { $fixtureIds += $child.ProcessId }
                }
            }
            if ($fixtureIds.Count -ge 3) { break }
            Start-Sleep -Milliseconds 250
        }
        Assert-Launcher ($fixtureIds.Count -ge 3) 'Expected venv root, Python supervisor and child worker'
        Stop-RentHubOwnedAiProcess -OwnedProcess $ownedTree -StartedAt $ownedTreeStartedAt
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            $remaining = @(Get-Process -Id $fixtureIds -ErrorAction SilentlyContinue)
            if (-not $remaining.Count) { break }
            Start-Sleep -Milliseconds 250
        }
        Assert-Launcher (-not $remaining.Count) 'Owned supervisor/worker processes must all exit'
        Write-Host 'PASS: disposable owned Python process tree fully stopped.'
    }
    finally {
        Stop-RentHubOwnedAiProcess -OwnedProcess $ownedTree -StartedAt $ownedTreeStartedAt
    }
}

# Mock both process lookup and native tree termination. Never kill any real PID.
$ownedFixture = [System.Diagnostics.Process]::GetCurrentProcess()
$fixtureStartedAt = $ownedFixture.StartTime
$script:fixtureLookup = [pscustomobject]@{ StartTime = $fixtureStartedAt }
$script:killCalls = 0
$script:killArguments = @()
function Get-Process {
    [CmdletBinding()]
    param([int]$Id)
    Assert-Launcher ($Id -eq $ownedFixture.Id) 'Cleanup must target only its owned root'
    return $script:fixtureLookup
}
function taskkill.exe {
    $script:killCalls++
    $script:killArguments = @($args)
    $global:LASTEXITCODE = 0
}
Assert-Launcher ((Get-Command taskkill.exe).CommandType -eq 'Function') 'Native termination must be mocked'
Stop-RentHubOwnedAiProcess -OwnedProcess $ownedFixture -StartedAt $fixtureStartedAt
Assert-Launcher ($script:killCalls -eq 1) 'Owned tree must be terminated once'
Assert-Launcher (($script:killArguments -join ' ') -eq
    "/PID $($ownedFixture.Id) /T /F") 'Must terminate the verified root tree, never by image name'

$script:fixtureLookup = [pscustomobject]@{ StartTime = $fixtureStartedAt.AddMinutes(1) }
Stop-RentHubOwnedAiProcess -OwnedProcess $ownedFixture -StartedAt $fixtureStartedAt -WarningAction SilentlyContinue
Assert-Launcher ($script:killCalls -eq 1) 'Reused PID must never be stopped'
$script:fixtureLookup = $null
Stop-RentHubOwnedAiProcess -OwnedProcess $ownedFixture -StartedAt $fixtureStartedAt
Assert-Launcher ($script:killCalls -eq 1) 'Missing process must never be stopped'

Write-Host 'PASS: launcher syntax, AI compatibility, reload arguments and owned-tree cleanup guards.'
