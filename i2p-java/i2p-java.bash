#!/bin/bash

# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# Launcher for the I2P (Java) router backend. It starts the system I2P
# installation with an isolated configuration directory.

set -Eeuo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &&
	pwd -P)"

# shellcheck source=../lib/router.bash
# shellcheck disable=SC1091
source "$_script_dir/../lib/router.bash"

router_load_backend i2p-java
router_prepare_config
router_start
