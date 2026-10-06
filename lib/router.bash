#!/bin/bash

# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# Shared abstraction over the supported I2P router backends.
#
# Backend implementations live in lib/backends/<name>.bash. Each one
# defines functions prefixed with "backend_" plus a few descriptive
# variables. This file contains everything that is common to all
# routers and delegates the implementation specific parts.

set -Eeuo pipefail

# Resolve the repository root from this file's location, unless the
# caller already provided one (used by the test suite).
if [[ -z ${I2PD_BROWSER_ROOT:-} ]]; then
	_router_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &&
		pwd -P)"
	I2PD_BROWSER_ROOT="$(cd "$_router_lib_dir/.." && pwd -P)"
	unset _router_lib_dir
fi

# Internal backend identifier and human readable names.
I2P_ROUTER_DEFAULT="${I2P_ROUTER_DEFAULT:-i2pd}"
I2P_ROUTER_CHOICES=(i2pd i2p-java)

# Normalized local endpoints. Both backends are configured to listen
# on these exact addresses, so the Firefox profile does not depend on
# the selected router.
ROUTER_HTTP_PROXY_HOST="${ROUTER_HTTP_PROXY_HOST:-127.0.0.1}"
ROUTER_HTTP_PROXY_PORT="${ROUTER_HTTP_PROXY_PORT:-4444}"
ROUTER_SOCKS_PROXY_HOST="${ROUTER_SOCKS_PROXY_HOST:-127.0.0.1}"
ROUTER_SOCKS_PROXY_PORT="${ROUTER_SOCKS_PROXY_PORT:-4447}"

router_log() {
	printf '%s [INFO] %s\n' \
		"$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

router_warn() {
	printf '%s [WARN] %s\n' \
		"$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

router_error() {
	printf '%s [ERROR] %s\n' \
		"$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# ------------------------------------------------------------------
# Backend description helpers
# ------------------------------------------------------------------

router_backend_pretty() {
	case "${1-}" in
	i2pd) printf 'i2pd (C++)\n' ;;
	i2p-java) printf 'I2P (Java)\n' ;;
	*) printf '%s\n' "${1-}" ;;
	esac
}

router_is_valid_backend() {
	local name="${1-}"
	local valid

	for valid in "${I2P_ROUTER_CHOICES[@]}"; do
		[[ $name == "$valid" ]] && return 0
	done
	return 1
}

router_require_valid_backend() {
	local name="${1-}"

	if [[ -z $name ]]; then
		router_error "No I2P router backend was specified."
		return 1
	fi
	if ! router_is_valid_backend "$name"; then
		router_error "Unknown I2P router backend: '$name'."
		router_error "Valid values: ${I2P_ROUTER_CHOICES[*]}."
		return 1
	fi
	return 0
}

# ------------------------------------------------------------------
# Persistence of the selected backend
# ------------------------------------------------------------------

router_conf_file() {
	printf '%s\n' \
		"${I2PD_BROWSER_CONF:-$I2PD_BROWSER_ROOT/i2pd-browser.conf}"
}

router_conf_get() {
	local file
	file="$(router_conf_file)"

	if [[ -r $file ]]; then
		sed -n \
			's/^[[:space:]]*I2P_ROUTER[[:space:]]*=[[:space:]]*//p' \
			"$file" | tail -n 1
	fi
}

router_conf_set() {
	local name="$1"
	local file
	file="$(router_conf_file)"

	router_require_valid_backend "$name" || return 1
	cat >"$file" <<EOF
# I2Pd Browser configuration
# Selected I2P router backend. Change it with:
#   ./install.bash configure --i2p-router=<i2pd|i2p-java>
I2P_ROUTER=$name
EOF
}

# Interactive selection. Returns the chosen identifier on stdout.
router_select_interactive() {
	local reply

	printf '\nSelect I2P router:\n\n'
	printf '  1) %s\n' "$(router_backend_pretty i2pd)"
	printf '  2) %s\n\n' "$(router_backend_pretty i2p-java)"
	printf 'Choice [1]: '

	read -r reply || reply=""
	case "${reply:-1}" in
	1 | i2pd)
		printf 'i2pd\n'
		;;
	2 | i2p-java)
		printf 'i2p-java\n'
		;;
	*)
		router_error "Invalid selection: '$reply'."
		return 1
		;;
	esac
}

# ------------------------------------------------------------------
# Backend loading and dispatch
# ------------------------------------------------------------------

router_backends_dir() {
	printf '%s\n' \
		"${I2PD_BROWSER_BACKENDS_DIR:-$I2PD_BROWSER_ROOT/lib/backends}"
}

router_load_backend() {
	local name="$1"
	local file

	router_require_valid_backend "$name" || return 1
	file="$(router_backends_dir)/$name.bash"
	if [[ ! -r $file ]]; then
		router_error "Backend implementation not found: $file"
		return 1
	fi

	# shellcheck source=/dev/null
	source "$file"

	if ! declare -F backend_is_installed >/dev/null; then
		router_error "Backend '$name' does not implement the" \
			" required interface."
		return 1
	fi

	# These are consumed by the callers of this library.
	local pretty
	pretty="$(router_backend_pretty "$name")"
	# shellcheck disable=SC2034
	ROUTER_BACKEND="${BACKEND_NAME:-$name}"
	# shellcheck disable=SC2034
	ROUTER_BACKEND_PRETTY="${BACKEND_PRETTY:-$pretty}"
}

