#!/usr/bin/env pwsh

# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# i2pd (C++) backend for the I2P router abstraction (PowerShell port).

Set-StrictMode -Version Latest

$script:BACKEND_NAME = 'i2pd'
$script:BACKEND_PRETTY = 'i2pd (C++)'
$script:BACKEND_DIR = Join-Path $script:I2PD_BROWSER_ROOT 'i2pd'
$script:BACKEND_CONSOLE_PORT = '7070'
$script:BACKEND_PID_FILE = Join-Path $script:BACKEND_DIR '.router.pid'

function script:Get-I2pdVendorDir { return (Join-Path (Get-RouterVendorDir) 'i2pd') }

function script:Get-I2pdVendorBin {
    return (Join-Path (Get-I2pdVendorDir) 'i2pd.exe')
}

function script:Get-I2pdVendorVersion {
    $file = Join-Path (Get-I2pdVendorDir) 'VERSION'
    if (Test-Path $file) { return (Get-Content $file -Raw).Trim() }
    return ''
}

function script:Get-I2pdVendorIsInstalled {
    return (Test-Path (Get-I2pdVendorBin))
}

function script:Get-I2pdSystemPath {
    $command = Get-Command 'i2pd' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'i2pd\i2pd.exe')
        (Join-Path $env:LOCALAPPDATA 'i2pd\i2pd.exe')
        (Join-Path $env:USERPROFILE 'i2pd\i2pd.exe')
    )
    # ProgramFiles(x86) only exists on 64-bit Windows.
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'i2pd\i2pd.exe')
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return $null
}

function script:Get-I2pdPath {
    if ((Get-RouterSource) -eq 'vendored') {
        if (Get-I2pdVendorIsInstalled) { return (Get-I2pdVendorBin) }
        return $null
    }
    return (Get-I2pdSystemPath)
}

function script:Get-BackendIsInstalled {
    return [bool](Get-I2pdPath)
}

function script:Get-BackendIsMisconfigured { return $false }

function script:Get-BackendIsRunning {
    if (Get-RouterManagedProcess) { return $true }
    return [bool](Get-Process -Name 'i2pd' -ErrorAction SilentlyContinue)
}

function script:Get-BackendIsManaged {
    return [bool](Get-RouterManagedProcess)
}

function script:Get-BackendExecutable {
    return (Get-I2pdPath)
}

function script:Get-BackendConsoleUrl {
    return "http://127.0.0.1:$script:BACKEND_CONSOLE_PORT/"
}

function script:Get-BackendConfigProxyPort {
    param([string]$Section)
    $current = ''
    $values = @()
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $script:BACKEND_DIR 'i2pd.conf'))) {
        if ($line -match '^\s*\[([^]]+)\]\s*$') { $current = $Matches[1] }
        if ($current -eq $Section -and $line -match '^\s*port\s*=\s*(.*?)\s*$') { $values += $Matches[1] }
    }
    if ($values.Count -ne 1) { throw 'Invalid proxy configuration' }
    return $values[0]
}

function script:Test-BackendConfig {
    $file = Join-Path $script:BACKEND_DIR 'i2pd.conf'
    $values = @{}
    $section = ''
    try {
        foreach ($line in [IO.File]::ReadAllLines($file)) {
            if ($line -match '^\s*\[([^]]+)\]\s*$') { $section = $Matches[1]; continue }
            if ($section -in @('http', 'httpproxy', 'socksproxy', 'sam') -and
                $line -match '^\s*(address|port)\s*=\s*(.*?)\s*$') {
                $key = "$section.$($Matches[1])"
                if ($values.ContainsKey($key)) { return $false }
                $values[$key] = $Matches[2]
            }
        }
        foreach ($section in @('http', 'httpproxy', 'socksproxy', 'sam')) {
            if ($values["$section.address"] -ne '127.0.0.1' -or
                -not (Test-RouterProxyEndpoint '127.0.0.1' $values["$section.port"])) {
                return $false
            }
        }
        if (-not ($script:ROUTER_HTTP_PROXY_HOST_OVERRIDE -or $script:ROUTER_HTTP_PROXY_PORT_OVERRIDE) -and
            $values['httpproxy.port'] -ne (Get-RouterHttpProxyPort)) { return $false }
        if (-not ($script:ROUTER_SOCKS_PROXY_HOST_OVERRIDE -or $script:ROUTER_SOCKS_PROXY_PORT_OVERRIDE) -and
            $values['socksproxy.port'] -ne (Get-RouterSocksProxyPort)) { return $false }
        return $true
    }
    catch {
        Write-RouterError (Get-I18nMessage 'error.effective-config' @($file))
        return $false
    }
}

function script:Initialize-BackendConfig {
    $conf = Join-Path $script:BACKEND_DIR 'i2pd.conf'
    if (-not (Test-Path $conf)) {
        Write-RouterError "i2pd configuration not found: $conf"
        return $false
    }

    return $true
}

