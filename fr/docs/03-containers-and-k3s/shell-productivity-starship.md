# Productivité du shell : Starship et ble.sh

Transforme l'invite Bash du serveur en une invite informative (répertoire, branche/état Git, contexte Kubernetes courant, durée de commande, heure) avec Starship, et ajoute des suggestions grises basées sur l'historique, la coloration syntaxique et une meilleure recherche dans l'historique avec ble.sh. Optionnel et purement cosmétique ; à ignorer sur les serveurs minimaux.

Exemple d'invite :

```
~/workspace/work/blog  main [!]                on ⛵ default  3s 14:32
❯
```

## 1. Nerd Font sur le portable

Les icônes de l'invite sont dessinées par le terminal du portable, pas par le serveur. Sans Nerd Font, elles s'affichent sous forme de carrés vides.

macOS (Homebrew) :

```bash
brew install --cask font-meslo-lg-nerd-font
```

Linux : téléchargez « Meslo » depuis https://www.nerdfonts.com/font-downloads, décompressez dans `~/.local/share/fonts`, exécutez `fc-cache -f`.

Sélectionnez ensuite explicitement `MesloLGS Nerd Font Mono` dans le profil du terminal et redémarrez-le :

| Terminal | Paramètre |
|---|---|
| iTerm2 | Settings > Profiles > Text > Font |
| Terminal VS Code / IDE | `terminal.integrated.fontFamily` |
| WezTerm | `config.font = wezterm.font("MesloLGS Nerd Font Mono")` dans `~/.wezterm.lua` |

> **Note :** installer la police ne suffit pas ; il faut indiquer au terminal de l'utiliser.

## 2. Installer Starship (sur le serveur)

```bash
sudo apt install -y curl
curl -sS https://starship.rs/install.sh | sh
starship --version
```

L'installateur demande une confirmation et s'installe dans `/usr/local/bin` (nécessite `sudo`).

## 3. Configuration de Starship

```bash
mkdir -p ~/.config
nano ~/.config/starship.toml
```

```toml
format = """
$username\
$hostname\
$directory\
$git_branch\
$git_state\
$git_status\
$git_metrics\
$fill\
$kubernetes\
$php\
$nodejs\
$cmd_duration $jobs $time\
$line_break\
$character"""

[fill]
symbol = " "

[directory]
style = "bold blue"
truncation_length = 4
truncate_to_repo = false

[character]
success_symbol = "[❯](purple)"
error_symbol = "[❯](red)"
vicmd_symbol = "[❮](green)"

[git_branch]
format = "[$symbol$branch]($style) "
style = "bright-black"

[git_status]
format = '([\[$all_status$ahead_behind\]]($style) )'
style = "cyan"

[git_state]
format = '\([$state( $progress_current/$progress_total)]($style)\) '
style = "bright-black"

[git_metrics]
disabled = false

# Le module Kubernetes est désactivé par défaut
[kubernetes]
disabled = false
format = 'on [⛵ $context](dimmed green) '

[php]
symbol = "🐘 "
format = "[$symbol($version )]($style)"
style = "bold 147"

[nodejs]
format = "[$symbol($version )]($style)"

[cmd_duration]
format = "[$duration]($style)"
style = "yellow"

[jobs]
number_threshold = 1
format = "[$symbol]($style)"
style = "bold red"

[time]
disabled = false
style = "bold white"
format = "[$time]($style)"
```

