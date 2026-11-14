#!/bin/bash
# Generate a desktop Exec argument without evaluating the installation path.
# Escape the desktop value layer as well as the Exec double-quote layer.
browser_desktop_entry() {
	local template="$1" output="$2" launcher="$3" line escaped
	[[ $launcher != *$'\n'* && $launcher != *$'\r'* ]] || return 1
	escaped="${launcher//\\/\\\\}"
	escaped="${escaped//\"/\\\"}"
	escaped="${escaped//\$/\\\$}"
	escaped="${escaped//\`/\\\`}"
	escaped="${escaped//%/%%}"
	escaped="${escaped//\\/\\\\}"
	while IFS= read -r line || [[ -n $line ]]; do
		if [[ $line == Exec=* ]]; then
			printf 'Exec="%s" --detach\n' "$escaped"
		else
			printf '%s\n' "$line"
		fi
	done <"$template" >"$output"
	chmod +x "$output"
}
