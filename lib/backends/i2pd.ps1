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

function Get-I2pdVendorDir { return (Join-Path (Get-RouterVendorDir) 'i2pd') }

function Get-I2pdVendorBin {
    return (Join-Path (Get-I2pdVendorDir) 'i2pd.exe')
}

function Get-I2pdVendorVersion {
    $file = Join-Path (Get-I2pdVendorDir) 'VERSION'
    if (Test-Path $file) { return (Get-Content $file -Raw).Trim() }
    return ''
}

function Get-I2pdVendorIsInstalled {
    return (Test-Path (Get-I2pdVendorBin))
}

function Get-I2pdSystemPath {
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

function Get-I2pdPath {
    if ((Get-RouterSource) -eq 'vendored') {
        if (Get-I2pdVendorIsInstalled) { return (Get-I2pdVendorBin) }
        return $null
    }
    return (Get-I2pdSystemPath)
}

function Get-BackendIsInstalled {
    return [bool](Get-I2pdPath)
}

function Get-BackendIsMisconfigured { return $false }

function Get-BackendIsRunning {
    if (Test-Path $script:BACKEND_PID_FILE) {
        $pidValue = (Get-Content $script:BACKEND_PID_FILE -Raw).Trim()
        if ($pidValue) {
            $process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
            if ($process) { return $true }
        }
    }
    return [bool](Get-Process -Name 'i2pd' -ErrorAction SilentlyContinue)
}

function Get-BackendIsManaged {
    if (-not (Test-Path $script:BACKEND_PID_FILE)) { return $false }
    $pidValue = (Get-Content $script:BACKEND_PID_FILE -Raw).Trim()
    if (-not $pidValue) { return $false }
    return [bool](Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue)
}

function Get-BackendConsoleUrl {
    return "http://127.0.0.1:$script:BACKEND_CONSOLE_PORT/"
}

function Test-I2pdDefenderExcluded {
    param([string[]]$Path)
    try {
        $preference = Get-MpPreference -ErrorAction Stop
        if ($preference.ExclusionProcess -notcontains 'i2pd.exe') {
            return $false
        }
        foreach ($item in $Path) {
            if ($item -and ($preference.ExclusionPath -notcontains $item)) {
                return $false
            }
        }
        return $true
    }
    catch {
        return $false
    }
}

function Add-I2pdDefenderExclusion {
    # Windows Defender has repeatedly flagged i2pd builds as malware
    # (false positive). Adding exclusions requires administrator rights,
    # so this is best effort and never fatal.
    param([string[]]$Path)

    if (-not (Get-Command 'Add-MpPreference' -ErrorAction SilentlyContinue)) {
        return
    }

    $paths = @($Path | Where-Object { $_ } | Select-Object -Unique)
    if (Test-I2pdDefenderExcluded -Path $paths) { return }

    try {
        Add-MpPreference -ExclusionProcess 'i2pd.exe' -ErrorAction Stop
        foreach ($item in $paths) {
            Add-MpPreference -ExclusionPath $item -ErrorAction Stop
        }
        Write-RouterLog 'Added a Windows Defender exclusion for i2pd.'
    }
    catch {
        Write-RouterWarn 'Could not add a Windows Defender exclusion for i2pd (administrator rights are required).'
    }
}

function Initialize-BackendConfig {
    $conf = Join-Path $script:BACKEND_DIR 'i2pd.conf'
    if (-not (Test-Path $conf)) {
        Write-RouterError "i2pd configuration not found: $conf"
        return $false
    }

    $paths = @($script:BACKEND_DIR)
    $binary = Get-I2pdPath
    if ($binary) { $paths += (Split-Path -Parent $binary) }
    Add-I2pdDefenderExclusion -Path $paths

    return $true
}

function Get-BackendDependencyHint {
    return @'
i2pd (C++) was not found.
Install it with winget:
  winget install PurpleI2P.i2pd
Or let I2Pd Browser download a managed build (latest stable):
  ./install.ps1 configure --i2p-router=i2pd --router-source=vendored
See https://i2pd.readthedocs.io for details.
'@
}

function Install-BackendDependencies {
    if (Test-RouterCommand 'winget') {
        & winget install --id PurpleI2P.i2pd --accept-source-agreements `
            --accept-package-agreements
        return ($LASTEXITCODE -eq 0)
    }
    Write-RouterWarn 'winget was not found; install i2pd manually.'
    return $false
}

function Get-I2pdVendorAssetName {
    param([string]$Version)
    switch (Get-RouterArch) {
        'x86_64' { return "i2pd_${Version}_win64_mingw.zip" }
        'i386' { return "i2pd_${Version}_win32_mingw.zip" }
        default { return $null }
    }
}

function Install-BackendVendor {
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

    # Exclude the vendor directory before extracting so Defender does
    # not quarantine the freshly downloaded binary.
    Add-I2pdDefenderExclusion -Path @($dir)

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

function Start-Backend {
    $binary = Get-I2pdPath
    if (-not $binary) {
        Write-RouterError 'i2pd was not found.'
        return $false
    }

    Write-RouterLog "Starting i2pd with binary: $binary"
    $process = Start-Process -FilePath $binary `
        -ArgumentList '--datadir=.' `
        -WorkingDirectory $script:BACKEND_DIR `
        -WindowStyle Hidden -PassThru
    Set-Content -Path $script:BACKEND_PID_FILE -Value $process.Id `
        -Encoding ascii
    return $true
}

function Stop-Backend {
    if (-not (Test-Path $script:BACKEND_PID_FILE)) {
        Write-RouterWarn 'No managed i2pd PID file was found.'
        return $false
    }
    $pidValue = (Get-Content $script:BACKEND_PID_FILE -Raw).Trim()
    Write-RouterLog 'Stopping the managed i2pd process.'
    if ($pidValue) {
        Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Force $script:BACKEND_PID_FILE -ErrorAction SilentlyContinue
    return $true
}
