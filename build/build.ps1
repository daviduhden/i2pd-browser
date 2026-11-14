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
$script:FinalBrowserDir = Join-Path $script:RepoRoot 'browser'
# Build into a staging directory and publish only after every step
# succeeds, so a failed build never removes a working browser.
$script:BrowserDir = Join-Path $script:RepoRoot '.browser-build'
$script:I2PD_BROWSER_ROOT = $script:RepoRoot
. (Join-Path $script:RepoRoot 'lib/i18n.ps1')
[void](Initialize-I2pdBrowserI18n)

$script:FirefoxSha512 = ''
$script:NoScriptVersion = ''
$script:NoScriptSha512 = ''
$script:NoScriptUrl = 'https://addons.mozilla.org/firefox/downloads/latest/noscript/latest.xpi'
$script:NoScriptExpectedSha512 = ''
$script:FirefoxUrl = ''
$script:FirefoxVersion = ''
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
            Get-I18nMessage 'usage.build-header' @('./build.ps1') | Write-Host
            Get-I18nMessage 'usage.build-options' | Write-Host
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

    # A redirect to a fallback locale would pass a checksum check but
    # leave the bundle in the wrong language. Reject it explicitly.
    $decoded = [Uri]::UnescapeDataString($final)
    $localePattern = '/' + [regex]::Escape($script:Language) + '/'
    if ($decoded -notmatch $localePattern) {
        Stop-Build (Get-I18nMessage 'error.invalid-locale-build' @(
                $script:Language))
    }
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
    $script:FirefoxSha512 = $actual.ToLowerInvariant()
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

    # Keep the portable profile across rebuilds. Without this, a
    # language change or a rebuild would delete bookmarks, history,
    # cookies, logins and extensions stored in browser/data.
    $oldData = Join-Path $script:FinalBrowserDir 'data'
    if (Test-Path $oldData) {
        Get-ChildItem -Path $oldData -Force | Copy-Item `
            -Destination $data -Recurse -Force
        # Remove only copied locks after the idle-profile guard.
        # Never remove locks from the published profile.
        foreach ($lock in @('.parentlock', 'parent.lock', 'lock')) {
            $lockPath = Join-Path $data $lock
            if (Test-Path $lockPath) { Remove-Item -Force $lockPath }
        }
    }
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
        'update-settings.ini'
        'updates'
        'uninstall'
        'uninstall.exe'
        'maintenanceservice.exe'
        'maintenanceservice_installer.exe'
        'default-browser-agent.exe'
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
    if (-not (Test-Path $ini)) {
        Stop-Build 'Firefox application.ini is missing.'
    }
    (Get-Content $ini) `
        -replace 'Enabled=1', 'Enabled=0' `
        -replace 'ServerURL=.*', 'ServerURL=-' |
        Set-Content $ini -Encoding ascii
}

function Initialize-NoScriptPin {
    $script:NoScriptUrl = 'https://addons.mozilla.org/firefox/downloads/latest/noscript/latest.xpi'
    $script:NoScriptExpectedSha512 = $env:NOSCRIPT_SHA512
    if ($env:NOSCRIPT_XPI_URL) {
        if ($env:NOSCRIPT_XPI_URL -cnotmatch '^https://addons\.mozilla\.org/firefox/downloads/file/[0-9]+/[A-Za-z0-9][A-Za-z0-9._-]*\.xpi$' -or
            $script:NoScriptExpectedSha512 -notmatch '^[0-9a-fA-F]{128}$') {
            Stop-Build (Get-I18nMessage 'error.noscript')
        }
        $script:NoScriptUrl = $env:NOSCRIPT_XPI_URL
    }
    if ($script:NoScriptExpectedSha512 -and
        $script:NoScriptExpectedSha512 -notmatch '^[0-9a-fA-F]{128}$') {
        Stop-Build (Get-I18nMessage 'error.noscript')
    }
}

function Install-NoScript {
    Initialize-NoScriptPin
    Write-BuildLog (Get-I18nMessage 'info.build.noscript')
    $extensions = Join-Path $script:BrowserDir 'browser\extensions'
    New-Item -ItemType Directory -Force -Path $extensions | Out-Null
    $target = Join-Path $extensions `
        '{73a6fe31-595d-460b-a920-fcc0f8843232}.xpi'
    Invoke-WebRequest -Uri $script:NoScriptUrl -OutFile $target -UseBasicParsing
    $script:NoScriptSha512 = (Get-FileHash $target -Algorithm SHA512).Hash.ToLowerInvariant()
    if ($script:NoScriptExpectedSha512 -and
        $script:NoScriptSha512 -ne $script:NoScriptExpectedSha512) {
        Stop-Build (Get-I18nMessage 'error.noscript')
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($target)
    try {
        $entries = @($zip.Entries | Where-Object FullName -eq 'manifest.json')
        if ($entries.Count -ne 1 -or $entries[0].Length -gt 1048576) {
            Stop-Build (Get-I18nMessage 'error.noscript')
        }
        $reader = New-Object IO.StreamReader($entries[0].Open())
        try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }
        $gecko = if ($manifest.PSObject.Properties['browser_specific_settings']) {
            $manifest.browser_specific_settings.gecko
        } else { $manifest.applications.gecko }
        if ($gecko.id -ne '{73a6fe31-595d-460b-a920-fcc0f8843232}' -or
            $manifest.version -notmatch '^[0-9]+(\.[0-9]+)*$' -or
            $gecko.strict_min_version -notmatch '^[0-9]+(\.[0-9]+)*$') {
            Stop-Build (Get-I18nMessage 'error.noscript')
        }
        $current = [version]($script:FirefoxVersion -replace 'esr$', '')
        if ($current -lt [version]$gecko.strict_min_version) {
            Stop-Build (Get-I18nMessage 'error.noscript')
        }
        if ($gecko.PSObject.Properties['strict_max_version'] -and
            $gecko.strict_max_version -ne '*') {
            $maximum = $gecko.strict_max_version
            if ($maximum -notmatch '^[0-9]+(\.[0-9]+)*(\.\*)?$') {
                Stop-Build (Get-I18nMessage 'error.noscript')
            }
            if ($maximum.EndsWith('.*')) {
                $prefix = $maximum.Substring(0, $maximum.Length - 2).Split('.')
                $parts = $current.ToString().Split('.')
                for ($i = 0; $i -lt $prefix.Count; $i++) {
                    if ([int]$parts[$i] -gt [int]$prefix[$i]) {
                        Stop-Build (Get-I18nMessage 'error.noscript')
                    }
                    if ([int]$parts[$i] -lt [int]$prefix[$i]) { break }
                }
            } elseif ($current -gt [version]$maximum) {
                Stop-Build (Get-I18nMessage 'error.noscript')
            }
        }
        $script:NoScriptVersion = $manifest.version
        # Read all entries so invalid compressed data fails before publication.
        foreach ($entry in $zip.Entries) {
            $stream = $entry.Open()
            try { $stream.CopyTo([IO.Stream]::Null) } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
}

function Format-PoliciesJson {
    $policies = Join-Path $script:BrowserDir 'distribution\policies.json'
    Write-BrowserProxyPolicy -InputPath $policies -OutputPath $policies -Endpoint (Get-RouterHttpProxy)
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
    # Both launchers are shipped in the bundle so a copy remains
    # usable when moved between platforms.
    Copy-Item -Force (Join-Path $script:RepoRoot 'lib\i18n.ps1') `
        $script:BrowserDir
    Copy-Item -Force (Join-Path $script:RepoRoot 'lib\i18n.bash') `
        $script:BrowserDir
    Copy-Item -Recurse -Force (Join-Path $script:RepoRoot 'locales') `
        $script:BrowserDir
}

function Test-BundleLayout {
    $required = @(
        'firefox.exe'
        '.i2pd-browser-build.json'
        'browser\extensions\{73a6fe31-595d-460b-a920-fcc0f8843232}.xpi'
        'application.ini'
        'i2pd-browser.cfg'
        'defaults\pref\autoconfig.js'
        'distribution\policies.json'
        'browser\override.ini'
        'data\user.js'
        '.i2pd-browser-locale'
        'start-i2pd-browser.bash'
        'start-i2pd-browser.ps1'
        'i18n.bash'
        'i18n.ps1'
        'locales\en-US.properties'
    )
    $missing = @()
    foreach ($item in $required) {
        if (-not (Test-Path (Join-Path $script:BrowserDir $item))) {
            $missing += $item
        }
    }
    if ($missing.Count -gt 0) {
        Stop-Build (Get-I18nMessage 'error.bundle-validation' @(
                ($missing -join ', ')))
    }

    if (-not (Test-BrowserProxyPolicy -Path (Join-Path $script:BrowserDir 'distribution\policies.json') -Endpoint (Get-RouterHttpProxy))) {
        Stop-Build (Get-I18nMessage 'error.bundle-validation' @('Proxy policy'))
    }
    $manifest = Get-Content (Join-Path $script:BrowserDir '.i2pd-browser-build.json') -Raw | ConvertFrom-Json
    if ($manifest.schema -ne 1 -or $manifest.built_epoch -le 0 -or
        $manifest.http_proxy -ne (Get-RouterHttpProxy) -or
        -not $manifest.firefox.version -or -not $manifest.noscript.version -or
        $manifest.firefox.sha512 -notmatch '^[0-9a-f]{128}$' -or
        $manifest.noscript.sha512 -notmatch '^[0-9a-f]{128}$' -or
        $manifest.noscript.url -notlike 'https://addons.mozilla.org/firefox/downloads/*' -or
        $manifest.firefox.url -notlike 'https://*') {
        Stop-Build (Get-I18nMessage 'error.bundle-metadata')
    }
}

function Publish-Browser {
    Assert-ProfileIdle
    $backup = Join-Path $script:RepoRoot '.browser-old'
    if (Test-Path $script:FinalBrowserDir) {
        Move-Item -Path $script:FinalBrowserDir -Destination $backup `
            -ErrorAction Stop
    }
    try {
        Move-Item -Path $script:BrowserDir `
            -Destination $script:FinalBrowserDir -ErrorAction Stop
    }
    catch {
        if (Test-Path $backup) {
            Move-Item -Path $backup -Destination $script:FinalBrowserDir `
                -ErrorAction SilentlyContinue
        }
        throw
    }
    # Installer transactions retain the old bundle until router commit succeeds.
    if ($env:I2PD_BROWSER_KEEP_BACKUP -ne '1' -and (Test-Path $backup)) {
        Remove-Item -Recurse -Force $backup
    }
}

