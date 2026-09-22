param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('write', 'read')]
  [string]$Phase,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9_-]{1,40}$')]
  [string]$RunId,

  [string]$ApiBaseUrl = 'http://localhost:3000/api/v1',
  [string]$SocketUrl = 'http://localhost:3000',
  [switch]$SkipPreflight
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$apiDirectory = Join-Path $projectRoot 'services/api'
$flutterDirectory = Join-Path $projectRoot 'apps/renthub_flutter'

$tokenNames = @(
  'RENTHUB_E2E_OWNER_TOKEN',
  'RENTHUB_E2E_RENTER_TOKEN',
  'RENTHUB_E2E_ADMIN_TOKEN'
)
$providedTokenCount = @(
  $tokenNames | Where-Object { -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_)) }
).Count
if ($providedTokenCount -ne 0 -and $providedTokenCount -ne $tokenNames.Count) {
  throw 'Set all three RENTHUB_E2E_*_TOKEN environment variables, or leave all three unset for mock authentication.'
}

if (-not $SkipPreflight) {
  Push-Location $apiDirectory
  try {
    npm.cmd run preflight:production
    if ($LASTEXITCODE -ne 0) { throw 'Production preflight failed.' }
  }
  finally {
    Pop-Location
  }
}

Push-Location $flutterDirectory
try {
  flutter test test/live_mongodb_e2e_test.dart `
    --dart-define=USE_MOCKS=false `
    --dart-define=LIVE_E2E_PHASE=$Phase `
    --dart-define=LIVE_E2E_RUN_ID=$RunId `
    --dart-define=API_BASE_URL=$ApiBaseUrl `
    --dart-define=SOCKET_URL=$SocketUrl
  if ($LASTEXITCODE -ne 0) { throw "Live E2E $Phase phase failed." }
}
finally {
  Pop-Location
}

Write-Host "RentHub live E2E $Phase phase passed for run '$RunId'."
