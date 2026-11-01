#!/usr/bin/env bash
# Static checks for every Terraform root module under platform/infra/terraform/*/ :
# fmt, init without a backend, validate, tests (mocked provider), tflint.
# No AWS credentials are needed. In GitHub Actions a failure is also printed as an annotation.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base="$root/platform/infra/terraform"
failed=0

annotate() { # title, text
  [ "${GITHUB_ACTIONS:-}" = "true" ] || return 0
  local body
  body="$(printf '%s' "$2" | head -c 3000 | awk 'BEGIN{ORS="%0A"} {gsub(/%/,"%25"); gsub(/\r/,"%0D"); print}')"
  echo "::error title=${1}::${body}"
}

run() { # title, command...
  local title="$1" out
  shift
  echo "+ $*"
  if out="$("$@" 2>&1)"; then
    return 0
  fi
  printf '%s\n' "$out"
  annotate "$title" "$out"
  failed=1
  return 1
}

shopt -s nullglob
for dir in "$base"/*/; do
  ls "$dir"*.tf >/dev/null 2>&1 || continue
  name="$(basename "$dir")"
  echo "=== $name"
  cd "$dir" || exit 1
  run "$name fmt" terraform fmt -check -diff || true
  run "$name init" terraform init -backend=false -input=false || continue
  run "$name validate" terraform validate || true
  if [ -d tests ]; then
    run "$name test" terraform test || true
  fi
  run "$name tflint init" tflint --config "$base/.tflint.hcl" --init || true
  run "$name tflint" tflint --config "$base/.tflint.hcl" || true
done

exit "$failed"
