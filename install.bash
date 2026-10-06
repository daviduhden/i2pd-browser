#!/bin/bash

# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# I2Pd Browser installer and router manager.
#
# It selects and persists the I2P router backend (i2pd or I2P Java),
# prepares its configuration and provides simple lifecycle commands.

set -Eeuo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &&
	pwd -P)"

# shellcheck source=lib/router.bash
# shellcheck disable=SC1091
source "$_script_dir/lib/router.bash"

PROXY_TIMEOUT="${PROXY_TIMEOUT:-90}"

subcommand="install"
option_router=""
non_interactive=0
no_browser=0
install_deps=0
no_start=0

usage() {
	cat <<'EOF'
Usage: install.bash [COMMAND] [OPTIONS]

Commands:
  install      Select the I2P router and prepare the browser (default).
  configure    Change the selected I2P router.
  start        Start the selected I2P router.
  stop         Stop the router started by I2Pd Browser.
  restart      Restart the router started by I2Pd Browser.
  status       Show the selected router and its state.
  console      Open the router console of the selected backend.
  detect       List the detected I2P router backends.

Options:
  --i2p-router=NAME   Select the backend: i2pd or i2p-java.
  --non-interactive   Never prompt; use the stored or default backend.
  --no-browser        Do not build the Firefox ESR bundle.
  --no-start          Do not start the router after install/configure.
  --install-deps      Install missing router packages automatically.
  -h, --help          Show this help.
EOF
}

parse_args() {
	while (($#)); do
		case "$1" in
		install | configure | start | stop | restart | status | console | detect)
			subcommand="$1"
			shift
			;;
		--i2p-router=*)
			option_router="${1#*=}"
			shift
			;;
		--i2p-router)
			if [[ $# -lt 2 ]]; then
				router_error "--i2p-router requires a value."
				exit 2
			fi
			option_router="$2"
			shift 2
			;;
		--non-interactive)
			non_interactive=1
			shift
			;;
		--no-browser)
			no_browser=1
			shift
			;;
		--no-start)
			no_start=1
			shift
			;;
		--install-deps)
			install_deps=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			router_error "Unknown argument: $1"
			usage >&2
			exit 2
			;;
		esac
	done
}

# Choose the backend from the command line, the stored value, the
# interactive prompt, or the historical default. Never prompts when a
# selection was already stored or when running non-interactively.
choose_backend() {
	local requested="$1"
	local existing

	if [[ -n $requested ]]; then
		router_require_valid_backend "$requested" || return 1
		printf '%s\n' "$requested"
		return 0
	fi

	existing="$(router_conf_get)"
	if [[ -n $existing ]] && router_is_valid_backend "$existing"; then
		printf '%s\n' "$existing"
		return 0
	fi

	if ((non_interactive == 1)) || [[ ! -t 0 ]]; then
		printf '%s\n' "$I2P_ROUTER_DEFAULT"
		return 0
	fi

	router_select_interactive
}

ensure_backend_available() {
	if router_is_installed && ! router_is_misconfigured; then
		return 0
	fi

	router_warn "$ROUTER_BACKEND_PRETTY is not available on this" \
		"system."
	router_dependency_hint || true

	if ((install_deps == 1)); then
		router_log "Attempting to install the required packages..."
		if router_install_dependencies && router_is_installed &&
			! router_is_misconfigured; then
			return 0
		fi
		router_error "Automatic dependency installation failed."
	fi

	router_error "Install $ROUTER_BACKEND_PRETTY and run the" \
		"installer again, or pass --install-deps."
	return 1
}

build_browser_if_needed() {
	if [[ -x "$I2PD_BROWSER_ROOT/browser/firefox" ]]; then
		router_log "The Firefox ESR bundle is already built."
		return 0
	fi
	router_log "Building the Firefox ESR bundle..."
	(
		cd "$I2PD_BROWSER_ROOT/build" || exit 1
		./build
	)
}

validate_browser_proxy() {
	local policies="$I2PD_BROWSER_ROOT/browser"
	local expected got

	policies+="/distribution/policies.json"
	expected="$(router_http_proxy)"

	if [[ ! -r $policies ]]; then
		router_warn "No built browser configuration to validate." \
			"Run './build/build' before launching Firefox."
		return 0
	fi

	if command -v jq >/dev/null 2>&1; then
		got="$(jq -r '.policies.Proxy.HTTPProxy // empty' "$policies")"
		if [[ -n $got && $got != "$expected" ]]; then
			router_warn "The Firefox proxy ($got) does not match the" \
				"selected router proxy ($expected);" \
				"rebuild the browser."
			return 1
		fi
	fi

	router_log "Firefox proxy endpoint: $expected"
	return 0
}

