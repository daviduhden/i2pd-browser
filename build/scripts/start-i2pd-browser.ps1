#!/usr/bin/env pwsh

# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# I2Pd Browser launcher for Windows (PowerShell port of
# build/scripts/start-i2pd-browser.bash).
#
# It starts the bundled Firefox ESR with the portable profile and
# forwards the remaining arguments to Firefox.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:BrowserDir = (Resolve-Path $PSScriptRoot).Path
$script:Firefox = Join-Path $script:BrowserDir 'firefox.exe'
. (Join-Path $script:BrowserDir 'i18n.ps1')
$script:I2PD_BROWSER_ROOT = $script:BrowserDir
$marker = Join-Path $script:BrowserDir '.i2pd-browser-locale'
$locale = if (Test-Path $marker) {
    (Get-Content $marker -Raw).Trim()
} else { 'en-US' }
[void](Initialize-I2pdBrowserI18n $locale)
$script:ShowOutput = $false
$script:Detach = $false
$script:ShowUsage = $false
$script:LogOutput = $false
$script:LogFile = $null

function Show-BrowserUsage {
    Get-I18nMessage 'launcher.usage' | Write-Host
}

function Import-BrowserArgs {
    param([string[]]$Arguments)
    $index = 0
    $remaining = @()
    while ($index -lt $Arguments.Count) {
        $argument = $Arguments[$index]
        switch -Regex ($argument) {
            '^(--detach)$' { $script:Detach = $true; $index++ }
            '^(-v|--verbose|-d|--debug)$' {
                $script:ShowOutput = $true
                $index++
            }
            '^(-h|-help|--help|-\?)$' {
                $script:ShowUsage = $true
                $script:ShowOutput = $true
                $index++
            }
            '^(-l|--log)$' {
                $script:LogOutput = $true
                if ($index + 1 -lt $Arguments.Count -and
                    -not $Arguments[$index + 1].StartsWith('-')) {
                    $script:LogFile = $Arguments[$index + 1]
                    $index += 2
                }
                else {
                    $script:LogFile = Join-Path $script:BrowserDir `
                        'i2pd-browser.log'
                    $index++
                }
            }
            default {
                $remaining += $argument
                $index++
            }
        }
    }
    return $remaining
}

function Start-Firefox {
    param([string[]]$FirefoxArgs)
    if (-not (Test-Path $script:Firefox)) {
        Write-Error (Get-I18nMessage 'error.browser-missing' @($script:Firefox))
        exit 1
    }

    $arguments = @('-profile', 'data') + $FirefoxArgs

    # If --log points at an existing directory, keep the default file
    # name inside it instead of failing to write to a directory.
    if ($script:LogOutput -and
        (Test-Path $script:LogFile -PathType Container)) {
        $script:LogFile = Join-Path $script:LogFile 'i2pd-browser.log'
    }

    if ($script:ShowUsage) {
        & $script:Firefox -profile data --help
        Show-BrowserUsage
        return
    }

    if ($script:Detach) {
        Start-Process -FilePath $script:Firefox -ArgumentList $arguments `
            -WorkingDirectory $script:BrowserDir | Out-Null
        return
    }

    if ($script:LogOutput) {
        & $script:Firefox @arguments 2>&1 |
            Tee-Object -FilePath $script:LogFile
        return
    }

    if ($script:ShowOutput) {
        & $script:Firefox @arguments
        return
    }

    & $script:Firefox @arguments 2>&1 | Out-Null
}

$browserArgs = Import-BrowserArgs -Arguments $args
Start-Firefox -FirefoxArgs $browserArgs
