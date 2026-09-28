#!/usr/bin/env bash
#
# Temporarily points the local AWS CLI at KodeKloud playground credentials
# (e.g. from CloudShell's `aws configure export-credentials`) and restores
# the original configuration afterwards.
#
# Usage:
#   . ./scripts/aws-cli-configuration.sh --set-credentials <input>
#   . ./scripts/aws-cli-configuration.sh --restore
#
# Parameters:
#   --set-credentials <input>
#       Backs up ~/.aws and current AWS environment variables.
#       Parses <input> (JSON format, or 'export AWS_...' format) and sets
#       the credentials for the current session.
#       Runs: aws sts get-caller-identity
#
#   --restore
#       Restores previously backed up ~/.aws files and environment variables.
#       Cleans up backup files and runs: aws sts get-caller-identity
#
#   --help / default
#       Displays this help text.
#
# Example:
#   In CloudShell, run: aws configure export-credentials
#   Locally, run:
#     . ./scripts/aws-cli-configuration.sh --set-credentials '<pasted-cloudshell-output>'
#
# Notes:
#   - Credentials are also written to ~/.aws/credentials and ~/.aws/config
#     ([default] profile) so separate shell invocations keep working. --restore
#     removes them again. Environment variables only survive the current shell
#     when this script is sourced (with `.` or `source`).
#   - Running --set-credentials again while a backup exists updates the
#     credentials but keeps the ORIGINAL backup, so the first --restore always
#     returns the original state.
#   - Secrets are never printed.

AWS_DIR="$HOME/.aws"
BACKUP_DIR="$HOME/.aws.claude-backup"
BACKUP_AWS_DIR="$BACKUP_DIR/aws"
BACKUP_ENV_FILE="$BACKUP_DIR/env.sh"
AWS_ENV_VARS=(
  AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  AWS_DEFAULT_REGION AWS_REGION AWS_PROFILE
  AWS_CREDENTIAL_EXPIRATION AWS_SHARED_CREDENTIALS_FILE AWS_CONFIG_FILE
)
DEFAULT_REGION='us-east-1'

show_aws_cli_config_help() {
  cat <<'EOF'
Usage:
  . ./scripts/aws-cli-configuration.sh --set-credentials <input>
  . ./scripts/aws-cli-configuration.sh --restore

Parameters:
  --set-credentials <input>
      Backs up ~/.aws and current AWS environment variables.
      Parses <input> (JSON format, or 'export AWS_...' format) and sets
      the credentials for the current session.
      Runs: aws sts get-caller-identity

  --restore
      Restores previously backed up ~/.aws files and environment variables.
      Cleans up backup files and runs: aws sts get-caller-identity

  --help / default
      Displays this help text.

Example:
  In CloudShell, run: aws configure export-credentials
  Locally, run:
    . ./scripts/aws-cli-configuration.sh --set-credentials '<pasted-cloudshell-output>'
EOF
}

