# Shell Productivity: Starship and ble.sh

Turns the Bash prompt on the server into an informative one (directory, Git branch/status, current Kubernetes context, command duration, time) with Starship, and adds grey history suggestions, syntax highlighting and better history search with ble.sh. Optional, cosmetic; skip on minimal servers.

Prompt example:

```
~/workspace/work/blog  main [!]                on ⛵ default  3s 14:32
❯
```

## 1. Nerd Font on the laptop

Prompt icons are drawn by the terminal on the laptop, not the server. Without a Nerd Font they show as empty squares.

macOS (Homebrew):

```bash
brew install --cask font-meslo-lg-nerd-font
```

Linux: download "Meslo" from https://www.nerdfonts.com/font-downloads, unpack into `~/.local/share/fonts`, run `fc-cache -f`.

Then select `MesloLGS Nerd Font Mono` explicitly in the terminal profile and restart it:

| Terminal | Setting |
|---|---|
| iTerm2 | Settings > Profiles > Text > Font |
| VS Code / IDE terminal | `terminal.integrated.fontFamily` |
| WezTerm | `config.font = wezterm.font("MesloLGS Nerd Font Mono")` in `~/.wezterm.lua` |

> **Note:** installing the font is not enough; the terminal must be told to use it.

## 2. Install Starship (on the server)

```bash
sudo apt install -y curl
curl -sS https://starship.rs/install.sh | sh
starship --version
```

The installer asks for confirmation and installs to `/usr/local/bin` (needs `sudo`).

## 3. Starship config

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

# The Kubernetes module is disabled by default
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

| Detail | Meaning |
|---|---|
| trailing `\` in `format` | TOML line continuation, otherwise each module lands on its own line |
| `$fill` | Stretches and pushes the following modules (Kubernetes, time) to the right edge |
| `[kubernetes]` | Shows `kubectl config current-context` (K3s: `default`); needs a working kubeconfig, see [K3s install](k3s-install.md) |
| `\[` `\]` in `git_status` | Literal brackets (unescaped brackets mean a styled block) |

## 4. Install ble.sh (on the server)

ble.sh (Bash Line Editor) adds zsh-style autosuggestions from history, syntax highlighting and a completion menu. Requires Bash 4.3+ (`bash --version`; Ubuntu ships 5.x).

```bash
sudo apt update && sudo apt install -y git make gawk
cd /tmp
git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git
make -C ble.sh install INSDIR=$HOME/.local/share/blesh
rm -rf ble.sh
cd ~
ls ~/.local/share/blesh/ble.sh
```

It installs into the home directory; no `sudo` is needed for the build. Use `gawk`, not `mawk`.

## 5. `~/.bashrc` order

> **Warning:** ble.sh must be loaded on the very first line of `~/.bashrc` (with `--noattach`) and attached on the very last line. Everything else (Starship, aliases, functions, completions) goes in between. Wrong order gives no suggestions or a broken prompt.

First line of `~/.bashrc`:

```bash
# ble.sh: load (must be first)
[[ $- == *i* ]] && source ~/.local/share/blesh/ble.sh --noattach
```

`[[ $- == *i* ]]` limits it to interactive shells; `--noattach` loads without activating.

Last lines of `~/.bashrc`:

```bash
# Starship prompt
eval "$(starship init bash)"

# ... aliases and helper functions go here (see the next page) ...

# ble.sh: attach (must be last)
[[ ! ${BLE_VERSION-} ]] || ble-attach
```

The resulting file layout:

| Position | Content |
|---|---|
| Top | `source ... ble.sh --noattach` |
| Middle | Stock Ubuntu `.bashrc`, `KUBECONFIG` export, `eval "$(starship init bash)"`, aliases, functions |
| Bottom | `[[ ! ${BLE_VERSION-} ]] \|\| ble-attach` |

Apply with `exec bash` (more reliable with ble.sh than `source ~/.bashrc`).

## Verify

- Prompt is coloured and shows directory, Git branch (inside a repo) and `⛵ default`.
- Run any command, retype its first letters: grey continuation appears; `→` or `End` accepts it. Suggestions come from history, so an empty history shows none.
- `kubectl` is highlighted as a known command, a nonsense word in another colour.
- `Ctrl+R` opens history search.

| Symptom | Fix |
|---|---|
| Squares/`?` instead of icons | Nerd Font not installed or not selected in the laptop terminal |
| Prompt unchanged | `eval "$(starship init bash)"` missing from `~/.bashrc`, or the shell was not restarted (`exec bash`) |
| No Kubernetes block | `kubectl config current-context` returns nothing; fix kubeconfig |
| No grey suggestions | Wrong order of the two ble.sh lines; file `~/.local/share/blesh/ble.sh` missing; history empty |
| Suggestions hard to read | `echo "ble-face auto_complete='fg=244'" >> ~/.blerc`, then `exec bash` (pick a value for your colour scheme) |
| Shell hangs after editing `.bashrc` | Unclosed quote/brace; fix it from a second SSH session. Syntax check: `bash -n ~/.bashrc` |
| Disable ble.sh | Comment out its two lines in `.bashrc`; remove completely with `rm -rf ~/.local/share/blesh` |

Next: [kubectl aliases and project helpers](k3s-productivity-aliases.md)
