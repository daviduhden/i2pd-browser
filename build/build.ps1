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

$script:Language = if ($env:language) { $env:language } else { 'en-US' }
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

function Resolve-FirefoxDownload {
    $os = Get-FirefoxOs
    $url = 'https://download.mozilla.org/?product=' + $script:EsrProduct +
    "&os=$os&lang=$script:Language"
    Write-BuildLog "Resolving latest Firefox ESR for $os, language: $script:Language"
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing
    }
    catch {
        Stop-Build 'Failed to query the redirector.'
    }
    $final = $response.BaseResponse.ResponseUri.AbsoluteUri
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
        [string]$FileName
    )
    try {
        $sums = Invoke-WebRequest -Uri "$ReleaseUrl/SHA512SUMS" `
            -UseBasicParsing
    }
    catch {
        Write-BuildWarn 'SHA512SUMS is not available for this platform.'
        return ''
    }
    $pattern = '^([0-9a-fA-F]{128})\s+(.*' +
    [regex]::Escape($FileName) + ')$'
    foreach ($line in ($sums.Content -split "`n")) {
        if ($line -match $pattern) {
            return $Matches[1]
        }
    }
    Write-BuildWarn "No checksum entry found for $FileName."
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

    Write-BuildLog "Downloading Firefox $Version"
    Invoke-WebRequest -Uri $Url -OutFile $installer -UseBasicParsing

    # SHA512SUMS lives at the release root, not in the platform
    # language directory that contains the installer.
    $releaseUrl = [regex]::Match(
        $Url, '^(.*/releases/[^/]+)/'
    ).Groups[1].Value
    if (-not $releaseUrl) { $releaseUrl = ($Url -replace '/[^/]+$', '') }
    $expected = Get-ExpectedChecksum -ReleaseUrl $releaseUrl `
        -FileName $fileName
    if ($expected) {
        $actual = (Get-FileHash -Path $installer -Algorithm SHA512).Hash
        if ($actual -ne $expected.ToUpperInvariant()) {
            Stop-Build 'Checksum verification failed.'
        }
        Write-BuildLog 'Checksum correct.'
    }

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
    Write-BuildLog 'Removing unnecessary files'
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
    Write-BuildLog 'Updating configuration files'
    $ini = Join-Path $script:BrowserDir 'application.ini'
    if (Test-Path $ini) {
        (Get-Content $ini) `
            -replace 'Enabled=1', 'Enabled=0' `
            -replace 'ServerURL=.*', 'ServerURL=-' |
            Set-Content $ini
    }
}

function Install-NoScript {
    Write-BuildLog 'Downloading the NoScript extension'
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
    Write-BuildLog 'Formatting distribution policy JSON'
    $data = Get-Content $policies -Raw | ConvertFrom-Json
    $data | ConvertTo-Json -Depth 100 | Set-Content $policies -Encoding utf8
}

function Copy-StandardConfigs {
    Write-BuildLog 'Adding standard configs'
    Copy-Item -Recurse -Force `
        (Join-Path $script:BuildDir 'preferences\*') $script:BrowserDir
    Copy-Item -Recurse -Force `
        (Join-Path $script:BuildDir 'profile\*') `
        (Join-Path $script:BrowserDir 'data')
}

function Copy-LaunchScripts {
    Write-BuildLog 'Copying launch scripts'
    Copy-Item -Recurse -Force `
        (Join-Path $script:BuildDir 'scripts\*') $script:BrowserDir
}

function Main {
    $url = Resolve-FirefoxDownload
    $version = Get-FirefoxVersion -Url $url
    Write-BuildLog "Preparing Firefox version $version for use with I2Pd"
    Install-Firefox -Url $url -Version $version
    Remove-UnneededFiles
    Update-Configs
    Install-NoScript
    Copy-StandardConfigs
    Format-PoliciesJson
    Copy-LaunchScripts
    Write-BuildLog 'Build completed'
}

# Router helpers used above are defined in lib/router.ps1.
. (Join-Path $script:RepoRoot 'lib/router.ps1')

Main