| Détail | Signification |
|---|---|
| `\` final dans `format` | Continuation de ligne TOML, sinon chaque module s'affiche sur sa propre ligne |
| `$fill` | S'étire et repousse les modules suivants (Kubernetes, heure) vers le bord droit |
| `[kubernetes]` | Affiche `kubectl config current-context` (K3s : `default`) ; nécessite un kubeconfig fonctionnel, voir [Installation de K3s](k3s-install.md) |
| `\[` `\]` dans `git_status` | Crochets littéraux (des crochets non échappés désignent un bloc stylisé) |

## 4. Installer ble.sh (sur le serveur)

ble.sh (Bash Line Editor) ajoute des suggestions automatiques à la zsh à partir de l'historique, la coloration syntaxique et un menu de complétion. Nécessite Bash 4.3+ (`bash --version` ; Ubuntu fournit la version 5.x).

```bash
sudo apt update && sudo apt install -y git make gawk
cd /tmp
git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git
make -C ble.sh install INSDIR=$HOME/.local/share/blesh
rm -rf ble.sh
cd ~
ls ~/.local/share/blesh/ble.sh
```

Il s'installe dans le répertoire personnel ; `sudo` n'est pas nécessaire pour la compilation. Utilisez `gawk`, pas `mawk`.

## 5. Ordre dans `~/.bashrc`

> **Attention :** ble.sh doit être chargé dès la toute première ligne de `~/.bashrc` (avec `--noattach`) et attaché à la toute dernière ligne. Tout le reste (Starship, alias, fonctions, complétions) se place entre les deux. Un mauvais ordre donne l'absence de suggestions ou une invite cassée.

Première ligne de `~/.bashrc` :

```bash
# ble.sh : chargement (doit être en premier)
[[ $- == *i* ]] && source ~/.local/share/blesh/ble.sh --noattach
```

`[[ $- == *i* ]]` le limite aux shells interactifs ; `--noattach` charge sans activer.

Dernières lignes de `~/.bashrc` :

```bash
# Invite Starship
eval "$(starship init bash)"

# ... les alias et fonctions utilitaires vont ici (voir la page suivante) ...

# ble.sh : attachement (doit être en dernier)
[[ ! ${BLE_VERSION-} ]] || ble-attach
```

Structure résultante du fichier :

| Position | Contenu |
|---|---|
| Haut | `source ... ble.sh --noattach` |
| Milieu | `.bashrc` Ubuntu d'origine, export de `KUBECONFIG`, `eval "$(starship init bash)"`, alias, fonctions |
| Bas | `[[ ! ${BLE_VERSION-} ]] \|\| ble-attach` |

Appliquez avec `exec bash` (plus fiable avec ble.sh que `source ~/.bashrc`).

## Vérification

- L'invite est colorée et affiche le répertoire, la branche Git (dans un dépôt) et `⛵ default`.
- Exécutez une commande quelconque, retapez ses premières lettres : une suite grise apparaît ; `→` ou `End` l'accepte. Les suggestions viennent de l'historique, donc un historique vide n'en montre aucune.
- `kubectl` est mis en évidence comme commande connue, un mot absurde dans une autre couleur.
- `Ctrl+R` ouvre la recherche dans l'historique.

| Symptôme | Solution |
|---|---|
| Carrés/`?` à la place des icônes | Nerd Font non installée ou non sélectionnée dans le terminal du portable |
| Invite inchangée | `eval "$(starship init bash)"` absent de `~/.bashrc`, ou shell non redémarré (`exec bash`) |
| Pas de bloc Kubernetes | `kubectl config current-context` ne renvoie rien ; corrigez le kubeconfig |
| Pas de suggestions grises | Mauvais ordre des deux lignes ble.sh ; fichier `~/.local/share/blesh/ble.sh` manquant ; historique vide |
| Suggestions difficiles à lire | `echo "ble-face auto_complete='fg=244'" >> ~/.blerc`, puis `exec bash` (choisissez une valeur adaptée à votre jeu de couleurs) |
| Le shell se fige après modification de `.bashrc` | Guillemet/accolade non fermé ; corrigez depuis une seconde session SSH. Vérification de syntaxe : `bash -n ~/.bashrc` |
| Désactiver ble.sh | Commentez ses deux lignes dans `.bashrc` ; suppression complète avec `rm -rf ~/.local/share/blesh` |

Suite : [Alias kubectl et utilitaires de projet](k3s-productivity-aliases.md)
