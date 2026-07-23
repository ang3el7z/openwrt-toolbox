# OpenWrt Toolbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build version 0.0.1 of a single-file interactive OpenWrt installer for Proton 2025, ttyd with Russian localization, and OpenSSH SFTP server.

**Architecture:** Production logic lives in one POSIX `sh` file organized into function sections. Package-manager-specific commands are isolated behind wrapper functions, while component functions use those wrappers. A shell test harness injects fake OpenWrt commands through `PATH` and a test mode so no real router is modified.

**Tech Stack:** POSIX `sh`, BusyBox `ash`, UCI, OpenWrt `opkg` and `apk`, GitHub Releases API, ShellCheck.

## Global Constraints

- Script version is exactly `0.0.1`.
- Production implementation is a single file named `openwrt-toolbox.sh`.
- Compatible with POSIX `sh` and BusyBox `ash`; no Bash-only syntax.
- Detect `apk` first and `opkg` second from available commands.
- Never remove Dropbear, Bootstrap, or automatically orphaned dependencies.
- Before removing Proton 2025, switch LuCI to Bootstrap and restart uHTTPd.
- Download Proton 2025 only from `ChesterGoodiny/luci-theme-proton2025` releases.
- Keep standard input available by documenting download-then-run rather than `wget | sh`.

---

### Task 1: Test harness and runtime foundation

**Files:**
- Create: `openwrt-toolbox.sh`
- Create: `tests/test-openwrt-toolbox.sh`

**Interfaces:**
- Produces: `detect_package_manager() -> sets PKG_MANAGER`
- Produces: `load_openwrt_release() -> sets OPENWRT_VERSION`
- Produces: `require_root()`, `require_openwrt()`, `require_downloader()`
- Produces: `main()`; skipped when `OPENWRT_TOOLBOX_TESTING=1`

- [ ] **Step 1: Write failing foundation tests**

Create a POSIX test harness that makes temporary `apk` and `opkg` executables, sources the script with `OPENWRT_TOOLBOX_TESTING=1`, and asserts:

```sh
assert_eq apk "$(PATH="$APK_BIN:$BASE_PATH" detect_and_print)"
assert_eq opkg "$(PATH="$OPKG_BIN:$BASE_PATH" detect_and_print)"
assert_failure env PATH="$EMPTY_BIN" sh -c '. ./openwrt-toolbox.sh; detect_package_manager'
```

The harness must count passes and failures and exit nonzero on any failure.

- [ ] **Step 2: Run tests and verify failure**

Run: `sh tests/test-openwrt-toolbox.sh`  
Expected: FAIL because `openwrt-toolbox.sh` and detection functions do not exist.

- [ ] **Step 3: Implement foundation**

Add the shebang, `TOOLBOX_VERSION="0.0.1"`, colors conditional on TTY, log helpers, OpenWrt/root/downloader checks, release parsing, `apk`-first detection, cleanup trap, and guarded entry point:

```sh
if [ "${OPENWRT_TOOLBOX_TESTING:-0}" != "1" ]; then
    main "$@"
fi
```

- [ ] **Step 4: Run foundation tests**

Run: `sh -n openwrt-toolbox.sh && sh tests/test-openwrt-toolbox.sh`  
Expected: syntax check succeeds and all foundation assertions pass.

- [ ] **Step 5: Commit**

```bash
git add openwrt-toolbox.sh tests/test-openwrt-toolbox.sh
git commit -m "feat: add toolbox runtime foundation"
```

### Task 2: Package-manager abstraction

**Files:**
- Modify: `openwrt-toolbox.sh`
- Modify: `tests/test-openwrt-toolbox.sh`

**Interfaces:**
- Consumes: global `PKG_MANAGER`
- Produces: `update_package_lists()`
- Produces: `install_repo_package(package)`
- Produces: `install_local_package(path)`
- Produces: `remove_package(package)`
- Produces: `is_package_installed(package)`

- [ ] **Step 1: Add failing command-mapping tests**

Fake commands append their arguments to `$COMMAND_LOG`. Assert exact mappings:

```text
opkg update
opkg install luci-app-ttyd
opkg install /tmp/theme.ipk
opkg remove luci-app-ttyd
apk update
apk add luci-app-ttyd
apk add --allow-untrusted /tmp/theme.apk
apk del luci-app-ttyd
```

Also assert that two calls to `update_package_lists` execute the manager update only once.

- [ ] **Step 2: Verify tests fail**

Run: `sh tests/test-openwrt-toolbox.sh`  
Expected: FAIL because package wrapper functions are undefined.

- [ ] **Step 3: Implement wrapper functions**

Implement `case "$PKG_MANAGER"` branches for the exact commands above. Implement installed-state checks using `opkg list-installed "$package"` and `apk info -e "$package"`. Track one update per process with `PKG_LISTS_UPDATED=0|1`.

- [ ] **Step 4: Run tests**

Run: `sh -n openwrt-toolbox.sh && sh tests/test-openwrt-toolbox.sh`  
Expected: all package mapping and update-cache tests pass.

- [ ] **Step 5: Commit**

```bash
git add openwrt-toolbox.sh tests/test-openwrt-toolbox.sh
git commit -m "feat: support apk and opkg operations"
```

### Task 3: Component operations and aggregate results

**Files:**
- Modify: `openwrt-toolbox.sh`
- Modify: `tests/test-openwrt-toolbox.sh`

**Interfaces:**
- Produces: `install_proton()`, `remove_proton()`, `status_proton()`
- Produces: `install_ttyd()`, `remove_ttyd()`, `status_ttyd()`
- Produces: `install_sftp()`, `remove_sftp()`, `status_sftp()`
- Produces: `install_all()`, `remove_all()`, `status_all()`

