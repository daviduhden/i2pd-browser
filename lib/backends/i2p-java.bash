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

i2p_java_vendor_dir() {
	printf '%s/i2p-java\n' "$(router_vendor_dir)"
}

i2p_java_vendor_home() {
	printf '%s/i2p\n' "$(i2p_java_vendor_dir)"
}

i2p_java_vendor_version() {
	local file
	file="$(i2p_java_vendor_dir)/VERSION"
	[[ -r $file ]] && cat "$file"
}

i2p_java_vendor_is_installed() {
	i2p_java_is_home "$(i2p_java_vendor_home)"
}

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

	if [[ ${ROUTER_SOURCE:-system} == vendored ]]; then
		candidate="$(i2p_java_vendor_home)"
		if i2p_java_is_home "$candidate"; then
			printf '%s\n' "$candidate"
			return 0
		fi
		return 1
	fi

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

# Official I2P (Java) download page. The latest stable release and its
# installer links are resolved from here.
i2p_java_download_page() {
	printf 'https://i2p.net/en/downloads/\n'
}

i2p_java_latest_version() {
	local html

	router_have curl || {
		router_error "curl is required to resolve the latest I2P" \
			"release."
		return 1
	}
	html="$(curl -fsSL "$(i2p_java_download_page)")" || {
		router_error "Could not query $(i2p_java_download_page)"
		return 1
	}
	printf '%s\n' "$html" |
		grep -oE 'i2pinstall_[0-9]+\.[0-9]+\.[0-9]+\.jar' |
		sed 's/^i2pinstall_//; s/\.jar$//' |
		sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1
}

i2p_java_installer_url() {
	local version="$1"
	local html href

	html="$(curl -fsSL "$(i2p_java_download_page)" 2>/dev/null ||
		true)"
	# Require HTTPS here; a plaintext installer URL must never be used.
	href="$(printf '%s\n' "$html" |
		grep -oE "https://(files\.i2p\.net|i2p\.net)/[^\"']*i2pinstall_${version//./\\.}\.jar" |
		head -n 1)"
	if [[ -z $href ]]; then
		href="https://files.i2p.net/${version}"
		href+="/i2pinstall_${version}.jar"
	fi
	printf '%s\n' "$href"
}

# Download the official I2P installer and run it into the managed
# vendor directory. The IzPack console installer is interactive.
backend_vendor_install() {
	local version url dir home installer java expected actual
	expected="${I2P_INSTALLER_SHA512:-}"
	if [[ ! $expected =~ ^[[:xdigit:]]{128}$ ]]; then
		router_error "$(router_t error.java-checksum)"
		return 1
	fi
	if [[ ${ROUTER_NON_INTERACTIVE:-0} == 1 || ! -t 0 ]]; then
		router_error "$(router_t error.java-interactive)"
		return 1
	fi

	version="$(i2p_java_latest_version)" || {
		router_error "Could not determine the latest I2P release."
		return 1
	}
	url="$(i2p_java_installer_url "$version")" || {
		router_error "Could not resolve the I2P installer URL."
		return 1
	}
	java="$(i2p_java_find_java)" || {
		router_error "A Java runtime is required to install I2P."
		return 1
	}

	dir="$(i2p_java_vendor_dir)"
	home="$(i2p_java_vendor_home)"
	installer="$dir/i2pinstall_${version}.jar"
	mkdir -p "$dir" "$home"

	router_log "Downloading I2P (Java) $version"
	if ! router_download "$url" "$installer"; then
		router_error "Could not download $url"
		return 1
	fi
	# The digest must be obtained independently from a trusted release source.
	actual="$(router_sha512sum "$installer")" || return 1
	if [[ ${actual,,} != "${expected,,}" ]]; then
		rm -f "$installer"
		router_error "$(router_t error.java-checksum)"
		return 1
	fi

	router_log "Running the I2P installer (console mode)."
	router_log "Install into: $home"
	(
		cd "$dir" || exit 1
		"$java" -jar "$installer" -console
	) || {
		router_error "The I2P installer did not complete."
		return 1
	}

	if ! i2p_java_vendor_is_installed; then
		router_error "No I2P installation found in $home."
		return 1
	fi

	printf '%s\n' "$version" >"$dir/VERSION"
	router_log "Vendored I2P (Java) $version installed in $home"
}

backend_dependency_hint() {
	cat <<'EOF'
I2P (Java) was not found, or no Java runtime is available.
Install a Java runtime and the I2P router, for example:
  Debian/Ubuntu : sudo apt install i2p default-jre-headless
  Fedora        : sudo dnf install i2p java-17-openjdk-headless
  Arch          : sudo pacman -S i2p jre-openjdk-headless
  openSUSE      : sudo zypper install i2p java-17-openjdk-headless
Or let I2Pd Browser download the latest stable release from i2p.net:
  ./install.bash configure --i2p-router=i2p-java
  ./install.bash configure --router-source=vendored
EOF
}

