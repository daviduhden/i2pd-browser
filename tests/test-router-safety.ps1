# Offline regression tests with backend doubles: no processes or listeners.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'i2pd-router-safety-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporaryRoot)
try {
    $env:I2PD_BROWSER_CONF = Join-Path $temporaryRoot 'selection.conf'
    $env:ROUTER_HTTP_PROXY_HOST = '127.0.0.1'
    $env:ROUTER_HTTP_PROXY_PORT = '4444'
    $env:ROUTER_SOCKS_PROXY_HOST = '127.0.0.1'
    $env:ROUTER_SOCKS_PROXY_PORT = '4447'
    $script:I2PD_BROWSER_ROOT = $root
    . (Join-Path $root 'lib/router.ps1')
    $original = "CUSTOM_SETTING=preserved`nI2P_ROUTER=i2pd`n"
    [IO.File]::WriteAllText($env:I2PD_BROWSER_CONF, $original)
    if (Set-RouterConf -Name unknown -Source system -Language en-US) {
        throw 'Invalid backend selection persisted.'
    }
    if ([IO.File]::ReadAllText($env:I2PD_BROWSER_CONF) -cne $original) {
        throw 'Invalid backend modified stored configuration.'
    }
    if (-not (Set-RouterConf -Name i2p-java -Source vendored -Language es-ES)) {
        throw 'Valid backend selection rejected.'
    }
    if ((Get-RouterConf) -cne 'i2p-java' -or
        (Get-RouterConfSource) -cne 'vendored' -or
        -not [IO.File]::ReadAllText($env:I2PD_BROWSER_CONF).Contains('CUSTOM_SETTING=preserved')) {
        throw 'Stored selection or unrelated configuration was lost.'
    }

    $script:BackendWrites = 0
    function Initialize-BackendConfig { $script:BackendWrites++; return $true }
    function Test-BackendConfig { return $false }
    function Get-BackendIsRunning { return $true }
    function Get-BackendIsManaged { return $false }
    function Start-Backend { $script:BackendWrites++; return $true }
    function Stop-Backend { $script:BackendWrites++; return $true }

    foreach ($invalidPort in @('0', '65536', '-1', '999999999999999999999999', '4444x')) {
        $script:ROUTER_HTTP_PROXY_PORT = $invalidPort
        if (Invoke-RouterPrepareConfig) { throw 'Invalid proxy reached backend preparation.' }
        if ($script:BackendWrites -ne 0) { throw 'Invalid proxy modified backend configuration.' }
    }
    $script:ROUTER_HTTP_PROXY_PORT = '4444'
    $script:ROUTER_SOCKS_PROXY_HOST = '0.0.0.0'
    if (Invoke-RouterPrepareConfig) { throw 'Non-loopback SOCKS endpoint accepted.' }
    if ($script:BackendWrites -ne 0) { throw 'Invalid SOCKS endpoint modified configuration.' }
    $script:ROUTER_SOCKS_PROXY_HOST = '127.0.0.1'
    if (Start-Router) { throw 'Unsafe effective backend configuration accepted.' }
    if (Stop-Router) { throw 'Unmanaged router stop succeeded.' }
    if ($script:BackendWrites -ne 0) { throw 'Unsafe lifecycle command reached backend.' }
    Write-Host 'PowerShell router safety behavior tests passed.'
}
finally { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
