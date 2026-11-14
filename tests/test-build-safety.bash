#!/usr/bin/env bash

# Offline tests against production build functions. Fixtures live outside the
# repository and command doubles only simulate a failed publication rename.
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
export I2PD_BROWSER_CONF="$tmp_dir/selection.conf"
# shellcheck disable=SC1091
source "$root/build/build.bash"
I2PD_BROWSER_ROOT="$tmp_dir/install"
build_lock="$I2PD_BROWSER_ROOT/.browser-build.lock"
mkdir -p "$I2PD_BROWSER_ROOT/build" "$I2PD_BROWSER_ROOT/browser/data"
cd "$I2PD_BROWSER_ROOT/build"
staging_dir="$I2PD_BROWSER_ROOT/.browser-build"

check_profile_idle
for name in .parentlock parent.lock lock; do
	ln -s missing-process "$I2PD_BROWSER_ROOT/browser/data/$name"
	if (check_profile_idle); then
		printf 'Active/stale profile marker accepted: %s\n' "$name" >&2
		exit 1
	fi
	rm "$I2PD_BROWSER_ROOT/browser/data/$name"
done

# Successful acquisition cleans only its own lock; contention preserves the
# other builder's marker and does not proceed into staging work.
(
	acquire_build_lock
	[[ -d $build_lock ]]
)
[[ ! -e $build_lock ]]
mkdir "$build_lock"
if (acquire_build_lock); then
	printf 'Concurrent build lock accepted.\n' >&2
	exit 1
fi
[[ -d $build_lock ]]
rmdir "$build_lock"

printf 'original profile\n' >"$I2PD_BROWSER_ROOT/browser/data/bookmarks.fixture"
mkdir -p "$staging_dir/data"
printf 'new browser\n' >"$staging_dir/new.fixture"
# The sourced publication function invokes this command double indirectly.
# shellcheck disable=SC2329
mv() {
	if [[ $1 == "$staging_dir" && $2 == ../browser ]]; then
		return 1
	fi
	command mv "$@"
}
if (publish_browser); then
	printf 'Injected publication failure unexpectedly succeeded.\n' >&2
	exit 1
fi
[[ $(cat "$I2PD_BROWSER_ROOT/browser/data/bookmarks.fixture") == 'original profile' ]]
[[ ! -e $I2PD_BROWSER_ROOT/.browser-old ]]
[[ -f $staging_dir/new.fixture ]]
unset -f mv

# Installer transactions request an intact backup until router selection is
# committed. The next ordinary publication returns to default cleanup.
I2PD_BROWSER_KEEP_BACKUP=1 publish_browser
[[ -f $I2PD_BROWSER_ROOT/browser/new.fixture ]]
[[ $(cat "$I2PD_BROWSER_ROOT/.browser-old/data/bookmarks.fixture") == 'original profile' ]]
rm -rf "$I2PD_BROWSER_ROOT/.browser-old"
mkdir -p "$staging_dir/data"
printf 'preserved staged profile\n' >"$staging_dir/data/bookmarks.fixture"
printf 'next browser\n' >"$staging_dir/next.fixture"
(
	unset I2PD_BROWSER_KEEP_BACKUP
	publish_browser
)
[[ -f $I2PD_BROWSER_ROOT/browser/next.fixture ]]
[[ $(cat "$I2PD_BROWSER_ROOT/browser/data/bookmarks.fixture") == 'preserved staged profile' ]]
[[ ! -e $I2PD_BROWSER_ROOT/.browser-old ]]

mkdir "$I2PD_BROWSER_ROOT/.browser-old"
printf 'recovery copy\n' >"$I2PD_BROWSER_ROOT/.browser-old/recovery.fixture"
if (acquire_build_lock); then
	printf 'Unresolved publication backup accepted.\n' >&2
	exit 1
fi
[[ $(cat "$I2PD_BROWSER_ROOT/.browser-old/recovery.fixture") == 'recovery copy' ]]

# Paths are serialized by the production desktop helper, never evaluated.
launcher="$tmp_dir/a space & \"quote\" \$literal \`literal\` 100%/browser"
browser_desktop_entry "$root/build/scripts/start-i2pd-browser.desktop" "$tmp_dir/desktop" "$launcher"
[[ $(grep -c '^Exec=' "$tmp_dir/desktop") == 1 ]]
grep -Fq '100%%/browser" --detach' "$tmp_dir/desktop"
if browser_desktop_entry "$root/build/scripts/start-i2pd-browser.desktop" "$tmp_dir/unsafe-desktop" $'/tmp/path\nExec=bad'; then
	printf 'Multiline desktop path accepted.\n' >&2
	exit 1
fi
printf 'Build safety behavior tests passed.\n'