backend_install_dependencies() {
	local manager

	manager="$(router_package_manager)"
	case "$manager" in
	brew)
		router_install_packages i2p openjdk screen
		;;
	apt)
		router_install_packages i2p default-jre-headless screen
		;;
	dnf)
		router_install_packages i2p java-17-openjdk-headless screen
		;;
	pacman)
		router_install_packages i2p jre-openjdk-headless screen
		;;
	zypper)
		router_install_packages i2p java-17-openjdk-headless screen
		;;
	*)
		router_warn "No supported package manager was found."
		return 1
		;;
	esac
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
	router_screen_is_managed
}

backend_console_url() {
	printf 'http://127.0.0.1:%s/\n' "$BACKEND_CONSOLE_PORT"
}

# Update one existing Java properties-style file atomically, requiring the
# expected key so a config schema change cannot silently ignore an override.
i2p_java_set_config_value() {
	local file="$1" key="$2" value="$3" tmp
	tmp="${file}.tmp.$$"
	if awk -v key="$key" -v value="$value" '
		BEGIN { prefix = key "=" }
		index($0, prefix) == 1 { print prefix value; found++; next }
		{ print }
		END { if (found != 1) exit 1 }
	' "$file" >"$tmp"; then
		mv "$tmp" "$file"
	else
		rm -f "$tmp"
		return 1
	fi
}

