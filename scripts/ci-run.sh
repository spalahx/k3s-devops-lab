#!/usr/bin/env bash
# Runs a command; when it fails inside GitHub Actions, also prints the tail of its output
# as an annotation, so the failure can be read without opening the raw log.
# usage: ci-run.sh <title> <command> [args...]
set -uo pipefail

title="$1"
shift
rc=0
out="$("$@" 2>&1)" || rc=$?
printf '%s\n' "$out"
if [ "$rc" -ne 0 ] && [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  body="$(printf '%s' "$out" | tail -c 16000 | awk 'BEGIN{ORS="%0A"} {gsub(/%/,"%25"); gsub(/\r/,"%0D"); print}')"
  echo "::error title=${title}::${body}"
fi
exit "$rc"
