# k3s-homelab-devbox

![Ubuntu](https://img.shields.io/badge/Ubuntu_Server-24.04_LTS-E95420?logo=ubuntu&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![K3s](https://img.shields.io/badge/K3s-FFC61E?logo=k3s&logoColor=black)
![Traefik](https://img.shields.io/badge/Traefik-24A1C1?logo=traefikproxy&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?logo=grafana&logoColor=white)
![GitLab CI](https://img.shields.io/badge/GitLab_CI-FC6D26?logo=gitlab&logoColor=white)

[English](README.md) | [Français](README.fr.md) | [Українська](README.uk.md) | **Русский**

Пошаговые инструкции: как превратить мини-ПК (или облачный VPS) в dev-сервер. Ubuntu Server, защищённый SSH, Docker, K3s с Traefik, проекты в виде Kubernetes-манифестов, удалённый доступ откуда угодно, CI/CD и мониторинг. В качестве примера используется WordPress, но подход подходит для любого веб-стека.

Результат: коробка в углу, которая круглосуточно крутит ваши сайты, и ноутбук, на котором остаются только редактор и браузер.

## Зачем свой dev-сервер

- **Слабый или старый ноутбук.** Контейнеры, базы данных и мониторинг работают на сервере. На ноутбуке только IDE и браузер.
- **Один dev-сервер на небольшую команду.** У всех одинаковое окружение, одно место для деплоя и просмотра логов.
- **Несколько проектов одновременно.** Каждый проект живёт в своём namespace, можно поднять два-три сайта рядом и проверять интеграцию между ними.
- **Ближе к продакшену.** Те же контейнеры, ingress и манифесты, что и в настоящем кластере Kubernetes, а не набор `docker-compose` файлов.
- **Дёшево.** Б/у мини-ПК окупается за пару месяцев аренды сопоставимых облачных машин, за простой платить не надо.
- **Доступ откуда угодно.** Небольшой VPS с публичным IP пробрасывает SSH на машину за домашним роутером.
- **Место для экспериментов.** Helm, Prometheus/Grafana/Loki, локальные LLM через Ollama: можно ломать, не трогая ничего важного.
- **Чистый ноутбук.** Никаких конфликтов локальных версий PHP/Node/MySQL.

## Что внутри

| Раздел | Что получается |
|---|---|
| ОС и сеть | Установка Ubuntu Server, статический IP, hostname |
| Безопасность | SSH-ключи, нестандартный порт, UFW, Fail2ban |
| Контейнеры | Docker, K3s, Traefik ingress, промпт и алиасы kubectl |
| Git и IDE | SSH-ключи для Git, раздельные рабочий/личный профили, PhpStorm / VS Code по SSH |
| Деплой проектов | Структура манифестов, пошаговый деплой, разбор манифестов WordPress, перенос сайта |
| Удалённый доступ | VPS-шлюз, обратный SSH-туннель, ProxyJump |
| CI/CD | GitLab Runner и пайплайн с деплоем в K3s |
| Мониторинг | Helm, Prometheus + Grafana, Loki |
| Дополнительно | Samba-шара, Ollama в отдельном namespace |

## С чего начать

- [English documentation](en/README.md)
- [Documentation en français](fr/README.md)
- [Документація українською](uk/README.md)
- [Документация на русском](ru/README.md)

## Чего здесь нет

Продакшен-хостинга, мультинодовых кластеров и высокой доступности. Это одноузловое dev-окружение.
