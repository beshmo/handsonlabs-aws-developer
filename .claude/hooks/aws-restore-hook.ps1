<#
.SYNOPSIS
  Stop hook for the `reviewer` subagent: puts the user's own ~/.aws and AWS environment
  variables back when the reviewer finishes, whether it passed, failed or was stopped by the
  credentials guardrail.

Runs `scripts/aws-cli-configuration.ps1 --restore`, which does nothing when there is no backup
(e.g. the reviewer never ran --set-credentials). Never blocks the subagent from stopping:
always exits 0, and reports problems on stderr only.
#>

try {
    $null = [Console]::In.ReadToEnd()   # hook payload is not needed
    $configScript = Join-Path $env:CLAUDE_PROJECT_DIR 'scripts\aws-cli-configuration.ps1'
    & $configScript --restore *>&1 | Out-Null
} catch {
    [Console]::Error.WriteLine("aws-restore-hook: restore failed ($($_.Exception.Message)). Run '. .\scripts\aws-cli-configuration.ps1 --restore' manually.")
}
exit 0
