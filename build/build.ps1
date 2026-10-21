#!/usr/bin/env pwsh

# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# Firefox ESR bundle builder for Windows (PowerShell port of
# build/build.bash).
#
# It resolves the latest Firefox ESR for Windows, downloads the
# official installer, verifies its checksum, installs it into the
# browser directory, removes unnecessary files, updates the Firefox
# configuration and installs the NoScript extension.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:BuildDir = (Resolve-Path $PSScriptRoot).Path
$script:RepoRoot = (Resolve-Path (Join-Path $script:BuildDir '..')).Path
$script:BrowserDir = Join-Path $script:RepoRoot 'browser'
$script:I2PD_BROWSER_ROOT = $script:RepoRoot
. (Join-Path $script:RepoRoot 'lib/i18n.ps1')
[void](Initialize-I2pdBrowserI18n)

$script:Language = $script:I2pdBrowserLanguage
$script:EsrProduct = if ($env:ESR_PRODUCT) {
    $env:ESR_PRODUCT
}
else {
    'firefox-esr-next-latest'
}

function Write-BuildLog { param([string]$Message) Write-Host "[INFO] $Message" }
function Write-BuildWarn { param([string]$Message) Write-Warning $Message }
function Write-BuildError { param([string]$Message) Write-Error $Message }
function Stop-Build { param([string]$Message) Write-BuildError $Message; exit 1 }

function Get-FirefoxOs {
    switch (Get-RouterArch) {
        'x86_64' { return 'win64' }
        'i386' { return 'win' }
        'aarch64' { return 'win64-aarch64' }
        default { Stop-Build "Unsupported architecture: $(Get-RouterArch)" }
    }
}

function Import-BuildArgs {
    param([string[]]$Arguments)
    $index = 0
    while ($index -lt $Arguments.Count) {
        $argument = $Arguments[$index]
        if ($argument -like '--language=*') {
            $script:Language = $argument.Substring(11)
        }
        elseif ($argument -eq '--language') {
            if ($index + 1 -ge $Arguments.Count) {
                Stop-Build (Get-I18nMessage 'error.argument-value' @('--language'))
            }
            $script:Language = $Arguments[$index + 1]
            $index++
        }
        elseif ($argument -in @('-h', '--help')) {
            Get-I18nMessage 'usage.header' @('./build.ps1') | Write-Host
            Get-I18nMessage 'usage.options' | Write-Host
            exit 0
        }
        else {
            Stop-Build (Get-I18nMessage 'error.unknown-argument' @($argument))
        }
        $index++
    }
    $locale = ConvertTo-I2pdBrowserLocale $script:Language
    if (-not $locale) {
        Stop-Build (Get-I18nMessage 'language.invalid' @($script:Language))
    }
    $script:Language = $locale
    [void](Initialize-I2pdBrowserI18n $locale)
}

function Resolve-FirefoxDownload {
    $os = Get-FirefoxOs
    $url = 'https://download.mozilla.org/?product=' + $script:EsrProduct +
    "&os=$os&lang=$script:Language"
    Write-BuildLog (Get-I18nMessage 'info.build.resolve' @(
            $os, $script:Language))
    try {
        # HEAD follows the redirector without downloading the installer.
        $response = Invoke-WebRequest -Uri $url -Method Head `
            -UseBasicParsing
    }
    catch {
        Stop-Build (
            "Failed to resolve a $script:EsrProduct build for $os; " +
            'the platform may no longer be published.'
        )
    }
    # ResponseUri exists on Windows PowerShell 5.1; on PowerShell 7 the
    # final URL comes from the request message.
    $base = $response.BaseResponse
    $final = $null
    if ($base.PSObject.Properties.Match('ResponseUri').Count -gt 0) {
        $final = $base.ResponseUri.AbsoluteUri
    }
    elseif ($base.PSObject.Properties.Match('RequestMessage').Count -gt 0) {
        $final = $base.RequestMessage.RequestUri.AbsoluteUri
    }
    if (-not $final) { Stop-Build 'Could not resolve the download URL.' }
    return $final
}

function Get-FirefoxVersion {
    param([string]$Url)
    $name = [System.IO.Path]::GetFileName([Uri]::UnescapeDataString($Url))
    if ($name -match '(\d+\.\d+(\.\d+)?)esr') { return $Matches[1] + 'esr' }
    Stop-Build "Could not parse the version from filename: $name"
}

function Get-ExpectedChecksum {
    param(
        [string]$ReleaseUrl,
        [string]$RelativePath
    )
    try {
        $sums = Invoke-WebRequest -Uri "$ReleaseUrl/SHA512SUMS" `
            -UseBasicParsing
    }
    catch {
        Write-BuildWarn 'SHA512SUMS is not available for this platform.'
        return ''
    }
    # Match the full path relative to the release root. The base name
    # alone is not unique (every platform and locale ships the same
    # installer name).
    $pattern = '^([0-9a-fA-F]{128})\s+' +
    [regex]::Escape($RelativePath) + '$'
    foreach ($line in ($sums.Content -split "`n")) {
        if ($line -match $pattern) {
            return $Matches[1]
        }
    }
    Write-BuildWarn "No checksum entry found for $RelativePath."
    return ''
}

