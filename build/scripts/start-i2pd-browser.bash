#!/bin/bash

# See the LICENSE file at the top of the project tree for copyright
# and license details.

# This script is used to start the I2Pd Browser with various options
# and ensure it operates correctly within different environments. It
# provides features such as error reporting and desktop application
# registration.

set -Eeuo pipefail

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
	printf '\nI2Pd Browser Script Options\n'
	printf '%s\n' \
		"  --verbose           Display Firefox" \
		" output in the terminal"
	printf '%s\n' \
		"  --log [file]        Record Firefox" \
		" output to file (default: i2pd-browser.log)"
	printf '%s\n' \
		"  --detach            Detach from" \
		" terminal and run I2Pd Browser in the background"
	printf '%s\n' \
		"  --register-app      Register I2Pd" \
		" Browser as a desktop app for this user"
	printf '%s\n' \
		"  --unregister-app    Unregister I2Pd" \
		" Browser as a desktop app for this user"
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
		complain "The I2Pd Browser Bundle should not be run" \
			" as root. Exiting."
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
	local exec_line escaped

	# The parent directory holds the relocatable .desktop copy. If it
	# is not writable the browser can still be launched, so skip the
	# refresh instead of aborting.
	[[ -w .. ]] || return 0

	cp start-i2pd-browser.desktop ../
	exec_line="Exec=bash -c '\"$PWD/start-i2pd-browser.bash\" --detach"
	exec_line+=" || ([ ! -x \"$PWD/start-i2pd-browser.bash\" ]"
	# shellcheck disable=SC2016
	exec_line+=' && "$(dirname "$*")"/browser/start-i2pd-browser.bash'
	exec_line+=" --detach)' dummy %k"
	# Escape the characters that are special in a sed replacement
	# (&, backslash and the chosen delimiter) so the literal command
	# is inserted instead of the matched text.
	escaped="${exec_line//\\/\\\\}"
	escaped="${escaped//&/\\&}"
	escaped="${escaped//,/\\,}"
	sed -i -e "s,^Exec=.*,$escaped," ../start-i2pd-browser.desktop
}

handle_app_registration() {
	if [[ $register_desktop_app -eq 1 ]]; then
		mkdir -p "$HOME/.local/share/i2pd-browser/"
		cp ../start-i2pd-browser.desktop \
			"$HOME/.local/share/i2pd-browser/"
		update-desktop-database \
			"$HOME/.local/share/i2pd-browser/" || true
		log "Desktop entry registered at" \
			" ~/.local/share/i2pd-browser/"
		exit 0
	fi

	if [[ $register_desktop_app -eq -1 ]]; then
		local desktop_path
		desktop_path="$HOME/.local/share/i2pd-browser"
		desktop_path+="/start-i2pd-browser.desktop"
		if [[ -e $desktop_path ]]; then
			rm -f "$desktop_path"
			update-desktop-database \
				"$HOME/.local/share/i2pd-browser/" || true
			log "Desktop entry removed from" \
				" ~/.local/share/i2pd-browser/"
		else
			warn "Desktop entry not found in" \
				" ~/.local/share/i2pd-browser/"
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

main() {
	check_runtime
	parse_args "$@"
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
