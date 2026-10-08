#!/usr/bin/env pwsh

# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# Shared abstraction over the supported I2P router backends
# (PowerShell port of lib/router.bash for Windows).
#
# Backend implementations live in lib/backends/<name>.ps1. Each one
# defines functions with the "Backend" noun plus a few descriptive
# variables. This file contains everything common to all routers.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $script:I2PD_BROWSER_ROOT) {
    $script:I2PD_BROWSER_ROOT = (
        Resolve-Path (Join-Path $PSScriptRoot '..')
    ).Path
}

$script:I2P_ROUTER_DEFAULT = if ($env:I2P_ROUTER_DEFAULT) {
    $env:I2P_ROUTER_DEFAULT
}
else {
    'i2pd'
}
$script:I2P_ROUTER_CHOICES = @('i2pd', 'i2p-java')

$script:I2P_ROUTER_SOURCE_DEFAULT = if ($env:I2P_ROUTER_SOURCE_DEFAULT) {
    $env:I2P_ROUTER_SOURCE_DEFAULT
}
else {
    'system'
}
$script:I2P_ROUTER_SOURCES = @('system', 'vendored')

$script:ROUTER_HTTP_PROXY_HOST = if ($env:ROUTER_HTTP_PROXY_HOST) {
    $env:ROUTER_HTTP_PROXY_HOST
}
else {
    '127.0.0.1'
}
$script:ROUTER_HTTP_PROXY_PORT = if ($env:ROUTER_HTTP_PROXY_PORT) {
    $env:ROUTER_HTTP_PROXY_PORT
}
else {
    '4444'
}
$script:ROUTER_SOCKS_PROXY_HOST = if ($env:ROUTER_SOCKS_PROXY_HOST) {
    $env:ROUTER_SOCKS_PROXY_HOST
}
else {
    '127.0.0.1'
}
$script:ROUTER_SOCKS_PROXY_PORT = if ($env:ROUTER_SOCKS_PROXY_PORT) {
    $env:ROUTER_SOCKS_PROXY_PORT
}
else {
    '4447'
}

$script:ROUTER_SOURCE = ''
$script:ROUTER_BACKEND = ''
$script:ROUTER_BACKEND_PRETTY = ''

# Optional per-backend endpoint overrides. Backends may set these;
# they are initialized here so they are safe under Set-StrictMode.
$script:BACKEND_HTTP_PROXY_HOST = ''
$script:BACKEND_HTTP_PROXY_PORT = ''
$script:BACKEND_SOCKS_PROXY_HOST = ''
$script:BACKEND_SOCKS_PROXY_PORT = ''

function Write-RouterLog {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Text)
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "$stamp [INFO] $($Text -join ' ')"
}

function Write-RouterWarn {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Text)
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "$stamp [WARN] $($Text -join ' ')"
}

function Write-RouterError {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Text)
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    [Console]::Error.WriteLine("$stamp [ERROR] $($Text -join ' ')")
}

# ------------------------------------------------------------------
# Backend and source descriptions
# ------------------------------------------------------------------

function Get-RouterBackendPretty {
    param([string]$Name = '')
    switch ($Name) {
        'i2pd' { return 'i2pd (C++)' }
        'i2p-java' { return 'I2P (Java)' }
        default { return $Name }
    }
}

function Test-RouterBackend {
    param([string]$Name = '')
    return ($script:I2P_ROUTER_CHOICES -contains $Name)
}

function Assert-RouterBackend {
    param([string]$Name = '')
    if (-not $Name) {
        Write-RouterError 'No I2P router backend was specified.'
        return $false
    }
    if (-not (Test-RouterBackend $Name)) {
        Write-RouterError "Unknown I2P router backend: '$Name'."
        Write-RouterError (
            'Valid values: ' + ($script:I2P_ROUTER_CHOICES -join ' ') + '.'
        )
        return $false
    }
    return $true
}

function Test-RouterSource {
    param([string]$Source = '')
    return ($script:I2P_ROUTER_SOURCES -contains $Source)
}