function script:Get-BackendDependencyHint {
    return @'
i2pd (C++) was not found.
Install it with winget:
  winget install PurpleI2P.i2pd
Or let I2Pd Browser download a managed build (latest stable):
  ./install.ps1 configure --i2p-router=i2pd --router-source=vendored
See https://i2pd.readthedocs.io for details.
'@
}

function script:Install-BackendDependencies {
    if (Test-RouterCommand 'winget') {
        & winget install --id PurpleI2P.i2pd --accept-source-agreements `
            --accept-package-agreements
        return ($LASTEXITCODE -eq 0)
    }
    Write-RouterWarn 'winget was not found; install i2pd manually.'
    return $false
}

function script:Get-I2pdVendorAssetName {
    param([string]$Version)
    switch (Get-RouterArch) {
        'x86_64' { return "i2pd_${Version}_win64_mingw.zip" }
        'i386' { return "i2pd_${Version}_win32_mingw.zip" }
        default { return $null }
    }
}

# Validate the release asset against its SHA-512 manifest before extracting
# it into the managed vendor directory.
function script:Install-BackendVendor {
    $version = Get-RouterLatestGithubRelease -Repo 'PurpleI2P/i2pd'
    if (-not $version) { return $false }

    $asset = Get-I2pdVendorAssetName -Version $version
    if (-not $asset) {
        Write-RouterError (
            'No vendored i2pd build for ' + (Get-RouterOs) + '/' +
            (Get-RouterArch) + '.'
        )
        return $false
    }

    $url = 'https://github.com/PurpleI2P/i2pd/releases/download'
    $url += "/$version/$asset"
    $dir = Get-I2pdVendorDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) `
        ("i2pd-vendor-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $archive = Join-Path $tmp $asset

    Write-RouterLog "Downloading i2pd $version ($asset)"
    if (-not (Invoke-RouterDownload -Url $url -Destination $archive)) {
        Remove-Item -Recurse -Force $tmp
        return $false
    }

    $sums = Join-Path $tmp 'SHA512SUMS'
    $sumsUrl = ($url -replace '/[^/]+$', '') + '/SHA512SUMS'
    if (-not (Invoke-RouterDownload -Url $sumsUrl -Destination $sums)) {
        Remove-Item -Recurse -Force $tmp
        Write-RouterError 'Could not download the i2pd SHA512SUMS.'
        return $false
    }
    if (-not (Test-RouterSha512 -File $archive -Sums $sums -Name $asset)) {
        Remove-Item -Recurse -Force $tmp
        return $false
    }

    Write-RouterLog "Extracting i2pd $version"
    $root = Join-Path $tmp 'root'
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    if (-not (Expand-RouterZip -Archive $archive -Destination $root)) {
        Remove-Item -Recurse -Force $tmp
        return $false
    }

    $exe = Get-ChildItem -Path $root -Recurse -Filter 'i2pd.exe' |
        Select-Object -First 1
    if (-not $exe) {
        Remove-Item -Recurse -Force $tmp
        Write-RouterError "i2pd.exe was not found in $asset."
        return $false
    }

    Copy-Item $exe.FullName (Get-I2pdVendorBin) -Force
    Set-Content -Path (Join-Path $dir 'VERSION') -Value $version -Encoding ascii
    Remove-Item -Recurse -Force $tmp

    Write-RouterLog "Vendored i2pd $version installed in $dir"
    return $true
}

# Start with the tracked i2pd configuration directory as the router data root;
# relative configuration paths and runtime state are resolved from this folder.
function script:Start-Backend {
    $binary = Get-I2pdPath
    if (-not $binary) {
        Write-RouterError 'i2pd was not found.'
        return $false
    }

    Write-RouterLog "Starting i2pd with binary: $binary"
    $arguments = @(('--datadir="' + $script:BACKEND_DIR + '"'))
    if ($script:ROUTER_HTTP_PROXY_HOST_OVERRIDE -or
        $script:ROUTER_HTTP_PROXY_PORT_OVERRIDE) {
        $arguments += "--httpproxy.address=$(Get-RouterHttpProxyHost)"
        $arguments += "--httpproxy.port=$(Get-RouterHttpProxyPort)"
    }
    if ($script:ROUTER_SOCKS_PROXY_HOST_OVERRIDE -or
        $script:ROUTER_SOCKS_PROXY_PORT_OVERRIDE) {
        $arguments += "--socksproxy.address=$(Get-RouterSocksProxyHost)"
        $arguments += "--socksproxy.port=$(Get-RouterSocksProxyPort)"
    }
    $process = Start-Process -FilePath $binary `
        -ArgumentList $arguments `
        -WorkingDirectory $script:BACKEND_DIR `
        -WindowStyle Hidden -PassThru
    if (-not (Save-RouterProcessIdentity $process)) {
        # This handle was created by this invocation; never leave it orphaned.
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit(30000) | Out-Null }
        Write-RouterError (Get-I18nMessage 'error.router-identity')
        return $false
    }
    return $true
}

function script:Stop-Backend {
    return (Stop-RouterManagedProcess)
}
