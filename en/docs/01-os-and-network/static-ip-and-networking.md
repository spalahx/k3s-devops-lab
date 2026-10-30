# Static IP and Networking

Gives the server a stable address, a hostname and a correct clock, and makes `*.<DOMAIN_BASE>` names resolve on the laptop. A changing IP breaks SSH aliases, hosts entries and every service that points to the server, so do this before anything else is built on top.

## 1. Find the interface

```bash
ip -br a            # interface name and current address
ip route | grep default   # gateway (router) address
resolvectl status | grep -A2 "Link"   # current DNS servers
```

Example values used below: interface `enp1s0`, server `192.168.1.150`, router `192.168.1.1`. Substitute your own (`<SERVER_IP>` is the address you choose).

## 2. Option A: DHCP reservation on the router (simplest)

In the router admin page (DHCP / LAN section) bind the server's MAC address to the desired IP. The MAC is shown by:

```bash
ip link show enp1s0 | grep link/ether
```

Nothing changes on the server. Names of the feature differ: DHCP reservation, static DHCP, address reservation. Reboot the server (or renew the lease) to pick up the address.

## 3. Option B: static IP with netplan

Netplan is Ubuntu's network configuration layer (YAML files in `/etc/netplan/`). Pick an address outside the router's DHCP pool.

```bash
ls /etc/netplan/
sudo cp /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak
sudo nano /etc/netplan/50-cloud-init.yaml
```

```yaml
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: false
      addresses:
        - <SERVER_IP>/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
```

- Indentation is spaces only, 2 per level. A tab or wrong indent makes the file invalid.
- `routes: to: default` replaces the deprecated `gateway4`.
- Netplan files must not be world-readable: `sudo chmod 600 /etc/netplan/*.yaml`.
- The file name may differ (`00-installer-config.yaml`); edit the one that exists.

Apply with automatic rollback, so a mistake does not lock you out:

```bash
sudo netplan try        # press Enter within 120 s to keep, otherwise it reverts
sudo netplan apply
```

> **Warning:** run `netplan try` from the console or an SSH session you can afford to lose. If you changed the IP, the current SSH session drops; reconnect to the new address.

## 4. Hostname and timezone

```bash
sudo hostnamectl set-hostname <SERVER_HOSTNAME>
sudo timedatectl set-timezone Europe/Berlin     # use your zone: timedatectl list-timezones
timedatectl set-ntp true
```

If `/etc/hosts` has a `127.0.1.1` line with the old hostname, update it to `<SERVER_HOSTNAME>`.

## 5. Name resolution on the server

```bash
resolvectl query ubuntu.com
ping -c2 1.1.1.1 && ping -c2 ubuntu.com
```

If the IP answers but the name does not, DNS is broken: recheck `nameservers` in the netplan file.

## 6. Resolving `*.<DOMAIN_BASE>` on the laptop

Projects are reached by hostnames such as `<PROJECT_NAME>.<DOMAIN_BASE>`, which Traefik routes by `Host` header. In a private LAN no public DNS record exists, so the laptop must map the names to `<SERVER_IP>`.

| Method | When | How |
|---|---|---|
| `hosts` file | A few projects, one laptop | One line per name, below |
| Local DNS (router or `dnsmasq`) | Many names or many devices | Wildcard `address=/<DOMAIN_BASE>/<SERVER_IP>` |
| Public DNS A record | Cloud server with a public IP | See [Local vs cloud differences](../00-overview/local-vs-cloud-differences.md) |

`hosts` file location: macOS/Linux `/etc/hosts` (edit with `sudo`).

```bash
echo "<SERVER_IP>  <PROJECT_NAME>.<DOMAIN_BASE> phpmyadmin.<PROJECT_NAME>.<DOMAIN_BASE>" | sudo tee -a /etc/hosts
# macOS only: flush the DNS cache
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

- The format is strict: IP, then names separated by spaces, one line. No `http://`, no trailing slash.
- A `hosts` file does not support wildcards; every name needs to be listed.
- Avoid the `.local` suffix for `<DOMAIN_BASE>` on macOS/Linux: it is reserved for mDNS and can resolve slowly or not at all. Prefer something like `.lab` or `.home.arpa`.

Local wildcard DNS with `dnsmasq` (on the server or any always-on LAN host), if you prefer it to `hosts`:

```bash
sudo apt install dnsmasq -y
echo "address=/<DOMAIN_BASE>/<SERVER_IP>" | sudo tee /etc/dnsmasq.d/lab.conf
sudo systemctl restart dnsmasq
```

Then set that host as DNS server on the router or the laptop. On a machine running `systemd-resolved` (the Ubuntu default) port 53 is held by the stub resolver; set `DNSStubListener=no` in `/etc/systemd/resolved.conf` first, or run dnsmasq on another host.

## Wi-Fi

Use Ethernet for a K3s node. Kubernetes health checks treat a short Wi-Fi stall as a node failure and pods restart at random. Some Wi-Fi chips have no mainline driver at all. If Wi-Fi is the only option, or the chip is not detected, see [Troubleshooting networking](../99-appendix/troubleshooting-networking.md); a USB Wi-Fi adapter with a long-supported chipset is the reliable fallback.

## Verify

```bash
ip -br a                       # <SERVER_IP> on the interface
ip route | grep default
hostnamectl                    # hostname, timezone via: timedatectl
ping -c2 ubuntu.com
```

From the laptop:

```bash
ping -c2 <SERVER_IP>
ping -c2 <PROJECT_NAME>.<DOMAIN_BASE>     # resolves to <SERVER_IP>
ssh <SERVER_USER>@<SERVER_IP>
```

Reboot once (`sudo reboot`) and confirm the address stays the same.

Next: [SSH hardening](../02-security/ssh-hardening.md)