# Parses $1 (JSON, or 'export AWS_...' lines) into the CRED_* globals.
parse_aws_credential_input() {
  local input="$1"
  local trimmed
  trimmed="$(printf '%s' "$input" | sed -e 's/^[[:space:]]*//')"

  CRED_ACCESS_KEY_ID=''
  CRED_SECRET_ACCESS_KEY=''
  CRED_SESSION_TOKEN=''
  CRED_EXPIRATION=''
  CRED_REGION=''

  if [[ "$trimmed" == \{* ]]; then
    CRED_ACCESS_KEY_ID="$(grep -oP '"AccessKeyId"\s*:\s*"\K[^"]*' <<<"$input" | head -1)"
    CRED_SECRET_ACCESS_KEY="$(grep -oP '"SecretAccessKey"\s*:\s*"\K[^"]*' <<<"$input" | head -1)"
    CRED_SESSION_TOKEN="$(grep -oP '"SessionToken"\s*:\s*"\K[^"]*' <<<"$input" | head -1)"
    CRED_EXPIRATION="$(grep -oP '"Expiration"\s*:\s*"\K[^"]*' <<<"$input" | head -1)"
  else
    local line name value
    while IFS= read -r line; do
      [[ "$line" =~ ^[[:space:]]*export[[:space:]]+(AWS_[A-Za-z_]+)=(.*)$ ]] || continue
      name="${BASH_REMATCH[1]^^}"
      value="${BASH_REMATCH[2]}"
      value="${value%;}"
      if [[ "$value" == \"*\" ]]; then value="${value:1:-1}"
      elif [[ "$value" == \'*\' ]]; then value="${value:1:-1}"
      fi
      case "$name" in
        AWS_ACCESS_KEY_ID)         CRED_ACCESS_KEY_ID="$value" ;;
        AWS_SECRET_ACCESS_KEY)     CRED_SECRET_ACCESS_KEY="$value" ;;
        AWS_SESSION_TOKEN)         CRED_SESSION_TOKEN="$value" ;;
        AWS_CREDENTIAL_EXPIRATION) CRED_EXPIRATION="$value" ;;
        AWS_DEFAULT_REGION)        CRED_REGION="$value" ;;
        AWS_REGION)                [ -z "$CRED_REGION" ] && CRED_REGION="$value" ;;
      esac
    done <<<"$input"
  fi

  if [ -z "$CRED_ACCESS_KEY_ID" ] || [ -z "$CRED_SECRET_ACCESS_KEY" ]; then
    echo "Could not find AccessKeyId/SecretAccessKey in the input (expected JSON or 'export AWS_...' format)." >&2
    return 1
  fi
  return 0
}

backup_aws_configuration() {
  if [ -d "$BACKUP_DIR" ]; then
    echo "Backup already exists at $BACKUP_DIR - keeping the original backup." >&2
    return 0
  fi
  mkdir -p "$BACKUP_DIR"

  local had_aws_dir=false
  if [ -d "$AWS_DIR" ]; then
    had_aws_dir=true
    cp -R "$AWS_DIR" "$BACKUP_AWS_DIR"
  fi

  {
    echo "had_aws_dir=$had_aws_dir"
    local name
    for name in "${AWS_ENV_VARS[@]}"; do
      if [ -n "${!name+x}" ]; then
        printf 'export %s=%q\n' "$name" "${!name}"
      else
        printf 'unset %s\n' "$name"
      fi
    done
  } >"$BACKUP_ENV_FILE"
  echo "Backed up ~/.aws and AWS environment variables to $BACKUP_DIR"
}

set_aws_cli_credentials() {
  local input_text="$1"
  if [ -z "${input_text//[[:space:]]/}" ]; then
    echo "--set-credentials requires the credentials as <input> (quote it)." >&2
    return 1
  fi
  parse_aws_credential_input "$input_text" || return 1

  backup_aws_configuration

  local region="${CRED_REGION:-${AWS_DEFAULT_REGION:-$DEFAULT_REGION}}"

  # Session env vars: drop anything that could override the credentials we write.
  unset AWS_PROFILE AWS_SHARED_CREDENTIALS_FILE AWS_CONFIG_FILE
  export AWS_ACCESS_KEY_ID="$CRED_ACCESS_KEY_ID"
  export AWS_SECRET_ACCESS_KEY="$CRED_SECRET_ACCESS_KEY"
  if [ -n "$CRED_SESSION_TOKEN" ]; then export AWS_SESSION_TOKEN="$CRED_SESSION_TOKEN"; else unset AWS_SESSION_TOKEN; fi
  if [ -n "$CRED_EXPIRATION" ]; then export AWS_CREDENTIAL_EXPIRATION="$CRED_EXPIRATION"; else unset AWS_CREDENTIAL_EXPIRATION; fi
  export AWS_DEFAULT_REGION="$region"
  unset AWS_REGION

  # Files: keep later shell invocations working (each tool call may be a fresh shell).
  mkdir -p "$AWS_DIR"
  {
    echo '[default]'
    echo "aws_access_key_id = $CRED_ACCESS_KEY_ID"
    echo "aws_secret_access_key = $CRED_SECRET_ACCESS_KEY"
    [ -n "$CRED_SESSION_TOKEN" ] && echo "aws_session_token = $CRED_SESSION_TOKEN"
  } >"$AWS_DIR/credentials"
  {
    echo '[default]'
    echo "region = $region"
    echo 'output = json'
  } >"$AWS_DIR/config"

  if [ -n "$CRED_EXPIRATION" ]; then
    local exp_epoch now_epoch left_seconds
    exp_epoch="$(date -d "$CRED_EXPIRATION" +%s 2>/dev/null)"
    if [ -n "$exp_epoch" ]; then
      now_epoch="$(date -u +%s)"
      left_seconds=$((exp_epoch - now_epoch))
      if [ "$left_seconds" -le 0 ]; then
        echo "WARNING: Credentials already expired at $CRED_EXPIRATION." >&2
      elif [ "$left_seconds" -lt 600 ]; then
        echo "WARNING: Credentials expire in $((left_seconds / 60)) minutes ($CRED_EXPIRATION)." >&2
      else
        echo "Credentials valid for about $((left_seconds / 60)) more minutes."
      fi
    else
      echo "WARNING: Could not parse Expiration '$CRED_EXPIRATION'." >&2
    fi
  fi

  echo "Credentials set for the current session and written to ~/.aws (region $region)."
  aws sts get-caller-identity
}

restore_aws_cli_configuration() {
  if [ ! -d "$BACKUP_DIR" ]; then
    echo 'No backup found - nothing to restore.' >&2
    return 0
  fi

  local had_aws_dir=false
  # shellcheck disable=SC1090
  source "$BACKUP_ENV_FILE"

  if [ -d "$AWS_DIR" ]; then rm -rf "$AWS_DIR"; fi
  if [ "$had_aws_dir" = true ]; then
    cp -R "$BACKUP_AWS_DIR" "$AWS_DIR"
  fi

  rm -rf "$BACKUP_DIR"
  echo 'Restored ~/.aws and AWS environment variables; backup removed.'
  aws sts get-caller-identity
}

# Dispatch. Functions use 'return', not 'exit', so sourcing this script never closes the
# caller's shell; exported env vars only persist in the caller's shell when sourced.
action="${1:---help}"
case "${action,,}" in
  --set-credentials)
    shift
    set_aws_cli_credentials "$(printf '%s\n' "$@")"
    ;;
  --restore)
    restore_aws_cli_configuration
    ;;
  *)
    show_aws_cli_config_help
    ;;
esac
