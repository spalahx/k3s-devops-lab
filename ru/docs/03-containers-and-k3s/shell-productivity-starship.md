# Продуктивность в шелле: Starship и ble.sh

Делает Bash-промпт на сервере информативным с помощью Starship (каталог, ветка/статус Git, текущий контекст Kubernetes, время выполнения команды, время), а ble.sh добавляет серые подсказки из истории, подсветку синтаксиса и удобный поиск по истории. Необязательно, чисто для удобства; на минимальных серверах можно пропустить.

Пример промпта:

```
~/workspace/work/blog  main [!]                on ⛵ default  3s 14:32
❯
```

## 1. Nerd Font на ноутбуке

Иконки промпта рисует терминал на ноутбуке, а не сервер. Без Nerd Font вместо них видны пустые квадраты.

macOS (Homebrew):

```bash
brew install --cask font-meslo-lg-nerd-font
```

Linux: скачайте "Meslo" с https://www.nerdfonts.com/font-downloads, распакуйте в `~/.local/share/fonts`, выполните `fc-cache -f`.

Затем явно выберите `MesloLGS Nerd Font Mono` в профиле терминала и перезапустите его:

| Терминал | Настройка |
|---|---|
| iTerm2 | Settings > Profiles > Text > Font |
| Терминал VS Code / IDE | `terminal.integrated.fontFamily` |
| WezTerm | `config.font = wezterm.font("MesloLGS Nerd Font Mono")` в `~/.wezterm.lua` |

> **Note:** одной установки шрифта недостаточно; терминалу нужно явно указать его использовать.

## 2. Установка Starship (на сервере)

```bash
sudo apt install -y curl
curl -sS https://starship.rs/install.sh | sh
starship --version
```

Установщик просит подтверждение и ставит бинарник в `/usr/local/bin` (нужен `sudo`).

## 3. Конфиг Starship

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

# Модуль Kubernetes по умолчанию выключен
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

| Деталь | Смысл |
|---|---|
| `\` в конце строк `format` | Продолжение строки в TOML, иначе каждый модуль окажется на отдельной строке |
| `$fill` | Растягивается и прижимает следующие модули (Kubernetes, время) к правому краю |
| `[kubernetes]` | Показывает `kubectl config current-context` (в K3s: `default`); нужен рабочий kubeconfig, см. [Установка K3s](k3s-install.md) |
| `\[` `\]` в `git_status` | Буквальные скобки (неэкранированные скобки означают стилизованный блок) |

## 4. Установка ble.sh (на сервере)

ble.sh (Bash Line Editor) добавляет подсказки из истории как в zsh, подсветку синтаксиса и меню автодополнения. Нужен Bash 4.3+ (`bash --version`; в Ubuntu 5.x).

```bash
sudo apt update && sudo apt install -y git make gawk
cd /tmp
git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git
make -C ble.sh install INSDIR=$HOME/.local/share/blesh
rm -rf ble.sh
cd ~
ls ~/.local/share/blesh/ble.sh
```

Ставится в домашний каталог; `sudo` для сборки не нужен. Нужен именно `gawk`, а не `mawk`.

## 5. Порядок в `~/.bashrc`

> **Warning:** ble.sh нужно загрузить в самой первой строке `~/.bashrc` (с `--noattach`) и активировать в самой последней. Всё остальное (Starship, алиасы, функции, автодополнения) находится между ними. При неверном порядке подсказок не будет или промпт сломается.

Первая строка `~/.bashrc`:

```bash
# ble.sh: загрузка (должна быть первой)
[[ $- == *i* ]] && source ~/.local/share/blesh/ble.sh --noattach
```

`[[ $- == *i* ]]` ограничивает загрузку интерактивными шеллами; `--noattach` загружает без активации.

Последние строки `~/.bashrc`:

```bash
# Промпт Starship
eval "$(starship init bash)"

# ... здесь алиасы и вспомогательные функции (см. следующую страницу) ...

# ble.sh: активация (должна быть последней)
[[ ! ${BLE_VERSION-} ]] || ble-attach
```

Итоговая раскладка файла:

| Позиция | Содержимое |
|---|---|
| Верх | `source ... ble.sh --noattach` |
| Середина | Стандартный `.bashrc` Ubuntu, экспорт `KUBECONFIG`, `eval "$(starship init bash)"`, алиасы, функции |
| Низ | `[[ ! ${BLE_VERSION-} ]] \|\| ble-attach` |

Применить: `exec bash` (с ble.sh надёжнее, чем `source ~/.bashrc`).

## Проверка

- Промпт цветной и показывает каталог, ветку Git (внутри репозитория) и `⛵ default`.
- Выполните любую команду и наберите её первые буквы: появится серое продолжение; `→` или `End` принимает его. Подсказки берутся из истории, при пустой истории их нет.
- `kubectl` подсвечивается как известная команда, бессмысленное слово другим цветом.
- `Ctrl+R` открывает поиск по истории.

| Симптом | Решение |
|---|---|
| Квадраты/`?` вместо иконок | Nerd Font не установлен или не выбран в терминале на ноутбуке |
| Промпт не изменился | В `~/.bashrc` нет `eval "$(starship init bash)"` или шелл не перезапущен (`exec bash`) |
| Нет блока Kubernetes | `kubectl config current-context` ничего не возвращает; исправьте kubeconfig |
| Нет серых подсказок | Неверный порядок двух строк ble.sh; нет файла `~/.local/share/blesh/ble.sh`; пустая история |
| Подсказки плохо видны | `echo "ble-face auto_complete='fg=244'" >> ~/.blerc`, затем `exec bash` (подберите значение под цветовую схему) |
| Шелл завис после правки `.bashrc` | Незакрытая кавычка/скобка; исправьте из второй SSH-сессии. Проверка синтаксиса: `bash -n ~/.bashrc` |
| Отключение ble.sh | Закомментируйте две его строки в `.bashrc`; полное удаление: `rm -rf ~/.local/share/blesh` |

Next: [Алиасы kubectl и хелперы проектов](k3s-productivity-aliases.md)
