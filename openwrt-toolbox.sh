#!/bin/sh

# OpenWrt Toolbox
# https://github.com/ang3el7z/openwrt-toolbox

# ---------------------------------------------------------------------------
# 1. Metadata
# ---------------------------------------------------------------------------

TOOLBOX_VERSION="0.0.1"

# ---------------------------------------------------------------------------
# 2. Constants and runtime state
# ---------------------------------------------------------------------------

PROTON_REPOSITORY="ChesterGoodiny/luci-theme-proton2025"
PROTON_PACKAGE="luci-theme-proton2025"
PROTON_MEDIA_URL="/luci-static/proton2025"
BOOTSTRAP_MEDIA_URL="/luci-static/bootstrap"

PKG_MANAGER=""
PKG_LISTS_UPDATED=0
OPENWRT_VERSION="unknown"
WORK_DIR=""

# ---------------------------------------------------------------------------
# 3. Output
# ---------------------------------------------------------------------------

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    COLOR_RED=$(printf '\033[0;31m')
    COLOR_GREEN=$(printf '\033[0;32m')
    COLOR_YELLOW=$(printf '\033[1;33m')
    COLOR_CYAN=$(printf '\033[0;36m')
    COLOR_BOLD=$(printf '\033[1m')
    COLOR_RESET=$(printf '\033[0m')
else
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_CYAN=""
    COLOR_BOLD=""
    COLOR_RESET=""
fi

log_info() {
    printf '%s[i]%s %s\n' "$COLOR_CYAN" "$COLOR_RESET" "$*"
}

log_success() {
    printf '%s[+]%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*"
}

log_warn() {
    printf '%s[!]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*"
}

log_error() {
    printf '%s[✗]%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2
}

separator() {
    printf '%s\n' "------------------------------------------------------------"
}

# ---------------------------------------------------------------------------
# 4. Runtime checks
# ---------------------------------------------------------------------------

require_root() {
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        log_error "Скрипт необходимо запускать от root."
        return 1
    fi
}

require_openwrt() {
    if [ ! -r "${OPENWRT_RELEASE_FILE:-/etc/openwrt_release}" ]; then
        log_error "Система OpenWrt не обнаружена."
        return 1
    fi
}

load_openwrt_release() {
    release_file=${OPENWRT_RELEASE_FILE:-/etc/openwrt_release}
    OPENWRT_VERSION=$(
        sed -n "s/^DISTRIB_RELEASE=['\"]\\([^'\"]*\\)['\"]$/\\1/p" "$release_file" |
            sed -n '1p'
    )
    [ -n "$OPENWRT_VERSION" ] || OPENWRT_VERSION="unknown"
}

detect_package_manager() {
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
    else
        log_error "Не найден пакетный менеджер apk или opkg."
        return 1
    fi
}

detect_package_manager_and_print() {
    detect_package_manager || return 1
    printf '%s' "$PKG_MANAGER"
}

require_downloader() {
    if command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    elif command -v uclient-fetch >/dev/null 2>&1; then
        DOWNLOADER="uclient-fetch"
    else
        log_error "Не найден wget или uclient-fetch."
        return 1
    fi
}

prepare_work_dir() {
    WORK_DIR=$(mktemp -d /tmp/openwrt-toolbox.XXXXXX) || {
        log_error "Не удалось создать временный каталог."
        return 1
    }
    chmod 0700 "$WORK_DIR" || return 1
}

cleanup() {
    case "$WORK_DIR" in
        /tmp/openwrt-toolbox.*)
            [ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
            ;;
    esac
}

trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# 5. Package manager abstraction
# ---------------------------------------------------------------------------

update_package_lists() {
    [ "$PKG_LISTS_UPDATED" -eq 1 ] && return 0
    log_info "Обновление списка пакетов..."
    case "$PKG_MANAGER" in
        apk) apk update ;;
        opkg) opkg update ;;
        *) return 1 ;;
    esac || return 1
    PKG_LISTS_UPDATED=1
}

is_package_installed() {
    package=$1
    case "$PKG_MANAGER" in
        apk) apk info -e "$package" >/dev/null 2>&1 ;;
        opkg) opkg list-installed "$package" 2>/dev/null |
            awk -v package="$package" '$1 == package { found=1 } END { exit !found }' ;;
        *) return 1 ;;
    esac
}

install_repo_package() {
    package=$1
    if is_package_installed "$package"; then
        log_success "$package уже установлен."
        return 0
    fi
    update_package_lists || return 1
    case "$PKG_MANAGER" in
        apk) apk add "$package" ;;
        opkg) opkg install "$package" ;;
        *) return 1 ;;
    esac
}

