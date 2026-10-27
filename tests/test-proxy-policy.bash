#!/usr/bin/env bash

# Verify that the same endpoint override used by the builders replaces both
# fixed proxy endpoints in the generated Firefox policy.
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

source_policy="$root/build/preferences/distribution/policies.json"
generated_policy="$tmp_dir/policies.json"
jq --arg endpoint "$(router_http_proxy)" \
	'.policies.Proxy.HTTPProxy = $endpoint |
	 .policies.Proxy.SSLProxy = $endpoint' \
	"$source_policy" >"$generated_policy"

jq --arg expected "127.0.0.1:15444" -e '
	.policies.Proxy.Mode == "manual" and
	.policies.Proxy.Locked == true and
	.policies.Proxy.HTTPProxy == $expected and
	.policies.Proxy.SSLProxy == $expected and
	.policies.Proxy.UseProxyForDNS == true and
	.policies.Proxy.Passthrough == ""
' "$generated_policy" >/dev/null

printf 'Proxy policy override test passed.\n'