function Install-Firefox {
    param(
        [string]$Url,
        [string]$Version
    )
    if (Test-Path $script:BrowserDir) {
        Remove-Item -Recurse -Force $script:BrowserDir
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) `
        ("i2pd-browser-build-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    New-Item -ItemType Directory -Force -Path $script:BrowserDir | Out-Null

    $fileName = [System.IO.Path]::GetFileName(
        [Uri]::UnescapeDataString($Url)
    )
    $installer = Join-Path $tmp $fileName

    Write-BuildLog (Get-I18nMessage 'info.build.downloading' @($Version))
    Invoke-WebRequest -Uri $Url -OutFile $installer -UseBasicParsing

    # SHA512SUMS lives at the release root, not in the platform
    # language directory that contains the installer. The relative
    # path (for example "win64/en-US/Firefox Setup ... .exe") is what
    # identifies the exact entry.
    $releaseUrl = [regex]::Match(
        $Url, '^(.*/releases/[^/]+)/'
    ).Groups[1].Value
    if (-not $releaseUrl) { $releaseUrl = ($Url -replace '/[^/]+$', '') }
    $relative = [Uri]::UnescapeDataString(
        $Url.Substring($releaseUrl.Length).TrimStart('/')
    )
    $expected = Get-ExpectedChecksum -ReleaseUrl $releaseUrl `
        -RelativePath $relative
    if (-not $expected) {
        Stop-Build "No SHA512 checksum was found for $relative."
    }
    $actual = (Get-FileHash -Path $installer -Algorithm SHA512).Hash
    if ($actual -ne $expected.ToUpperInvariant()) {
        Stop-Build (Get-I18nMessage 'error.checksum')
    }
    Write-BuildLog (Get-I18nMessage 'info.build.checksum-ok')

    Write-BuildLog 'Installing Firefox'
    $process = Start-Process -FilePath $installer -Wait -PassThru `
        -ArgumentList @('/S', "/D=$script:BrowserDir")
    if ($process.ExitCode -ne 0) {
        Stop-Build "The Firefox installer failed with code $($process.ExitCode)."
    }

    Remove-Item -Recurse -Force $tmp
    $data = Join-Path $script:BrowserDir 'data'
    New-Item -ItemType Directory -Force -Path $data | Out-Null
}

function Remove-UnneededFiles {
    Write-BuildLog (Get-I18nMessage 'info.build.removing')
    $targets = @(
        'crashreporter.exe'
        'crashreporter'
        'crashhelper.exe'
        'crashhelper'
        'minidump-analyzer.exe'
        'pingsender.exe'
        'precomplete'
        'removed-files'
        'updater.exe'
        'updater.ini'
        'uninstall'
        'uninstall.exe'
        'Throbber-small.gif'
        'browser\crashreporter-override.ini'
        'browser\features\formautofill@mozilla.org.xpi'
        'browser\features\screenshots@mozilla.org.xpi'
        'browser\features\webcompat-reporter@mozilla.org.xpi'
    )
    foreach ($target in $targets) {
        $path = Join-Path $script:BrowserDir $target
        if (Test-Path $path) { Remove-Item -Recurse -Force $path }
    }
    $icons = Join-Path $script:BrowserDir 'icons'
    if (Test-Path $icons) { Remove-Item -Recurse -Force $icons }
}

function Update-Configs {
    Write-BuildLog (Get-I18nMessage 'info.build.configuring')
    $ini = Join-Path $script:BrowserDir 'application.ini'
    if (Test-Path $ini) {
        (Get-Content $ini) `
            -replace 'Enabled=1', 'Enabled=0' `
            -replace 'ServerURL=.*', 'ServerURL=-' |
            Set-Content $ini -Encoding ascii
    }
}

function Install-NoScript {
    Write-BuildLog (Get-I18nMessage 'info.build.noscript')
    $extensions = Join-Path $script:BrowserDir 'browser\extensions'
    New-Item -ItemType Directory -Force -Path $extensions | Out-Null
    $target = Join-Path $extensions `
        '{73a6fe31-595d-460b-a920-fcc0f8843232}.xpi'
    Invoke-WebRequest -Uri (
        'https://addons.mozilla.org/firefox/downloads/latest/noscript/latest.xpi'
    ) -OutFile $target -UseBasicParsing
}

