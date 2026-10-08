# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# I2P (Java) backend for the I2P router abstraction (PowerShell port).
#
# The router is started directly with an isolated configuration
# directory, mirroring the way i2pd is started with a data directory.

Set-StrictMode -Version Latest

$script:BACKEND_NAME = 'i2p-java'
$script:BACKEND_PRETTY = 'I2P (Java)'
$script:BACKEND_DIR = Join-Path $script:I2PD_BROWSER_ROOT 'i2p-java'
$script:BACKEND_CONFIG_DIR = Join-Path $script:BACKEND_DIR 'config'
$script:BACKEND_DATA_DIR = Join-Path $script:BACKEND_DIR 'data'
$script:BACKEND_CONSOLE_PORT = '7657'
$script:BACKEND_PID_FILE = Join-Path $script:BACKEND_DIR '.router.pid'

function Get-I2pJavaVendorDir {
    return (Join-Path (Get-RouterVendorDir) 'i2p-java')
}

function Get-I2pJavaVendorHome {
    return (Join-Path (Get-I2pJavaVendorDir) 'i2p')
}

function Get-I2pJavaVendorVersion {
    $file = Join-Path (Get-I2pJavaVendorDir) 'VERSION'
    if (Test-Path $file) { return (Get-Content $file -Raw).Trim() }
    return ''
}

