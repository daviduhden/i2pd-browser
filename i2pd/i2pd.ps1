# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# Launcher for the i2pd (C++) I2P router backend (PowerShell port).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $script:Root 'lib/router.ps1')

if (-not (Import-RouterBackend 'i2pd')) { exit 1 }
Invoke-RouterPrepareConfig | Out-Null
if (-not (Start-Router)) { exit 1 }
