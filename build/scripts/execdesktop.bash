#!/bin/bash

# See the LICENSE file at the top of the project tree for copyright
# and license details.

# This script extracts the I2Pd Browser startup program from the
# given file. The program is specified in the line that starts with
# 'X-I2PdBrowser-ExecShell'. The line is processed to remove the
# prefix and any trailing characters.

set -Eeuo pipefail

log() {
	printf '%s [INFO] %s\n' \
		"$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

warn() {
	printf '%s [WARN] %s\n' \
		"$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

error() {
	printf '%s [ERROR] %s\n' \
		"$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

trap 'error "Unhandled error at line $LINENO."' ERR

desktop_file=""
I2PDB_START_PROG=""
passthrough_args=()

usage() {
	log "Usage: $0 <desktop-file> [args...]"
}

parse_args() {
	if [[ $# -lt 1 ]]; then
		usage
		exit 1
	fi

	desktop_file="$1"
	shift
	passthrough_args=("$@")
}

extract_command() {
	local line
	local extracted

	extracted=""
	while IFS= read -r line; do
		[[ $line == X-I2PdBrowser-ExecShell=* ]] || continue
		extracted="${line#X-I2PdBrowser-ExecShell=}"
	done <"$desktop_file"

	[[ -n $extracted ]] || {
		error "X-I2PdBrowser-ExecShell not found in $desktop_file"
		exit 1
	}

	I2PDB_START_PROG="${extracted//%?/}"
}

announce_launch() {
	if [[ $# -ge 1 ]]; then
		log "Launching: ${I2PDB_START_PROG} $*"
	else
		log "Launching: ${I2PDB_START_PROG}"
	fi
}

run_start_program() {
	${I2PDB_START_PROG} "$@"
}

main() {
	parse_args "$@"
	extract_command
	announce_launch "${passthrough_args[@]}"
	run_start_program "${passthrough_args[@]}"
}

main "$@"
