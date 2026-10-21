#!/bin/bash

set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export I2PD_BROWSER_ROOT="$root"
export I2PD_BROWSER_CONF="$tmp/i2pd-browser.conf"
# shellcheck source=../lib/i18n.bash
source "$root/lib/i18n.bash"

assert_eq() {
	[[ $1 == "$2" ]] || {
		printf 'expected %q, got %q\n' "$2" "$1" >&2
		exit 1
	}
}

for locale in en-US es-ES ru zh-CN; do
	[[ -s "$root/locales/$locale.properties" ]]
	diff -u \
		<(grep -vE '^(#|$)' "$root/locales/en-US.properties" |
			cut -d= -f1 | sort) \
		<(grep -vE '^(#|$)' "$root/locales/$locale.properties" |
			cut -d= -f1 | sort)
	i18n_init "$locale"
	[[ -n $(i18n_message language.selected "$locale") ]]
done

assert_eq "$(i18n_normalize_locale en_GB)" en-US
assert_eq "$(i18n_normalize_locale es_MX)" es-ES
assert_eq "$(i18n_normalize_locale ru_RU)" ru
assert_eq "$(i18n_normalize_locale zh-Hans-CN)" zh-CN
i18n_normalize_locale de-DE && exit 1

old_language="${LANGUAGE-}"
old_lc_all="${LC_ALL-}"
old_lc_messages="${LC_MESSAGES-}"
old_lang="${LANG-}"
export LANGUAGE='de:ru_RU' LC_ALL='' LC_MESSAGES='' LANG=''
assert_eq "$(i18n_system_locale)" ru
export LANGUAGE="$old_language" LC_ALL="$old_lc_all" \
	LC_MESSAGES="$old_lc_messages" LANG="$old_lang"
I2PD_BROWSER_LANGUAGE=zh-Hans i18n_select_locale >"$tmp/locale"
assert_eq "$(<"$tmp/locale")" zh-CN
(
	export I2PD_BROWSER_LANGUAGE=zh-Hans
	i18n_init
	assert_eq "$I2PD_BROWSER_LANGUAGE" zh-CN
)

# A localized catalog falls back to a key available only in English.
cp "$root/locales/en-US.properties" "$tmp/en-US.properties"
printf 'fallback.only=English fallback {0}\\n' >>"$tmp/en-US.properties"
original_root="$I2PD_BROWSER_ROOT"
I2PD_BROWSER_ROOT="$tmp"
mkdir -p "$tmp/locales"
mv "$tmp/en-US.properties" "$tmp/locales/en-US.properties"
cp "$root/locales/es-ES.properties" "$tmp/locales/es-ES.properties"
i18n_init es-ES
assert_eq "$(i18n_message fallback.only 'a&b')" 'English fallback a&b'
I2PD_BROWSER_ROOT="$original_root"
i18n_init en-US

cat >"$I2PD_BROWSER_CONF" <<'EOF'
I2P_ROUTER=i2pd
I2PD_BROWSER_LANGUAGE=es-ES
CUSTOM_SETTING=preserved
EOF
i18n_init
assert_eq "$I2PD_BROWSER_LANGUAGE" es-ES

# A stored selection wins over an application environment value.
export I2PD_BROWSER_LANGUAGE=zh-Hans
i18n_init
assert_eq "$I2PD_BROWSER_LANGUAGE" es-ES

# shellcheck source=../lib/router.bash
source "$root/lib/router.bash"
router_conf_set i2pd system ru
grep -qx 'CUSTOM_SETTING=preserved' "$I2PD_BROWSER_CONF"
grep -qx 'I2PD_BROWSER_LANGUAGE=ru' "$I2PD_BROWSER_CONF"

# Firefox's locale preference is generated in the portable profile and
# is not part of the hardened policy file.
grep -q 'intl.locale.requested' "$root/build/build.bash"
grep -q 'intl.locale.requested' "$root/build/build.ps1"
grep -q 'intl.locale.requested' \
	"$root/build/preferences/distribution/policies.json" && exit 1

printf 'Bash i18n tests passed\n'
