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

$script:ProxyTimeout = 90
if ($env:PROXY_TIMEOUT) { $script:ProxyTimeout = [int]$env:PROXY_TIMEOUT }

$script:Subcommand = 'install'
$script:OptionRouter = ''
$script:OptionSource = ''
$script:NonInteractive = $false
$script:NoBrowser = $false
$script:InstallDeps = $false
$script:NoStart = $false

function Show-Usage {
    @'
Usage: install.ps1 [COMMAND] [OPTIONS]

Commands:
  install      Select the I2P router and prepare the browser (default).
  configure    Change the selected I2P router.
  start        Start the selected I2P router.
  stop         Stop the router started by I2Pd Browser.
  restart      Restart the router started by I2Pd Browser.
  status       Show the selected router and its state.
  console      Open the router console of the selected backend.
  detect       List the detected I2P router backends.

Options:
  --i2p-router=NAME     Select the backend: i2pd or i2p-java.
  --router-source=SRC   Use the system install (system) or a managed
                        copy downloaded by I2Pd Browser (vendored).
  --non-interactive     Never prompt; use the stored or default values.
  --no-browser          Do not build the Firefox ESR bundle.
  --no-start            Do not start the router after install/configure.
  --install-deps        Install missing router packages automatically.
  -h, --help            Show this help.
'@
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
            '^(-h|--help)$' { Show-Usage; exit 0 }
            default {
                Write-RouterError "Unknown argument: $argument"
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
    if ($script:NonInteractive -or -not [Environment]::UserInteractive) {
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
    if ($script:NonInteractive -or -not [Environment]::UserInteractive) {
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
        Write-RouterError 'Automatic dependency installation failed.'
    }

    Write-RouterError "Install $script:ROUTER_BACKEND_PRETTY and run the installer again, or pass --install-deps or --router-source=vendored."
    return $false
}

function Build-BrowserIfNeeded {
    $firefox = Join-Path $script:I2PD_BROWSER_ROOT 'browser/firefox.exe'
    if (Test-Path $firefox) {
        Write-RouterLog 'The Firefox ESR bundle is already built.'
        return $true
    }
    Write-RouterLog 'Building the Firefox ESR bundle...'
    & (Join-Path $script:I2PD_BROWSER_ROOT 'build/build.ps1')
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
    $config = Get-Content $policies -Raw | ConvertFrom-Json
    $got = $config.policies.Proxy.HTTPProxy
    if ($got -and $got -ne $expected) {
        Write-RouterWarn "The Firefox proxy ($got) does not match the selected router proxy ($expected); rebuild the browser."
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
    Write-Host "Router      : $script:ROUTER_BACKEND_PRETTY"
    Write-Host "Backend id  : $script:ROUTER_BACKEND"
    Write-Host "Source      : $(Get-RouterSource)"
    Write-Host "HTTP proxy  : $(Get-RouterHttpProxy)"
    Write-Host "SOCKS proxy : $(Get-RouterSocksProxy)"
    Write-Host "Console     : $(Get-RouterConsoleUrl)"
    Write-Host ''
    Write-Host 'Run start-i2pd-browser.ps1 to launch Firefox.'
}

function Invoke-Install {
    $backend = Select-BackendName -Requested $script:OptionRouter
    if (-not $backend) { exit 1 }
    $source = Select-SourceName -Requested $script:OptionSource
    if (-not $source) { exit 1 }

    if (-not (Set-RouterConf -Name $backend -Source $source)) { exit 1 }
    if (-not (Import-RouterBackend $backend)) { exit 1 }

    Write-RouterLog "Selected router: $script:ROUTER_BACKEND_PRETTY ($source)"

    if (-not (Confirm-BackendAvailable)) { exit 1 }
    if (-not (Invoke-RouterPrepareConfig)) { exit 1 }

    if (-not $script:NoBrowser) {
        if (-not (Build-BrowserIfNeeded)) { exit 1 }
    }

    Test-BrowserProxy | Out-Null
    if (-not (Wait-ProxyOrWarn)) { exit 1 }
    Show-Summary
}

function Invoke-Configure {
    $backend = $script:OptionRouter
    $source = $script:OptionSource
    $current = Get-RouterConf
    $currentSource = Get-RouterConfSource

    if (-not $backend -and $current) { $backend = $current }
    if (-not $backend) { $backend = $script:I2P_ROUTER_DEFAULT }
    if (-not (Assert-RouterBackend $backend)) { exit 1 }

    if (-not $source -and $currentSource) { $source = $currentSource }
    if (-not $source) { $source = $script:I2P_ROUTER_SOURCE_DEFAULT }
    if (-not (Assert-RouterSource $source)) { exit 1 }

    if ($current -and $current -ne $backend -and (Test-RouterBackend $current)) {
        Write-RouterLog "Switching from $(Get-RouterBackendPretty $current) to $(Get-RouterBackendPretty $backend)."
        if (Import-RouterBackend $current) {
            if (Test-RouterRunning) {
                if (Test-RouterManaged) {
                    if (-not (Stop-Router)) { exit 1 }
                }
                else {
                    Write-RouterWarn "$(Get-RouterBackendPretty $current) is running but is not managed; leaving it running."
                }
            }
        }
    }

    if (-not (Set-RouterConf -Name $backend -Source $source)) { exit 1 }
    $script:ROUTER_SOURCE = $source
    if (-not (Import-RouterBackend $backend)) { exit 1 }
    Write-RouterLog "Selected router: $script:ROUTER_BACKEND_PRETTY ($source)"

    if (-not (Confirm-BackendAvailable)) { exit 1 }
    if (-not (Invoke-RouterPrepareConfig)) { exit 1 }
    Test-BrowserProxy | Out-Null
    if (-not (Wait-ProxyOrWarn)) { exit 1 }
    Show-Summary
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
    Write-Host "Router      : $script:ROUTER_BACKEND_PRETTY"
    Write-Host "Backend id  : $script:ROUTER_BACKEND"
    Write-Host "Source      : $(Get-RouterSource)"
    Write-Host "State       : $(Get-RouterState)"
    Write-Host "HTTP proxy  : $(Get-RouterHttpProxy)"
    Write-Host "SOCKS proxy : $(Get-RouterSocksProxy)"
    Write-Host "Console     : $(Get-RouterConsoleUrl)"
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
            Write-Host ('{0,-9} {1}' -f $name, 'unavailable')
        }
    }
}

Import-Args -Arguments $args
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
