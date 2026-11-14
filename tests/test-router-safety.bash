#!/usr/bin/env bash

# Offline regression tests: selection output, configuration write boundaries,
# and refusal to start or stop an unsafe/unowned router. Backend doubles never
# launch a real process or contact a service.
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
export I2PD_BROWSER_ROOT="$root" I2PD_BROWSER_CONF="$tmp_dir/selection.conf"
export ROUTER_HTTP_PROXY_HOST=127.0.0.1 ROUTER_HTTP_PROXY_PORT=4444
export ROUTER_SOCKS_PROXY_HOST=127.0.0.1 ROUTER_SOCKS_PROXY_PORT=4447
# shellcheck disable=SC1091
source "$root/lib/router.bash"

assert_equal() {
	[[ $1 == "$2" ]] || {
		printf 'Expected %q, got %q\n' "$2" "$1" >&2
		exit 1
	}
}

# Call exactly as the installer does: prompts must not pollute the value.
assert_equal "$(router_select_interactive <<<2 2>"$tmp_dir/prompts")" i2p-java
[[ -s $tmp_dir/prompts ]]
assert_equal "$(router_select_interactive <<<'')" i2pd
assert_equal "$(router_select_source_interactive <<<2)" vendored
assert_equal "$(router_select_source_interactive <<<'')" system
if router_select_interactive <<<invalid >"$tmp_dir/result" 2>/dev/null; then
	printf 'Invalid selection accepted.\n' >&2
	exit 1
fi
[[ ! -s $tmp_dir/result ]]

printf 'CUSTOM_SETTING=preserved\nI2P_ROUTER=i2pd\n' >"$I2PD_BROWSER_CONF"
cp "$I2PD_BROWSER_CONF" "$tmp_dir/original.conf"
if router_conf_set unknown system en-US 2>/dev/null; then
	printf 'Invalid backend selection persisted.\n' >&2
	exit 1
fi
cmp "$I2PD_BROWSER_CONF" "$tmp_dir/original.conf"
router_conf_set i2p-java vendored es-ES
assert_equal "$(router_conf_get)" i2p-java
assert_equal "$(router_conf_get_source)" vendored
grep -qx 'CUSTOM_SETTING=preserved' "$I2PD_BROWSER_CONF"

# A backend write serves as a sentinel for mutations behind validation.
backend_prepare_config() { printf 'prepared\n' >>"$tmp_dir/backend-writes"; }
backend_validate_config() { [[ ! -e $tmp_dir/unsafe-config ]]; }
backend_is_running() { return 0; }
backend_is_managed() { return 1; }
backend_start() { printf 'started\n' >>"$tmp_dir/backend-writes"; }
backend_stop() { printf 'stopped\n' >>"$tmp_dir/backend-writes"; }

for invalid_port in 0 65536 -1 999999999999999999999999 4444x; do
	ROUTER_HTTP_PROXY_PORT="$invalid_port"
	if router_prepare_config 2>/dev/null; then
		printf 'Invalid endpoint reached configuration preparation.\n' >&2
		exit 1
	fi
	[[ ! -e $tmp_dir/backend-writes ]]
done
ROUTER_HTTP_PROXY_PORT=4444
ROUTER_SOCKS_PROXY_HOST=0.0.0.0
if router_prepare_config 2>/dev/null; then
	printf 'Non-loopback SOCKS endpoint accepted.\n' >&2
	exit 1
fi
[[ ! -e $tmp_dir/backend-writes ]]
ROUTER_SOCKS_PROXY_HOST=127.0.0.1
touch "$tmp_dir/unsafe-config"
if router_start 2>/dev/null; then
	printf 'Unsafe effective configuration was accepted.\n' >&2
	exit 1
fi
[[ ! -e $tmp_dir/backend-writes ]]
if router_stop >/dev/null; then
	printf 'Unmanaged router stop succeeded.\n' >&2
	exit 1
fi
[[ ! -e $tmp_dir/backend-writes ]]
printf 'Router safety behavior tests passed.\n'
