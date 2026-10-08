#!/bin/bash

# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# Launcher for the i2pd (C++) I2P router backend. Kept as a thin
# wrapper around the shared router abstraction so the original
# behaviour of this file is preserved.

set -Eeuo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &&
	pwd -P)"

# shellcheck source=../lib/router.bash
# shellcheck disable=SC1091
source "$_script_dir/../lib/router.bash"

router_load_backend i2pd
router_prepare_config
router_start
