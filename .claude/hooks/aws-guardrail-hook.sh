#!/usr/bin/env bash
#
# PreToolUse hook for the `reviewer` subagent: blocks any AWS CLI command unless the
# active credentials belong to a KodeKloud playground user (kk_labs_user_*).
#
# Reads the hook JSON from stdin. Exit 0 = no objection, exit 2 = block (stderr goes to the
# agent as feedback). Fails closed: if the identity can't be verified, the command is blocked.
#
# Always allowed (needed to set up / tear down the check itself):
#   - commands that do not invoke the AWS CLI
#   - . ./scripts/aws-cli-configuration.sh --set-credentials|--restore|--help  (only when it
#     is the sole AWS-related part of the command; anything else chained to it is still checked)

set -u

ALLOWED_ARN_PATTERN='^arn:aws:iam::[0-9]{12}:user/kk_labs_user_.+$'

block() {
  echo "CREDENTIALS_SETUP_FAILED: $1" >&2
  echo "Stop immediately: run no further lab or aws commands. Run only '. ./scripts/aws-cli-configuration.sh --restore', then report CREDENTIALS_SETUP_FAILED, this reason and any Arn/Account shown above to the main agent." >&2
  exit 2
}

# Extracts a top-level JSON field from stdin ($1 = field name), preferring jq, falling
# back to python3.
json_field() {
  local field="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('$field') or '')
except Exception:
    pass
"
  fi
}

payload="$(cat)"

if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  block "guardrail hook could not read the tool input (neither jq nor python3 is available)."
fi

command_text="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
if [ -z "$command_text" ] && command -v python3 >/dev/null 2>&1; then
  command_text="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("tool_input", {}).get("command") or "")
except Exception:
    pass
')"
fi

if [ -z "${command_text// /}" ]; then
  exit 0
fi

# Ignore quoted strings (credentials, JSON, message text) when looking for an aws invocation,
# and drop the credentials-script call itself so only other commands remain.
scan="$(printf '%s' "$command_text" | sed -E "s/'[^']*'/ /g; s/\"[^\"]*\"/ /g")"
scan="$(printf '%s' "$scan" | sed -E 's#[^][:space:];|&()]*aws-cli-configuration\.sh[[:space:]]+--(set-credentials|restore|help)\b[^;|&]*# #Ig')"

if ! printf '%s' "$scan" | grep -qiP '(^|[\s;|&(`{])([^\s;|&()]*[\\/])?aws(\.exe)?(\s|$)'; then
  exit 0
fi

# An aws command is about to run: verify who the CLI is authenticated as.
export AWS_PAGER=''
raw="$(aws sts get-caller-identity --output json --cli-connect-timeout 10 --cli-read-timeout 15 2>&1)"
code=$?
if [ "$code" -ne 0 ]; then
  first_line="$(printf '%s\n' "$raw" | grep -m1 .)"
  block "'aws sts get-caller-identity' failed (credentials missing, invalid or expired): $first_line"
fi

arn="$(printf '%s' "$raw" | json_field Arn)"
account="$(printf '%s' "$raw" | json_field Account)"

if [ -z "$arn" ]; then
  block "unexpected 'aws sts get-caller-identity' output."
fi

if ! printf '%s' "$arn" | grep -qE "$ALLOWED_ARN_PATTERN"; then
  block "identity is not a KodeKloud playground user. Arn=$arn Account=$account (expected arn:aws:iam::<account>:user/kk_labs_user_*)."
fi

exit 0
