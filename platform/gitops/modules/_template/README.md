# Module template

Copy this directory to `platform/gitops/modules/<name>/` and fill in every section. A module is accepted only when all items of the contract hold (decision D-013).

## What it does

One paragraph: what the module provides and why someone would enable it.

## Dependencies

Other modules or core components it needs.

## Resources

Measured `requests` and `limits` of every container (not estimates).

## Targets

Targets and profiles on which it was tested.

## Access

Which groups from `access/users.yaml` get which rights.

## Health check

Read-only commands and what a good result looks like.

## Removal

What is left after the module is switched off (only explicitly listed PVCs).

## Contract checklist

- [ ] README is filled in, resources are measured
- [ ] Helm chart or Application with pinned versions and per-target overlays
- [ ] `requests` and `limits` on every container, NetworkPolicy, non-root where possible
- [ ] SSO through Keycloak if the module has a web UI
- [ ] Metrics exported to Prometheus if the tool provides them
- [ ] Health check commands only read
- [ ] Clean removal
- [ ] Backup if the module stores data
