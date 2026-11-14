#!/bin/bash

# See the LICENSE file at the top of the project tree for copyright
# and license details.

# This script is used to start the I2Pd Browser with various options
# and ensure it operates correctly within different environments. It
# provides features such as error reporting and desktop application
# registration.

set -Eeuo pipefail

_launcher_path="$(readlink -f "${BASH_SOURCE[0]}")"
_launcher_dir="$(dirname "$_launcher_path")"
# shellcheck disable=SC2034
I2PD_BROWSER_ROOT="$_launcher_dir"
# shellcheck disable=SC1091
source "$_launcher_dir/i18n.bash"
# shellcheck disable=SC1091
source "$_launcher_dir/desktop-entry.bash"
_launcher_locale="$(cat "$_launcher_dir/.i2pd-browser-locale" 2>/dev/null ||
	printf 'en-US')"
i18n_init "$_launcher_locale" || i18n_init en-US
unset _launcher_dir _launcher_locale

log() {
	printf '%s [INFO] %s\n' \
		"$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

warn() {
	printf '%s [WARN] %s\n' \
		"$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# shellcheck disable=SC2329
error() {
	printf '%s [ERROR] %s\n' \
		"$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

trap 'error "Unhandled error at line $LINENO."' ERR

complain_dialog_title="I2Pd Browser"

# Display error messages (GUI if possible, otherwise stderr)
complain() {
	local complain_message="$1"

	# Trim leading newlines using parameter expansion
	complain_message="${complain_message#"\
${complain_message%%[!$'\n']*}"}"

	if [[ ${show_output:-0} -eq 1 ]]; then
		echo "$complain_message" >&2
		return
	fi

	if zenity --error --title="$complain_dialog_title" \
		--text="$complain_message"; then return; fi
	if kdialog --title "$complain_dialog_title" \
		--error "$complain_message"; then return; fi
	if xmessage -title "$complain_dialog_title" \
		-center -buttons OK -default OK \
		-xrm '*message.scrollVertical: Never' \
		"$complain_message"; then return; fi
	gxmessage -title "$complain_dialog_title" \
		-center -buttons GTK_STOCK_OK \
		-default OK "$complain_message" || true
}

# Show script usage
browser_usage() {
	i18n_message launcher.usage
}

log_output=0
show_output=0
detach=0
show_usage=0
register_desktop_app=0
logfile=/dev/null
myname=""
mydir=""
browser_args=()
browser_launcher=()

check_runtime() {
	local cpu_arch

	if [[ "$(id -u)" -eq 0 ]]; then
		complain "The I2Pd Browser Bundle should not be run as root. Exiting."
		exit 1
	fi

	cpu_arch="$(uname -m)"
	case "$cpu_arch" in
	x86_64 | amd64 | i386 | i686)
		if [[ -r /proc/cpuinfo ]] &&
			! grep -q '^flags\s*:.* sse2' /proc/cpuinfo; then
			complain "I2Pd Browser requires a" \
				" CPU with SSE2 support. Exiting."
			exit 1
		fi
		;;
	esac

	unset SESSION_MANAGER
}

parse_args() {
	browser_args=("$@")
	set -- "${browser_args[@]}"

	while :; do
		case "${1-}" in
		--detach)
			detach=1
			shift
			;;
		-v | --verbose | -d | --debug)
			show_output=1
			shift
			;;
		-h | "-?" | --help | -help)
			show_usage=1
			show_output=1
			shift
			;;
		-l | --log)
			# shellcheck disable=SC2088
			case "${2-}" in
			"" | -*)
				logfile="../i2pd-browser.log"
				log "Firefox log" \
					" file: $logfile"
				;;
			"~")
				logfile="$HOME"
				log "Firefox log" \
					" file: $logfile"
				shift
				;;
			"~/"*)
				logfile="$HOME/${2#\~/}"
				log "Firefox log" \
					" file: $logfile"
				shift
				;;
			/*)
				logfile="$2"
				log "Firefox log" \
					" file: $logfile"
				shift
				;;
			*)
				logfile="../$2"
				log "Firefox log" \
					" file: $logfile"
				shift
				;;
			esac
			log_output=1
			shift
			;;
		--register-app)
			register_desktop_app=1
			show_output=1
			shift
			;;
		--unregister-app)
			register_desktop_app=-1
			show_output=1
			shift
			;;
		*)
			break
			;;
		esac
	done

	# A --log argument that names an existing directory (for example a
	# bare "~") is treated as the directory to hold the default log
	# file, instead of failing when the shell tries to redirect to it.
	if [[ -d ${logfile:-} ]]; then
		logfile="$logfile/i2pd-browser.log"
	fi

	if [[ $show_output -eq 1 && $detach -eq 1 ]]; then
		detach=0
	fi

	browser_args=("$@")
}

configure_output() {
	if [[ $show_output -eq 0 ]]; then
		# Fall back to /dev/null when the log directory is not
		# writable instead of failing to redirect.
		if [[ ! -w $(dirname "$logfile") ]]; then
			logfile=/dev/null
		fi
		exec >"$logfile"
		exec 2>"$logfile"
	fi
}

resolve_script_path() {
	local possibly_my_real_name

	myname="$0"
	if [[ -L $myname ]]; then
		if possibly_my_real_name="$(
			realpath "$myname" 2>/dev/null
		)"; then
			myname="$possibly_my_real_name"
		else
			if ! myname="$(
				readlink -f "$myname" 2>/dev/null
			)"; then
				complain "start-i2pd-browser.bash cannot be run" \
					" using a symlink on this operating system."
			fi
		fi
	fi

	mydir="$(dirname "$myname")"
	[[ -d $mydir ]] && { cd "$mydir" || exit 1; }
}

setup_shell_env() {
	if [[ -z ${XAUTHORITY-} ]]; then
		export XAUTHORITY="$HOME/.Xauthority"
	fi

	if [[ -z ${PWD-} ]]; then
		PWD="$(pwd)"
	fi
}

setup_ibus_workaround() {
	if [[ ! -d ".config/ibus" ]]; then
		mkdir -p .config/ibus
		ln -nsf ~/.config/ibus/bus .config/ibus
	fi
}

update_desktop_launcher() {
	[[ -w .. ]] || return 0
	browser_desktop_entry start-i2pd-browser.desktop ../start-i2pd-browser.desktop "$PWD/start-i2pd-browser.bash"
}

handle_app_registration() {
	if [[ $register_desktop_app -eq 1 ]]; then
		mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/applications/"
		cp ../start-i2pd-browser.desktop \
			"${XDG_DATA_HOME:-$HOME/.local/share}/applications/"
		update-desktop-database \
			"${XDG_DATA_HOME:-$HOME/.local/share}/applications/" || true
		log "Desktop entry registered at" \
			" ${XDG_DATA_HOME:-$HOME/.local/share}/applications/"
		exit 0
	fi

	if [[ $register_desktop_app -eq -1 ]]; then
		local desktop_path
		desktop_path="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
		desktop_path+="/start-i2pd-browser.desktop"
		if [[ -e $desktop_path ]]; then
			rm -f "$desktop_path"
			update-desktop-database \
				"${XDG_DATA_HOME:-$HOME/.local/share}/applications/" || true
			log "Desktop entry removed from" \
				" ${XDG_DATA_HOME:-$HOME/.local/share}/applications/"
		else
			warn "Desktop entry not found in" \
				" ${XDG_DATA_HOME:-$HOME/.local/share}/applications/"
		fi
		exit 0
	fi
}

# Detect the secureblue operating system, which loads hardened_malloc
# via /etc/ld.so.preload and provides the with-standard-malloc helper.
is_secureblue() {
	local os_release

	os_release=/etc/os-release
	[[ -r $os_release ]] || os_release=/usr/lib/os-release
	[[ -r $os_release ]] || return 1
	grep -q '^ID=secureblue$' "$os_release"
}

prepare_browser_env() {
	export HOME="$PWD"

	# On secureblue, unsetting LD_PRELOAD is not enough because
	# hardened_malloc is loaded through /etc/ld.so.preload. Use the
	# provided helper so only the browser runs with the standard
	# allocator, keeping the rest of the session hardened.
	if is_secureblue; then
		if command -v with-standard-malloc >/dev/null 2>&1; then
			browser_launcher=(with-standard-malloc)
		else
			warn "with-standard-malloc not found;" \
				" falling back to unsetting LD_PRELOAD."
			unset LD_PRELOAD || true
		fi
	else
		unset LD_PRELOAD || true
	fi

	export GSETTINGS_BACKEND=memory
	cd "$HOME" || exit 1
}

run_browser() {
	local rc

	if [[ $show_usage -eq 1 ]]; then
		"${browser_launcher[@]}" ./firefox --class "I2Pd Browser" \
			-profile data --help 2>/dev/null
		browser_usage
		return 0
	fi

	if [[ $detach -eq 1 ]]; then
		"${browser_launcher[@]}" ./firefox --class "I2Pd Browser" \
			-profile data "$@" \
			>"$logfile" 2>&1 </dev/null &
		disown "$!"
		return 0
	fi

	if [[ $log_output -eq 1 && $show_output -eq 1 ]]; then
		"${browser_launcher[@]}" ./firefox --class "I2Pd Browser" \
			-profile data "$@" 2>&1 </dev/null |
			tee "$logfile"
		rc=$?
		return "$rc"
	fi

	if [[ $show_output -eq 1 ]]; then
		"${browser_launcher[@]}" ./firefox --class "I2Pd Browser" \
			-profile data "$@" </dev/null
		rc=$?
		return "$rc"
	fi

	"${browser_launcher[@]}" ./firefox --class "I2Pd Browser" \
		-profile data "$@" \
		>"$logfile" 2>&1 </dev/null
}

warn_bundle_age() {
	local metadata="$I2PD_BROWSER_ROOT/.i2pd-browser-build.json" built now
	if command -v jq >/dev/null 2>&1 &&
		built="$(jq -er '.built_epoch | select(type == "number" and . > 0 and floor == .)' "$metadata" 2>/dev/null)"; then
		now="$(date +%s)"
		if ((now - built > 30 * 86400)); then
			warn "$(i18n_message warning.bundle-age 30)"
		fi
	else
		warn "$(i18n_message error.bundle-metadata)"
	fi
}

main() {
	parse_args "$@"
	if [[ $show_usage -eq 1 ]]; then
		browser_usage
		return 0
	fi
	check_runtime
	local operation_lock
	for operation_lock in "$I2PD_BROWSER_ROOT/../.browser-build.lock" "$I2PD_BROWSER_ROOT/../.browser-switch.lock"; do
		if [[ -e $operation_lock || -L $operation_lock ]]; then
			complain "$(i18n_message error.build-locked "$operation_lock")"
			return 1
		fi
	done
	warn_bundle_age
	configure_output
	resolve_script_path
	setup_shell_env
	setup_ibus_workaround
	update_desktop_launcher
	handle_app_registration
	prepare_browser_env
	run_browser "${browser_args[@]}"
	exit $?
}

main "$@"
