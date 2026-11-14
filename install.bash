#!/bin/bash

# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# I2Pd Browser installer and router manager.
#
# It selects and persists the I2P router backend (i2pd or I2P Java),
# prepares its configuration and provides simple lifecycle commands.

# Treat unset variables and failed pipeline components as errors; keep this
# strict mode in mind when adding optional values or sourced helper commands.
set -Eeuo pipefail

_initial_language_override="${I2PD_BROWSER_LANGUAGE:-${language:-}}"

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &&
	pwd -P)"

# shellcheck source=lib/router.bash
# shellcheck disable=SC1091
source "$_script_dir/lib/router.bash"
# shellcheck source=lib/browser-policy.bash
# shellcheck disable=SC1091
source "$_script_dir/lib/browser-policy.bash"

PROXY_TIMEOUT="${PROXY_TIMEOUT:-90}"

subcommand="install"
option_router=""
option_source=""
option_language=""
non_interactive=0
no_browser=0
install_deps=0
no_start=0
show_help=0

usage() {
	router_t usage.header "./install.bash"
	router_t usage.commands
	router_t usage.options
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
		--language=*)
			option_language="${1#*=}"
			shift
			;;
		--language)
			if [[ $# -lt 2 ]]; then
				router_error "$(router_t error.argument-value --language)"
				exit 2
			fi
			option_language="$2"
			shift 2
			;;
		--i2p-router)
			if [[ $# -lt 2 ]]; then
				router_error "--i2p-router requires a value."
				exit 2
			fi
			option_router="$2"
			shift 2
			;;
		--router-source=*)
			option_source="${1#*=}"
			shift
			;;
		--router-source)
			if [[ $# -lt 2 ]]; then
				router_error "--router-source requires a value."
				exit 2
			fi
			option_source="$2"
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
		--no-install-deps)
			install_deps=0
			shift
			;;
		-h | --help)
			show_help=1
			shift
			;;
		*)
			router_error "$(router_t error.unknown-argument "$1")"
			usage >&2
			exit 2
			;;
		esac
	done
}

choose_language() {
	local requested="$1" selected reply
	if [[ -n $requested ]]; then
		selected="$(i18n_normalize_locale "$requested")" || return 1
		printf '%s\n' "$selected"
		return 0
	fi
	if [[ -n $(i18n_stored_locale) || -n $_initial_language_override ]] ||
		((non_interactive == 1)) || [[ ! -t 0 ]]; then
		i18n_select_locale
		return 0
	fi
	router_t prompt.language >&2
	read -r reply || reply=""
	case "${reply:-1}" in
	1 | en-US) printf 'en-US\n' ;;
	2 | es-ES) printf 'es-ES\n' ;;
	3 | ru) printf 'ru\n' ;;
	4 | zh-CN) printf 'zh-CN\n' ;;
	*) return 1 ;;
	esac
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

# Choose the router source (system or vendored), mirroring
# choose_backend.
choose_source() {
	local requested="$1"
	local existing

	if [[ -n $requested ]]; then
		router_require_valid_source "$requested" || return 1
		printf '%s\n' "$requested"
		return 0
	fi

	existing="$(router_conf_get_source)"
	if [[ -n $existing ]] && router_is_valid_source "$existing"; then
		printf '%s\n' "$existing"
		return 0
	fi

	if ((non_interactive == 1)) || [[ ! -t 0 ]]; then
		printf '%s\n' "$I2P_ROUTER_SOURCE_DEFAULT"
		return 0
	fi

	router_select_source_interactive
}

ensure_backend_available() {
	if [[ ${ROUTER_SOURCE:-system} == vendored ]]; then
		if router_is_installed; then
			if router_is_misconfigured; then
				router_warn "$ROUTER_BACKEND_PRETTY is installed but" \
					"a runtime dependency is missing."
			fi
			return 0
		fi
		router_log "Installing the vendored $ROUTER_BACKEND_PRETTY" \
			"build..."
		if router_vendor_install && router_is_installed; then
			if router_is_misconfigured; then
				router_warn "$ROUTER_BACKEND_PRETTY is installed but" \
					"a runtime dependency is missing."
			fi
			return 0
		fi
		router_error "Could not install the vendored" \
			"$ROUTER_BACKEND_PRETTY build."
		return 1
	fi

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
		router_error "Install $ROUTER_BACKEND_PRETTY manually, or" \
			"pass --router-source=vendored."
	else
		router_error "Install $ROUTER_BACKEND_PRETTY and run the" \
			"installer again, or pass --install-deps or" \
			"--router-source=vendored."
	fi
	return 1
}

