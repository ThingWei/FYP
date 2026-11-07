param(
    [ValidateSet('pack', 'api', 'ai', 'flutter', 'blockchain', 'launcher')]
    [string[]]$Suites = @('pack', 'api', 'ai', 'flutter', 'blockchain', 'launcher'),
    [switch]$Builds,
    [switch]$LauncherIntegration,
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pythonPath = Join-Path $projectRoot 'services\ai\.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
    throw 'The AI Python environment is missing. Follow the README first-time setup; no environment was created or replaced.'
}
$testArguments = @((Join-Path $PSScriptRoot 'run_platform_tests.py'), '--suites') + $Suites
if ($Builds) { $testArguments += '--builds' }
if ($LauncherIntegration) { $testArguments += '--launcher-integration' }
if ($PrepareOnly) { $testArguments += '--prepare-only' }
& $pythonPath @testArguments
exit $LASTEXITCODE
