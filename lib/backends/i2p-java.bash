#!/bin/bash

# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# I2P (Java) backend for the I2P router abstraction.
#
# The router is started directly from the system installation with an
# isolated configuration directory, mirroring the way i2pd is started
# with its own data directory.

# shellcheck shell=bash

# shellcheck disable=SC2034
BACKEND_NAME="i2p-java"
# shellcheck disable=SC2034
BACKEND_PRETTY="I2P (Java)"
BACKEND_DIR="${I2PD_BROWSER_ROOT}/i2p-java"
BACKEND_CONFIG_DIR="$BACKEND_DIR/config"
BACKEND_DATA_DIR="$BACKEND_DIR/data"
BACKEND_SCREEN_SESSION="i2p-java"
BACKEND_CONSOLE_PORT="7657"

i2p_java_is_home() {
	local dir="${1-}"
	local jar

	[[ -d "$dir/lib" ]] || return 1
	for jar in "$dir"/lib/*.jar; do
		[[ -e $jar ]] && return 0
	done
	return 1
}

i2p_java_find_router_script() {
	local candidate
	local -a candidates

	if command -v i2prouter >/dev/null 2>&1; then
		command -v i2prouter
		return 0
	fi

	candidates=(
		/usr/bin/i2prouter
		/usr/local/bin/i2prouter
	)
	for candidate in "${candidates[@]}"; do
		if [[ -x $candidate ]]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

i2p_java_home_from_script() {
	local script="$1"

	sed -n 's/^I2P="\([^"]*\)"$/\1/p' "$script" | head -n 1
}

i2p_java_find_home() {
	local candidate
	local router_script
	local -a candidates

	for candidate in "${I2P_HOME:-}" "${I2P_BASE:-}"; do
		[[ -n $candidate ]] || continue
		if i2p_java_is_home "$candidate"; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	router_script="$(i2p_java_find_router_script || true)"
	if [[ -n $router_script ]]; then
		candidate="$(i2p_java_home_from_script "$router_script" ||
			true)"
		if [[ -n $candidate ]] && i2p_java_is_home "$candidate"; then
			printf '%s\n' "$candidate"
			return 0
		fi
		candidate="$(cd "$(dirname "$router_script")" &&
			pwd -P)"
		if i2p_java_is_home "$candidate"; then
			printf '%s\n' "$candidate"
			return 0
		fi
	fi

	candidates=(
		/usr/share/i2p
		/usr/local/share/i2p
		/opt/i2p
		"$HOME/i2p"
		"$HOME/.local/share/i2p"
	)
	for candidate in "${candidates[@]}"; do
		if i2p_java_is_home "$candidate"; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	return 1
}

i2p_java_find_java() {
	if [[ -n ${JAVA_HOME:-} && -x "$JAVA_HOME/bin/java" ]]; then
		printf '%s\n' "$JAVA_HOME/bin/java"
		return 0
	fi
	if command -v java >/dev/null 2>&1; then
		command -v java
		return 0
	fi
	return 1
}

backend_dependency_hint() {
	cat <<'EOF'
I2P (Java) was not found, or no Java runtime is available.
Install a Java runtime and the I2P router, for example:
  Debian/Ubuntu : sudo apt install i2p default-jre-headless
  Fedora        : sudo dnf install i2p java-17-openjdk-headless
  Arch          : sudo pacman -S i2p jre-openjdk-headless
  openSUSE      : sudo zypper install i2p java-17-openjdk-headless
Or install I2P from https://geti2p.net/en/download and make it
available in /usr/share/i2p or through the i2prouter wrapper.
EOF
}

backend_install_dependencies() {
	if command -v apt-get >/dev/null 2>&1; then
		router_install_packages i2p default-jre-headless
	elif command -v dnf >/dev/null 2>&1; then
		router_install_packages i2p java-17-openjdk-headless
	elif command -v pacman >/dev/null 2>&1; then
		router_install_packages i2p jre-openjdk-headless
	elif command -v zypper >/dev/null 2>&1; then
		router_install_packages i2p java-17-openjdk-headless
	else
		router_warn "No supported package manager was found."
		return 1
	fi
}

backend_is_installed() {
	i2p_java_find_home >/dev/null 2>&1
}

backend_is_misconfigured() {
	backend_is_installed || return 1
	i2p_java_find_java >/dev/null 2>&1 && return 1
	return 0
}

backend_is_running() {
	if command -v systemctl >/dev/null 2>&1 &&
		systemctl is-active --quiet i2p 2>/dev/null; then
		return 0
	fi
	if command -v pgrep >/dev/null 2>&1 &&
		pgrep -f 'net\.i2p\.router\.Router' >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

backend_is_managed() {
	command -v screen >/dev/null 2>&1 || return 1
	screen -ls 2>/dev/null |
		grep -q "[0-9]\.${BACKEND_SCREEN_SESSION}[[:space:]]"
}

backend_console_url() {
	printf 'http://127.0.0.1:%s/\n' "$BACKEND_CONSOLE_PORT"
}

# Seed the effective configuration directory from the vendored files.
# Existing files are never overwritten, so router state and any user
# changes are preserved.
backend_prepare_config() {
	local src="$BACKEND_CONFIG_DIR"
	local dst="$BACKEND_DATA_DIR"
	local file rel

	if [[ ! -d $src ]]; then
		router_error "I2P (Java) configuration not found: $src"
		return 1
	fi

	mkdir -p "$dst"

	while IFS= read -r -d '' file; do
		rel="${file#"$src"/}"
		mkdir -p "$dst/$(dirname "$rel")"
		if [[ ! -e "$dst/$rel" ]]; then
			cp "$file" "$dst/$rel"
		fi
	done < <(find "$src" -type f -print0)

	mkdir -p "$dst/addressbook"
	return 0
}

backend_start() {
	local home java cp jar data_dir

	home="$(i2p_java_find_home)" || {
		router_error "I2P (Java) installation not found."
		return 1
	}
	java="$(i2p_java_find_java)" || {
		router_error "A Java runtime is required but 'java' was not" \
			"found."
		return 1
	}
	if ! command -v screen >/dev/null 2>&1; then
		router_error "Required command 'screen' not found."
		return 1
	fi

	backend_prepare_config || return 1

	cp=""
	for jar in "$home"/lib/*.jar; do
		[[ -e $jar ]] || continue
		cp="${cp:+$cp:}$jar"
	done
	if [[ -z $cp ]]; then
		router_error "No I2P libraries found in $home/lib."
		return 1
	fi

	data_dir="$BACKEND_DATA_DIR"
	mkdir -p "$data_dir"

	router_log "Starting I2P (Java) with: $java"
	(
		umask 077
		cd "$BACKEND_DIR" || exit 1
		screen -Adm -S "$BACKEND_SCREEN_SESSION" \
			"$java" \
			-Djava.awt.headless=true \
			-Di2p.dir.base="$home" \
			-Di2p.dir.config="$data_dir" \
			-Djava.library.path="$home:$home/lib" \
			-Djava.net.preferIPv4Stack=false \
			-DloggerFilenameOverride=logs/log-router-@.txt \
			-cp "$cp" \
			net.i2p.router.RouterLaunch
	)
}

backend_stop() {
	command -v screen >/dev/null 2>&1 || {
		router_error "Required command 'screen' not found."
		return 1
	}
	router_log "Stopping the managed I2P (Java) screen session."
	screen -S "$BACKEND_SCREEN_SESSION" -X quit
}