install_local_package() {
    package_file=$1
    case "$PKG_MANAGER" in
        apk) apk add --allow-untrusted "$package_file" ;;
        opkg) opkg install "$package_file" ;;
        *) return 1 ;;
    esac
}

remove_package() {
    package=$1
    if ! is_package_installed "$package"; then
        log_success "$package уже отсутствует."
        return 0
    fi
    case "$PKG_MANAGER" in
        apk) apk del "$package" ;;
        opkg) opkg remove "$package" ;;
        *) return 1 ;;
    esac
}

package_status() {
    package=$1
    label=$2
    if is_package_installed "$package"; then
        printf '  %s: %sустановлен%s\n' "$label" "$COLOR_GREEN" "$COLOR_RESET"
        return 0
    fi
    printf '  %s: %sне установлен%s\n' "$label" "$COLOR_YELLOW" "$COLOR_RESET"
    return 1
}

download_to_file() {
    url=$1
    destination=$2
    case "$DOWNLOADER" in
        wget) wget -q -O "$destination" "$url" ;;
        uclient-fetch) uclient-fetch -q -O "$destination" "$url" ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# 6. Proton 2025
# ---------------------------------------------------------------------------

resolve_proton_asset_url() {
    case "$PKG_MANAGER" in
        apk) extension="apk" ;;
        opkg) extension="ipk" ;;
        *) return 1 ;;
    esac

    if ! command -v jsonfilter >/dev/null 2>&1; then
        log_error "Не найден jsonfilter, необходимый для разбора ответа GitHub API."
        return 1
    fi

    release_json="$WORK_DIR/proton-release.json"
    asset_urls="$WORK_DIR/proton-assets.txt"
    release_api="https://api.github.com/repos/$PROTON_REPOSITORY/releases/latest"

    download_to_file "$release_api" "$release_json" || {
        log_error "Не удалось получить данные актуального релиза Proton 2025."
        return 1
    }

    if ! jsonfilter -q -i "$release_json" \
        -e '@.assets[*].browser_download_url' >"$asset_urls"; then
        log_error "GitHub API вернул некорректный JSON."
        return 1
    fi

    urls=$(
        grep "/${PROTON_PACKAGE}[^/]*\.${extension}$" "$asset_urls" || true
    )
    count=$(printf '%s\n' "$urls" | sed '/^$/d' | wc -l | tr -d ' ')

    if [ "$count" != "1" ]; then
        log_error "Ожидался один пакет Proton 2025 .${extension}, найдено: $count."
        if [ -s "$asset_urls" ]; then
            log_warn "Ссылки, найденные в актуальном релизе:"
            sed 's/^/  - /' "$asset_urls" >&2
        fi
        return 1
    fi

    printf '%s\n' "$urls"
}

select_luci_theme() {
    media_url=$1
    uci set luci.main.mediaurlbase="$media_url" &&
        uci commit luci &&
        /etc/init.d/uhttpd restart
}

