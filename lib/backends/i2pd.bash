#!/bin/bash

# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# i2pd (C++) backend for the I2P router abstraction.

# shellcheck shell=bash

# shellcheck disable=SC2034
BACKEND_NAME="i2pd"
# shellcheck disable=SC2034
BACKEND_PRETTY="i2pd (C++)"
BACKEND_DIR="${I2PD_BROWSER_ROOT}/i2pd"
BACKEND_SCREEN_SESSION="i2pd"
BACKEND_CONSOLE_PORT="7070"

i2pd_find_path() {
    local -a locations
    local location brew_prefix

    locations=(
        /usr/sbin/i2pd
        /usr/local/sbin/i2pd
        /usr/bin/i2pd
        /usr/local/bin/i2pd
        /sbin/i2pd
        /bin/i2pd
        /home/linuxbrew/.linuxbrew/bin/i2pd
        /home/linuxbrew/.linuxbrew/sbin/i2pd
    )

    if command -v i2pd >/dev/null 2>&1; then
        command -v i2pd
        return 0
    fi

    if command -v brew >/dev/null 2>&1; then
        brew_prefix="$(brew --prefix 2>/dev/null || true)"
        if [[ -n "$brew_prefix" ]]; then
            locations+=("$brew_prefix/bin/i2pd" \
                "$brew_prefix/sbin/i2pd")
        fi
    fi

    for location in "${locations[@]}"; do
        if [[ -x "$location" ]]; then
            printf '%s\n' "$location"
            return 0
        fi
    done

    return 1
}

backend_dependency_hint() {
    cat <<'EOF'
i2pd (C++) was not found.
Install it with your system package manager, for example:
  Debian/Ubuntu : sudo apt install i2pd
  Fedora        : sudo dnf install i2pd
  Arch          : sudo pacman -S i2pd
  Homebrew      : brew install i2pd
Or build it from source and install it into your PATH.
See https://i2pd.readthedocs.io for details.
EOF
}

backend_install_dependencies() {
    router_install_packages i2pd
}

backend_is_installed() {
    i2pd_find_path >/dev/null 2>&1
}

# Installed but unable to actually run.
backend_is_misconfigured() {
    backend_is_installed || return 1
    command -v screen >/dev/null 2>&1 && return 1
    return 0
}

backend_is_running() {
    if command -v systemctl >/dev/null 2>&1 && \
        systemctl is-active --quiet i2pd 2>/dev/null; then
        return 0
    fi
    if command -v pgrep >/dev/null 2>&1; then
        if pgrep -x i2pd >/dev/null 2>&1 || \
            pgrep -x i2pd-daemon >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# True only for the instance started by this project.
backend_is_managed() {
    command -v screen >/dev/null 2>&1 || return 1
    screen -ls 2>/dev/null | \
        grep -q "[0-9]\.${BACKEND_SCREEN_SESSION}[[:space:]]"
}

backend_console_url() {
    printf 'http://127.0.0.1:%s/\n' "$BACKEND_CONSOLE_PORT"
}

backend_prepare_config() {
    if [[ ! -r "$BACKEND_DIR/i2pd.conf" ]]; then
        router_error "i2pd configuration not found:" \
            "$BACKEND_DIR/i2pd.conf"
        return 1
    fi
    return 0
}

backend_start() {
    local i2pd_path arch

    i2pd_path="$(i2pd_find_path)" || {
        router_error "i2pd not found in standard or Homebrew" \
            "locations."
        return 1
    }

    if ! command -v screen >/dev/null 2>&1; then
        router_error "Required command 'screen' not found."
        return 1
    fi

    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64|i686|i386|arm64|aarch64)
            ;;
        *)
            router_error "Unsupported system architecture: $arch"
            return 1 ;;
    esac

    router_log "Starting i2pd with binary: $i2pd_path"
    # i2pd reads i2pd.conf and tunnels.conf from its data directory.
    (
        cd "$BACKEND_DIR" || exit 1
        screen -Adm -S "$BACKEND_SCREEN_SESSION" \
            "$i2pd_path" --datadir=.
    )
}

backend_stop() {
    command -v screen >/dev/null 2>&1 || {
        router_error "Required command 'screen' not found."
        return 1
    }
    router_log "Stopping the managed i2pd screen session."
    screen -S "$BACKEND_SCREEN_SESSION" -X quit
}
