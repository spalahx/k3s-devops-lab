# Changelog

All notable changes are listed here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/); a new major version marks a new platform generation (see the README).

## [Unreleased]

### Added

- Repository scaffold for the automated lab: pinned tool versions, `task doctor`, static checks in CI, example configuration, module template.
- AWS bootstrap Terraform module (state and backup buckets, GitHub OIDC with plan and apply roles, budget and cost anomaly alerts) with mocked-provider tests; checks run in CI without AWS credentials. Not yet applied to a real account.

### Changed

- Manual guide (v1): status note, "not verified" marks, fixes for SSH on Ubuntu 26.04 and for UFW with K3s, Ollama chapter removed.
