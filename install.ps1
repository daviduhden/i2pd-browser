#!/usr/bin/env pwsh

# See the LICENSE file at the top of the project tree for copyright
# and license details.
#
# I2Pd Browser installer and router manager (PowerShell port).
#
# It selects and persists the I2P router backend and source, prepares
# the configuration and provides simple lifecycle commands.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:InstallDir = (
    Resolve-Path (Split-Path -Parent $PSCommandPath)
).Path
. (Join-Path $script:InstallDir 'lib/router.ps1')
. (Join-Path $script:InstallDir 'lib/browser-policy.ps1')

$script:ProxyTimeout = 90
if ($env:PROXY_TIMEOUT) { $script:ProxyTimeout = [int]$env:PROXY_TIMEOUT }

$script:Subcommand = 'install'
$script:OptionRouter = ''
$script:OptionSource = ''
$script:OptionLanguage = ''
$script:NonInteractive = $false
$script:NoBrowser = $false
$script:InstallDeps = $false
$script:NoStart = $false
$script:ShowHelp = $false

function Show-Usage {
    Get-I18nMessage 'usage.header' @('./install.ps1') | Write-Host
    Get-I18nMessage 'usage.commands' | Write-Host
    Get-I18nMessage 'usage.options' | Write-Host
}

function Select-Language {
    param([string]$Requested)
    if ($Requested) { return (ConvertTo-I2pdBrowserLocale $Requested) }
    if ((Get-I2pdBrowserStoredLocale) -or $env:I2PD_BROWSER_LANGUAGE -or
        $env:language -or $script:NonInteractive -or
        -not (Test-RouterInteractive)) {
        return (Select-I2pdBrowserLocale)
    }
    Get-I18nMessage 'prompt.language' | Write-Host
    $reply = Read-Host
    switch ($reply) {
        '' { return 'en-US' }
        '1' { return 'en-US' }
        'en-US' { return 'en-US' }
        '2' { return 'es-ES' }
        'es-ES' { return 'es-ES' }
        '3' { return 'ru' }
        'ru' { return 'ru' }
        '4' { return 'zh-CN' }
        'zh-CN' { return 'zh-CN' }
        default { return $null }
    }
}

function Import-Args {
    param([string[]]$Arguments)
    $index = 0
    while ($index -lt $Arguments.Count) {
        $argument = $Arguments[$index]
        switch -Regex ($argument) {
            '^(install|configure|start|stop|restart|status|console|detect)$' {
                $script:Subcommand = $argument
                $index++
            }
            '^--i2p-router=(.*)$' {
                $script:OptionRouter = $Matches[1]
                $index++
            }
            '^--language=(.*)$' {
                $script:OptionLanguage = $Matches[1]
                $index++
            }
            '^--language$' {
                if ($index + 1 -ge $Arguments.Count) {
                    Write-RouterError (Get-I18nMessage 'error.argument-value' @('--language'))
                    exit 2
                }
                $script:OptionLanguage = $Arguments[$index + 1]
                $index += 2
            }
            '^--i2p-router$' {
                if ($index + 1 -ge $Arguments.Count) {
                    Write-RouterError '--i2p-router requires a value.'
                    exit 2
                }

                $script:OptionRouter = $Arguments[$index + 1]
                $index += 2
            }
            '^--router-source=(.*)$' {
                $script:OptionSource = $Matches[1]
                $index++
            }
            '^--router-source$' {
                if ($index + 1 -ge $Arguments.Count) {
                    Write-RouterError '--router-source requires a value.'
                    exit 2
                }
                $script:OptionSource = $Arguments[$index + 1]
                $index += 2
            }
            '^--non-interactive$' { $script:NonInteractive = $true; $index++ }
            '^--no-browser$' { $script:NoBrowser = $true; $index++ }
            '^--no-start$' { $script:NoStart = $true; $index++ }
            '^--install-deps$' { $script:InstallDeps = $true; $index++ }
            '^--no-install-deps$' { $script:InstallDeps = $false; $index++ }
            '^(-h|--help)$' { $script:ShowHelp = $true; $index++ }
            default {
                Write-RouterError (Get-I18nMessage 'error.unknown-argument' @($argument))
                Show-Usage
                exit 2
            }
        }
    }
}

