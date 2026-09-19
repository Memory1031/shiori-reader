# Build first: flutter build windows --profile --no-pub -t integration_test/desktop/restart_smoke.dart
# Then: ./integration_test/desktop/run_restart_smoke.ps1 -Executable ./build/windows/x64/runner/Profile/shiori.exe
# Restore the ordinary app afterward: flutter build windows --profile --no-pub -t lib/main.dart
param([Parameter(Mandatory = $true)][string]$Executable)

$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path -LiteralPath $Executable).Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runRoot = Join-Path $projectRoot ('.tooling/restart-runs/' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $runRoot 'restart-probe.owner'), 'shiori-desktop-restart')
$results = @()
$exitFailures = @()
Write-Output "Restart evidence: $runRoot"

foreach ($phase in @('plain', 'webview', 'webview-cycle', 'prepare', 'restart', 'killed')) {
    # This acceptance exercises the visible application startup/close flow.
    # CloseMainWindow cannot address a process launched with a hidden window.
    $probe = Start-Process -FilePath $exePath -WorkingDirectory (Split-Path -Parent $exePath) -ArgumentList @(('"' + $runRoot + '"'), $phase) -WindowStyle Normal -PassThru -RedirectStandardOutput (Join-Path $runRoot "$phase.stdout.log") -RedirectStandardError (Join-Path $runRoot "$phase.stderr.log")
    try {
        $reportPath = Join-Path $runRoot "$phase.json"
        $deadline = [DateTime]::UtcNow.AddSeconds(120)
        while (!(Test-Path -LiteralPath $reportPath)) {
            $probe.Refresh()
            if ($probe.HasExited) { throw "$phase exited before its report; inspect $runRoot" }
            if ([DateTime]::UtcNow -gt $deadline) { throw "$phase timed out; inspect $runRoot" }
            Start-Sleep -Milliseconds 250
        }
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        if ($report.pid -ne $probe.Id) { throw 'Report process identity mismatch' }
        if ($report.status -eq 'failed') { throw $report.error }
        if ($phase -eq 'restart') {
            if ($report.status -ne 'ready-to-kill') { throw 'Missing kill checkpoint' }
            $probe.Refresh()
            if ($probe.HasExited) { throw 'Kill phase must still have its live process/database' }
            Stop-Process -Id $probe.Id -Force
            if (!$probe.WaitForExit(10000)) { throw 'Process did not terminate' }
        } else {
            if ($report.status -ne 'passed') { throw 'Phase did not pass' }
            # Send the native window's close request, as with its titlebar X.
            if (!$probe.CloseMainWindow()) { throw 'Native close request was not sent' }
            if (!$probe.WaitForExit(15000)) { throw 'Normal application exit did not complete' }
            if ($probe.ExitCode -ne 0) {
                # Still inspect persistence in the next process, but never turn
                # a shutdown crash into a passing acceptance result.
                $exitFailures += "$phase exited with $($probe.ExitCode)"
            }
        }
        $report | Add-Member -NotePropertyName exitMode -NotePropertyValue $(if ($phase -eq 'restart') { 'forced' } else { 'window-close' })
        $report | Add-Member -NotePropertyName exitCode -NotePropertyValue $probe.ExitCode
        $results += $report
        $results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'results.json') -Encoding utf8
        Write-Output "$phase persistence PASS (PID $($probe.Id), exit $($probe.ExitCode))"
    } finally {
        $probe.Refresh()
        if (!$probe.HasExited) { Stop-Process -Id $probe.Id -Force }
        $probe.Dispose()
    }
}
if ($exitFailures.Count -gt 0) {
    throw "Persistence checks passed, but normal exit failed: $($exitFailures -join '; '). Inspect $runRoot"
}
Write-Output "DESKTOP_RESTART_PASS $runRoot"
