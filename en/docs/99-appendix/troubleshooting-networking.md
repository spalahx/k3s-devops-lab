# Troubleshooting networking (local hardware only)

Diagnosing a missing or unstable network adapter, mostly Wi-Fi, on a physical machine. Not applicable to a VPS. If the server has Ethernet, use it and skip Wi-Fi entirely.

Work through the steps in order; stop at the first one that explains the symptom.

## 1. Is the interface present?

```bash
ip link
ip -br addr
```

Expect `lo`, an Ethernet name such as `enp2s0`, and for Wi-Fi a `wlan0`/`wlp*` entry. Virtual `cni0`, `flannel.1`, `veth*`, `docker0` belong to containers and say nothing about physical adapters.

## 2. Is it blocked in software?

```bash
rfkill list
sudo rfkill unblock wifi
```

`Soft blocked: yes` is fixed by the unblock. If the adapter is absent from `rfkill list` too, the problem is deeper (driver).

## 3. Does the hardware exist on the bus?

```bash
lspci -nn | grep -iE 'network|wireless|wifi|ethernet'
lsusb
```

| Result | Meaning |
|---|---|
| Device listed with `[vendor:device]` ID | Hardware is fine; the driver is missing or failing. Note the ID |
| Not listed | Physical problem: reseat the M.2 card, check BIOS settings (adapter disabled), try another USB port |

## 4. Driver and firmware

```bash
lspci -nnk | grep -iA3 'network'      # "Kernel driver in use:" line
sudo dmesg | grep -iE 'firmware|wlan|wifi|iwlwifi|ath|rtw|mt79|r8169|e1000|enp'
uname -r
```

- No `Kernel driver in use` line: no driver bound to the device.
- `firmware: failed to load` or `-2`: install firmware, then reboot.

```bash
sudo apt update
sudo apt install --reinstall linux-firmware
```

- Check whether a driver module covers your ID (`modinfo <module> | grep -i alias`, search for the device part of the ID).
- New chips are often supported only in newer kernels. Update the system first; on an LTS release install the HWE kernel:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install linux-generic-hwe-$(lsb_release -rs)
sudo reboot
```

- Forcing an unsupported ID onto a related driver via `new_id` usually fails with `Invalid argument` when the chip differs internally; do not rely on it:

```bash
echo "<vendor> <device>" | sudo tee /sys/bus/pci/drivers/<module>/new_id
```

> **Warning:** A hand-built out-of-tree driver breaks silently on the next kernel update, and the headless server drops off the network. K3s reacts to network stalls by restarting Pods. For a server prefer Ethernet, or a USB Wi-Fi adapter whose chip is supported by the in-kernel driver.

## 5. Netplan configuration

Interface names in netplan must match `ip link`. Files are in `/etc/netplan/`.

```yaml
# /etc/netplan/50-wifi.yaml  (Wi-Fi example, mode 600)
network:
  version: 2
  renderer: networkd
  wifis:
    wlan0:
      dhcp4: true
      access-points:
        "<WIFI_SSID>":
          password: "<WIFI_PASSWORD>"
```

```bash
sudo chmod 600 /etc/netplan/*.yaml
sudo netplan try        # reverts after 120 s if you lose connectivity
sudo netplan apply
```

`wpasupplicant` must be installed for Wi-Fi (`sudo apt install wpasupplicant`). `<WIFI_SSID>` and `<WIFI_PASSWORD>` are your network name and key. Static addressing: [Static IP and networking](../01-os-and-network/static-ip-and-networking.md).

## 6. Wi-Fi power saving

Symptoms: high latency, SSH freezes after idle. Check and disable:

```bash
iw dev wlan0 get power_save
sudo iw dev wlan0 set power_save off
```

To make it persistent, create `/etc/NetworkManager/conf.d/wifi-powersave.conf` with `[connection]` and `wifi.powersave = 2` if NetworkManager is used. On networkd, use a systemd unit or udev rule that runs the `iw` command above at boot.

## 7. DNS and routing

Connected but names do not resolve:

```bash
ip route                         # a default route exists?
ping -c2 1.1.1.1                 # IP connectivity
ping -c2 example.com             # name resolution
resolvectl status                # DNS servers per link
```

- IP works, names do not: set `nameservers: addresses: [1.1.1.1, 8.8.8.8]` in netplan and apply.
- No default route: gateway wrong in static config.
- Two default routes (Ethernet and Wi-Fi both up): set `dhcp4-overrides: {route-metric: 600}` on the secondary interface.

## 8. Last resorts

- After a kernel update the network vanished: boot an older kernel from the GRUB "Advanced options" menu, or plug in Ethernet.
- Check the cable, switch port and router DHCP lease table before blaming drivers.

Next: [Glossary](glossary.md)