function Assert-RouterSource {
    param([string]$Source = '')
    if (-not (Test-RouterSource $Source)) {
        Write-RouterError "Unknown I2P router source: '$Source'."
        Write-RouterError (
            'Valid values: ' + ($script:I2P_ROUTER_SOURCES -join ' ') + '.'
        )
        return $false
    }
    return $true
}

# ------------------------------------------------------------------
# Persistence
# ------------------------------------------------------------------

function Get-RouterConfFile {
    if ($env:I2PD_BROWSER_CONF) { return $env:I2PD_BROWSER_CONF }
    return (Join-Path $script:I2PD_BROWSER_ROOT 'i2pd-browser.conf')
}

function Get-RouterConfValue {
    param([string]$Key)
    $file = Get-RouterConfFile
    if (-not (Test-Path $file)) { return '' }
    $match = Select-String -Path $file -Pattern "^$Key=(.*)$" |
        Select-Object -Last 1
    if ($match) { return $match.Matches[0].Groups[1].Value.Trim() }
    return ''
}

function Get-RouterConf {
    return (Get-RouterConfValue 'I2P_ROUTER')
}

function Get-RouterConfSource {
    return (Get-RouterConfValue 'I2P_ROUTER_SOURCE')
}

function Set-RouterConf {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Source = ''
    )
    if (-not (Assert-RouterBackend $Name)) { return $false }
    if (-not $Source) { $Source = Get-RouterConfSource }
    if (-not $Source) { $Source = $script:I2P_ROUTER_SOURCE_DEFAULT }
    if (-not (Assert-RouterSource $Source)) { return $false }

    $file = Get-RouterConfFile
    $lines = @(
        '# I2Pd Browser configuration'
        '# Selected I2P router backend and source. Change them with:'
        '#   ./install.ps1 configure --i2p-router=<i2pd|i2p-java>'
        '#   ./install.ps1 configure --router-source=<system|vendored>'
        "I2P_ROUTER=$Name"
        "I2P_ROUTER_SOURCE=$Source"
    )
    Set-Content -Path $file -Value $lines -Encoding ascii
    return $true
}

function Select-RouterInteractive {
    Write-Host ''
    Write-Host 'Select I2P router:'
    Write-Host ''
    Write-Host ('  1) ' + (Get-RouterBackendPretty 'i2pd'))
    Write-Host ('  2) ' + (Get-RouterBackendPretty 'i2p-java'))
    Write-Host ''
    $reply = Read-Host 'Choice [1]'
    if (-not $reply) { $reply = '1' }
    switch ($reply) {
        '1' { return 'i2pd' }
        'i2pd' { return 'i2pd' }
        '2' { return 'i2p-java' }
        'i2p-java' { return 'i2p-java' }
        default {
            Write-RouterError "Invalid selection: '$reply'."
            return $null
        }
    }
}

function Select-RouterSourceInteractive {
    Write-Host ''
    Write-Host 'Select I2P router source:'
    Write-Host ''
    Write-Host '  1) system packages (already installed)'
    Write-Host '  2) vendored (download the latest stable release)'
    Write-Host ''
    $reply = Read-Host 'Choice [1]'
    if (-not $reply) { $reply = '1' }
    switch ($reply) {
        '1' { return 'system' }
        'system' { return 'system' }
        '2' { return 'vendored' }
        'vendored' { return 'vendored' }
        default {
            Write-RouterError "Invalid selection: '$reply'."
            return $null
        }
    }
}

# ------------------------------------------------------------------
# Router source and vendored releases
# ------------------------------------------------------------------

function Get-RouterVendorDir {
    if ($env:I2PD_BROWSER_VENDOR_DIR) {
        return $env:I2PD_BROWSER_VENDOR_DIR
    }
    return (Join-Path $script:I2PD_BROWSER_ROOT 'vendor')
}

# Effective source: an explicit value wins, then the stored value,
# then the default (system).
function Get-RouterSource {
    if ($script:ROUTER_SOURCE -and (Test-RouterSource $script:ROUTER_SOURCE)) {
        return $script:ROUTER_SOURCE
    }
    $stored = Get-RouterConfSource
    if ($stored -and (Test-RouterSource $stored)) { return $stored }
    return $script:I2P_ROUTER_SOURCE_DEFAULT
}

