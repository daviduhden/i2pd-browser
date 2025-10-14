# Copyright (c) 2025, The PurpleI2P Project
# This file is part of Purple i2pd project and licensed under BSD3
# See full license text in LICENSE file at top of project tree

param(
  [Parameter(Mandatory = $true)]
  [string]$JsonPath,

  [Parameter(Mandatory = $true)]
  [ValidateSet('win32','win64')]
  [string]$OsTag
)

try {
  $json = Get-Content -Raw -ErrorAction Stop -Path $JsonPath | ConvertFrom-Json
} catch {
  Write-Error "Failed to read or parse JSON: $($_.Exception.Message)"
  exit 1
}

$pattern = "_${OsTag}_mingw\.zip$"
$asset = $json.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1

if (-not $asset) {
  Write-Error "No matching i2pd asset for $OsTag"
  exit 2
}

$asset.browser_download_url
