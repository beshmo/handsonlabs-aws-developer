<#
.SYNOPSIS
  PreToolUse hook for the `reviewer` subagent: blocks any AWS CLI command unless the
  active credentials belong to a KodeKloud playground user (kk_labs_user_*).

Reads the hook JSON from stdin. Exit 0 = no objection, exit 2 = block (stderr goes to the
agent as feedback). Fails closed: if the identity can't be verified, the command is blocked.

Always allowed (needed to set up / tear down the check itself):
  - commands that do not invoke the AWS CLI
  - . .\scripts\aws-cli-configuration.ps1 --set-credentials|--restore|--help  (only when it
    is the sole AWS-related part of the command; anything else chained to it is still checked)
#>

$AllowedArnPattern = '^arn:aws:iam::\d{12}:user/kk_labs_user_.+$'

function Block([string]$Reason) {
    [Console]::Error.WriteLine("CREDENTIALS_SETUP_FAILED: $Reason")
    [Console]::Error.WriteLine("Stop immediately: run no further lab or aws commands. Run only '. .\scripts\aws-cli-configuration.ps1 --restore', then report CREDENTIALS_SETUP_FAILED, this reason and any Arn/Account shown above to the main agent.")
    exit 2
}

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $command = [string]$payload.tool_input.command
} catch {
    Block "guardrail hook could not read the tool input ($($_.Exception.Message))."
}
if ([string]::IsNullOrWhiteSpace($command)) { exit 0 }

# Ignore quoted strings (credentials, JSON, message text) when looking for an aws invocation,
# and drop the credentials-script call itself so only other commands remain.
$scan = $command
$scan = [regex]::Replace($scan, "(?s)'[^']*'|""[^""]*""", ' ')
$scan = [regex]::Replace($scan, '(?i)[^\s;|&()]*aws-cli-configuration\.ps1\s+--(set-credentials|restore|help)\b[^;|&\r\n]*', ' ')
$awsInvocation = '(?i)(^|[\s;|&(`{])([^\s;|&()]*[\\/])?aws(\.exe)?(\s|$)'
if ($scan -notmatch $awsInvocation) { exit 0 }

# An aws command is about to run: verify who the CLI is authenticated as.
$env:AWS_PAGER = ''
try {
    $raw = & aws sts get-caller-identity --output json --cli-connect-timeout 10 --cli-read-timeout 15 2>&1
    $code = $LASTEXITCODE
} catch {
    Block "could not run 'aws sts get-caller-identity' ($($_.Exception.Message))."
}
$text = ($raw | Out-String).Trim()
if ($code -ne 0) {
    $firstLine = ($text -split "\r?\n" | Where-Object { $_ } | Select-Object -First 1)
    Block "'aws sts get-caller-identity' failed (credentials missing, invalid or expired): $firstLine"
}
try { $identity = $text | ConvertFrom-Json } catch { Block "unexpected 'aws sts get-caller-identity' output." }

if ($identity.Arn -notmatch $AllowedArnPattern) {
    Block "identity is not a KodeKloud playground user. Arn=$($identity.Arn) Account=$($identity.Account) (expected arn:aws:iam::<account>:user/kk_labs_user_*)."
}
exit 0