function Format-PoliciesJson {
    # Format the copy in the built browser so the tracked source file is
    # never rewritten (ConvertTo-Json escapes differently from jq).
    $policies = Join-Path $script:BrowserDir 'distribution\policies.json'
    Write-BuildLog (Get-I18nMessage 'info.build.configuring')
    $data = Get-Content $policies -Raw | ConvertFrom-Json
    $json = $data | ConvertTo-Json -Depth 100
    # Write UTF-8 without a BOM: Windows PowerShell 5.1 adds one with
    # Set-Content -Encoding utf8.
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($policies, $json, $utf8)
}

function Copy-StandardConfigs {
    Write-BuildLog (Get-I18nMessage 'info.build.standard-config')
    Copy-Item -Recurse -Force `
        (Join-Path $script:BuildDir 'preferences\*') $script:BrowserDir
    Copy-Item -Recurse -Force `
        (Join-Path $script:BuildDir 'profile\*') `
        (Join-Path $script:BrowserDir 'data')
}

function Set-FirefoxLocale {
    $profile = Join-Path $script:BrowserDir 'data'
    $userJs = Join-Path $profile 'user.js'
    $content = @(
        '// Generated by I2Pd Browser; do not edit.'
        ('user_pref("intl.locale.requested", "' + $script:Language + '");')
    )
    $utf8 = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllLines($userJs, $content, $utf8)
    [IO.File]::WriteAllText(
        (Join-Path $script:BrowserDir '.i2pd-browser-locale'),
        $script:Language + [Environment]::NewLine, $utf8
    )
}

function Copy-LaunchScripts {
    Write-BuildLog (Get-I18nMessage 'info.build.launchers')
    Copy-Item -Recurse -Force `
        (Join-Path $script:BuildDir 'scripts\*') $script:BrowserDir
    Copy-Item -Force (Join-Path $script:RepoRoot 'lib\i18n.ps1') `
        $script:BrowserDir
    Copy-Item -Recurse -Force (Join-Path $script:RepoRoot 'locales') `
        $script:BrowserDir
}

function Main {
    Import-BuildArgs -Arguments $args
    $url = Resolve-FirefoxDownload
    $version = Get-FirefoxVersion -Url $url
    Write-BuildLog (Get-I18nMessage 'info.build.preparing' @($version))
    Install-Firefox -Url $url -Version $version
    Remove-UnneededFiles
    Update-Configs
    Install-NoScript
    Copy-StandardConfigs
    Set-FirefoxLocale
    Format-PoliciesJson
    Copy-LaunchScripts
    Write-BuildLog (Get-I18nMessage 'info.build.complete')
}

# Router helpers used above are defined in lib/router.ps1.
. (Join-Path $script:RepoRoot 'lib/router.ps1')

Main
exit 0
