# Disposable native console fixtures only; no Flutter app, phone, .env or services.
param([switch]$Integration, [switch]$KeyProbe)
$ErrorActionPreference = 'Stop'
$launcherPath = Join-Path $PSScriptRoot '..\run-renthub.ps1'
$tokens = $null; $errors = $null
$tree = [Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $launcherPath).Path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Launcher syntax errors.' }
foreach ($helper in $tree.FindAll({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in @('ConvertTo-RentHubProcessArguments', 'Invoke-RentHubFlutterConsole', 'Stop-RentHubOwnedApiProcess')
}, $true)) { . ([scriptblock]::Create($helper.Extent.Text)) }

function Assert-Terminal {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

if (-not $Integration -and -not $KeyProbe) {
    Write-Host 'PASS: terminal helper syntax. Use -Integration for native fixtures, or -KeyProbe in an interactive terminal.'
    return
}
if ($KeyProbe -and [Console]::IsInputRedirected) {
    throw 'KeyProbe requires an interactive PowerShell terminal, without redirected input.'
}
$node = (Get-Command node -CommandType Application | Select-Object -First 1).Source
$fixtureDirectory = Join-Path ([IO.Path]::GetTempPath()) ('renthub-console-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixtureDirectory)
$fixtureScript = Join-Path $fixtureDirectory 'console.cjs'
$fixtureBatch = Join-Path $fixtureDirectory 'flutter fixture.cmd'
$inputPath = Join-Path $fixtureDirectory 'empty-input.txt'
$utf8 = [Text.UTF8Encoding]::new($false)
$source = @'
const fs = require('node:fs');
const path = require('node:path');
const save = (name, value) => fs.writeFileSync(path.join(__dirname, name), JSON.stringify(value));
if (process.argv.includes('--background')) {
  let received = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', input => received += input);
  process.stdin.on('end', () => { save('background.json', {eof: true, received}); process.exit(0); });
  process.stdin.resume();
} else if (process.argv.includes('--watch-server')) {
  save('watch.json', {ready: true});
  setInterval(() => {}, 1000);
} else if (process.argv.includes('--keys')) {
  const keys = [];
  console.log('KEY_FIXTURE_READY tty=' + !!process.stdin.isTTY + ' - press r, R, then q');
  if (process.stdin.isTTY) process.stdin.setRawMode(true);
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', input => {
    for (const key of input) {
      if (['r', 'R', 'q'].includes(key)) { keys.push(key); console.log('KEY_RECEIVED:' + key); }
      if (key === 'q') {
        save('keys.json', {tty: !!process.stdin.isTTY, keys});
        if (process.stdin.isTTY) process.stdin.setRawMode(false);
        process.exit(0);
      }
      if (key.charCodeAt(0) === 3) {
        if (process.stdin.isTTY) process.stdin.setRawMode(false);
        process.exit(130);
      }
    }
  });
} else {
  save('arguments.json', process.argv.slice(2));
  process.exit(7);
}
'@
try {
    [IO.File]::WriteAllText($fixtureScript, $source, $utf8)
    [IO.File]::WriteAllText($fixtureBatch, "@echo off`r`nchcp 65001 >nul`r`n`"$node`" `"%~dp0console.cjs`" %*`r`n", $utf8)
    [IO.File]::WriteAllBytes($inputPath, [byte[]]@())
    if ($Integration) {
        $arguments = @('run', '-d', 'fixture-phone', 'label with spaces',
            'https://example.invalid/callback?a=1&b=2', 'C:\folder with spaces\',
            'quote"inside', '', ('Unicode-' + [char]0x4e2d + [char]0x6587))
        $exitCode = Invoke-RentHubFlutterConsole -FlutterPath $fixtureBatch -WorkingDirectory $fixtureDirectory -Arguments $arguments
        Assert-Terminal ($exitCode -eq 7) 'The interactive child exit code must be preserved.'
        $received = Get-Content -LiteralPath (Join-Path $fixtureDirectory 'arguments.json') -Encoding UTF8 -Raw | ConvertFrom-Json
        Assert-Terminal ($received.Count -eq $arguments.Count) 'Console handoff must preserve every argument.'
        for ($i = 0; $i -lt $arguments.Count; $i++) {
            Assert-Terminal ($received[$i] -ceq $arguments[$i]) 'Console handoff must preserve spaces, quotes, Unicode, empty values, URL ampersands and trailing backslashes.'
        }
        $background = Start-Process -FilePath $node `
            -ArgumentList (ConvertTo-RentHubProcessArguments -Arguments @($fixtureScript, '--background')) `
            -WindowStyle Hidden -RedirectStandardInput $inputPath -PassThru
        $null = $background.Handle
        try {
            Assert-Terminal ($background.WaitForExit(5000)) 'A background child must receive EOF promptly.'
            Assert-Terminal ($background.ExitCode -eq 0) 'Background input isolation must succeed.'
            $result = Get-Content -LiteralPath (Join-Path $fixtureDirectory 'background.json') -Raw | ConvertFrom-Json
            Assert-Terminal ($result.eof -and $result.received.Length -eq 0) 'Background children must not receive terminal keys.'
        }
        finally {
            if (-not $background.HasExited) { $background.Kill(); $null = $background.WaitForExit(2000) }
            $background.Dispose()
        }
        $watcher = Start-Process -FilePath $node `
            -ArgumentList (ConvertTo-RentHubProcessArguments -Arguments @('--watch', $fixtureScript, '--watch-server')) `
            -WindowStyle Hidden -RedirectStandardInput $inputPath `
            -RedirectStandardOutput (Join-Path $fixtureDirectory 'watch.log') `
            -RedirectStandardError (Join-Path $fixtureDirectory 'watch-error.log') -PassThru
        $null = $watcher.Handle
        $watcherStarted = $watcher.StartTime
        try {
            $ready = Join-Path $fixtureDirectory 'watch.json'
            for ($attempt = 0; $attempt -lt 40 -and -not (Test-Path -LiteralPath $ready) -and -not $watcher.HasExited; $attempt++) {
                Start-Sleep -Milliseconds 100
            }
            Assert-Terminal ((Test-Path -LiteralPath $ready) -and -not $watcher.HasExited) 'Node development watch must stay running when background stdin is closed.'
        }
        finally {
            Stop-RentHubOwnedApiProcess -OwnedProcess $watcher -StartedAt $watcherStarted
            $null = $watcher.WaitForExit(2000)
            $watcher.Dispose()
        }
        Write-Host 'PASS: inherited console launch, batch arguments, exit codes and background EOF isolation.'
        Write-Host 'PASS: background Node development watcher remains alive without terminal input.'
    }
    if ($KeyProbe) {
        $exitCode = Invoke-RentHubFlutterConsole -FlutterPath $fixtureBatch -WorkingDirectory $fixtureDirectory -Arguments @('--keys')
        Assert-Terminal ($exitCode -eq 0) 'Interactive fixture must exit normally on q.'
        $result = Get-Content -LiteralPath (Join-Path $fixtureDirectory 'keys.json') -Raw | ConvertFrom-Json
        Assert-Terminal ($result.tty -and ($result.keys -join ',') -ceq 'r,R,q') 'The inherited terminal must deliver r, R and q in order.'
        Write-Host 'PASS: real terminal delivered r, R and q to the child process.'
    }
}
finally {
    # Only these known, newly created fixture files; no recursive deletion.
    foreach ($name in @('console.cjs', 'flutter fixture.cmd', 'empty-input.txt', 'arguments.json', 'background.json', 'keys.json', 'watch.json', 'watch.log', 'watch-error.log')) {
        $path = Join-Path $fixtureDirectory $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    [IO.Directory]::Delete($fixtureDirectory)
}
