<#
.SYNOPSIS
  Temporarily points the local AWS CLI at KodeKloud playground credentials
  (e.g. from CloudShell's `aws configure export-credentials`) and restores
  the original configuration afterwards.

Usage:
  .\aws-cli-configuration.ps1 --set-credentials <input>
  .\aws-cli-configuration.ps1 --restore

Parameters:
  --set-credentials <input>
      Backs up ~/.aws and current AWS environment variables.
      Parses <input> (JSON format, 'export AWS_...', or '$Env:AWS_...' format)
      and sets the credentials for the current session.
      Runs: aws sts get-caller-identity

  --restore
      Restores previously backed up ~/.aws files and environment variables.
      Cleans up backup files and runs: aws sts get-caller-identity

  --help / default
      Displays this help text.

Example:
  In CloudShell, run: aws configure export-credentials
  Locally, run:
    . .\aws-cli-configuration.ps1 --set-credentials '<pasted-cloudshell-output>'

Notes:
  - Credentials are also written to ~/.aws/credentials and ~/.aws/config
    ([default] profile) so separate shell invocations keep working. --restore
    removes them again. Environment variables only survive the current session
    when this script is dot-sourced.
  - Running --set-credentials again while a backup exists updates the
    credentials but keeps the ORIGINAL backup, so the first --restore always
    returns the original state.
  - Secrets are never printed.
#>

$script:AwsDir = Join-Path $HOME '.aws'
$script:BackupDir = Join-Path $HOME '.aws.claude-backup'
$script:BackupAwsDir = Join-Path $script:BackupDir 'aws'
$script:BackupEnvFile = Join-Path $script:BackupDir 'env.json'
$script:AwsEnvVars = @(
    'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_SESSION_TOKEN',
    'AWS_DEFAULT_REGION', 'AWS_REGION', 'AWS_PROFILE',
    'AWS_CREDENTIAL_EXPIRATION', 'AWS_SHARED_CREDENTIALS_FILE', 'AWS_CONFIG_FILE'
)
$script:DefaultRegion = 'us-east-1'

function Show-AwsCliConfigHelp {
    @'
Usage:
  .\aws-cli-configuration.ps1 --set-credentials <input>
  .\aws-cli-configuration.ps1 --restore

Parameters:
  --set-credentials <input>
      Backs up ~/.aws and current AWS environment variables.
      Parses <input> (JSON format, 'export AWS_...', or '$Env:AWS_...' format)
      and sets the credentials for the current session.
      Runs: aws sts get-caller-identity

  --restore
      Restores previously backed up ~/.aws files and environment variables.
      Cleans up backup files and runs: aws sts get-caller-identity

  --help / default
      Displays this help text.

Example:
  In CloudShell, run: aws configure export-credentials
  Locally, run:
    . .\aws-cli-configuration.ps1 --set-credentials '<pasted-cloudshell-output>'
'@ | Write-Host
}

function Set-ProcessEnv([string]$Name, $Value) {
    # SetEnvironmentVariable($null) can leave an empty value on Windows, which the CLI
    # reads as a profile named ''. Remove-Item is the reliable way to unset.
    if ([string]::IsNullOrEmpty($Value)) { Remove-Item -Path "Env:$Name" -ErrorAction SilentlyContinue }
    else { Set-Item -Path "Env:$Name" -Value $Value }
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function ConvertFrom-AwsCredentialInput([string]$Text) {
    # Returns @{ AccessKeyId; SecretAccessKey; SessionToken; Expiration; Region }
    $result = @{ AccessKeyId = $null; SecretAccessKey = $null; SessionToken = $null; Expiration = $null; Region = $null }
    $trimmed = $Text.Trim()

    if ($trimmed.StartsWith('{')) {
        try {
            $json = $trimmed | ConvertFrom-Json
            $result.AccessKeyId = $json.AccessKeyId
            $result.SecretAccessKey = $json.SecretAccessKey
            $result.SessionToken = $json.SessionToken
            # ConvertFrom-Json turns ISO dates into DateTime; normalise back to ISO 8601 UTC,
            # the only format botocore accepts for AWS_CREDENTIAL_EXPIRATION.
            $exp = $json.Expiration
            if ($exp -is [DateTime]) { $exp = $exp.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'") }
            $result.Expiration = $exp
        } catch {
            throw "Input looks like JSON but could not be parsed: $($_.Exception.Message)"
        }
    } else {
        # 'export AWS_X=value' or '$Env:AWS_X = "value"' (any quoting).
        $pattern = '(?im)^\s*(?:export\s+|\$Env:)(AWS_[A-Z_]+)\s*=\s*(?:"([^"]*)"|''([^'']*)''|([^\s;]+))'
        foreach ($m in [regex]::Matches($trimmed, $pattern)) {
            $value = @($m.Groups[2].Value, $m.Groups[3].Value, $m.Groups[4].Value) | Where-Object { $_ } | Select-Object -First 1
            switch ($m.Groups[1].Value.ToUpperInvariant()) {
                'AWS_ACCESS_KEY_ID'         { $result.AccessKeyId = $value }
                'AWS_SECRET_ACCESS_KEY'     { $result.SecretAccessKey = $value }
                'AWS_SESSION_TOKEN'         { $result.SessionToken = $value }
                'AWS_CREDENTIAL_EXPIRATION' { $result.Expiration = $value }
                'AWS_DEFAULT_REGION'        { $result.Region = $value }
                'AWS_REGION'                { if (-not $result.Region) { $result.Region = $value } }
            }
        }
    }

    if (-not $result.AccessKeyId -or -not $result.SecretAccessKey) {
        throw 'Could not find AccessKeyId/SecretAccessKey in the input (expected JSON, "export AWS_..." or "$Env:AWS_..." format).'
    }
    return $result
}

function Backup-AwsConfiguration {
    if (Test-Path $script:BackupDir) {
        Write-Host "Backup already exists at $script:BackupDir - keeping the original backup." -ForegroundColor Yellow
        return
    }
    New-Item -ItemType Directory -Path $script:BackupDir | Out-Null

    $hadAwsDir = Test-Path $script:AwsDir
    if ($hadAwsDir) {
        Copy-Item -Path $script:AwsDir -Destination $script:BackupAwsDir -Recurse -Force
    }

    $envState = [ordered]@{ hadAwsDir = $hadAwsDir; env = [ordered]@{} }
    foreach ($name in $script:AwsEnvVars) {
        $envState.env[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    Write-Utf8NoBom $script:BackupEnvFile ($envState | ConvertTo-Json -Depth 4)
    Write-Host "Backed up ~/.aws and AWS environment variables to $script:BackupDir"
}

function Set-AwsCliCredentials([string]$InputText) {
    if ([string]::IsNullOrWhiteSpace($InputText)) {
        Write-Error '--set-credentials requires the credentials as <input> (quote it).'
        return
    }
    try { $creds = ConvertFrom-AwsCredentialInput $InputText } catch { Write-Error $_.Exception.Message; return }

    Backup-AwsConfiguration

    $region = if ($creds.Region) { $creds.Region } elseif ($env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION } else { $script:DefaultRegion }

    # Session env vars: drop anything that could override the credentials we write.
    foreach ($name in 'AWS_PROFILE', 'AWS_SHARED_CREDENTIALS_FILE', 'AWS_CONFIG_FILE') {
        Set-ProcessEnv $name $null
    }
    $env:AWS_ACCESS_KEY_ID = $creds.AccessKeyId
    $env:AWS_SECRET_ACCESS_KEY = $creds.SecretAccessKey
    if ($creds.SessionToken) { $env:AWS_SESSION_TOKEN = $creds.SessionToken } else { Remove-Item Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue }
    if ($creds.Expiration) { $env:AWS_CREDENTIAL_EXPIRATION = [string]$creds.Expiration } else { Remove-Item Env:AWS_CREDENTIAL_EXPIRATION -ErrorAction SilentlyContinue }
    $env:AWS_DEFAULT_REGION = $region
    Remove-Item Env:AWS_REGION -ErrorAction SilentlyContinue

    # Files: keep later shell invocations working (each tool call may be a fresh shell).
    if (-not (Test-Path $script:AwsDir)) { New-Item -ItemType Directory -Path $script:AwsDir | Out-Null }
    $credLines = @('[default]', "aws_access_key_id = $($creds.AccessKeyId)", "aws_secret_access_key = $($creds.SecretAccessKey)")
    if ($creds.SessionToken) { $credLines += "aws_session_token = $($creds.SessionToken)" }
    Write-Utf8NoBom (Join-Path $script:AwsDir 'credentials') (($credLines -join "`n") + "`n")
    Write-Utf8NoBom (Join-Path $script:AwsDir 'config') ("[default]`nregion = $region`noutput = json`n")

    if ($creds.Expiration) {
        try {
            $exp = [DateTimeOffset]::Parse([string]$creds.Expiration, [Globalization.CultureInfo]::InvariantCulture)
            $left = $exp - [DateTimeOffset]::UtcNow
            if ($left.TotalSeconds -le 0) { Write-Warning "Credentials already expired at $exp." }
            elseif ($left.TotalMinutes -lt 10) { Write-Warning ("Credentials expire in {0} minutes ({1})." -f [int][math]::Floor($left.TotalMinutes), $exp) }
            else { Write-Host ("Credentials valid for about {0} more minutes." -f [int][math]::Floor($left.TotalMinutes)) }
        } catch { Write-Warning "Could not parse Expiration '$($creds.Expiration)'." }
    }

    Write-Host "Credentials set for the current session and written to ~/.aws (region $region)."
    aws sts get-caller-identity
}

function Restore-AwsCliConfiguration {
    if (-not (Test-Path $script:BackupDir)) {
        Write-Host 'No backup found - nothing to restore.' -ForegroundColor Yellow
        return
    }

    $state = Get-Content -Raw -Path $script:BackupEnvFile | ConvertFrom-Json

    if (Test-Path $script:AwsDir) { Remove-Item -Path $script:AwsDir -Recurse -Force }
    if ($state.hadAwsDir) {
        Copy-Item -Path $script:BackupAwsDir -Destination $script:AwsDir -Recurse -Force
    }

    foreach ($name in $script:AwsEnvVars) {
        Set-ProcessEnv $name $state.env.$name
    }

    Remove-Item -Path $script:BackupDir -Recurse -Force
    Write-Host 'Restored ~/.aws and AWS environment variables; backup removed.'
    aws sts get-caller-identity
}

# Dispatch. Use 'return' (not 'exit') so dot-sourcing doesn't close the caller's session.
$action = if ($args.Count -gt 0) { [string]$args[0] } else { '--help' }
switch ($action.ToLowerInvariant()) {
    '--set-credentials' {
        $rest = if ($args.Count -gt 1) { ($args[1..($args.Count - 1)] | ForEach-Object { [string]$_ }) -join "`n" } else { '' }
        Set-AwsCliCredentials $rest
    }
    '--restore' { Restore-AwsCliConfiguration }
    default     { Show-AwsCliConfigHelp }
}