function Test-RouterCommand {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-RouterOs {
    # $IsWindows/$IsLinux/$IsMacOS only exist on PowerShell 6+ and
    # referencing them under Set-StrictMode fails on Windows PowerShell
    # 5.1, which is always Windows.
    if ($PSVersionTable.PSEdition -ne 'Core') { return 'windows' }
    if ($IsWindows) { return 'windows' }
    if ($IsLinux) { return 'linux' }
    if ($IsMacOS) { return 'macos' }
    return 'unknown'
}

function Get-RouterArch {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    switch ($arch.ToString()) {
        'X64' { return 'x86_64' }
        'X86' { return 'i386' }
        'Arm64' { return 'aarch64' }
        'Arm' { return 'armhf' }
        default { return $arch.ToString().ToLowerInvariant() }
    }
}

function Invoke-RouterDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        return $true
    }
    catch {
        Write-RouterError "Could not download $Url"
        return $false
    }
}

function Get-RouterLatestGithubRelease {
    param([Parameter(Mandatory = $true)][string]$Repo)
    try {
        $release = Invoke-RestMethod \
            -Uri "https://api.github.com/repos/$Repo/releases/latest" \
            -Headers @{ 'User-Agent' = 'i2pd-browser' } \
            -UseBasicParsing
    }
    catch {
        Write-RouterError "Could not query the latest release of $Repo."
        return $null
    }
    if (-not $release.tag_name) {
        Write-RouterError "Could not parse the latest release of $Repo."
        return $null
    }
    return $release.tag_name.TrimStart('v')
}

function Expand-RouterZip {
    param(
        [Parameter(Mandatory = $true)][string]$Archive,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    try {
        Expand-Archive -Path $Archive -DestinationPath $Destination -Force
        return $true
    }
    catch {
        Write-RouterError "Could not extract $Archive"
        return $false
    }
}

function Get-RouterExpectedSha512 {
    param(
        [Parameter(Mandatory = $true)][string]$Sums,
        [Parameter(Mandatory = $true)][string]$Name
    )
    foreach ($line in (Get-Content $Sums)) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -lt 2) { continue }
        $file = $parts[1].TrimStart('*')
        if ($file -eq $Name) { return $parts[0] }
    }
    return ''
}

function Test-RouterSha512 {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [Parameter(Mandatory = $true)][string]$Sums,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $expected = Get-RouterExpectedSha512 -Sums $Sums -Name $Name
    if (-not $expected) {
        Write-RouterError "No checksum entry found for $Name"
        return $false
    }
    $actual = (Get-FileHash -Path $File -Algorithm SHA512).Hash
    if ($actual -ne $expected.ToUpperInvariant()) {
        Write-RouterError "Checksum verification failed for $Name"
        return $false
    }
    Write-RouterLog 'Checksum correct.'
    return $true
}

# ------------------------------------------------------------------
# Backend loading and dispatch
# ------------------------------------------------------------------

function Get-RouterBackendsDir {
    if ($env:I2PD_BROWSER_BACKENDS_DIR) {
        return $env:I2PD_BROWSER_BACKENDS_DIR
    }
    return (Join-Path $script:I2PD_BROWSER_ROOT 'lib/backends')
}

function Import-RouterBackend {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Assert-RouterBackend $Name)) { return $false }

    $file = Join-Path (Get-RouterBackendsDir) "$Name.ps1"
    if (-not (Test-Path $file)) {
        Write-RouterError "Backend implementation not found: $file"
        return $false
    }

    . $file

    if (-not (Get-Command 'Get-BackendIsInstalled' -ErrorAction SilentlyContinue)) {
        Write-RouterError (
            "Backend '$Name' does not implement the required interface."
        )
        return $false
    }

    $script:ROUTER_BACKEND = $Name
    $script:ROUTER_BACKEND_PRETTY = Get-RouterBackendPretty $Name
    if (-not $script:ROUTER_SOURCE) {
        $script:ROUTER_SOURCE = Get-RouterSource
    }
    return $true
}

function Import-ConfiguredRouterBackend {
    $name = Get-RouterConf
    if (-not (Test-RouterBackend $name)) {
        $name = $script:I2P_ROUTER_DEFAULT
    }
    return (Import-RouterBackend $name)
}