wait_for_proxy_or_warn() {
	if ((no_start == 1)); then
		return 0
	fi
	router_start || return 1
	if router_wait_for_proxy "$PROXY_TIMEOUT"; then
		router_log "The I2P HTTP proxy is reachable at" \
			"$(router_http_proxy)."
	else
		router_warn "The I2P HTTP proxy did not become reachable" \
			"within ${PROXY_TIMEOUT}s; it may still be starting."
	fi
	return 0
}

print_summary() {
	printf '\n'
	printf 'Router      : %s\n' "$ROUTER_BACKEND_PRETTY"
	printf 'Backend id  : %s\n' "$ROUTER_BACKEND"
	printf 'HTTP proxy  : %s\n' "$(router_http_proxy)"
	printf 'SOCKS proxy : %s\n' "$(router_socks_proxy)"
	printf 'Console     : %s\n' "$(router_console_url)"
	printf '\n'
	printf 'Run ./start-i2pd-browser.desktop to launch Firefox.\n'
}

cmd_install() {
	local backend

	backend="$(choose_backend "$option_router")" || exit 1
	router_conf_set "$backend" || exit 1
	router_load_backend "$backend" || exit 1

	router_log "Selected router: $ROUTER_BACKEND_PRETTY"

	ensure_backend_available || exit 1
	router_prepare_config || exit 1

	if ((no_browser == 0)); then
		build_browser_if_needed || exit 1
	fi

	validate_browser_proxy || true
	wait_for_proxy_or_warn || exit 1
	print_summary
}

cmd_configure() {
	local backend="$option_router"
	local current current_pretty

	current="$(router_conf_get)"
	if [[ -z $backend && -n $current ]]; then
		backend="$current"
	fi
	if [[ -z $backend ]]; then
		backend="$I2P_ROUTER_DEFAULT"
	fi
	router_require_valid_backend "$backend" || exit 1

	if [[ -n $current && $current != "$backend" ]] &&
		router_is_valid_backend "$current"; then
		current_pretty="$(router_backend_pretty "$current")"
		router_log "Switching from $current_pretty" \
			"to $(router_backend_pretty "$backend")."
		if router_load_backend "$current"; then
			if router_is_running; then
				if router_is_managed; then
					router_stop || exit 1
				else
					router_warn "$(router_backend_pretty "$current")" \
						"is running but is not managed; leaving it" \
						"running."
				fi
			fi
		fi
	fi

	router_conf_set "$backend" || exit 1
	router_load_backend "$backend" || exit 1
	router_log "Selected router: $ROUTER_BACKEND_PRETTY"

	ensure_backend_available || exit 1
	router_prepare_config || exit 1
	validate_browser_proxy || true
	wait_for_proxy_or_warn || exit 1
	print_summary
}

load_backend_for_command() {
	if [[ -n $option_router ]]; then
		router_require_valid_backend "$option_router" || return 1
		router_load_backend "$option_router" || return 1
	else
		router_load_configured_backend || return 1
	fi
}

cmd_start() {
	load_backend_for_command || exit 1
	router_log "Selected router: $ROUTER_BACKEND_PRETTY"
	router_start
}

cmd_stop() {
	load_backend_for_command || exit 1
	router_stop
}

cmd_restart() {
	load_backend_for_command || exit 1
	router_restart
}

cmd_status() {
	load_backend_for_command || exit 1

	printf 'Router      : %s\n' "$ROUTER_BACKEND_PRETTY"
	printf 'Backend id  : %s\n' "$ROUTER_BACKEND"
	printf 'State       : %s\n' "$(router_state)"
	printf 'HTTP proxy  : %s\n' "$(router_http_proxy)"
	printf 'SOCKS proxy : %s\n' "$(router_socks_proxy)"
	printf 'Console     : %s\n' "$(router_console_url)"
}

cmd_console() {
	local url
	load_backend_for_command || exit 1
	url="$(router_console_url)"

	if command -v xdg-open >/dev/null 2>&1; then
		xdg-open "$url"
	else
		printf '%s\n' "$url"
	fi
}

cmd_detect() {
	local name
	for name in "${I2P_ROUTER_CHOICES[@]}"; do
		if router_load_backend "$name" 2>/dev/null; then
			printf '%-9s %-14s %s\n' \
				"$name" "$(router_state)" "$(router_console_url)"
		else
			printf '%-9s %s\n' "$name" "unavailable"
		fi
	done
}

main() {
	parse_args "$@"

	case "$subcommand" in
	install) cmd_install ;;
	configure) cmd_configure ;;
	start) cmd_start ;;
	stop) cmd_stop ;;
	restart) cmd_restart ;;
	status) cmd_status ;;
	console) cmd_console ;;
	detect) cmd_detect ;;
	*)
		router_error "Unknown command: $subcommand"
		usage >&2
		exit 2
		;;
	esac
}

main "$@"