function Select-BackendName {
    param([string]$Requested)
    if ($Requested) {
        if (-not (Assert-RouterBackend $Requested)) { return $null }
        return $Requested
    }
    $existing = Get-RouterConf
    if ($existing -and (Test-RouterBackend $existing)) { return $existing }
    if ($script:NonInteractive -or -not (Test-RouterInteractive)) {
        return $script:I2P_ROUTER_DEFAULT
    }
    return (Select-RouterInteractive)
}

function Select-SourceName {
    param([string]$Requested)
    if ($Requested) {
        if (-not (Assert-RouterSource $Requested)) { return $null }
        return $Requested
    }
    $existing = Get-RouterConfSource
    if ($existing -and (Test-RouterSource $existing)) { return $existing }
    if ($script:NonInteractive -or -not (Test-RouterInteractive)) {
        return $script:I2P_ROUTER_SOURCE_DEFAULT
    }
    return (Select-RouterSourceInteractive)
}

function Confirm-BackendAvailable {
    if ((Get-RouterSource) -eq 'vendored') {
        if (Test-RouterInstalled) {
            if (Test-RouterMisconfigured) {
                Write-RouterWarn "$script:ROUTER_BACKEND_PRETTY is installed but a runtime dependency is missing."
            }
            return $true
        }
        Write-RouterLog "Installing the vendored $script:ROUTER_BACKEND_PRETTY build..."
        if ((Install-RouterVendor) -and (Test-RouterInstalled)) {
            if (Test-RouterMisconfigured) {
                Write-RouterWarn "$script:ROUTER_BACKEND_PRETTY is installed but a runtime dependency is missing."
            }
            return $true
        }
        Write-RouterError "Could not install the vendored $script:ROUTER_BACKEND_PRETTY build."
        return $false
    }

    if ((Test-RouterInstalled) -and -not (Test-RouterMisconfigured)) {
        return $true
    }

    Write-RouterWarn "$script:ROUTER_BACKEND_PRETTY is not available on this system."
    Get-RouterDependencyHint | Write-Host

    if ($script:InstallDeps) {
        Write-RouterLog 'Attempting to install the required packages...'
        if ((Install-RouterDependencies) -and (Test-RouterInstalled) -and
            -not (Test-RouterMisconfigured)) {
            return $true
        }
        Write-RouterError "Install $script:ROUTER_BACKEND_PRETTY manually, or pass --router-source=vendored."
    }
    else {
        Write-RouterError "Install $script:ROUTER_BACKEND_PRETTY and run the installer again, or pass --install-deps or --router-source=vendored."
    }
    return $false
}

function Test-BuildInputsNewer {
    $marker = Join-Path $script:I2PD_BROWSER_ROOT `
        'browser/.i2pd-browser-locale'
    if (-not (Test-Path $marker)) { return $false }

    $paths = @(
        (Join-Path $script:I2PD_BROWSER_ROOT 'build/preferences')
        (Join-Path $script:I2PD_BROWSER_ROOT 'build/profile')
        (Join-Path $script:I2PD_BROWSER_ROOT 'build/scripts')
        (Join-Path $script:I2PD_BROWSER_ROOT 'build/build.bash')
        (Join-Path $script:I2PD_BROWSER_ROOT 'build/build.ps1')
        (Join-Path $script:I2PD_BROWSER_ROOT 'lib/i18n.bash')
        (Join-Path $script:I2PD_BROWSER_ROOT 'lib/i18n.ps1')
        (Join-Path $script:I2PD_BROWSER_ROOT 'locales')
    )
    $markerTime = (Get-Item $marker).LastWriteTime
    foreach ($path in $paths) {
        if (-not (Test-Path $path)) { continue }
        $files = if (Test-Path $path -PathType Container) {
            Get-ChildItem -Path $path -Recurse -File
        }
        else { Get-Item $path }
        if ($files | Where-Object { $_.LastWriteTime -gt $markerTime } |
            Select-Object -First 1) {
            return $true
        }
    }
    return $false
}

function Build-BrowserIfNeeded {
    $firefox = Join-Path $script:I2PD_BROWSER_ROOT 'browser/firefox.exe'
    $localeFile = Join-Path $script:I2PD_BROWSER_ROOT 'browser/.i2pd-browser-locale'
    $policies = Join-Path $script:I2PD_BROWSER_ROOT 'browser/distribution/policies.json'
    $expectedProxy = Get-RouterHttpProxy
    if ((Test-Path $firefox) -and (Test-Path $localeFile) -and
        ((Get-Content $localeFile -Raw).Trim() -eq
            $script:I2pdBrowserLanguage) -and (Test-Path $policies)) {
        try {
            $currentPolicy = Get-Content $policies -Raw | ConvertFrom-Json
        }
        catch {
            $currentPolicy = $null
        }
        if ($currentPolicy -and
            $currentPolicy.policies.Proxy.HTTPProxy -eq $expectedProxy -and
            $currentPolicy.policies.Proxy.SSLProxy -eq $expectedProxy -and
            (Test-BrowserProxyPolicy -Path $policies -Endpoint $expectedProxy)) {
        Write-RouterLog 'The Firefox ESR bundle is already built.'
        if (Test-BuildInputsNewer) {
            Write-RouterWarn (Get-I18nMessage 'warn.build-inputs-newer')
        }
        return $true
        }
        Write-RouterLog 'The existing Firefox proxy policy does not match the selected router endpoint; rebuilding.'
    }
    Write-RouterLog 'Building the Firefox ESR bundle...'
    & (Join-Path $script:I2PD_BROWSER_ROOT 'build/build.ps1') `
        "--language=$script:I2pdBrowserLanguage"
    return ($LASTEXITCODE -eq 0)
}

