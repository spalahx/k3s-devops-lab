# Продуктивність оболонки: Starship і ble.sh

Робить запрошення Bash на сервері інформативним (каталог, гілка/стан Git, поточний контекст Kubernetes, тривалість команди, час) за допомогою Starship, а також додає сірі підказки з історії, підсвічування синтаксису та кращий пошук в історії за допомогою ble.sh. Необов'язково, суто косметика; пропустіть на мінімальних серверах.

Приклад запрошення:

```
~/workspace/work/blog  main [!]                on ⛵ default  3s 14:32
❯
```

## 1. Nerd Font на ноутбуці

Значки запрошення малює термінал на ноутбуці, а не сервер. Без Nerd Font вони відображаються як порожні квадрати.

macOS (Homebrew):

```bash
brew install --cask font-meslo-lg-nerd-font
```

Linux: завантажте "Meslo" з https://www.nerdfonts.com/font-downloads, розпакуйте в `~/.local/share/fonts`, виконайте `fc-cache -f`.

Потім явно виберіть `MesloLGS Nerd Font Mono` у профілі терміналу та перезапустіть його:

| Термінал | Налаштування |
|---|---|
| iTerm2 | Settings > Profiles > Text > Font |
| Термінал VS Code / IDE | `terminal.integrated.fontFamily` |
| WezTerm | `config.font = wezterm.font("MesloLGS Nerd Font Mono")` у `~/.wezterm.lua` |

> **Примітка:** встановити шрифт недостатньо; терміналу треба вказати, що його слід використовувати.

## 2. Встановлення Starship (на сервері)

```bash
sudo apt install -y curl
curl -sS https://starship.rs/install.sh | sh
starship --version
```

Інсталятор просить підтвердження та встановлює в `/usr/local/bin` (потрібен `sudo`).

## 3. Конфігурація Starship

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

# Модуль Kubernetes типово вимкнений
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

| Деталь | Значення |
|---|---|
| кінцевий `\` у `format` | Продовження рядка в TOML, інакше кожен модуль опиниться в окремому рядку |
| `$fill` | Розтягується та відсуває наступні модулі (Kubernetes, час) до правого краю |
| `[kubernetes]` | Показує `kubectl config current-context` (K3s: `default`); потрібен робочий kubeconfig, див. [Встановлення K3s](k3s-install.md) |
| `\[` `\]` у `git_status` | Буквальні дужки (неекрановані дужки означають стильований блок) |

## 4. Встановлення ble.sh (на сервері)

ble.sh (Bash Line Editor) додає автопідказки з історії в стилі zsh, підсвічування синтаксису та меню автодоповнення. Потрібен Bash 4.3+ (`bash --version`; Ubuntu постачається з 5.x).

```bash
sudo apt update && sudo apt install -y git make gawk
cd /tmp
git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git
make -C ble.sh install INSDIR=$HOME/.local/share/blesh
rm -rf ble.sh
cd ~
ls ~/.local/share/blesh/ble.sh
```

Встановлюється в домашній каталог; для збирання `sudo` не потрібен. Використовуйте `gawk`, а не `mawk`.

## 5. Порядок у `~/.bashrc`

> **Попередження:** ble.sh має бути завантажений у самому першому рядку `~/.bashrc` (з `--noattach`) і підключений в останньому рядку. Усе інше (Starship, аліаси, функції, автодоповнення) розташовується між ними. Хибний порядок дає відсутність підказок або зламане запрошення.

Перший рядок `~/.bashrc`:

```bash
# ble.sh: завантаження (має бути першим)
[[ $- == *i* ]] && source ~/.local/share/blesh/ble.sh --noattach
```

`[[ $- == *i* ]]` обмежує його інтерактивними оболонками; `--noattach` завантажує без активації.

Останні рядки `~/.bashrc`:

```bash
# Запрошення Starship
eval "$(starship init bash)"

# ... тут розміщуються аліаси та допоміжні функції (див. наступну сторінку) ...

# ble.sh: підключення (має бути останнім)
[[ ! ${BLE_VERSION-} ]] || ble-attach
```

Підсумкова структура файлу:

| Позиція | Вміст |
|---|---|
| Початок | `source ... ble.sh --noattach` |
| Середина | Стандартний `.bashrc` Ubuntu, експорт `KUBECONFIG`, `eval "$(starship init bash)"`, аліаси, функції |
| Кінець | `[[ ! ${BLE_VERSION-} ]] \|\| ble-attach` |

Застосуйте через `exec bash` (з ble.sh надійніше, ніж `source ~/.bashrc`).

## Перевірка

- Запрошення кольорове та показує каталог, гілку Git (всередині репозиторію) і `⛵ default`.
- Виконайте будь-яку команду, наберіть знову її перші літери: з'являється сіре продовження; `→` або `End` приймає його. Підказки беруться з історії, тож порожня історія їх не показує.
- `kubectl` підсвічується як відома команда, безглузде слово іншим кольором.
- `Ctrl+R` відкриває пошук в історії.

| Симптом | Рішення |
|---|---|
| Квадрати/`?` замість значків | Nerd Font не встановлено або не вибрано в терміналі на ноутбуці |
| Запрошення не змінилося | `eval "$(starship init bash)"` відсутній у `~/.bashrc`, або оболонку не перезапущено (`exec bash`) |
| Немає блока Kubernetes | `kubectl config current-context` нічого не повертає; виправте kubeconfig |
| Немає сірих підказок | Хибний порядок двох рядків ble.sh; файл `~/.local/share/blesh/ble.sh` відсутній; історія порожня |
| Підказки важко читати | `echo "ble-face auto_complete='fg=244'" >> ~/.blerc`, потім `exec bash` (підберіть значення під свою кольорову схему) |
| Оболонка зависає після редагування `.bashrc` | Незакрита лапка/дужка; виправте з другого сеансу SSH. Перевірка синтаксису: `bash -n ~/.bashrc` |
| Вимкнути ble.sh | Закоментуйте його два рядки в `.bashrc`; повне видалення: `rm -rf ~/.local/share/blesh` |

Далі: [Аліаси kubectl і помічники для проєктів](k3s-productivity-aliases.md)
