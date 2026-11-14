#!/usr/bin/env pwsh

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

function script:Get-I2pJavaVendorDir {
    return (Join-Path (Get-RouterVendorDir) 'i2p-java')
}

function script:Get-I2pJavaVendorHome {
    return (Join-Path (Get-I2pJavaVendorDir) 'i2p')
}

function script:Get-I2pJavaVendorVersion {
    $file = Join-Path (Get-I2pJavaVendorDir) 'VERSION'
    if (Test-Path $file) { return (Get-Content $file -Raw).Trim() }
    return ''
}

function script:Test-I2pJavaIsHome {
    param([string]$Path)
    if (-not $Path) { return $false }
    $lib = Join-Path $Path 'lib'
    if (-not (Test-Path $lib)) { return $false }
    return [bool](Get-ChildItem -Path $lib -Filter '*.jar' `
            -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function script:Get-I2pJavaVendorIsInstalled {
    return (Test-I2pJavaIsHome (Get-I2pJavaVendorHome))
}

function script:Get-I2pJavaSystemHome {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'I2P')
        (Join-Path $env:APPDATA 'I2P')
        (Join-Path $env:ProgramFiles 'i2p')
        (Join-Path $env:ProgramData 'i2p')
        (Join-Path $env:USERPROFILE 'i2p')
    )
    # ProgramFiles(x86) only exists on 64-bit Windows.
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'i2p')
    }
    if ($env:I2P_HOME) { $candidates = @($env:I2P_HOME) + $candidates }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-I2pJavaIsHome $candidate)) {
            return $candidate
        }
    }
    return $null
}

function script:Get-I2pJavaHome {
    if ((Get-RouterSource) -eq 'vendored') {
        if (Get-I2pJavaVendorIsInstalled) { return (Get-I2pJavaVendorHome) }
        return $null
    }
    return (Get-I2pJavaSystemHome)
}

function script:Get-I2pJavaExecutable {
    if ($env:JAVA_HOME) {
        $candidate = Join-Path $env:JAVA_HOME 'bin\java.exe'
        if (Test-Path $candidate) { return $candidate }
    }
    $command = Get-Command 'java' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function script:Get-BackendIsInstalled {
    return [bool](Get-I2pJavaHome)
}

function script:Get-BackendIsMisconfigured {
    if (-not (Get-I2pJavaHome)) { return $false }
    return (-not (Get-I2pJavaExecutable))
}

function script:Get-I2pJavaProcess {
    $managed = Get-RouterManagedProcess
    if ($managed) { return $managed }
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

function script:Get-BackendIsRunning {
    return [bool](Get-I2pJavaProcess)
}

function script:Get-BackendIsManaged {
    return [bool](Get-RouterManagedProcess)
}

function script:Get-BackendExecutable {
    return (Get-I2pJavaExecutable)
}

function script:Get-BackendConsoleUrl {
    return "http://127.0.0.1:$script:BACKEND_CONSOLE_PORT/"
}

function script:Get-BackendDependencyHint {
    return @'
I2P (Java) was not found, or no Java runtime is available.
Install a Java runtime and the I2P router with winget:
  winget install Microsoft.OpenJDK.21
  winget install I2P.I2P
Or let I2Pd Browser download the latest stable release from i2p.net:
  ./install.ps1 configure --i2p-router=i2p-java --router-source=vendored
'@
}

function script:Install-BackendDependencies {
    if (Test-RouterCommand 'winget') {
        & winget install --id Microsoft.OpenJDK.21 `
            --accept-source-agreements --accept-package-agreements
        $javaOk = ($LASTEXITCODE -eq 0)
        & winget install --id I2P.I2P `
            --accept-source-agreements --accept-package-agreements
        $i2pOk = ($LASTEXITCODE -eq 0)
        return ($javaOk -and $i2pOk)
    }
    Write-RouterWarn 'winget was not found; install Java and I2P manually.'
    return $false
}

function script:Set-I2pJavaConfigValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $encoding = New-Object Text.UTF8Encoding $hasBom
    $offset = if ($hasBom) { 3 } else { 0 }
    $content = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    $pattern = '(?m)^' + [regex]::Escape($Key) + '=[^\r\n]*'
    if ([regex]::Matches($content, $pattern).Count -ne 1) { return $false }
    $updated = [regex]::Replace($content, $pattern, "$Key=$Value", 1)
    $temporary = "$Path.tmp.$PID"
    try {
        [IO.File]::WriteAllText($temporary, $updated, $encoding)
        [IO.File]::Replace($temporary, $Path,
            [System.Management.Automation.Language.NullString]::Value)
    }
    catch {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        return $false
    }
    return $true
}

# Restrict Java Properties to canonical, unescaped, unique keys. Reject
# continuation syntax so hidden aliases cannot bypass listener validation.
function script:Test-I2pJavaProperties {
    param([string]$Path)
    $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*([#!]|$)') { continue }
        if ($line -cnotmatch '^([A-Za-z0-9_.-]+)=' -or $line.EndsWith('\')) { return $false }
        if (-not $keys.Add($Matches[1])) { return $false }
    }
    return $true
}

function script:Get-I2pJavaConfigValue {
    param([string]$Path, [string]$Key)
    $pattern = '^' + [regex]::Escape($Key) + '=(.*)$'
    $found = @([IO.File]::ReadAllLines($Path) | Where-Object { $_ -cmatch $pattern })
    if ($found.Count -ne 1) { throw "Invalid configuration key: $Key" }
    return $found[0].Substring($Key.Length + 1)
}

function script:Test-I2pJavaConfigDirectory {
    param([string]$Directory)
    try {
        foreach ($file in @('i2ptunnel.config', 'clients.config', 'addressbook/config.txt', 'router.config')) {
            if (-not (Test-I2pJavaProperties (Join-Path $Directory $file))) { return $false }
        }
        $tunnels = Join-Path $Directory 'i2ptunnel.config'
        foreach ($key in @('tunnel.0.interface', 'tunnel.1.interface')) {
            if ((Get-I2pJavaConfigValue $tunnels $key) -ne '127.0.0.1') { return $false }
        }
        foreach ($line in [IO.File]::ReadAllLines($tunnels)) {
            if ($line -match '^tunnel\.[0-9]+\.interface=(.*)$' -and
                $Matches[1] -notin @('127.0.0.1', '::1')) { return $false }
        }
        if ((Get-I2pJavaConfigValue $tunnels 'tunnel.0.listenPort') -ne (Get-RouterHttpProxyPort) -or
            (Get-I2pJavaConfigValue $tunnels 'tunnel.1.listenPort') -ne (Get-RouterSocksProxyPort)) { return $false }
        if ((Get-I2pJavaConfigValue (Join-Path $Directory 'clients.config') 'clientApp.0.args') -ne
            '7657 ::1,127.0.0.1 ./webapps/') { return $false }
        foreach ($entry in @(
            @('addressbook/config.txt', 'proxy_host', 'proxy_port'),
            @('router.config', 'router.updateProxyHost', 'router.updateProxyPort')
        )) {
            $file = Join-Path $Directory $entry[0]
            if ((Get-I2pJavaConfigValue $file $entry[1]) -ne '127.0.0.1' -or
                (Get-I2pJavaConfigValue $file $entry[2]) -ne (Get-RouterHttpProxyPort)) { return $false }
        }
        return $true
    }
    catch { return $false }
}

function script:Get-BackendConfigProxyPort {
    param([string]$Section)
    $directory = $script:BACKEND_CONFIG_DIR
    if (Test-Path $script:BACKEND_DATA_DIR) { $directory = $script:BACKEND_DATA_DIR }
    $key = if ($Section -eq 'httpproxy') { 'tunnel.0.listenPort' } else { 'tunnel.1.listenPort' }
    return (Get-I2pJavaConfigValue (Join-Path $directory 'i2ptunnel.config') $key)
}

function script:Test-BackendConfig {
    $directory = $script:BACKEND_CONFIG_DIR
    if (Test-Path $script:BACKEND_DATA_DIR) { $directory = $script:BACKEND_DATA_DIR }
    if (-not (Test-I2pJavaConfigDirectory $directory)) {
        Write-RouterError (Get-I18nMessage 'error.effective-config' @($directory))
        return $false
    }
    return $true
}

function script:Set-I2pJavaStagedProxyOverrides {
    param([string]$Directory)
    $tunnels = Join-Path $Directory 'i2ptunnel.config'
    if ($script:ROUTER_HTTP_PROXY_HOST_OVERRIDE -or
        $script:ROUTER_HTTP_PROXY_PORT_OVERRIDE) {
        $hostName = Get-RouterHttpProxyHost
        $port = Get-RouterHttpProxyPort
        $addressBook = Join-Path $Directory 'addressbook/config.txt'
        $routerConfig = Join-Path $Directory 'router.config'
        if (-not (Set-I2pJavaConfigValue -Path $tunnels `
                    -Key 'tunnel.0.interface' -Value $hostName)) { return $false }
        if (-not (Set-I2pJavaConfigValue -Path $tunnels `
                    -Key 'tunnel.0.listenPort' -Value $port)) { return $false }
        if (-not (Set-I2pJavaConfigValue -Path $addressBook `
                    -Key 'proxy_host' -Value $hostName)) { return $false }
        if (-not (Set-I2pJavaConfigValue -Path $addressBook `
                    -Key 'proxy_port' -Value $port)) { return $false }
        if (-not (Set-I2pJavaConfigValue -Path $routerConfig `
                    -Key 'router.updateProxyHost' -Value $hostName)) { return $false }
        if (-not (Set-I2pJavaConfigValue -Path $routerConfig `
                    -Key 'router.updateProxyPort' -Value $port)) { return $false }
    }
    if ($script:ROUTER_SOCKS_PROXY_HOST_OVERRIDE -or
        $script:ROUTER_SOCKS_PROXY_PORT_OVERRIDE) {
        if (-not (Set-I2pJavaConfigValue -Path $tunnels `
                    -Key 'tunnel.1.interface' -Value (Get-RouterSocksProxyHost))) {
            return $false
        }
        if (-not (Set-I2pJavaConfigValue -Path $tunnels `
                    -Key 'tunnel.1.listenPort' -Value (Get-RouterSocksProxyPort))) {
            return $false
        }
    }
    return $true
}

# Validate and stage the related files before replacing any effective file.
function script:Set-I2pJavaProxyOverrides {
    if (-not (Assert-RouterProxySettings)) { return $false }
    if (-not ($script:ROUTER_HTTP_PROXY_HOST_OVERRIDE -or $script:ROUTER_HTTP_PROXY_PORT_OVERRIDE -or
            $script:ROUTER_SOCKS_PROXY_HOST_OVERRIDE -or $script:ROUTER_SOCKS_PROXY_PORT_OVERRIDE)) { return $true }
    $stage = Join-Path $script:BACKEND_DATA_DIR ('.proxy-config-' + [guid]::NewGuid().ToString('N'))
    $new = Join-Path $stage 'new'
    $old = Join-Path $stage 'old'
    $files = @('i2ptunnel.config', 'addressbook/config.txt', 'router.config')
    $published = @()
    $keepRecovery = $false
    try {
        foreach ($directory in @($new, $old)) {
            New-Item -ItemType Directory -Path (Join-Path $directory 'addressbook') -Force | Out-Null
        }
        foreach ($file in ($files + @('clients.config'))) {
            Copy-Item -LiteralPath (Join-Path $script:BACKEND_DATA_DIR $file) -Destination (Join-Path $new $file)
        }
        if (-not (Set-I2pJavaStagedProxyOverrides $new) -or -not (Test-I2pJavaConfigDirectory $new)) { return $false }
        foreach ($file in $files) {
            [IO.File]::Replace((Join-Path $new $file), (Join-Path $script:BACKEND_DATA_DIR $file), (Join-Path $old $file))
            $published += $file
        }
        return $true
    }
    catch {
        foreach ($file in $published) {
            try {
                [IO.File]::Replace((Join-Path $old $file), (Join-Path $script:BACKEND_DATA_DIR $file),
                    [System.Management.Automation.Language.NullString]::Value)
            }
            catch {
                Write-RouterError (Get-I18nMessage 'error.effective-config' @($old))
                # Keep the recovery copies when restoration fails.
                $keepRecovery = $true
                return $false
            }
        }
        return $false
    }
    finally {
        if (-not $keepRecovery) {
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Seed only missing files: this is both the initial configuration copy and
# the preservation boundary for existing effective settings and router state.
function script:Initialize-BackendConfig {
    if (-not (Assert-RouterProxySettings)) { return $false }
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
    if (-not (Set-I2pJavaProxyOverrides)) {
        Write-RouterError 'Could not apply proxy overrides to the I2P (Java) configuration.'
        return $false
    }
    return $true
}

function script:Get-I2pJavaLatestVersion {
    try {
        $page = Invoke-WebRequest -Uri 'https://i2p.net/en/downloads/' `
            -UseBasicParsing
    }
    catch {
        Write-RouterError 'Could not query https://i2p.net/en/downloads/'
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

function script:Get-I2pJavaInstallerUrl {
    param([string]$Version)
    return "https://files.i2p.net/$Version/i2pinstall_$Version.jar"
}

function script:Install-BackendVendor {
    $expected = $env:I2P_INSTALLER_SHA512
    if (-not $expected -or $expected -notmatch '^[0-9a-fA-F]{128}$') {
        Write-RouterError (Get-I18nMessage 'error.java-checksum')
        return $false
    }
    $nonInteractive = Get-Variable -Name ROUTER_NON_INTERACTIVE -Scope Script -ErrorAction SilentlyContinue
    if (($nonInteractive -and $nonInteractive.Value) -or -not (Test-RouterInteractive)) {
        Write-RouterError (Get-I18nMessage 'error.java-interactive')
        return $false
    }
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

    # Obtain the expected digest independently from a trusted release source.
    $actual = (Get-FileHash -LiteralPath $installer -Algorithm SHA512).Hash
    if ($actual -ne $expected) {
        Remove-Item -LiteralPath $installer -Force
        Write-RouterError (Get-I18nMessage 'error.java-checksum')
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

function script:Get-BackendClasspath {
    param([string]$Home)
    $jars = Get-ChildItem -Path (Join-Path $Home 'lib') -Filter '*.jar'
    return (($jars | ForEach-Object { $_.FullName }) -join ';')
}

# Pass an absolute isolated config path to Java so the router does not use
# the launching user's global configuration directory.
function script:Start-Backend {
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
    # Quote values that may contain spaces (for example
    # "C:\Program Files\i2p"): Start-Process joins the argument array
    # with spaces without adding quotes itself.
    $arguments = @(
        '-Djava.awt.headless=true'
        ('-Di2p.dir.base="' + $home + '"')
        ('-Di2p.dir.config="' + $dataDir + '"')
        ('-Djava.library.path="' + $home + ';' + $home + '\lib"')
        '-Djava.net.preferIPv4Stack=false'
        '-DloggerFilenameOverride=logs/log-router-@.txt'
        '-cp'
        ('"' + $classpath + '"')
        'net.i2p.router.RouterLaunch'
    )
    $process = Start-Process -FilePath $java -ArgumentList $arguments `
        -WorkingDirectory $script:BACKEND_DIR -WindowStyle Hidden -PassThru
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
