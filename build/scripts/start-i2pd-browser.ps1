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

function ConvertTo-WindowsArgument {
    param([AllowEmptyString()][string]$Value)
    $result = '"'
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) { $slashes++; continue }
        if ($character -eq [char]34) {
            $result += ('\' * (2 * $slashes + 1)) + '"'
        } else { $result += ('\' * $slashes) + $character }
        $slashes = 0
    }
    return $result + ('\' * (2 * $slashes)) + '"'
}

function Show-BundleAge {
    $metadata = Join-Path $script:BrowserDir '.i2pd-browser-build.json'
    try {
        $manifest = Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json
        $epoch = [long]$manifest.built_epoch
        if ($manifest.schema -ne 1 -or $epoch -le 0) { throw 'Invalid metadata' }
        if ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $epoch -gt 30 * 86400) {
            Write-Warning (Get-I18nMessage 'warning.bundle-age' @(30))
        }
    } catch { Write-Warning (Get-I18nMessage 'error.bundle-metadata') }
}

function Start-Firefox {
    param([string[]]$FirefoxArgs)
    if (-not (Test-Path $script:Firefox)) {
        Write-Error (Get-I18nMessage 'error.browser-missing' @($script:Firefox))
        exit 1
    }

    # Use an absolute profile path: the launcher may be invoked from any
    # working directory, including by double-clicking the .cmd shim.
    $profileDir = Join-Path $script:BrowserDir 'data'
    $arguments = @('-profile', $profileDir) + $FirefoxArgs

    # If --log points at an existing directory, keep the default file
    # name inside it instead of failing to write to a directory.
    if ($script:LogOutput -and
        (Test-Path $script:LogFile -PathType Container)) {
        $script:LogFile = Join-Path $script:LogFile 'i2pd-browser.log'
    }


    if ($script:Detach) {
        # Start-Process joins its argument array with spaces without
        # adding quotes, so quote a profile path that contains spaces.
        $startArguments = @('-profile', $profileDir) + $FirefoxArgs
        $startArguments = ($startArguments | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' '
        Start-Process -FilePath $script:Firefox `
            -ArgumentList $startArguments `
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
if ($script:ShowUsage) { Show-BrowserUsage; exit 0 }
foreach ($lockName in @('.browser-build.lock', '.browser-switch.lock')) {
    $operationLock = Join-Path $script:BrowserDir ('../' + $lockName)
    if (Get-Item -LiteralPath $operationLock -Force -ErrorAction SilentlyContinue) {
        Write-Error (Get-I18nMessage 'error.build-locked' @($operationLock)); exit 1
    }
}
Show-BundleAge
Start-Firefox -FirefoxArgs $browserArgs
if ($script:Detach) { exit 0 }
exit $LASTEXITCODE
