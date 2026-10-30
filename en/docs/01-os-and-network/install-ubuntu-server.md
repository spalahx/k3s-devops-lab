# Install Ubuntu Server

Installs Ubuntu Server LTS on a bare machine from a USB stick. Skip it if the machine is a cloud VPS that already ships with Ubuntu (see [Local vs cloud differences](../00-overview/local-vs-cloud-differences.md)).

## 1. Choose the image

| Choice | Value |
|---|---|
| Distribution | Ubuntu Server (no desktop), latest LTS (for example 24.04 LTS; LTS = 5 years of security updates) |
| Architecture | `amd64` for Intel/AMD machines, `arm64` for ARM boards. A wrong architecture does not boot |
| Download | `https://ubuntu.com/download/server` (ISO is about 2 GB) |

Verify the download against the published SHA256 sum:

```bash
# macOS
shasum -a 256 ~/Downloads/ubuntu-*-live-server-amd64.iso
# Linux
sha256sum ~/Downloads/ubuntu-*-live-server-amd64.iso
```

## 2. Write the USB stick

Use a stick of 8 GB or more. Everything on it is erased.

### macOS

```bash
diskutil list                         # find the stick by size, e.g. /dev/disk4 (external, physical)
diskutil unmountDisk /dev/diskN
sudo dd if=~/Downloads/ubuntu-XX.XX-live-server-amd64.iso of=/dev/rdiskN bs=1m status=progress
diskutil eject /dev/diskN
```

### Linux

```bash
lsblk                                 # find the stick, e.g. /dev/sdb (not a partition like sdb1)
sudo umount /dev/sdb* 2>/dev/null
sudo dd if=~/Downloads/ubuntu-XX.XX-live-server-amd64.iso of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

- `rdiskN` on macOS is the raw device and writes much faster than `diskN`.
- `dd` asks no confirmation. A wrong `of=` target (for example the internal disk `disk0`) destroys that disk. Check the size in `diskutil list` / `lsblk` twice.
- `Resource busy` on macOS means the stick is still mounted: run `diskutil unmountDisk` again.

## 3. Boot the machine from USB

1. Connect the machine to the router with an Ethernet cable. Use wired networking for the installation: the installer downloads packages, and some Wi-Fi chips have no driver in the installer (see [Troubleshooting networking](../99-appendix/troubleshooting-networking.md)).
2. Attach a monitor and a keyboard (only needed until SSH works).
3. Insert the stick, power on, and press the boot-menu key repeatedly (commonly `F7`, `F10`, `F11`, `F12`, `Esc` or `Del`; depends on the vendor).
4. Pick the entry that starts with `UEFI:` and names the stick. Do not pick `Legacy`.

If the stick is not listed: use a different USB port (prefer a USB 2.0 port), re-write the stick with another tool, and make sure Secure Boot is not blocking it (the Ubuntu ISO is signed and normally boots with Secure Boot on).

## 4. Installer choices

The installer is text-based: arrows, `Tab`, `Space` (toggle), `Enter`.

| Screen | Choice |
|---|---|
| Language / keyboard | English (error messages are easier to search) |
| Installation type | `Ubuntu Server` (not minimized) |
| Network | Wired interface should show an address via DHCP. Leave as is; a static IP is set later ([Static IP](static-ip-and-networking.md)) |
| Proxy / mirror | Defaults |
| Storage | Use an entire disk, keep "Set up this disk as an LVM group" enabled (partitions can be resized later). Select the internal disk, not the USB stick |
| Profile | Your name, server name `<SERVER_HOSTNAME>`, username `<SERVER_USER>`, a strong password (still needed for `sudo` after password SSH login is disabled) |
| Ubuntu Pro | Skip |
| SSH | **Tick "Install OpenSSH server"**. Do not import keys now |
| Featured snaps | Select nothing |

Wait for the installation and updates to finish (10-20 minutes), then select **Reboot**. When prompted, **remove the USB stick** before pressing `Enter`, otherwise the machine boots the installer again.

> **Warning:** if OpenSSH server was not ticked, install it at the console: `sudo apt install openssh-server`.

## 5. First login and update

At the console log in as `<SERVER_USER>` (the password is not echoed while typing). Find the address:

```bash
ip -br a
```

Example: `enp1s0  UP  192.168.1.150/24`. Interface names (`enp1s0`, `eno1`, `eth0`) differ per machine.

Now work from the laptop; the monitor and keyboard are no longer needed:

```bash
ssh <SERVER_USER>@<SERVER_IP>
```

Answer `yes` to the host-fingerprint question on first connection (it is stored in `~/.ssh/known_hosts` and warns if the host changes later). Then update:

```bash
sudo apt update && sudo apt upgrade -y
sudo reboot        # if the kernel or libc was upgraded
```

## Verify

```bash
lsb_release -d                       # Ubuntu LTS
systemctl is-active ssh              # active
ip -br a                             # wired interface has an address
sudo apt update && apt list --upgradable   # nothing (or only held-back packages) left
```

## Common failures

| Symptom | Cause / fix |
|---|---|
| Installer shows no network | Re-seat the cable, try another cable/port, check that the router runs DHCP |
| `ssh: Connection timed out` | Wrong IP, or laptop is on another network; recheck `ip -br a` on the server |
| `ssh: Connection refused` | OpenSSH server not installed or not running: `sudo apt install openssh-server && systemctl status ssh` |
| Lost the user password | Needs console access and GRUB recovery mode, or a reinstall |

Next: [Static IP and networking](static-ip-and-networking.md)