- [ ] **Step 1: Add failing component tests**

Use fakes to verify:

- ttyd installation requests `luci-app-ttyd` and `luci-i18n-ttyd-ru`, then enables and starts `/etc/init.d/ttyd` when present.
- SFTP installation and removal target only `openssh-sftp-server`.
- SFTP never installs or removes `dropbear`.
- Proton removal performs `uci set luci.main.mediaurlbase=/luci-static/bootstrap`, `uci commit luci`, package removal, and uHTTPd restart in that order.
- Aggregate installation order is Proton, ttyd, SFTP.
- Aggregate removal order is SFTP, ttyd, Proton.
- Aggregate functions continue after one component fails and return nonzero.

- [ ] **Step 2: Verify tests fail**

Run: `sh tests/test-openwrt-toolbox.sh`  
Expected: FAIL because component functions are undefined.

- [ ] **Step 3: Implement repository components**

Implement idempotent install/remove functions. Already installed and already absent states return success. Do not use dependency autoremove flags. Implement per-package status output for both ttyd packages.

- [ ] **Step 4: Implement Proton release resolution**

Query:

```text
https://api.github.com/repos/ChesterGoodiny/luci-theme-proton2025/releases/latest
```

Select exactly one `browser_download_url` matching `luci-theme-proton2025` and the required `.ipk` or `.apk` suffix. Reject zero or multiple matches. Download into the secured temporary directory, verify it is a nonempty regular file with the expected suffix, install it, verify package state, select `/luci-static/proton2025`, commit UCI, and restart uHTTPd.

- [ ] **Step 5: Run component tests**

Run: `sh -n openwrt-toolbox.sh && sh tests/test-openwrt-toolbox.sh`  
Expected: all component and ordering assertions pass.

- [ ] **Step 6: Commit**

```bash
git add openwrt-toolbox.sh tests/test-openwrt-toolbox.sh
git commit -m "feat: manage toolbox components"
```

### Task 4: Interactive menus

**Files:**
- Modify: `openwrt-toolbox.sh`
- Modify: `tests/test-openwrt-toolbox.sh`

**Interfaces:**
- Produces: `component_menu(title, install_fn, remove_fn, status_fn)`
- Produces: `all_components_menu()`
- Produces: `main_menu()`

- [ ] **Step 1: Add failing menu tests**

Feed scripted input and assert dispatch without changing the host:

```sh
printf '2\n3\n0\n0\n' | run_test_menu
```

Assert this opens Proton, calls only `status_proton`, returns to the main menu, and exits. Add a test that invalid input prints a warning and performs no component action.

- [ ] **Step 2: Verify tests fail**

Run: `sh tests/test-openwrt-toolbox.sh`  
Expected: FAIL because menu functions are undefined.

- [ ] **Step 3: Implement menus**

Print version, detected OpenWrt version, package manager, numbered choices, and prompts in Russian. Use `read -r`, `case`, and loops. Pause after actions only when running interactively, so test input cannot deadlock.

- [ ] **Step 4: Run menu tests**

Run: `sh -n openwrt-toolbox.sh && sh tests/test-openwrt-toolbox.sh`  
Expected: all menu dispatch tests pass.

- [ ] **Step 5: Commit**

```bash
git add openwrt-toolbox.sh tests/test-openwrt-toolbox.sh
git commit -m "feat: add interactive toolbox menu"
```

### Task 5: Documentation and final verification

**Files:**
- Modify: `README.md`
- Create: `LICENSE`
- Modify: `tests/test-openwrt-toolbox.sh`

**Interfaces:**
- Consumes: completed `openwrt-toolbox.sh`
- Produces: user-facing installation and usage documentation

- [ ] **Step 1: Expand README**

Document version 0.0.1, all three components, root/OpenWrt requirements, menu behavior, `opkg`/`apk` auto-detection, removal behavior, external theme attribution, and this exact command:

```sh
wget -O /tmp/openwrt-toolbox.sh https://raw.githubusercontent.com/ang3el7z/openwrt-toolbox/main/openwrt-toolbox.sh && sh /tmp/openwrt-toolbox.sh
```

- [ ] **Step 2: Add license**

Add the MIT License for original toolbox code. State in README that Proton 2025 remains governed by its own upstream license and is not redistributed by this repository.

- [ ] **Step 3: Run automated verification**

Run:

```sh
sh -n openwrt-toolbox.sh
sh tests/test-openwrt-toolbox.sh
shellcheck -s sh openwrt-toolbox.sh tests/test-openwrt-toolbox.sh
```

Expected: syntax succeeds, test summary reports zero failures, and ShellCheck reports no findings. If ShellCheck is unavailable, record that limitation and still run syntax and behavioral tests.

- [ ] **Step 4: Perform remote-source sanity check**

Verify the latest Proton release contains exactly one matching asset for each supported manager. Do not install it on the development host.

- [ ] **Step 5: Review diff and commit**

Run: `git diff --check && git status --short`  
Expected: no whitespace errors; only intended files are changed.

```bash
git add README.md LICENSE openwrt-toolbox.sh tests/test-openwrt-toolbox.sh
git commit -m "docs: document OpenWrt Toolbox 0.0.1"
```

- [ ] **Step 6: Router verification checklist**

On disposable OpenWrt test systems, verify:

1. one `opkg`-based router installs, reports, and removes all components;
2. one `apk`-based router installs, reports, and removes all components;
3. LuCI remains reachable after Proton removal;
4. ttyd appears in LuCI and starts;
5. an SFTP client can connect through Dropbear;
6. repeating every install and removal operation is safe.
