# OpenWrt Toolbox

Интерактивный установщик полезных компонентов для OpenWrt с автоматической
поддержкой `apk` и `opkg`.

Текущая версия: **0.0.2**

## Компоненты

- [LuCI Theme Proton 2025](https://github.com/ChesterGoodiny/luci-theme-proton2025)
- `luci-app-ttyd`
- `luci-i18n-ttyd-ru`
- `openssh-sftp-server`

Каждый компонент можно установить, удалить или проверить отдельно. Также
доступны установка, удаление и проверка всего набора.

## Быстрый запуск

Подключитесь к роутеру по SSH под пользователем `root` и выполните:

```sh
wget -O /tmp/openwrt-toolbox.sh https://raw.githubusercontent.com/ang3el7z/openwrt-toolbox/main/openwrt-toolbox.sh && sh /tmp/openwrt-toolbox.sh
```

Скрипт сначала сохраняется в `/tmp`, поэтому стандартный ввод остаётся
доступным для интерактивного меню.

## Меню

```text
OpenWrt Toolbox
Версия: 0.0.1
Система: OpenWrt <версия>
Менеджер пакетов: <apk|opkg>

1. Все компоненты
2. Тема Proton 2025
3. Веб-терминал ttyd
4. SFTP-сервер
0. Выход
```

Внутри каждого раздела:

```text
1. Установить
2. Удалить
3. Показать состояние
0. Назад
```

## Совместимость

- OpenWrt с пакетным менеджером `opkg`;
- OpenWrt с пакетным менеджером `apk`;
- BusyBox `ash` и POSIX `sh`;
- запуск от `root`;
- для загрузки требуется `wget` или `uclient-fetch`.

Скрипт определяет пакетный менеджер по доступной команде, а не только по номеру
версии OpenWrt. Если присутствуют обе команды, используется `apk`.

## Безопасное удаление

- перед удалением Proton 2025 LuCI переключается на стандартную тему Bootstrap;
- Bootstrap не удаляется;
- Dropbear не заменяется и не удаляется;
- удаление SFTP затрагивает только `openssh-sftp-server`;
- автоматическое удаление неиспользуемых зависимостей не выполняется.

## Proton 2025

Тема не хранится и не распространяется в этом репозитории. Toolbox загружает
подходящий `.ipk` или `.apk` непосредственно из последнего релиза исходного
проекта. Авторские права и лицензия темы принадлежат её авторам и определяются
[репозиторием Proton 2025](https://github.com/ChesterGoodiny/luci-theme-proton2025).

## Проверка

```sh
sh -n openwrt-toolbox.sh
sh tests/test-openwrt-toolbox.sh
shellcheck -s sh openwrt-toolbox.sh tests/test-openwrt-toolbox.sh
```

`ShellCheck` нужен только для разработки и не требуется на роутере.

## Лицензия

Исходный код OpenWrt Toolbox распространяется по лицензии MIT.
