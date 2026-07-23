#!/bin/sh

set -u

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$PROJECT_DIR/openwrt-toolbox.sh"
TEST_ROOT=$(mktemp -d /tmp/openwrt-toolbox-tests.XXXXXX) || exit 1
BASE_PATH=$PATH
PASS=0
FAIL=0

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT INT TERM

pass() {
    PASS=$((PASS + 1))
    printf 'ok - %s\n' "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf 'not ok - %s\n' "$1" >&2
}

assert_eq() {
    name=$1
    expected=$2
    actual=$3
    if [ "$expected" = "$actual" ]; then
        pass "$name"
    else
        fail "$name (expected: $expected, actual: $actual)"
    fi
}

make_command() {
    directory=$1
    command_name=$2
    mkdir -p "$directory"
    {
        printf '%s\n' '#!/bin/sh'
        printf '%s\n' 'exit 0'
    } > "$directory/$command_name"
    chmod +x "$directory/$command_name"
}

source_and_run() {
    PATH=$1 OPENWRT_TOOLBOX_TESTING=1 sh -c \
        '. "$1"; shift; "$@"' sh "$SCRIPT" "$2"
}

test_version() {
    actual=$(OPENWRT_TOOLBOX_TESTING=1 sh -c \
        '. "$1"; printf "%s" "$TOOLBOX_VERSION"' sh "$SCRIPT")
    assert_eq "version is 0.0.1" "0.0.1" "$actual"
}

test_apk_preferred() {
    bin="$TEST_ROOT/both"
    make_command "$bin" apk
    make_command "$bin" opkg
    actual=$(source_and_run "$bin:$BASE_PATH" detect_package_manager_and_print)
    assert_eq "apk is preferred when both exist" "apk" "$actual"
}

test_opkg_fallback() {
    bin="$TEST_ROOT/opkg"
    make_command "$bin" opkg
    actual=$(source_and_run "$bin:$BASE_PATH" detect_package_manager_and_print)
    assert_eq "opkg is used when apk is absent" "opkg" "$actual"
}

assert_script_contains() {
    name=$1
    pattern=$2
    if grep -F "$pattern" "$SCRIPT" >/dev/null 2>&1; then
        pass "$name"
    else
        fail "$name (missing: $pattern)"
    fi
}

test_required_operations() {
    assert_script_contains "opkg update mapping" 'opkg update'
    assert_script_contains "apk update mapping" 'apk update'
    assert_script_contains "trusted apk local install is explicit" 'apk add --allow-untrusted'
    assert_script_contains "ttyd application is managed" 'luci-app-ttyd'
    assert_script_contains "ttyd Russian locale is managed" 'luci-i18n-ttyd-ru'
    assert_script_contains "SFTP server is managed" 'openssh-sftp-server'
    assert_script_contains "Bootstrap is restored before theme removal" \
        'uci set luci.main.mediaurlbase="$BOOTSTRAP_MEDIA_URL"'
    assert_script_contains "Proton release API is used" \
        'api.github.com/repos/$PROTON_REPOSITORY/releases/latest'
}

test_release_asset_resolution() {
    fixture="$TEST_ROOT/release.json"
    work="$TEST_ROOT/work"
    mkdir -p "$work"
    cat > "$fixture" <<'EOF'
{
  "assets": [
    {"browser_download_url": "https://example.test/luci-theme-proton2025_1.3.0_all.ipk"},
    {"browser_download_url": "https://example.test/luci-theme-proton2025_1.3.0_all.ipk.sha256"},
    {"browser_download_url": "https://example.test/luci-theme-proton2025-1.3.0.apk"},
    {"browser_download_url": "https://example.test/luci-theme-proton2025-1.3.0.apk.sha256"}
  ]
}
EOF
    actual=$(
        OPENWRT_TOOLBOX_TESTING=1 sh -c '
            . "$1"
            PKG_MANAGER=opkg
            WORK_DIR=$2
            FIXTURE=$3
            download_to_file() { cp "$FIXTURE" "$2"; }
            resolve_proton_asset_url
        ' sh "$SCRIPT" "$work" "$fixture"
    )
    assert_eq "IPK release asset is resolved uniquely" \
        "https://example.test/luci-theme-proton2025_1.3.0_all.ipk" "$actual"

    actual=$(
        OPENWRT_TOOLBOX_TESTING=1 sh -c '
            . "$1"
            PKG_MANAGER=apk
            WORK_DIR=$2
            FIXTURE=$3
            download_to_file() { cp "$FIXTURE" "$2"; }
            resolve_proton_asset_url
        ' sh "$SCRIPT" "$work" "$fixture"
    )
    assert_eq "APK release asset is resolved uniquely" \
        "https://example.test/luci-theme-proton2025-1.3.0.apk" "$actual"
}

test_version
test_apk_preferred
test_opkg_fallback
test_required_operations
test_release_asset_resolution

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