function Test-I2pJavaIsHome {
    param([string]$Path)
    if (-not $Path) { return $false }
    $lib = Join-Path $Path 'lib'
    if (-not (Test-Path $lib)) { return $false }
    return [bool](Get-ChildItem -Path $lib -Filter '*.jar' `
            -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-I2pJavaVendorIsInstalled {
    return (Test-I2pJavaIsHome (Get-I2pJavaVendorHome))
}

function Get-I2pJavaSystemHome {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'I2P')
        (Join-Path $env:APPDATA 'I2P')
        (Join-Path $env:ProgramFiles 'i2p')
        (Join-Path ${env:ProgramFiles(x86)} 'i2p')
        (Join-Path $env:ProgramData 'i2p')
        (Join-Path $env:USERPROFILE 'i2p')
    )
    if ($env:I2P_HOME) { $candidates = @($env:I2P_HOME) + $candidates }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-I2pJavaIsHome $candidate)) {
            return $candidate
        }
    }
    return $null
}

function Get-I2pJavaHome {
    if ((Get-RouterSource) -eq 'vendored') {
        if (Get-I2pJavaVendorIsInstalled) { return (Get-I2pJavaVendorHome) }
        return $null
    }
    return (Get-I2pJavaSystemHome)
}

function Get-I2pJavaExecutable {
    if ($env:JAVA_HOME) {
        $candidate = Join-Path $env:JAVA_HOME 'bin\java.exe'
        if (Test-Path $candidate) { return $candidate }
    }
    $command = Get-Command 'java' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function Get-BackendIsInstalled {
    return [bool](Get-I2pJavaHome)
}

function Get-BackendIsMisconfigured {
    if (-not (Get-I2pJavaHome)) { return $false }
    return (-not (Get-I2pJavaExecutable))
}

function Get-I2pJavaProcess {
    $pidFile = $script:BACKEND_PID_FILE
    if (Test-Path $pidFile) {
        $pidValue = (Get-Content $pidFile -Raw).Trim()
        if ($pidValue) {
            $process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
            if ($process) { return $process }
        }
    }
    try {
        $processes = Get-CimInstance Win32_Process -Filter "Name='java.exe'"
        foreach ($process in $processes) {
            if ($process.CommandLine -match 'net\.i2p\.router\.Router') {
                return $process
            }
        }
    }
    catch {
        return $null
    }
    return $null
}

function Get-BackendIsRunning {
    return [bool](Get-I2pJavaProcess)
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

function Get-BackendDependencyHint {
    return @'
I2P (Java) was not found, or no Java runtime is available.
Install a Java runtime and the I2P router with winget:
  winget install Microsoft.OpenJDK.21
  winget install I2P.I2P
Or let I2Pd Browser download the latest stable release from i2p.net:
  ./install.ps1 configure --i2p-router=i2p-java --router-source=vendored
'@
}

function Install-BackendDependencies {
    if (Test-RouterCommand 'winget') {
        & winget install --id Microsoft.OpenJDK.21 `
            --accept-source-agreements --accept-package-agreements
        & winget install --id I2P.I2P `
            --accept-source-agreements --accept-package-agreements
        return ($LASTEXITCODE -eq 0)
    }
    Write-RouterWarn 'winget was not found; install Java and I2P manually.'
    return $false
}

function Initialize-BackendConfig {
    $src = $script:BACKEND_CONFIG_DIR
    $dst = $script:BACKEND_DATA_DIR

    if (-not (Test-Path $src)) {
        Write-RouterError "I2P (Java) configuration not found: $src"
        return $false
    }

    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    foreach ($file in Get-ChildItem -Path $src -Recurse -File) {
        $relative = $file.FullName.Substring($src.Length).TrimStart('\', '/')
        $target = Join-Path $dst $relative
        $targetDir = Split-Path -Parent $target
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        if (-not (Test-Path $target)) {
            Copy-Item $file.FullName $target
        }
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $dst 'addressbook') `
        | Out-Null
    return $true
}

function Get-I2pJavaLatestVersion {
    try {
        $page = Invoke-WebRequest -Uri 'https://geti2p.net/en/download' `
            -UseBasicParsing
    }
    catch {
        Write-RouterError 'Could not query https://geti2p.net/en/download'
        return $null
    }
    $matches = [regex]::Matches(
        $page.Content, 'i2pinstall_([0-9]+\.[0-9]+\.[0-9]+)\.jar'
    )
    $versions = $matches | ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
    if (-not $versions) { return $null }
    return ($versions | Sort-Object { [version]$_ } | Select-Object -Last 1)
}

function Get-I2pJavaInstallerUrl {
    param([string]$Version)
    return "https://files.i2p-projekt.de/$Version/i2pinstall_$Version.jar"
}

function Install-BackendVendor {
    $version = Get-I2pJavaLatestVersion
    if (-not $version) {
        Write-RouterError 'Could not determine the latest I2P release.'
        return $false
    }
    $java = Get-I2pJavaExecutable
    if (-not $java) {
        Write-RouterError 'A Java runtime is required to install I2P.'
        return $false
    }

    $url = Get-I2pJavaInstallerUrl -Version $version
    $dir = Get-I2pJavaVendorDir
    $home = Get-I2pJavaVendorHome
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    New-Item -ItemType Directory -Force -Path $home | Out-Null

    $installer = Join-Path $dir "i2pinstall_$version.jar"
    Write-RouterLog "Downloading I2P (Java) $version"
    if (-not (Invoke-RouterDownload -Url $url -Destination $installer)) {
        return $false
    }

    Write-RouterLog 'Running the I2P installer (console mode).'
    Write-RouterLog "Install into: $home"
    & $java -jar $installer -console
    if ($LASTEXITCODE -ne 0) {
        Write-RouterError 'The I2P installer did not complete.'
        return $false
    }

    if (-not (Get-I2pJavaVendorIsInstalled)) {
        Write-RouterError "No I2P installation found in $home."
        return $false
    }

    Set-Content -Path (Join-Path $dir 'VERSION') -Value $version `
        -Encoding ascii
    Write-RouterLog "Vendored I2P (Java) $version installed in $home"
    return $true
}

function Get-BackendClasspath {
    param([string]$Home)
    $jars = Get-ChildItem -Path (Join-Path $Home 'lib') -Filter '*.jar'
    return (($jars | ForEach-Object { $_.FullName }) -join ';')
}

function Start-Backend {
    $home = Get-I2pJavaHome
    if (-not $home) {
        Write-RouterError 'I2P (Java) installation not found.'
        return $false
    }
    $java = Get-I2pJavaExecutable
    if (-not $java) {
        Write-RouterError "A Java runtime is required but 'java' was not found."
        return $false
    }

    if (-not (Initialize-BackendConfig)) { return $false }

    $classpath = Get-BackendClasspath -Home $home
    if (-not $classpath) {
        Write-RouterError "No I2P libraries found in $home\lib."
        return $false
    }

    $dataDir = $script:BACKEND_DATA_DIR
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

    Write-RouterLog "Starting I2P (Java) with: $java"
    $arguments = @(
        '-Djava.awt.headless=true'
        "-Di2p.dir.base=$home"
        "-Di2p.dir.config=$dataDir"
        "-Djava.library.path=$home;$home\lib"
        '-Djava.net.preferIPv4Stack=false'
        '-DloggerFilenameOverride=logs/log-router-@.txt'
        '-cp', $classpath
        'net.i2p.router.RouterLaunch'
    )
    $process = Start-Process -FilePath $java -ArgumentList $arguments `
        -WorkingDirectory $script:BACKEND_DIR -WindowStyle Hidden -PassThru
    Set-Content -Path $script:BACKEND_PID_FILE -Value $process.Id `
        -Encoding ascii
    return $true
}

function Stop-Backend {
    if (-not (Test-Path $script:BACKEND_PID_FILE)) {
        Write-RouterWarn 'No managed I2P (Java) PID file was found.'
        return $false
    }
    $pidValue = (Get-Content $script:BACKEND_PID_FILE -Raw).Trim()
    Write-RouterLog 'Stopping the managed I2P (Java) process.'
    if ($pidValue) {
        Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Force $script:BACKEND_PID_FILE -ErrorAction SilentlyContinue
    return $true
}