function Assert-ProfileIdle {
    foreach ($name in @('.parentlock', 'parent.lock', 'lock')) {
        $path = Join-Path $script:FinalBrowserDir ('data/' + $name)
        if (Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue) {
            if ($name -ne 'parent.lock') {
                Stop-Build (Get-I18nMessage 'error.profile-active' @($path))
            }
            # An existing Windows lock file can survive normal shutdown.
            # Exclusive open tests its live OS lock without deleting it.
            $profileLock = $null
            try {
                $profileLock = [IO.File]::Open($path, [IO.FileMode]::Open,
                    [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            } catch { Stop-Build (Get-I18nMessage 'error.profile-active' @($path)) }
            finally { if ($null -ne $profileLock) { $profileLock.Dispose() } }
        }
    }
}

function Write-BuildManifest {
    $now = [DateTimeOffset]::UtcNow
    $manifest = @{
        schema = 1; built_at = $now.ToString('yyyy-MM-ddTHH:mm:ssZ')
        built_epoch = $now.ToUnixTimeSeconds(); platform = (Get-FirefoxOs)
        locale = $script:Language; http_proxy = (Get-RouterHttpProxy)
        firefox = @{version = $script:FirefoxVersion; product = $script:EsrProduct
            url = $script:FirefoxUrl; sha512 = $script:FirefoxSha512}
        noscript = @{version = $script:NoScriptVersion; sha512 = $script:NoScriptSha512
            url = $script:NoScriptUrl}
    }
    $utf8 = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText((Join-Path $script:BrowserDir '.i2pd-browser-build.json'),
        ($manifest | ConvertTo-Json -Depth 10), $utf8)
}

function Main {
    Import-BuildArgs -Arguments $args
    Initialize-NoScriptPin

    if (-not (Test-RouterProxySettings)) {
        Stop-Build 'Proxy overrides must use 127.0.0.1 and ports from 1 to 65535.'
    }

    if ($script:EsrProduct -notmatch '^[A-Za-z0-9._-]+$') {
        Stop-Build (Get-I18nMessage 'error.invalid-product' @(
                $script:EsrProduct))
    }

    Assert-ProfileIdle
    $url = Resolve-FirefoxDownload
    $version = Get-FirefoxVersion -Url $url
    $script:FirefoxUrl = $url
    $script:FirefoxVersion = $version
    Write-BuildLog (Get-I18nMessage 'info.build.preparing' @($version))
    Install-Firefox -Url $url -Version $version
    Remove-UnneededFiles
    Update-Configs
    Install-NoScript
    Copy-StandardConfigs
    Format-PoliciesJson
    Copy-LaunchScripts
    Set-FirefoxLocale
    Write-BuildManifest
    Test-BundleLayout
    Publish-Browser
    Write-BuildLog (Get-I18nMessage 'info.build.complete')
}

# Router helpers used above are defined in lib/router.ps1.
. (Join-Path $script:RepoRoot 'lib/router.ps1')
. (Join-Path $script:RepoRoot 'lib/browser-policy.ps1')

if ($MyInvocation.InvocationName -ne '.') {
    $buildLock = Join-Path $script:RepoRoot '.browser-build.lock'
    $lockStream = $null
    try {
        # --help returns before obtaining a lock or performing any writes.
        if (@($args | Where-Object { $_ -in @('--help', '-h') }).Count -gt 0) { Main @args; exit 0 }
        try {
            $lockStream = [IO.File]::Open($buildLock, [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write, [IO.FileShare]::None)
        } catch { Stop-Build (Get-I18nMessage 'error.build-locked' @($buildLock)) }
        $switchLock = Join-Path $script:RepoRoot '.browser-switch.lock'
        if ((Get-Item -LiteralPath $switchLock -Force -ErrorAction SilentlyContinue) -and
            ($env:I2PD_BROWSER_CONFIGURE_BUILD -ne '1' -or $env:I2PD_BROWSER_KEEP_BACKUP -ne '1')) {
            Stop-Build (Get-I18nMessage 'error.build-locked' @($switchLock))
        }
        if (Get-Item -LiteralPath (Join-Path $script:RepoRoot '.browser-old') -Force -ErrorAction SilentlyContinue) {
            Stop-Build (Get-I18nMessage 'error.build-locked' @('.browser-old'))
        }
        Main @args
    } finally {
        if ($null -ne $lockStream) {
            $lockStream.Dispose()
            Remove-Item -LiteralPath $buildLock -Force
        }
    }
    exit 0

}