build_inputs_newer() {
	local marker="$I2PD_BROWSER_ROOT/browser/.i2pd-browser-locale"
	local newer

	[[ -r $marker ]] || return 1
	newer="$(find "$I2PD_BROWSER_ROOT/build" \
		"$I2PD_BROWSER_ROOT/lib/i18n.bash" \
		"$I2PD_BROWSER_ROOT/lib/i18n.ps1" \
		"$I2PD_BROWSER_ROOT/locales" \
		-type f \
		! -path "$I2PD_BROWSER_ROOT/build/firefox/*" \
		! -name 'SHA512SUMS' \
		! -name 'firefox-*.tar.*' \
		-newer "$marker" -print -quit 2>/dev/null)"
	[[ -n $newer ]]
}

build_browser_if_needed() {
	local locale_file="$I2PD_BROWSER_ROOT/browser/.i2pd-browser-locale"
	local policies="$I2PD_BROWSER_ROOT/browser/distribution/policies.json"
	local expected got_http got_ssl
	expected="$(router_http_proxy)"
	if [[ -x "$I2PD_BROWSER_ROOT/browser/firefox" ]] &&
		[[ -r $locale_file ]] &&
		[[ $(<"$locale_file") == "$I2PD_BROWSER_LANGUAGE" ]] &&
		[[ -r $policies ]] && command -v jq >/dev/null 2>&1; then
		got_http="$(jq -r '.policies.Proxy.HTTPProxy // empty' "$policies")"
		got_ssl="$(jq -r '.policies.Proxy.SSLProxy // empty' "$policies")"
		if [[ $got_http == "$expected" && $got_ssl == "$expected" ]] &&
			browser_policy_validate "$policies" "$expected"; then
			router_log "$(router_t info.bundle-built)"
			if build_inputs_newer; then
				router_warn "$(router_t warn.build-inputs-newer)"
			fi
			return 0
		fi
		router_log "The existing Firefox proxy policy does not match the selected router endpoint; rebuilding."
	fi
	router_log "$(router_t info.building)"
	(
		cd "$I2PD_BROWSER_ROOT/build" || exit 1
		./build.bash --language="$I2PD_BROWSER_LANGUAGE"
	)
}

validate_browser_proxy() {
	local policies="$I2PD_BROWSER_ROOT/browser"
	local expected

	policies+="/distribution/policies.json"
	expected="$(router_http_proxy)"

	if [[ ! -r $policies ]]; then
		router_warn "No built browser configuration to validate." \
			"Run './build/build.bash' before launching Firefox."
		return 0
	fi

	if ! command -v jq >/dev/null 2>&1 ||
		! browser_policy_validate "$policies" "$expected"; then
		router_error "$(router_t error.effective-config "$policies")"
		return 1
	fi

	router_log "$(router_t info.proxy "$expected")"
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
	router_t status.language "$I2PD_BROWSER_LANGUAGE"
	router_t status.router "$ROUTER_BACKEND_PRETTY"
	router_t status.backend "$ROUTER_BACKEND"
	router_t status.source "$(router_source)"
	router_t status.http-proxy "$(router_http_proxy)"
	router_t status.socks-proxy "$(router_socks_proxy)"
	router_t status.console "$(router_console_url)"
	printf '\n'
	router_t launcher.run ./start-i2pd-browser.desktop
}

cmd_install() {
	local backend source selected_language

	selected_language="$(choose_language "$option_language")" || {
		router_error "$(router_t language.invalid "$option_language")"
		exit 2
	}
	i18n_init "$selected_language"
	backend="$(choose_backend "$option_router")" || exit 1
	source="$(choose_source "$option_source")" || exit 1

	# Do not persist a new selection until the requested backend is
	# actually available and its configuration can be prepared.
	ROUTER_SOURCE="$source"
	router_load_backend "$backend" || exit 1
	router_require_proxy_settings || exit 1
	ensure_backend_available || exit 1
	router_prepare_config || exit 1
	router_conf_set "$backend" "$source" "$selected_language" || exit 1

	router_log "$(router_t status.selected-router "$ROUTER_BACKEND_PRETTY" "$source")"

	if ((no_browser == 0)); then
		build_browser_if_needed || exit 1
	fi

	validate_browser_proxy || exit 1
	wait_for_proxy_or_warn || exit 1
	print_summary
}

configure_start_router() {
	((no_start == 0)) || return 0
	if ! router_start || ! router_wait_for_proxy "$PROXY_TIMEOUT" ||
		{ ((allow_external == 0)) && ! router_is_managed; }; then
		router_error "$(router_t error.effective-config "$(router_http_proxy)")"
		return 1
	fi
}

restore_browser_after_configure() {
	local backup="$I2PD_BROWSER_ROOT/.browser-old" browser="$I2PD_BROWSER_ROOT/browser"
	[[ -d $backup && ! -L $backup ]] || return 0
	if [[ -e $browser/data/lock || -L $browser/data/lock ||
		-e $browser/data/.parentlock || -L $browser/data/.parentlock ||
		-e $browser/data/parent.lock || -L $browser/data/parent.lock ||
		-e $I2PD_BROWSER_ROOT/.browser-switch-failed || -L $I2PD_BROWSER_ROOT/.browser-switch-failed ]]; then
		router_error "$(router_t error.effective-config "$backup")"
		return 1
	fi
	if [[ -e $browser ]]; then
		mv "$browser" "$I2PD_BROWSER_ROOT/.browser-switch-failed" || return 1
	fi
	mv "$backup" "$browser"
}

cmd_configure() {
	local lock="$I2PD_BROWSER_ROOT/.browser-switch.lock" status=0
	if ! mkdir "$lock"; then
		router_error "$(router_t error.effective-config "$lock")"
		return 1
	fi
	# Only remove this invocation's empty lock directory; never delete user data.
	trap 'rmdir "$I2PD_BROWSER_ROOT/.browser-switch.lock" 2>/dev/null || true' EXIT
	if [[ -e $I2PD_BROWSER_ROOT/.browser-build.lock || -L $I2PD_BROWSER_ROOT/.browser-build.lock ]]; then
		router_error "$(router_t error.effective-config "$I2PD_BROWSER_ROOT/.browser-build.lock")"
		status=1
	else
		configure_transaction || status=$?
	fi
	rmdir "$lock" || return 1
	trap - EXIT
	return "$status"
}

configure_transaction() {
	local backend source selected_language current current_source old_language
	local was_running=0 must_stop=0 stopped=0 allow_external=0 snapshot="" old_http_port=4444 old_socks_port=4447
	if [[ -e $I2PD_BROWSER_ROOT/.browser-old || -L $I2PD_BROWSER_ROOT/.browser-old ||
		-e $I2PD_BROWSER_ROOT/.browser-switch-failed || -L $I2PD_BROWSER_ROOT/.browser-switch-failed ]]; then
		router_error "$(router_t error.effective-config "$I2PD_BROWSER_ROOT/.browser-old")"
		return 1
	fi
	current="$(router_conf_get)"
	[[ -n $current ]] || current="$I2P_ROUTER_DEFAULT"
	current_source="$(router_conf_get_source)"
	[[ -n $current_source ]] || current_source="$I2P_ROUTER_SOURCE_DEFAULT"
	old_language="$(i18n_stored_locale)"
	[[ -n $old_language ]] || old_language="$I2PD_BROWSER_LANGUAGE"
	backend="${option_router:-${current:-$I2P_ROUTER_DEFAULT}}"
	source="${option_source:-$current_source}"
	router_require_valid_backend "$backend" || return 1
	router_require_valid_source "$source" || return 1
	selected_language="$(i18n_select_locale "$option_language")" || return 2

	# Inspect ownership before changing effective files or stopping anything.
	if [[ -n $current ]] && router_is_valid_backend "$current"; then
		ROUTER_SOURCE="$current_source"
		router_load_backend "$current" || return 1
		if router_is_running; then
			was_running=1
			old_http_port="$(backend_config_proxy_port httpproxy)" || return 1
			old_socks_port="$(backend_config_proxy_port socksproxy)" || return 1
			if [[ $current != "$backend" || $current_source != "$source" ||
				-n $ROUTER_HTTP_PROXY_OVERRIDE || -n $ROUTER_SOCKS_PROXY_OVERRIDE ]]; then
				if ! router_is_managed; then
					router_error "$(router_t error.router-conflict)"
					return 1
				fi
				must_stop=1
			fi
		fi
	fi
	ROUTER_SOURCE="$source"
	router_load_backend "$backend" || return 1
	router_require_proxy_settings || return 1
	ensure_backend_available || return 1
	if router_is_running && ! router_is_managed; then
		if [[ $current == "$backend" && $current_source == "$source" &&
			-z $ROUTER_HTTP_PROXY_OVERRIDE && -z $ROUTER_SOCKS_PROXY_OVERRIDE ]]; then
			allow_external=1
		else
			router_error "$(router_t error.router-conflict)"
			return 1
		fi
	fi
	i18n_init "$selected_language" || return 2
	# Downloads and bundle validation finish while the old router still runs.
	if ((no_browser == 0)); then
		if ! I2PD_BROWSER_CONFIGURE_BUILD=1 I2PD_BROWSER_KEEP_BACKUP=1 build_browser_if_needed; then
			restore_browser_after_configure || return 1
			return 1
		fi
	fi
	if ! validate_browser_proxy; then
		restore_browser_after_configure || return 1
		return 1
	fi

	if ((must_stop == 1)); then
		ROUTER_SOURCE="$current_source"
		if ! router_load_backend "$current" || ! router_stop; then
			restore_browser_after_configure || return 1
			return 1
		fi
		stopped=1
	fi
	ROUTER_SOURCE="$source"
	if router_load_backend "$backend" && snapshot="$(router_snapshot_config)" &&
		router_prepare_config && configure_start_router &&
		router_conf_set "$backend" "$source" "$selected_language"; then
		[[ -z $snapshot ]] || rm -rf "$snapshot"
		[[ ! -d $I2PD_BROWSER_ROOT/.browser-old ]] || rm -rf "$I2PD_BROWSER_ROOT/.browser-old"
		router_log "$(router_t status.selected-router "$ROUTER_BACKEND_PRETTY" "$source")"
		print_summary
		return 0
	fi

	# A failed start or persistence step must not silently replace the selection.
	# Stop only the new managed instance that this change could have started.
	if ((stopped == 1)) || ((was_running == 0)); then
		if router_is_running && router_is_managed; then
			if ! router_stop; then
				router_error "$(router_t error.configure-rollback)"
				return 1
			fi
		fi
	fi
	if ! restore_browser_after_configure || ! router_restore_config "$snapshot"; then
		router_error "$(router_t error.configure-rollback)"
		return 1
	fi
	if ((stopped == 1)); then
		ROUTER_SOURCE="$current_source"
		router_load_backend "$current" || return 1
		i18n_init "$old_language" || return 1
		# Overrides belong to the failed request, not to the old running router.
		ROUTER_HTTP_PROXY_OVERRIDE=""
		ROUTER_SOCKS_PROXY_OVERRIDE=""
		# shellcheck disable=SC2034 # Consumed by lib/router.bash.
		ROUTER_HTTP_PROXY_HOST=127.0.0.1
		# shellcheck disable=SC2034 # Consumed by lib/router.bash.
		ROUTER_SOCKS_PROXY_HOST=127.0.0.1
		# shellcheck disable=SC2034 # Consumed by lib/router.bash.
		ROUTER_HTTP_PROXY_PORT="$old_http_port"
		# shellcheck disable=SC2034 # Consumed by lib/router.bash.
		ROUTER_SOCKS_PROXY_PORT="$old_socks_port"
		if ! router_start; then
			router_error "$(router_t error.configure-rollback)"
			return 1
		fi
	fi
	router_warn "$(router_t info.configure-restored)"
	return 1
}

load_backend_for_command() {
	if [[ -n $option_source ]]; then
		router_require_valid_source "$option_source" || return 1
		ROUTER_SOURCE="$option_source"
	fi
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

	router_t status.language "$I2PD_BROWSER_LANGUAGE"
	router_t status.router "$ROUTER_BACKEND_PRETTY"
	router_t status.backend "$ROUTER_BACKEND"
	router_t status.source "$(router_source)"
	router_t status.state "$(router_state)"
	router_t status.http-proxy "$(router_http_proxy)"
	router_t status.socks-proxy "$(router_socks_proxy)"
	router_t status.console "$(router_console_url)"
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
			printf '%-9s %s\n' "$name" "$(router_t state.unavailable)"
		fi
	done
}

main() {
	parse_args "$@"
	# shellcheck disable=SC2034 # Consumed by the selected backend.
	ROUTER_NON_INTERACTIVE="$non_interactive"
	if ((show_help == 1)); then
		# Show help in the requested language when it is valid, but
		# never reject --help because of a bad --language value.
		if [[ -n $option_language ]]; then
			i18n_init "$option_language" || true
		fi
		usage
		exit 0
	fi
	if [[ -n $option_language ]]; then
		if ! i18n_init "$option_language"; then
			router_error "$(router_t language.invalid "$option_language")"
			exit 2
		fi
	fi

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
