#!/usr/bin/env bash
#
# Stop hook for the `reviewer` subagent: puts the user's own ~/.aws and AWS environment
# variables back when the reviewer finishes, whether it passed, failed or was stopped by the
# credentials guardrail.
#
# Runs `scripts/aws-cli-configuration.sh --restore`, which does nothing when there is no backup
# (e.g. the reviewer never ran --set-credentials). Never blocks the subagent from stopping:
# always exits 0, and reports problems on stderr only.

set -u

cat >/dev/null   # hook payload is not needed

config_script="$CLAUDE_PROJECT_DIR/scripts/aws-cli-configuration.sh"

if [ ! -f "$config_script" ]; then
  echo "aws-restore-hook: restore failed (script not found at $config_script). Run '. ./scripts/aws-cli-configuration.sh --restore' manually." >&2
  exit 0
fi

restore_output="$(bash "$config_script" --restore 2>&1 >/dev/null)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "aws-restore-hook: restore failed ($restore_output). Run '. ./scripts/aws-cli-configuration.sh --restore' manually." >&2
fi

exit 0