install_proton() {
    if is_package_installed "$PROTON_PACKAGE"; then
        log_success "Тема Proton 2025 уже установлена."
        return 0
    fi
    log_info "Поиск актуального пакета Proton 2025..."
    asset_url=$(resolve_proton_asset_url) || return 1
    asset_name=${asset_url##*/}
    package_file="$WORK_DIR/$asset_name"
    download_to_file "$asset_url" "$package_file" || {
        log_error "Не удалось скачать пакет Proton 2025."
        return 1
    }
    [ -f "$package_file" ] && [ -s "$package_file" ] || {
        log_error "Загруженный пакет Proton 2025 пуст или недоступен."
        return 1
    }
    install_local_package "$package_file" &&
        is_package_installed "$PROTON_PACKAGE" &&
        select_luci_theme "$PROTON_MEDIA_URL" || {
            log_error "Не удалось установить или активировать Proton 2025."
            return 1
        }
    log_success "Тема Proton 2025 установлена и активирована."
}

remove_proton() {
    log_info "Переключение LuCI на Bootstrap..."
    uci set luci.main.mediaurlbase="$BOOTSTRAP_MEDIA_URL" &&
        uci commit luci || {
            log_error "Не удалось переключить LuCI на Bootstrap. Удаление отменено."
            return 1
        }
    remove_package "$PROTON_PACKAGE" || return 1
    /etc/init.d/uhttpd restart || return 1
    log_success "Тема Proton 2025 удалена."
}

status_proton() {
    package_status "$PROTON_PACKAGE" "Proton 2025"
}

# ---------------------------------------------------------------------------
# 7. ttyd
# ---------------------------------------------------------------------------

install_ttyd() {
    install_repo_package "luci-app-ttyd" || return 1
    install_repo_package "luci-i18n-ttyd-ru" || return 1
    if [ -x /etc/init.d/ttyd ]; then
        /etc/init.d/ttyd enable || return 1
        /etc/init.d/ttyd restart || return 1
    fi
    log_success "Веб-терминал ttyd установлен."
}

remove_ttyd() {
    remove_package "luci-i18n-ttyd-ru" || return 1
    remove_package "luci-app-ttyd" || return 1
    log_success "Веб-терминал ttyd удалён."
}

status_ttyd() {
    result=0
    package_status "luci-app-ttyd" "ttyd" || result=1
    package_status "luci-i18n-ttyd-ru" "Русская локализация" || result=1
    return "$result"
}

# ---------------------------------------------------------------------------
# 8. SFTP
# ---------------------------------------------------------------------------

install_sftp() {
    install_repo_package "openssh-sftp-server" || return 1
    log_success "SFTP-сервер установлен. Dropbear продолжает обслуживать SSH."
}

remove_sftp() {
    remove_package "openssh-sftp-server" || return 1
    log_success "SFTP-сервер удалён. Dropbear не изменён."
}

status_sftp() {
    package_status "openssh-sftp-server" "OpenSSH SFTP server"
}

# ---------------------------------------------------------------------------
# 9. Aggregate operations
# ---------------------------------------------------------------------------

run_and_report() {
    label=$1
    action=$2
    if "$action"; then
        printf '  %s: %sготово%s\n' "$label" "$COLOR_GREEN" "$COLOR_RESET"
        return 0
    fi
    printf '  %s: %sошибка%s\n' "$label" "$COLOR_RED" "$COLOR_RESET"
    return 1
}

install_all() {
    result=0
    run_and_report "Proton 2025" install_proton || result=1
    run_and_report "ttyd" install_ttyd || result=1
    run_and_report "SFTP" install_sftp || result=1
    return "$result"
}

remove_all() {
    result=0
    run_and_report "SFTP" remove_sftp || result=1
    run_and_report "ttyd" remove_ttyd || result=1
    run_and_report "Proton 2025" remove_proton || result=1
    return "$result"
}

status_all() {
    result=0
    status_proton || result=1
    status_ttyd || result=1
    status_sftp || result=1
    return "$result"
}

# ---------------------------------------------------------------------------
# 10. Menus
# ---------------------------------------------------------------------------

pause_if_interactive() {
    if [ -t 0 ]; then
        printf '\nНажмите Enter, чтобы продолжить...'
        read -r _pause
    fi
}

component_menu() {
    title=$1
    install_action=$2
    remove_action=$3
    status_action=$4
    while :; do
        separator
        printf '%s%s%s\n\n' "$COLOR_BOLD" "$title" "$COLOR_RESET"
        printf '%s\n' "1. Установить" "2. Удалить" "3. Показать состояние" "0. Назад"
        printf '\nВыберите действие: '
        read -r choice || return 0
        case "$choice" in
            1) "$install_action"; pause_if_interactive ;;
            2) "$remove_action"; pause_if_interactive ;;
            3) "$status_action" || true; pause_if_interactive ;;
            0) return 0 ;;
            *) log_warn "Неизвестный пункт: $choice" ;;
        esac
    done
}

all_components_menu() {
    component_menu "Все компоненты" install_all remove_all status_all
}

main_menu() {
    while :; do
        separator
        printf '%sOpenWrt Toolbox%s\n' "$COLOR_BOLD" "$COLOR_RESET"
        printf 'Версия: %s\n' "$TOOLBOX_VERSION"
        printf 'Система: OpenWrt %s\n' "$OPENWRT_VERSION"
        printf 'Менеджер пакетов: %s\n\n' "$PKG_MANAGER"
        printf '%s\n' \
            "1. Все компоненты" \
            "2. Тема Proton 2025" \
            "3. Веб-терминал ttyd" \
            "4. SFTP-сервер" \
            "0. Выход"
        printf '\nВыберите пункт: '
        read -r choice || return 0
        case "$choice" in
            1) all_components_menu ;;
            2) component_menu "Тема Proton 2025" install_proton remove_proton status_proton ;;
            3) component_menu "Веб-терминал ttyd" install_ttyd remove_ttyd status_ttyd ;;
            4) component_menu "SFTP-сервер" install_sftp remove_sftp status_sftp ;;
            0) return 0 ;;
            *) log_warn "Неизвестный пункт: $choice" ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 11. Entry point
# ---------------------------------------------------------------------------

main() {
    require_root || exit 1
    require_openwrt || exit 1
    load_openwrt_release
    detect_package_manager || exit 1
    require_downloader || exit 1
    prepare_work_dir || exit 1
    main_menu
}

if [ "${OPENWRT_TOOLBOX_TESTING:-0}" != "1" ]; then
    main "$@"
fi
