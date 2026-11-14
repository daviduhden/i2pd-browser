#!/usr/bin/env bash

# Python's standard library creates offline XPI fixtures; the production
# download/validation function runs with curl replaced by a local copy.
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
export I2PD_BROWSER_CONF="$tmp_dir/selection.conf"
# shellcheck disable=SC1091
source "$root/build/build.bash"
command -v python3 >/dev/null || {
	printf 'python3 is required for XPI test fixtures.\n' >&2
	exit 1
}
python3 - "$tmp_dir" <<'PY'
import copy
import json
import pathlib
import sys
import warnings
import zipfile

directory = pathlib.Path(sys.argv[1])
base = {"version": "11.5.0", "browser_specific_settings": {"gecko": {
    "id": "{73a6fe31-595d-460b-a920-fcc0f8843232}", "strict_min_version": "128.0"}}}
for name, change in (
    ("valid", {}),
    ("wrong-id", {"id": "other@example.invalid"}),
    ("too-new", {"strict_min_version": "999.0"}),
    ("too-old", {"strict_max_version": "100.*"}),
):
    manifest = copy.deepcopy(base)
    manifest["browser_specific_settings"]["gecko"].update(change)
    with zipfile.ZipFile(directory / (name + ".xpi"), "w") as archive:
        archive.writestr("manifest.json", json.dumps(manifest))
        archive.writestr("background.js", "// fixture\n")
with zipfile.ZipFile(directory / "missing-manifest.xpi", "w") as archive:
    archive.writestr("background.js", "// fixture\n")
with warnings.catch_warnings():
    warnings.simplefilter("ignore", UserWarning)
    with zipfile.ZipFile(directory / "duplicate-manifest.xpi", "w") as archive:
        archive.writestr("manifest.json", json.dumps(base))
        archive.writestr("manifest.json", json.dumps(base))
(directory / "malformed.xpi").write_text("PK this is not a ZIP archive")
PY

# These globals are inputs to the production function sourced above.
# shellcheck disable=SC2034
staging_dir="$tmp_dir/staging"
# shellcheck disable=SC2034
version=140.0esr
fixture="$tmp_dir/valid.xpi"
unset NOSCRIPT_XPI_URL NOSCRIPT_SHA512
curl() {
	local destination=""
	while (($#)); do
		if [[ $1 == -o ]]; then
			destination="$2"
			break
		fi
		shift
	done
	[[ -n $destination ]] || return 1
	cp "$fixture" "$destination"
}
download_noscript
# These outputs are assigned by the sourced production function.
# shellcheck disable=SC2154
[[ $noscript_version == 11.5.0 && $noscript_sha512 =~ ^[a-f0-9]{128}$ ]]
# A pinned official release must match its expected digest before parsing.
NOSCRIPT_XPI_URL='https://addons.mozilla.org/firefox/downloads/file/123456/noscript-fixture.xpi'
NOSCRIPT_SHA512="$(sha512sum "$fixture" | awk '{print $1}')"
export NOSCRIPT_XPI_URL NOSCRIPT_SHA512
download_noscript
NOSCRIPT_SHA512="$(printf '%0128d' 0)"
if (download_noscript); then
	printf 'NoScript checksum mismatch accepted.\n' >&2
	exit 1
fi
unset NOSCRIPT_XPI_URL NOSCRIPT_SHA512
for name in wrong-id too-new too-old missing-manifest duplicate-manifest malformed; do
	fixture="$tmp_dir/$name.xpi"
	if (download_noscript); then
		printf 'Invalid NoScript payload accepted: %s\n' "$name" >&2
		exit 1
	fi
done
printf 'NoScript payload behavior tests passed.\n'
