#!/usr/bin/env bash

# Shared by the builder and offline policy regression tests. This library
# neither resolves downloads nor starts Firefox or a router.
browser_policy_endpoint_valid() {
	local endpoint="$1" port
	[[ $endpoint =~ ^127\.0\.0\.1:([0-9]{1,5})$ ]] || return 1
	port="${BASH_REMATCH[1]}"
	((10#$port >= 1 && 10#$port <= 65535))
}

browser_policy_validate() {
	local policy="$1" endpoint="$2"
	browser_policy_endpoint_valid "$endpoint" || return 1
	jq --arg endpoint "$endpoint" -e '
		.policies.Proxy.Mode == "manual" and
		.policies.Proxy.Locked == true and
		.policies.Proxy.HTTPProxy == $endpoint and
		.policies.Proxy.SSLProxy == $endpoint and
		.policies.Proxy.UseProxyForDNS == true and
		.policies.Proxy.Passthrough == "" and
		.policies.DNSOverHTTPS.Enabled == false and
		.policies.DNSOverHTTPS.Locked == true and
		.policies.DisableTelemetry == true and
		.policies.DisableAppUpdate == true
	' "$policy" >/dev/null
}

browser_policy_generate() {
	local input="$1" output="$2" endpoint="$3" temporary
	browser_policy_endpoint_valid "$endpoint" || return 1
	temporary="$(mktemp "${output}.tmp.XXXXXX")" || return 1
	if jq --arg endpoint "$endpoint" '
		.policies.Proxy.HTTPProxy = $endpoint |
		.policies.Proxy.SSLProxy = $endpoint
	' "$input" >"$temporary" &&
		browser_policy_validate "$temporary" "$endpoint" &&
		mv -f -- "$temporary" "$output"; then
		return 0
	fi
	rm -f -- "$temporary"
	return 1
}
