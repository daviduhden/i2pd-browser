#!/usr/bin/env bash

# Exercise the production policy helper without network or a Firefox build.
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# These values are read by the router library loaded through the computed path.
# shellcheck disable=SC2034
ROUTER_HTTP_PROXY_HOST=127.0.0.1
# shellcheck disable=SC2034
ROUTER_HTTP_PROXY_PORT=15444
# shellcheck disable=SC2034
I2PD_BROWSER_ROOT="$root"
# ShellCheck cannot resolve this source path because it is computed at runtime.
# shellcheck disable=SC1091
source "$root/lib/router.bash"
router_validate_proxy_settings
# shellcheck disable=SC1091
source "$root/lib/browser-policy.bash"

source_policy="$root/build/preferences/distribution/policies.json"
generated_policy="$tmp_dir/policies.json"
browser_policy_generate "$source_policy" "$generated_policy" "$(router_http_proxy)"
browser_policy_validate "$generated_policy" '127.0.0.1:15444'

jq --arg expected "127.0.0.1:15444" -e '
	.policies.Proxy.Mode == "manual" and
	.policies.Proxy.Locked == true and
	.policies.Proxy.HTTPProxy == $expected and
	.policies.Proxy.SSLProxy == $expected and
	.policies.Proxy.UseProxyForDNS == true and
	.policies.Proxy.Passthrough == ""
' "$generated_policy" >/dev/null

# Refuse invalid endpoints before touching the previously published policy.
cp "$generated_policy" "$tmp_dir/original.json"
for endpoint in 127.0.0.1:0 127.0.0.1:65536 127.0.0.1:-1 \
	127.0.0.1:4444x localhost:4444 0.0.0.0:4444 example.com:4444; do
	if browser_policy_generate "$source_policy" "$generated_policy" "$endpoint"; then
		printf 'Invalid endpoint accepted: %s\n' "$endpoint" >&2
		exit 1
	fi
	cmp "$generated_policy" "$tmp_dir/original.json"
done

# A valid endpoint must not hide weakened or missing privacy controls.
for mutation in '.policies.Proxy.Locked = false' \
	'.policies.Proxy.Mode = "system"' \
	'.policies.Proxy.UseProxyForDNS = false' \
	'.policies.Proxy.Passthrough = "localhost"' \
	'del(.policies.Proxy)' '.policies.DNSOverHTTPS.Enabled = true' \
	'.policies.DisableTelemetry = false' '.policies.DisableAppUpdate = false'; do
	jq "$mutation" "$source_policy" >"$tmp_dir/unsafe.json"
	if browser_policy_generate "$tmp_dir/unsafe.json" "$generated_policy" '127.0.0.1:15444'; then
		printf 'Unsafe policy accepted: %s\n' "$mutation" >&2
		exit 1
	fi
	cmp "$generated_policy" "$tmp_dir/original.json"
done
printf '{invalid JSON\n' >"$tmp_dir/unsafe.json"
if browser_policy_generate "$tmp_dir/unsafe.json" "$generated_policy" '127.0.0.1:15444'; then
	printf 'Malformed policy accepted.\n' >&2
	exit 1
fi
cmp "$generated_policy" "$tmp_dir/original.json"
for port in 1 65535; do
	browser_policy_generate "$source_policy" "$generated_policy" "127.0.0.1:$port"
	browser_policy_validate "$generated_policy" "127.0.0.1:$port"
done

printf 'Proxy policy behavior tests passed.\n'