function Test-BrowserProxy {
    $policies = Join-Path $script:I2PD_BROWSER_ROOT `
        'browser/distribution/policies.json'
    $expected = Get-RouterHttpProxy
    if (-not (Test-Path $policies)) {
        Write-RouterWarn 'No built browser configuration to validate.'
        return $true
    }
    if (-not (Test-BrowserProxyPolicy -Path $policies -Endpoint $expected)) {
        Write-RouterError (Get-I18nMessage 'error.effective-config' @($policies))
        return $false
    }
    Write-RouterLog "Firefox proxy endpoint: $expected"
    return $true
}

function Wait-ProxyOrWarn {
    if ($script:NoStart) { return $true }
    if (-not (Start-Router)) { return $false }
    if (Wait-RouterProxy -TimeoutSeconds $script:ProxyTimeout) {
        Write-RouterLog "The I2P HTTP proxy is reachable at $(Get-RouterHttpProxy)."
    }
    else {
        Write-RouterWarn "The I2P HTTP proxy did not become reachable within $script:ProxyTimeout seconds; it may still be starting."
    }
    return $true
}

function Show-Summary {
    Write-Host ''
    Get-I18nMessage 'status.language' @($script:I2pdBrowserLanguage) | Write-Host
    Get-I18nMessage 'status.router' @($script:ROUTER_BACKEND_PRETTY) | Write-Host
    Get-I18nMessage 'status.backend' @($script:ROUTER_BACKEND) | Write-Host
    Get-I18nMessage 'status.source' @(Get-RouterSource) | Write-Host
    Get-I18nMessage 'status.http-proxy' @(Get-RouterHttpProxy) | Write-Host
    Get-I18nMessage 'status.socks-proxy' @(Get-RouterSocksProxy) | Write-Host
    Get-I18nMessage 'status.console' @(Get-RouterConsoleUrl) | Write-Host
    Write-Host ''
    Get-I18nMessage 'launcher.run' @('browser/start-i2pd-browser.ps1') | Write-Host
}

function Invoke-Install {
    $locale = Select-Language -Requested $script:OptionLanguage
    if (-not $locale) {
        Write-RouterError (Get-I18nMessage 'language.invalid' @($script:OptionLanguage))
        exit 2
    }
    [void](Initialize-I2pdBrowserI18n $locale)
    $backend = Select-BackendName -Requested $script:OptionRouter
    if (-not $backend) { exit 1 }
    $source = Select-SourceName -Requested $script:OptionSource
    if (-not $source) { exit 1 }

    # Do not persist a new selection until the requested backend is
    # actually available and its configuration can be prepared.
    $script:ROUTER_SOURCE = $source
    if (-not (Import-RouterBackend $backend)) { exit 1 }
    if (-not (Assert-RouterProxySettings)) { exit 1 }
    if (-not (Confirm-BackendAvailable)) { exit 1 }
    if (-not (Invoke-RouterPrepareConfig)) { exit 1 }
    if (-not (Set-RouterConf -Name $backend -Source $source -Language $locale)) { exit 1 }

    Write-RouterLog "Selected router: $script:ROUTER_BACKEND_PRETTY ($source)"

    if (-not $script:NoBrowser) {
        if (-not (Build-BrowserIfNeeded)) { exit 1 }
    }

    if (-not (Test-BrowserProxy)) { exit 1 }
    if (-not (Wait-ProxyOrWarn)) { exit 1 }
    Show-Summary
}

function Start-ConfiguredRouter {
    param([bool]$AllowExternal = $false)
    if ($script:NoStart) { return $true }
    if (-not (Start-Router) -or -not (Wait-RouterProxy -TimeoutSeconds $script:ProxyTimeout) -or
        (-not $AllowExternal -and -not (Test-RouterManaged))) {
        Write-RouterError (Get-I18nMessage 'error.effective-config' @((Get-RouterHttpProxy)))
        return $false
    }
    return $true
}

function Restore-BrowserAfterConfigure {
    $backup = Join-Path $script:I2PD_BROWSER_ROOT '.browser-old'
    $browser = Join-Path $script:I2PD_BROWSER_ROOT 'browser'
    $failed = Join-Path $script:I2PD_BROWSER_ROOT '.browser-switch-failed'
    if (-not (Test-Path -LiteralPath $backup)) { return $true }
    foreach ($name in @('lock', '.parentlock', 'parent.lock')) {
        if (Get-Item -LiteralPath (Join-Path $browser "data/$name") -Force -ErrorAction SilentlyContinue) {
            Write-RouterError (Get-I18nMessage 'error.effective-config' @($backup))
            return $false
        }
    }
    if (Test-Path -LiteralPath $failed) { return $false }
    try {
        if (Test-Path -LiteralPath $browser) { [IO.Directory]::Move($browser, $failed) }
        [IO.Directory]::Move($backup, $browser)
        return $true
    }
    catch { return $false }
}

function Invoke-Configure {
    $lock = Join-Path $script:I2PD_BROWSER_ROOT '.browser-switch.lock'
    $stream = $null
    try {
        $stream = [IO.File]::Open($lock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    }
    catch {
        Write-RouterError (Get-I18nMessage 'error.effective-config' @($lock))
        exit 1
    }
    try {
        $buildLock = Join-Path $script:I2PD_BROWSER_ROOT '.browser-build.lock'
        if (Get-Item -LiteralPath $buildLock -Force -ErrorAction SilentlyContinue) {
            Write-RouterError (Get-I18nMessage 'error.effective-config' @($buildLock))
            exit 1
        }
        Invoke-ConfigureTransaction
    }
    finally {
        $stream.Dispose()
        Remove-Item -LiteralPath $lock -Force
    }
}

function Invoke-ConfigureTransaction {
    foreach ($path in @('.browser-old', '.browser-switch-failed')) {
        $existing = Join-Path $script:I2PD_BROWSER_ROOT $path
        if (Get-Item -LiteralPath $existing -Force -ErrorAction SilentlyContinue) {
            Write-RouterError (Get-I18nMessage 'error.effective-config' @($existing))
            exit 1
        }
    }
    $current = Get-RouterConf
    if (-not $current) { $current = $script:I2P_ROUTER_DEFAULT }
    $currentSource = Get-RouterConfSource
    if (-not $currentSource) { $currentSource = $script:I2P_ROUTER_SOURCE_DEFAULT }
    $oldLanguage = Get-I2pdBrowserStoredLocale
    if (-not $oldLanguage) { $oldLanguage = $script:I2pdBrowserLanguage }
    $backend = if ($script:OptionRouter) { $script:OptionRouter } elseif ($current) { $current } else { $script:I2P_ROUTER_DEFAULT }
    $source = if ($script:OptionSource) { $script:OptionSource } else { $currentSource }
    if (-not (Assert-RouterBackend $backend) -or -not (Assert-RouterSource $source)) { exit 1 }
    $locale = Select-I2pdBrowserLocale $script:OptionLanguage
    if (-not $locale) { exit 2 }
    $wasRunning = $false
    $allowExternal = $false
    $mustStop = $false
    $stopped = $false
    $snapshot = ''
    $oldHttpPort = '4444'
    $oldSocksPort = '4447'
    if ($current -and (Test-RouterBackend $current)) {
        $script:ROUTER_SOURCE = $currentSource
        if (-not (Import-RouterBackend $current)) { exit 1 }
        if (Test-RouterRunning) {
            $wasRunning = $true
            $oldHttpPort = Get-BackendConfigProxyPort 'httpproxy'
            $oldSocksPort = Get-BackendConfigProxyPort 'socksproxy'
            if ($current -ne $backend -or $currentSource -ne $source -or
                $script:ROUTER_HTTP_PROXY_HOST_OVERRIDE -or $script:ROUTER_HTTP_PROXY_PORT_OVERRIDE -or
                $script:ROUTER_SOCKS_PROXY_HOST_OVERRIDE -or $script:ROUTER_SOCKS_PROXY_PORT_OVERRIDE) {
                if (-not (Test-RouterManaged)) {
                    Write-RouterError (Get-I18nMessage 'error.router-conflict')
                    exit 1
                }
                $mustStop = $true
            }
        }
    }
    $script:ROUTER_SOURCE = $source
    if (-not (Import-RouterBackend $backend) -or -not (Assert-RouterProxySettings) -or
        -not (Confirm-BackendAvailable)) { exit 1 }
    if ((Test-RouterRunning) -and -not (Test-RouterManaged)) {
        if ($current -eq $backend -and $currentSource -eq $source -and
            -not ($script:ROUTER_HTTP_PROXY_HOST_OVERRIDE -or $script:ROUTER_HTTP_PROXY_PORT_OVERRIDE -or
                $script:ROUTER_SOCKS_PROXY_HOST_OVERRIDE -or $script:ROUTER_SOCKS_PROXY_PORT_OVERRIDE)) {
            $allowExternal = $true
        }
        else {
            Write-RouterError (Get-I18nMessage 'error.router-conflict')
            exit 1
        }
    }
    [void](Initialize-I2pdBrowserI18n $locale)
    # Download and validate the bundle before disturbing the current router.
    $built = $true
    $previousKeepBackup = $env:I2PD_BROWSER_KEEP_BACKUP
    $previousConfigureBuild = $env:I2PD_BROWSER_CONFIGURE_BUILD
    try {
        $env:I2PD_BROWSER_KEEP_BACKUP = '1'
        $env:I2PD_BROWSER_CONFIGURE_BUILD = '1'
        if (-not $script:NoBrowser) { $built = Build-BrowserIfNeeded }
    }
    catch { $built = $false }
    finally {
        $env:I2PD_BROWSER_KEEP_BACKUP = $previousKeepBackup
        $env:I2PD_BROWSER_CONFIGURE_BUILD = $previousConfigureBuild
    }
    if (-not $built -or -not (Test-BrowserProxy)) {
        [void](Restore-BrowserAfterConfigure)
        exit 1
    }
    if ($mustStop) {
        $script:ROUTER_SOURCE = $currentSource
        if (-not (Import-RouterBackend $current) -or -not (Stop-Router)) {
            [void](Restore-BrowserAfterConfigure)
            exit 1
        }
        $stopped = $true
    }
    $script:ROUTER_SOURCE = $source
    $success = $false
    try {
        if (-not (Import-RouterBackend $backend)) { throw 'Backend import failed' }
        $snapshot = Save-RouterConfigSnapshot
        $success = (Invoke-RouterPrepareConfig) -and (Start-ConfiguredRouter -AllowExternal $allowExternal) -and
            (Set-RouterConf -Name $backend -Source $source -Language $locale)
    }
    catch { $success = $false }
    if ($success) {
        if ($snapshot) { Remove-Item -LiteralPath $snapshot -Recurse -Force }
        $backup = Join-Path $script:I2PD_BROWSER_ROOT '.browser-old'
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
        Write-RouterLog (Get-I18nMessage 'status.selected-router' @($script:ROUTER_BACKEND_PRETTY, $source))
        Show-Summary
        return
    }
    if ($stopped -or -not $wasRunning) {
        if ((Test-RouterRunning) -and (Test-RouterManaged)) {
            if (-not (Stop-Router)) {
                Write-RouterError (Get-I18nMessage 'error.configure-rollback')
                exit 1
            }
        }
    }
    if (-not (Restore-BrowserAfterConfigure) -or -not (Restore-RouterConfigSnapshot $snapshot)) {
        Write-RouterError (Get-I18nMessage 'error.configure-rollback')
        exit 1
    }
    if ($stopped) {
        $script:ROUTER_SOURCE = $currentSource
        if (-not (Import-RouterBackend $current)) { exit 1 }
        [void](Initialize-I2pdBrowserI18n $oldLanguage)
        $script:ROUTER_HTTP_PROXY_HOST_OVERRIDE = $false
        $script:ROUTER_HTTP_PROXY_PORT_OVERRIDE = $false
        $script:ROUTER_SOCKS_PROXY_HOST_OVERRIDE = $false
        $script:ROUTER_SOCKS_PROXY_PORT_OVERRIDE = $false
        $script:ROUTER_HTTP_PROXY_HOST = '127.0.0.1'
        $script:ROUTER_SOCKS_PROXY_HOST = '127.0.0.1'
        $script:ROUTER_HTTP_PROXY_PORT = $oldHttpPort
        $script:ROUTER_SOCKS_PROXY_PORT = $oldSocksPort
        if (-not (Start-Router)) {
            Write-RouterError (Get-I18nMessage 'error.configure-rollback')
            exit 1
        }
    }
    Write-RouterWarn (Get-I18nMessage 'info.configure-restored')
    exit 1
}

function Import-BackendForCommand {
    if ($script:OptionSource) {
        if (-not (Assert-RouterSource $script:OptionSource)) { return $false }
        $script:ROUTER_SOURCE = $script:OptionSource
    }
    if ($script:OptionRouter) {
        if (-not (Assert-RouterBackend $script:OptionRouter)) { return $false }
        return (Import-RouterBackend $script:OptionRouter)
    }
    return (Import-ConfiguredRouterBackend)
}

function Invoke-StartCommand {
    if (-not (Import-BackendForCommand)) { exit 1 }
    Write-RouterLog "Selected router: $script:ROUTER_BACKEND_PRETTY"
    if (-not (Start-Router)) { exit 1 }
}

function Invoke-StopCommand {
    if (-not (Import-BackendForCommand)) { exit 1 }
    if (-not (Stop-Router)) { exit 1 }
}

function Invoke-RestartCommand {
    if (-not (Import-BackendForCommand)) { exit 1 }
    if (-not (Restart-Router)) { exit 1 }
}

function Invoke-StatusCommand {
    if (-not (Import-BackendForCommand)) { exit 1 }
    Get-I18nMessage 'status.language' @($script:I2pdBrowserLanguage) | Write-Host
    Get-I18nMessage 'status.router' @($script:ROUTER_BACKEND_PRETTY) | Write-Host
    Get-I18nMessage 'status.backend' @($script:ROUTER_BACKEND) | Write-Host
    Get-I18nMessage 'status.source' @(Get-RouterSource) | Write-Host
    Get-I18nMessage 'status.state' @(Get-RouterState) | Write-Host
    Get-I18nMessage 'status.http-proxy' @(Get-RouterHttpProxy) | Write-Host
    Get-I18nMessage 'status.socks-proxy' @(Get-RouterSocksProxy) | Write-Host
    Get-I18nMessage 'status.console' @(Get-RouterConsoleUrl) | Write-Host
}

function Invoke-ConsoleCommand {
    if (-not (Import-BackendForCommand)) { exit 1 }
    $url = Get-RouterConsoleUrl
    Start-Process $url
}

function Invoke-DetectCommand {
    foreach ($name in $script:I2P_ROUTER_CHOICES) {
        if (Import-RouterBackend $name) {
            Write-Host ('{0,-9} {1,-14} {2}' -f `
                    $name, (Get-RouterState), (Get-RouterConsoleUrl))
        }
        else {
            Write-Host ('{0,-9} {1}' -f $name, (Get-I18nMessage 'state.unavailable'))
        }
    }
}

Import-Args -Arguments $args
$script:ROUTER_NON_INTERACTIVE = $script:NonInteractive
if ($script:ShowHelp) {
    # Show help in the requested language when it is valid, but never
    # reject --help because of a bad --language value.
    if ($script:OptionLanguage) {
        [void](Initialize-I2pdBrowserI18n $script:OptionLanguage)
    }
    Show-Usage
    exit 0
}
if ($script:OptionLanguage) {
    if (-not (Initialize-I2pdBrowserI18n $script:OptionLanguage)) {
        Write-RouterError (
            Get-I18nMessage 'language.invalid' @($script:OptionLanguage)
        )
        exit 2
    }
}
switch ($script:Subcommand) {
    'install' { Invoke-Install }
    'configure' { Invoke-Configure }
    'start' { Invoke-StartCommand }
    'stop' { Invoke-StopCommand }
    'restart' { Invoke-RestartCommand }
    'status' { Invoke-StatusCommand }
    'console' { Invoke-ConsoleCommand }
    'detect' { Invoke-DetectCommand }
    default {
        Write-RouterError "Unknown command: $script:Subcommand"
        exit 2
    }
}