function Get-RouterHttpProxyHost {
    if ($script:BACKEND_HTTP_PROXY_HOST) {
        return $script:BACKEND_HTTP_PROXY_HOST
    }
    return $script:ROUTER_HTTP_PROXY_HOST
}

function Get-RouterHttpProxyPort {
    if ($script:BACKEND_HTTP_PROXY_PORT) {
        return $script:BACKEND_HTTP_PROXY_PORT
    }
    return $script:ROUTER_HTTP_PROXY_PORT
}

function Get-RouterSocksProxyHost {
    if ($script:BACKEND_SOCKS_PROXY_HOST) {
        return $script:BACKEND_SOCKS_PROXY_HOST
    }
    return $script:ROUTER_SOCKS_PROXY_HOST
}

function Get-RouterSocksProxyPort {
    if ($script:BACKEND_SOCKS_PROXY_PORT) {
        return $script:BACKEND_SOCKS_PROXY_PORT
    }
    return $script:ROUTER_SOCKS_PROXY_PORT
}

function Get-RouterHttpProxy {
    return ((Get-RouterHttpProxyHost) + ':' + (Get-RouterHttpProxyPort))
}

function Get-RouterSocksProxy {
    return ((Get-RouterSocksProxyHost) + ':' + (Get-RouterSocksProxyPort))
}

function Get-RouterConsoleUrl { return (Get-BackendConsoleUrl) }
function Test-RouterInstalled { return (Get-BackendIsInstalled) }
function Test-RouterRunning { return (Get-BackendIsRunning) }
function Test-RouterManaged { return (Get-BackendIsManaged) }
function Test-RouterMisconfigured { return (Get-BackendIsMisconfigured) }
function Invoke-RouterPrepareConfig { return (Initialize-BackendConfig) }
function Get-RouterDependencyHint { return (Get-BackendDependencyHint) }
function Install-RouterDependencies { return (Install-BackendDependencies) }
function Install-RouterVendor { return (Install-BackendVendor) }

function Get-RouterState {
    if (-not (Get-BackendIsInstalled)) { return 'not-installed' }
    if (Get-BackendIsRunning) { return 'running' }
    if (Get-BackendIsMisconfigured) { return 'misconfigured' }
    return 'stopped'
}

function Start-Router {
    if (Get-BackendIsRunning) {
        if (Get-BackendIsManaged) {
            Write-RouterLog 'The I2P router is already running (managed by I2Pd Browser).'
        }
        else {
            Write-RouterLog 'An I2P router instance is already running (not managed by I2Pd Browser).'
        }
        return $true
    }
    if (-not (Get-BackendIsInstalled)) {
        Write-RouterError 'The selected I2P router is not installed.'
        Get-BackendDependencyHint | Write-Host
        return $false
    }
    if (Get-BackendIsMisconfigured) {
        Write-RouterError 'The selected I2P router is not runnable.'
        Get-BackendDependencyHint | Write-Host
        return $false
    }
    return (Start-Backend)
}

function Stop-Router {
    if (-not (Get-BackendIsRunning)) {
        Write-RouterLog 'The I2P router is not running.'
        return $true
    }
    if (-not (Get-BackendIsManaged)) {
        Write-RouterWarn 'The running I2P router was not started by I2Pd Browser; refusing to stop it.'
        Write-RouterWarn "Use the system service or the router's own tooling instead."
        return $false
    }
    return (Stop-Backend)
}

function Restart-Router {
    if (-not (Stop-Router)) { return $false }
    return (Start-Router)
}

# Wait until the HTTP proxy accepts TCP connections. This only checks
# local reachability, never performs any network request.
function Test-RouterPort {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutMs = 1000
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        if ($task.Wait($TimeoutMs)) { return $client.Connected }
        return $false
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Wait-RouterProxy {
    param([int]$TimeoutSeconds = 60)
    $hostName = Get-RouterHttpProxyHost
    $port = [int](Get-RouterHttpProxyPort)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-RouterPort -HostName $hostName -Port $port) {
            return $true
        }
        Start-Sleep -Seconds 1
    }
    return $false
}
