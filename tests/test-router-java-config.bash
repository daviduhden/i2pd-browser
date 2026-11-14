#!/usr/bin/env bash

# Real Java configuration staging/rollback with one failed rename injected.
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
export I2PD_BROWSER_ROOT="$root" I2PD_BROWSER_CONF="$tmp_dir/selection.conf"
export ROUTER_HTTP_PROXY_HOST=127.0.0.1 ROUTER_HTTP_PROXY_PORT=15444
export ROUTER_SOCKS_PROXY_HOST=127.0.0.1 ROUTER_SOCKS_PROXY_PORT=4447
# shellcheck disable=SC1091
source "$root/lib/router.bash"
# shellcheck disable=SC1091
source "$root/lib/backends/i2p-java.bash"
BACKEND_DATA_DIR="$tmp_dir/data"
cp -r "$root/i2p-java/config" "$BACKEND_DATA_DIR"
printf '\ncustom.fixture=preserved\n' >>"$BACKEND_DATA_DIR/router.config"
cp -r "$BACKEND_DATA_DIR" "$tmp_dir/original"

assert_original() {
	local file
	for file in i2ptunnel.config addressbook/config.txt router.config clients.config; do
		cmp "$BACKEND_DATA_DIR/$file" "$tmp_dir/original/$file"
	done
}

# Fail the second publication rename, after i2ptunnel.config was committed.
# The sourced configuration publisher invokes this double indirectly.
# shellcheck disable=SC2329
mv() {
	if [[ $1 == */new/addressbook/config.txt ]]; then return 1; fi
	command mv "$@"
}
if i2p_java_apply_proxy_overrides; then
	printf 'Injected Java configuration publication failure succeeded.\n' >&2
	exit 1
fi
assert_original
unset -f mv

ROUTER_HTTP_PROXY_PORT=65536
if i2p_java_apply_proxy_overrides; then
	printf 'Invalid Java proxy port accepted.\n' >&2
	exit 1
fi
assert_original
ROUTER_HTTP_PROXY_PORT=15444
i2p_java_apply_proxy_overrides
i2p_java_validate_config_dir "$BACKEND_DATA_DIR"
[[ $(i2p_java_config_value "$BACKEND_DATA_DIR/i2ptunnel.config" tunnel.0.listenPort) == 15444 ]]
[[ $(i2p_java_config_value "$BACKEND_DATA_DIR/addressbook/config.txt" proxy_port) == 15444 ]]
[[ $(i2p_java_config_value "$BACKEND_DATA_DIR/router.config" router.updateProxyPort) == 15444 ]]
grep -qx 'custom.fixture=preserved' "$BACKEND_DATA_DIR/router.config"
cmp "$BACKEND_DATA_DIR/clients.config" "$tmp_dir/original/clients.config"

# Reject Java Properties syntax that could alias a validated key when the
# upstream parser decodes whitespace, escapes, separators or continuations.
# Each mutation lives in a separate copy of the effective fixture directory.
for unsafe_line in \
	' tunnel.0.interface=0.0.0.0' \
	'tunnel.0.interface =0.0.0.0' \
	'tunnel.0.interface:0.0.0.0' \
	'tunnel\.0.interface=0.0.0.0' \
	'tunnel.\u0030.interface=0.0.0.0' \
	'tunnel.0.interface=0.0.0.0' \
	$'custom.continuation=value\\'; do
	fixture_dir="$(mktemp -d "$tmp_dir/invalid.XXXXXX")"
	cp -r "$BACKEND_DATA_DIR/." "$fixture_dir/"
	printf '\n%s\n' "$unsafe_line" >>"$fixture_dir/i2ptunnel.config"
	if i2p_java_validate_config_dir "$fixture_dir"; then
		printf 'Ambiguous Java Properties syntax accepted: %s\n' "$unsafe_line" >&2
		exit 1
	fi
done

# Equals signs inside a value remain supported by the canonical subset.
fixture_dir="$(mktemp -d "$tmp_dir/valid.XXXXXX")"
cp -r "$BACKEND_DATA_DIR/." "$fixture_dir/"
printf '\ncustom.extra=a=b=c\n' >>"$fixture_dir/router.config"
i2p_java_validate_config_dir "$fixture_dir"
[[ $(i2p_java_config_value "$fixture_dir/router.config" custom.extra) == a=b=c ]]
printf 'Java configuration rollback behavior tests passed.\n'
