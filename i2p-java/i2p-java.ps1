# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# Launcher for the I2P (Java) router backend (PowerShell port). It
# starts the I2P installation with an isolated configuration directory.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $script:Root 'lib/router.ps1')

if (-not (Import-RouterBackend 'i2p-java')) { exit 1 }
Invoke-RouterPrepareConfig | Out-Null
if (-not (Start-Router)) { exit 1 }
