# Tunnel SSH inverse en tant que service systemd

Maintient une connexion SSH sortante permanente du serveur domestique vers le VPS, en publiant le port SSH du serveur domestique sous la forme `127.0.0.1:<TUNNEL_PORT>` sur le VPS. Nécessite la [passerelle VPS](vps-gateway-setup.md) avec l'utilisateur et la clé du tunnel.

## 1. Test manuel

À exécuter sur le serveur domestique :

```bash
ssh -N -R 127.0.0.1:<TUNNEL_PORT>:localhost:<SSH_PORT> \
    -i ~/.ssh/id_ed25519_tunnel \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -p <SSH_PORT> <TUNNEL_USER>@<VPS_IP>
```

| Option | Signification |
|---|---|
| `-N` | Aucune commande distante ; maintient uniquement la redirection |
| `-R 127.0.0.1:<TUNNEL_PORT>:localhost:<SSH_PORT>` | Écoute sur le loopback du VPS au port `<TUNNEL_PORT>` et redirige vers le port SSH du serveur domestique lui-même |
| `ExitOnForwardFailure=yes` | Quitte si le port ne peut pas être lié, afin que systemd le redémarre au lieu de laisser un tunnel mort |
| `ServerAliveInterval=30`, `ServerAliveCountMax=3` | Sonde toutes les 30 s, abandonne après 3 échecs (environ 90 s) afin qu'une connexion à moitié morte soit détectée et rétablie |

Sur le VPS, confirmez que l'écoute existe :

```bash
ss -tlnp | grep <TUNNEL_PORT>
```

Arrêtez le test avec `Ctrl+C` avant de créer le service.

> **Avertissement :** l'option s'appelle `ServerAliveCountMax`. `ServerAliveCountAlive` n'existe pas et est rejetée par ssh.

## 2. Créer l'unité systemd

Un simple `ssh` avec keepalive suffit. `autossh` est un wrapper alternatif, mais avec `ExitOnForwardFailure` et `Restart=always` il n'apporte rien.

```bash
sudo nano /etc/systemd/system/vps-reverse-tunnel.service
```

```ini
[Unit]
Description=Reverse SSH tunnel to VPS gateway
After=network-online.target
Wants=network-online.target

[Service]
User=<SERVER_USER>
ExecStart=/usr/bin/ssh -N \
  -R 127.0.0.1:<TUNNEL_PORT>:localhost:<SSH_PORT> \
  -i /home/<SERVER_USER>/.ssh/id_ed25519_tunnel \
  -o IdentitiesOnly=yes \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o StrictHostKeyChecking=accept-new \
  -p <SSH_PORT> <TUNNEL_USER>@<VPS_IP>
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

`StrictHostKeyChecking=accept-new` enregistre la clé d'hôte du VPS à la première connexion sans invite (un service ne peut pas répondre à une invite). Pour ne pas lui faire confiance aveuglément, connectez-vous d'abord une fois manuellement en tant que `<SERVER_USER>` et confirmez l'empreinte.

## 3. Activer et démarrer

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now vps-reverse-tunnel.service
```

## 4. État et journaux

```bash
systemctl status vps-reverse-tunnel.service
journalctl -u vps-reverse-tunnel.service -f
```

## Comportement de reconnexion

| Événement | Résultat |
|---|---|
| L'IP domestique change / le Wi-Fi tombe | Le keepalive échoue en ~90 s, ssh se termine, systemd le redémarre après `RestartSec` |
| Redémarrage du serveur | L'unité est activée et démarre après `network-online.target` |
| Redémarrage du VPS | ssh se termine, systemd réessaie toutes les 10 s jusqu'au retour du VPS |
| Ancienne session toujours retenue par le VPS | La nouvelle tentative échoue avec `remote port forwarding failed` ; avec `ExitOnForwardFailure`, ssh se termine et réessaie jusqu'à ce que le VPS abandonne la session périmée. Si cela ne se résout jamais, définissez `ClientAliveInterval 30` et `ClientAliveCountMax 3` dans le `sshd_config` du VPS |

## Vérification

Sur le VPS :

```bash
ss -tlnp | grep <TUNNEL_PORT>
ssh -p <TUNNEL_PORT> <SERVER_USER>@127.0.0.1
```

La seconde commande doit ouvrir le shell du serveur domestique (vérifiez avec `hostname`). Configurez ensuite le côté client.

Erreurs courantes :

| Message | Cause / solution |
|---|---|
| `remote port forwarding failed for listen port` | Port occupé sur le VPS (session périmée ou autre processus), ou `permitlisten` dans `authorized_keys` ne correspond pas à l'adresse de `-R` |
| `Permission denied (publickey)` sur le VPS | Mauvaise clé ou mauvaises permissions sur `authorized_keys` / `.ssh` de `<TUNNEL_USER>` |
| `Permission denied (publickey)` sur `127.0.0.1:<TUNNEL_PORT>` | La clé publique de l'utilisateur qui se connecte n'est pas dans `authorized_keys` de l'utilisateur du serveur domestique |
| L'unité boucle en redémarrages | Lisez `journalctl -u vps-reverse-tunnel` ; généralement le VPS est injoignable ou le port est pris |

Suite : [Configuration client ProxyJump](proxyjump-client-config.md)