# Populate the global ROUTER_BACKEND from the stored configuration,
# defaulting to i2pd for existing installations without a conf file.
router_load_configured_backend() {
	local name

	name="$(router_conf_get)"
	if [[ -z $name ]] || ! router_is_valid_backend "$name"; then
		name="$I2P_ROUTER_DEFAULT"
	fi
	router_load_backend "$name"
}

router_http_proxy_host() {
	printf '%s\n' "${BACKEND_HTTP_PROXY_HOST:-$ROUTER_HTTP_PROXY_HOST}"
}

router_http_proxy_port() {
	printf '%s\n' "${BACKEND_HTTP_PROXY_PORT:-$ROUTER_HTTP_PROXY_PORT}"
}

router_socks_proxy_host() {
	local host
	host="${BACKEND_SOCKS_PROXY_HOST:-$ROUTER_SOCKS_PROXY_HOST}"
	printf '%s\n' "$host"
}

router_socks_proxy_port() {
	local port
	port="${BACKEND_SOCKS_PROXY_PORT:-$ROUTER_SOCKS_PROXY_PORT}"
	printf '%s\n' "$port"
}

router_http_proxy() {
	printf '%s:%s\n' \
		"$(router_http_proxy_host)" "$(router_http_proxy_port)"
}

router_socks_proxy() {
	printf '%s:%s\n' \
		"$(router_socks_proxy_host)" "$(router_socks_proxy_port)"
}

router_console_url() {
	backend_console_url
}

router_is_installed() {
	backend_is_installed
}

router_is_running() {
	backend_is_running
}

router_is_managed() {
	backend_is_managed
}

router_is_misconfigured() {
	backend_is_misconfigured
}

router_prepare_config() {
	backend_prepare_config
}

router_dependency_hint() {
	backend_dependency_hint
}

router_install_dependencies() {
	backend_install_dependencies
}

# Human readable state of the selected backend.
router_state() {
	if ! backend_is_installed; then
		printf 'not-installed\n'
	elif backend_is_running; then
		printf 'running\n'
	elif backend_is_misconfigured; then
		printf 'misconfigured\n'
	else
		printf 'stopped\n'
	fi
}

router_start() {
	if backend_is_running; then
		if backend_is_managed; then
			router_log "The I2P router is already running" \
				"(managed by I2Pd Browser)."
		else
			router_log "An I2P router instance is already running" \
				"(not managed by I2Pd Browser)."
		fi
		return 0
	fi

	if ! backend_is_installed; then
		router_error "The selected I2P router is not installed."
		backend_dependency_hint >&2 || true
		return 1
	fi
	if ! command -v screen >/dev/null 2>&1; then
		router_error "Required command 'screen' not found."
		return 1
	fi
	if backend_is_misconfigured; then
		router_error "The selected I2P router is not runnable."
		backend_dependency_hint >&2 || true
		return 1
	fi

	backend_start
}

router_stop() {
	if ! backend_is_running; then
		router_log "The I2P router is not running."
		return 0
	fi
	if ! backend_is_managed; then
		router_warn "The running I2P router was not started by" \
			"I2Pd Browser; refusing to stop it."
		router_warn "Use the system service or the router's own" \
			"tooling instead."
		return 1
	fi

	backend_stop
}

router_restart() {
	router_stop || return 1
	router_start
}

# Wait until the HTTP proxy accepts TCP connections. This only
# checks local reachability, never performs any network request.
router_wait_for_proxy() {
	local timeout="${1:-60}"
	local host port deadline now

	host="$(router_http_proxy_host)"
	port="$(router_http_proxy_port)"
	deadline=$(($(date +%s) + timeout))

	while :; do
		if (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then
			return 0
		fi
		now="$(date +%s)"
		if ((now >= deadline)); then
			return 1
		fi
		sleep 1
	done
}

# ------------------------------------------------------------------
# Dependency installation helpers
# ------------------------------------------------------------------

router_install_packages() {
	(($#)) || return 0

	local -a sudo_cmd=()
	if ((EUID != 0)); then
		sudo_cmd=(sudo)
	fi

	if command -v apt-get >/dev/null 2>&1; then
		"${sudo_cmd[@]}" apt-get update
		"${sudo_cmd[@]}" apt-get install -y "$@"
	elif command -v dnf >/dev/null 2>&1; then
		"${sudo_cmd[@]}" dnf install -y "$@"
	elif command -v pacman >/dev/null 2>&1; then
		"${sudo_cmd[@]}" pacman -S --noconfirm "$@"
	elif command -v zypper >/dev/null 2>&1; then
		"${sudo_cmd[@]}" zypper install -y "$@"
	elif command -v brew >/dev/null 2>&1; then
		brew install "$@"
	else
		router_warn "No supported package manager was found."
		return 1
	fi
}
