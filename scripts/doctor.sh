#!/usr/bin/env bash
# Compares the tools installed on this machine with the versions pinned in .mise.toml.
# Exit code 0 when everything matches, 1 when something is missing or different.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pins="$root/.mise.toml"

# tool name in .mise.toml -> command that prints its version
version_cmd() {
  case "$1" in
    terraform) terraform version ;;
    task) task --version ;;
    kubectl) kubectl version --client ;;
    helm) helm version --short ;;
    sops) sops --version ;;
    age) age --version ;;
    tflint) tflint --version ;;
    trivy) trivy --version ;;
    gitleaks) gitleaks version ;;
    shellcheck) shellcheck --version ;;
    kubeconform) kubeconform -v ;;
    lychee) lychee --version ;;
    pipx:ansible-core) ansible --version ;;
    pipx:checkov) checkov --version ;;
    pipx:yamllint) yamllint --version ;;
    npm:markdownlint-cli2) markdownlint-cli2 --version ;;
    *) return 2 ;;
  esac
}

# command name used to detect presence
binary_of() {
  case "$1" in
    pipx:ansible-core) echo ansible ;;
    pipx:checkov) echo checkov ;;
    pipx:yamllint) echo yamllint ;;
    npm:markdownlint-cli2) echo markdownlint-cli2 ;;
    *) echo "$1" ;;
  esac
}

failures=0
printf '%-24s %-12s %s\n' TOOL PINNED STATUS

while IFS= read -r line; do
  [[ "$line" =~ ^\"?([A-Za-z0-9:_.-]+)\"?[[:space:]]*=[[:space:]]*\"([0-9][^\"]*)\" ]] || continue
  tool="${BASH_REMATCH[1]}"
  want="${BASH_REMATCH[2]}"
  bin="$(binary_of "$tool")"
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf '%-24s %-12s %s\n' "$tool" "$want" "MISSING"
    failures=$((failures + 1))
    continue
  fi
  if out="$(version_cmd "$tool" 2>&1)" && grep -Fq "$want" <<<"$out"; then
    printf '%-24s %-12s %s\n' "$tool" "$want" "ok"
  else
    printf '%-24s %-12s %s\n' "$tool" "$want" "DIFFERENT (installed: $(head -n1 <<<"$out"))"
    failures=$((failures + 1))
  fi
done <"$pins"

if [ "$failures" -gt 0 ]; then
  echo
  echo "$failures tool(s) missing or different. Install the pinned versions with: mise install"
  exit 1
fi
echo
echo "All pinned tools match."
