# Shared by the Windows builder and offline policy regression tests.
function Test-BrowserPolicyEndpoint {
    param([string]$Endpoint)
    if ($Endpoint -cnotmatch '\A127\.0\.0\.1:([0-9]{1,5})\z') { return $false }
    $portNumber = [int]$Matches[1]
    return ($portNumber -ge 1 -and $portNumber -le 65535)
}

function Test-BrowserProxyPolicy {
    param([string]$Path, [string]$Endpoint)
    if (-not (Test-BrowserPolicyEndpoint $Endpoint)) { return $false }
    try {
        $data = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        $proxy = $data.policies.Proxy
        return ($proxy.Mode -is [string] -and $proxy.Mode -ceq 'manual' -and
            $proxy.Locked -is [bool] -and
            $proxy.Locked -eq $true -and
            $proxy.HTTPProxy -is [string] -and $proxy.HTTPProxy -ceq $Endpoint -and
            $proxy.SSLProxy -is [string] -and $proxy.SSLProxy -ceq $Endpoint -and
            $proxy.UseProxyForDNS -is [bool] -and $proxy.UseProxyForDNS -eq $true -and
            $proxy.Passthrough -is [string] -and $proxy.Passthrough -ceq '' -and
            $data.policies.DNSOverHTTPS.Enabled -is [bool] -and
            $data.policies.DNSOverHTTPS.Enabled -eq $false -and
            $data.policies.DNSOverHTTPS.Locked -is [bool] -and
            $data.policies.DNSOverHTTPS.Locked -eq $true -and
            $data.policies.DisableTelemetry -is [bool] -and
            $data.policies.DisableTelemetry -eq $true -and
            $data.policies.DisableAppUpdate -is [bool] -and
            $data.policies.DisableAppUpdate -eq $true)
    }
    catch { return $false }
}

function Write-BrowserProxyPolicy {
    param([string]$InputPath, [string]$OutputPath, [string]$Endpoint)
    if (-not (Test-BrowserPolicyEndpoint $Endpoint)) {
        throw 'Invalid loopback browser proxy endpoint.'
    }
    $temporary = $OutputPath + '.tmp.' + [Guid]::NewGuid().ToString('N')
    try {
        $data = [IO.File]::ReadAllText($InputPath) | ConvertFrom-Json
        $data.policies.Proxy.HTTPProxy = $Endpoint
        $data.policies.Proxy.SSLProxy = $Endpoint
        [IO.File]::WriteAllText($temporary, ($data | ConvertTo-Json -Depth 100),
            [Text.UTF8Encoding]::new($false))
        if (-not (Test-BrowserProxyPolicy -Path $temporary -Endpoint $Endpoint)) {
            throw 'Browser proxy policy validation failed.'
        }
        if ([IO.File]::Exists($OutputPath)) {
            [IO.File]::Replace($temporary, $OutputPath,
                [System.Management.Automation.Language.NullString]::Value)
        }
        else { [IO.File]::Move($temporary, $OutputPath) }
    }
    finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}
