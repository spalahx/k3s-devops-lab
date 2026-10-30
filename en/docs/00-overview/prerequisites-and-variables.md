# Prerequisites and variables

Hardware, software and accounts needed before starting, and every placeholder used in the docs. Replace placeholders with your own values when copying commands.

## Hardware

| Item | Minimum | Comfortable |
|---|---|---|
| CPU | 2 cores, x86_64 or arm64 | 4+ cores |
| RAM | 4 GB (K3s alone about 1 GB) | 16 GB+ (several projects, monitoring) |
| Disk | 40 GB SSD | 250 GB+ SSD |
| Network | Wired Ethernet | Wired Ethernet, router with DHCP reservation |
| Local LLMs (optional) | 16 GB RAM | 32 GB+ RAM or a supported GPU |

Prefer Ethernet over Wi-Fi for a server (see [Network troubleshooting](../99-appendix/troubleshooting-networking.md)).

## Software and accounts

- Installer USB stick (8 GB+) and a tool to write the ISO, for local hardware; or a VPS with Ubuntu Server LTS image.
- Laptop with a terminal and `ssh` (macOS or Linux), plus an IDE with Remote-SSH support.
- Git hosting account (GitHub or GitLab) for code; one per identity if you separate work and personal.
- Optional: VPS with a public IP (remote access), a registered domain (public sites), container registry.

## Placeholders

| Placeholder | Meaning | Example |
|---|---|---|
| `<SERVER_USER>` | Non-root sudo user on the server | `dev` |
| `<SERVER_HOSTNAME>` | Server hostname | `devbox` |
| `<SERVER_IP>` | Server address on the LAN (or public IP of a VPS) | `192.168.1.50` |
| `<SSH_PORT>` | Custom SSH port chosen during hardening | `2222` |
| `<DOMAIN_BASE>` | Base domain or local suffix for project hostnames | `devbox.local`, `example.com` |
| `<PROJECT_NAME>` | Short lowercase project name, used for folder, namespace and hostname | `blog` |
| `<VPS_IP>` | Public IP of the gateway VPS | `203.0.113.10` |
| `<GIT_WORK_EMAIL>` | E-mail for work commits | `me@work.example` |
| `<GIT_PERSONAL_EMAIL>` | E-mail for personal commits | `me@home.example` |
| `<DB_PASSWORD>` | Database password you generate (`openssl rand -base64 24`) | not stored in the repo |
| `<PROJECT_GROUP>` | Directory grouping projects (company, client, `personal`) | `personal` |
| `<DB_NAME>` | Database name | `wordpress` |
| `<OLD_DOMAIN>` | Domain of a site being migrated | `old.example.com` |
| `<GIT_USER_NAME>` | Name for Git commits | `Jane Doe` |
| `<ORG>`, `<REPO>` | Git organization/user and repository name | `acme`, `blog` |
| `<VPS_USER>` | Admin user on the gateway VPS | `admin` |
| `<TUNNEL_USER>`, `<TUNNEL_PORT>` | Restricted user on the VPS and the port the tunnel listens on | `tunnel`, `2200` |
| `<GRAFANA_ADMIN_PASSWORD>`, `<SAMBA_PASSWORD>` | Passwords you generate | not stored in the repo |

Naming rules: `<PROJECT_NAME>` must be a valid Kubernetes name (lowercase letters, digits, `-`). Keep it identical in the code directory, manifest directory, namespace and hostname.

Next: [Local vs cloud differences](local-vs-cloud-differences.md)