# Apply explicit endpoint overrides only to effective runtime files. The
# tracked config/ templates and existing user values remain untouched when
# the corresponding environment override is absent.
# Java Properties supports aliases, escapes and continuations. This manager
# accepts a deliberately narrow canonical subset instead of guessing how a
# router will resolve ambiguous or duplicate keys. Values may contain '='.
i2p_java_validate_properties() {
	awk '
		/^[[:space:]]*([#!]|$)/ { next }
		{ sub(/\r$/, "") }
		!/^[A-Za-z0-9_.-]+=/ { exit 1 }
		{ key=$0; sub(/=.*/, "", key); if (seen[key]++) exit 1 }
		/\\$/ { exit 1 }
	' "$1"
}

i2p_java_config_value() {
	local file="$1" key="$2"
	awk -v key="$key" '
		index($0, key "=") == 1 { value=substr($0,length(key)+2); count++ }
		END { if (count != 1) exit 1; sub(/\r$/, "", value); print value }
	' "$file"
}

# Validate the effective files, falling back to templates only before seeding.
# All configured tunnel interfaces must remain local, including user additions.
i2p_java_validate_config_dir() {
	local dir="$1" file key value expected
	for file in i2ptunnel.config clients.config addressbook/config.txt router.config; do
		i2p_java_validate_properties "$dir/$file" || return 1
	done
	for key in tunnel.0.interface tunnel.1.interface; do
		value="$(i2p_java_config_value "$dir/i2ptunnel.config" "$key")" || return 1
		[[ $value == 127.0.0.1 ]] || return 1
	done
	while IFS='=' read -r key value; do
		value="${value%$'\r'}"
		if [[ $key =~ ^tunnel\.[0-9]+\.interface$ ]]; then
			[[ $value == 127.0.0.1 || $value == ::1 ]] || return 1
		fi
	done <"$dir/i2ptunnel.config"
	for key in tunnel.0.listenPort tunnel.1.listenPort; do
		value="$(i2p_java_config_value "$dir/i2ptunnel.config" "$key")" || return 1
		router_validate_proxy_endpoint 127.0.0.1 "$value" || return 1
		expected="$(router_http_proxy_port)"
		[[ $key == tunnel.0.listenPort ]] || expected="$(router_socks_proxy_port)"
		[[ $value == "$expected" ]] || return 1
	done
	value="$(i2p_java_config_value "$dir/clients.config" clientApp.0.args)" || return 1
	[[ $value == '7657 ::1,127.0.0.1 ./webapps/' ]] || return 1
	for file in addressbook/config.txt router.config; do
		if [[ $file == router.config ]]; then
			key=router.updateProxyHost
		else
			key=proxy_host
		fi
		value="$(i2p_java_config_value "$dir/$file" "$key")" || return 1
		[[ $value == 127.0.0.1 ]] || return 1
		if [[ $file == router.config ]]; then key=router.updateProxyPort; else key=proxy_port; fi
		value="$(i2p_java_config_value "$dir/$file" "$key")" || return 1
		[[ $value == "$(router_http_proxy_port)" ]] || return 1
	done
}

backend_config_proxy_port() {
	local key=tunnel.0.listenPort dir="$BACKEND_CONFIG_DIR"
	[[ $1 == httpproxy ]] || key=tunnel.1.listenPort
	[[ ! -d $BACKEND_DATA_DIR ]] || dir="$BACKEND_DATA_DIR"
	i2p_java_config_value "$dir/i2ptunnel.config" "$key"
}

backend_validate_config() {
	local dir="$BACKEND_CONFIG_DIR"
	[[ ! -d $BACKEND_DATA_DIR ]] || dir="$BACKEND_DATA_DIR"
	if ! i2p_java_validate_config_dir "$dir"; then
		router_error "$(router_t error.effective-config "$dir")"
		return 1
	fi
}

# Stage the complete related configuration set before replacing any file.
# Backups remain available until every rename has succeeded.
i2p_java_apply_proxy_overrides() {
	local http_host http_port socks_host socks_port entry file key value stage restored_file
	local -a files=(i2ptunnel.config addressbook/config.txt router.config)
	[[ -n $ROUTER_HTTP_PROXY_OVERRIDE || -n $ROUTER_SOCKS_PROXY_OVERRIDE ]] || return 0
	router_require_proxy_settings || return 1
	stage="$(mktemp -d "$BACKEND_DATA_DIR/.proxy-config.XXXXXX")" || return 1
	mkdir -p "$stage/new/addressbook" "$stage/old/addressbook" || {
		rm -rf "$stage"
		return 1
	}
	for file in "${files[@]}" clients.config; do
		cp -p "$BACKEND_DATA_DIR/$file" "$stage/new/$file" || {
			rm -rf "$stage"
			return 1
		}
	done
	for file in "${files[@]}"; do
		cp -p "$BACKEND_DATA_DIR/$file" "$stage/old/$file" || {
			rm -rf "$stage"
			return 1
		}
	done
	if [[ -n $ROUTER_HTTP_PROXY_OVERRIDE ]]; then
		http_host="$(router_http_proxy_host)"
		http_port="$(router_http_proxy_port)"
		for entry in \
			"i2ptunnel.config|tunnel.0.interface|$http_host" \
			"i2ptunnel.config|tunnel.0.listenPort|$http_port" \
			"addressbook/config.txt|proxy_host|$http_host" \
			"addressbook/config.txt|proxy_port|$http_port" \
			"router.config|router.updateProxyHost|$http_host" \
			"router.config|router.updateProxyPort|$http_port"; do
			IFS='|' read -r file key value <<<"$entry"
			i2p_java_set_config_value "$stage/new/$file" "$key" "$value" || {
				rm -rf "$stage"
				return 1
			}
		done
	fi
	if [[ -n $ROUTER_SOCKS_PROXY_OVERRIDE ]]; then
		socks_host="$(router_socks_proxy_host)"
		socks_port="$(router_socks_proxy_port)"
		if ! i2p_java_set_config_value "$stage/new/i2ptunnel.config" tunnel.1.interface "$socks_host" ||
			! i2p_java_set_config_value "$stage/new/i2ptunnel.config" tunnel.1.listenPort "$socks_port"; then
			rm -rf "$stage"
			return 1
		fi
	fi
	i2p_java_validate_config_dir "$stage/new" || {
		rm -rf "$stage"
		return 1
	}
	for file in "${files[@]}"; do
		if ! mv "$stage/new/$file" "$BACKEND_DATA_DIR/$file"; then
			for restored_file in "${files[@]}"; do
				cp -p "$stage/old/$restored_file" "$BACKEND_DATA_DIR/$restored_file" || {
					router_error "$(router_t error.effective-config "$stage/old")"
					return 1
				}
			done
			rm -rf "$stage"
			return 1
		fi
	done
	rm -rf "$stage"
}

# Seed only missing files so first-run defaults do not overwrite effective
# settings or runtime state. Keep newly created data private.
backend_prepare_config() {
	router_require_proxy_settings || return 1
	local src="$BACKEND_CONFIG_DIR"
	local dst="$BACKEND_DATA_DIR"
	local file rel

	if [[ ! -d $src ]]; then
		router_error "I2P (Java) configuration not found: $src"
		return 1
	fi

	# The effective configuration and runtime state live in data/.
	# Keep newly created files private even if the caller's umask is
	# permissive.
	if ! (
		umask 077

		mkdir -p "$dst" || exit 1

		while IFS= read -r -d '' file; do
			rel="${file#"$src"/}"
			mkdir -p "$dst/$(dirname "$rel")" || exit 1
			if [[ ! -e "$dst/$rel" ]]; then
				cp "$file" "$dst/$rel" || exit 1
			fi
		done < <(find "$src" -type f -print0)

		mkdir -p "$dst/addressbook"
	); then
		router_error "Could not prepare the I2P (Java) configuration."
		return 1
	fi
	i2p_java_apply_proxy_overrides || {
		router_error "Could not apply proxy overrides to the I2P (Java) configuration."
		return 1
	}
	return 0
}

# Launch Java I2P with its configuration root explicitly set to the isolated
# data directory; omitting this property could use the user's global ~/.i2p.
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
		router_start_screen \
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
	router_stop_screen
}
