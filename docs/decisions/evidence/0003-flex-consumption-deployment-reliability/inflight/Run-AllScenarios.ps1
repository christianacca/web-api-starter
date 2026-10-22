$s = "$env:TEMP\opencode\inflight\Invoke-InflightScenario.ps1"
# the scenarios that need no upload go first
$plan = @(
    @{ Scenario = 'Restart';   Args = @{ } },
    @{ Scenario = 'StopStart'; Args = @{ } },
    # longer jobs for the deployment, so that an upload of a couple of minutes still lands while they are running
    @{ Scenario = 'Deploy';    Args = @{ QueueJobSeconds = 420; SettleTimeoutMinutes = 30 } }
)
foreach ($p in $plan) {
    "===================== $($p.Scenario) $(Get-Date -Format 'HH:mm:ss')"
    $a = $p.Args
    try { & $s -Scenario $p.Scenario @a } catch { "SCENARIO FAILED: $_" }
}
"===================== ALL DONE $(Get-Date -Format 'HH:mm:ss')"
