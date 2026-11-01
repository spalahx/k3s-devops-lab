# Introduction

A single Ubuntu Server machine (a home mini-PC or a cloud VPS) runs K3s, a lightweight Kubernetes. Every project is described by YAML manifests, and the machine is managed over SSH from a laptop. Skip this setup if one `docker compose` file on the laptop already covers your needs.

## What you get

- One always-on Linux host with a hardened SSH entry point (key-only login, firewall, brute-force protection).
- Docker for building images and K3s for running them; Traefik routes HTTP traffic to projects by hostname.
- Code on the server edited from the laptop IDE via Remote-SSH; changes show up in running Pods through `hostPath` volumes.
- Optional: remote access through a VPS, CI/CD, monitoring (Prometheus, Grafana, Loki), file storage.

## When it is useful

- **Weak or busy laptop.** Databases, several web stacks and a browser do not fit together; move the runtime to the server and keep only the IDE locally.
- **Shared dev server for a small team.** One host, one namespace per project, everybody connects over SSH with their own key.
- **Parallel multi-project work and integration testing.** Several projects run side by side on different hostnames without port or dependency conflicts.
- **Prod-like environment.** The same Kubernetes objects (Deployment, Service, Ingress) used in production are exercised during development.
- **Experiments.** Throwaway namespaces and new tooling with resource limits so they do not starve other projects.

## Reading order

1. Overview: [Architecture](architecture-overview.md), [Prerequisites and variables](prerequisites-and-variables.md), [Local vs cloud](local-vs-cloud-differences.md).
2. Base system: [OS and network](../01-os-and-network/install-ubuntu-server.md), then [Security](../02-security/ssh-hardening.md). Do both before installing anything else.
3. Platform: [Docker](../03-containers-and-k3s/docker-install.md), [K3s](../03-containers-and-k3s/k3s-install.md), [Ingress and first app](../03-containers-and-k3s/ingress-traefik-first-app.md).
4. Workflow: [Git and IDE](../04-git-and-ide/ssh-keys-for-git.md), then [Deploying projects](../05-deploying-projects/k8s-structure-conventions.md).
5. Optional, in any order: [Remote access](../06-remote-access/vps-gateway-setup.md), [CI/CD](../07-cicd/gitlab-ci-petproject-pipeline.md), [Monitoring](../08-monitoring/helm-basics.md), [Extras](../09-optional-extras/samba-file-storage.md).

The full ordered checklist is in [Roadmap checklist](../99-appendix/roadmap-checklist.md).

Next: [Architecture overview](architecture-overview.md)
