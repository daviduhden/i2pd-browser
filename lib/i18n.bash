#!/bin/bash

# Shared, data-only localization support. Catalogs use UTF-8 key=value
# records and are never sourced as shell code.

declare -A I18N_MESSAGES=()
I2PD_BROWSER_LANGUAGE="${I2PD_BROWSER_LANGUAGE:-}"

i18n_normalize_locale() {
	local locale="${1-}"
	locale="${locale%%.*}"
	locale="${locale//_/-}"
	case "${locale,,}" in
	en | en-*) printf 'en-US\n' ;;
	es | es-*) printf 'es-ES\n' ;;
	ru | ru-*) printf 'ru\n' ;;
	zh | zh-cn | zh-hans | zh-hans-cn) printf 'zh-CN\n' ;;
	*) return 1 ;;
	esac
}

i18n_config_file() {
	printf '%s\n' "${I2PD_BROWSER_CONF:-$I2PD_BROWSER_ROOT/i2pd-browser.conf}"
}

i18n_stored_locale() {
	local file
	file="$(i18n_config_file)"
	[[ -r $file ]] || return 0
	sed -n 's/^[[:space:]]*I2PD_BROWSER_LANGUAGE[[:space:]]*=[[:space:]]*//p' \
		"$file" | tr -d '\r' | tail -n 1
}

i18n_system_locale() {
	local candidate language_preferences
	if [[ -n ${LANGUAGE:-} ]]; then
		IFS=: read -r -a language_preferences <<<"$LANGUAGE"
		for candidate in "${language_preferences[@]}"; do
			i18n_normalize_locale "$candidate" && return 0
		done
	fi
	for candidate in "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LANG:-}"; do
		i18n_normalize_locale "$candidate" && return 0
	done
	printf 'en-US\n'
}

i18n_select_locale() {
	local explicit="${1-}" stored env_locale detected
	if [[ -n $explicit ]]; then
		i18n_normalize_locale "$explicit" || return 1
		return 0
	fi
	stored="$(i18n_stored_locale)"
	if [[ -n $stored ]] && detected="$(i18n_normalize_locale "$stored")"; then
		printf '%s\n' "$detected"
		return 0
	fi
	env_locale="${I2PD_BROWSER_LANGUAGE:-${language:-}}"
	if [[ -n $env_locale ]] &&
		detected="$(i18n_normalize_locale "$env_locale")"; then
		printf '%s\n' "$detected"
		return 0
	fi
	i18n_system_locale
}

i18n_load_catalog() {
	local locale="$1" key value catalog
	I18N_MESSAGES=()
	for catalog in "$I2PD_BROWSER_ROOT/locales/en-US.properties" \
		"$I2PD_BROWSER_ROOT/locales/$locale.properties"; do
		[[ -r $catalog ]] || continue
		while IFS='=' read -r key value || [[ -n $key ]]; do
			[[ -n $key && ${key:0:1} != '#' && $key != *' '* ]] || continue
			I18N_MESSAGES["$key"]="$value"
		done <"$catalog"
	done
}

i18n_init() {
	local explicit="${1-}" locale
	locale="$(i18n_select_locale "$explicit")" || return 1
	I2PD_BROWSER_LANGUAGE="$locale"
	i18n_load_catalog "$locale"
}

i18n_message() {
	local key="$1" message index=0 value replacement
	shift
	message="${I18N_MESSAGES[$key]-}"
	if [[ -z $message ]]; then
		printf '[[%s]]' "$key" >&2
		printf '%s\n' "$key"
		return 1
	fi
	for value in "$@"; do
		replacement="${value//\\/\\\\}"
		replacement="${replacement//&/\\&}"
		message="${message//\{$index\}/$replacement}"
		index=$((index + 1))
	done
	printf '%b\n' "$message"
}
