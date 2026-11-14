# Exercises the production policy helper using isolated, offline fixtures.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $root 'lib/browser-policy.ps1')
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'i2pd-browser-policy-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporaryRoot)
try {
    $source = Join-Path $root 'build/preferences/distribution/policies.json'
    $output = Join-Path $temporaryRoot 'policies.json'
    $unsafe = Join-Path $temporaryRoot 'unsafe.json'
    $endpoint = '127.0.0.1:15444'
    Write-BrowserProxyPolicy -InputPath $source -OutputPath $output -Endpoint $endpoint
    if (-not (Test-BrowserProxyPolicy -Path $output -Endpoint $endpoint)) {
        throw 'Generated policy does not preserve privacy controls.'
    }
    $original = [IO.File]::ReadAllText($output)
    foreach ($invalid in @('127.0.0.1:0', '127.0.0.1:65536', '127.0.0.1:-1',
            '127.0.0.1:4444x', 'localhost:4444', '0.0.0.0:4444', 'example.com:4444')) {
        $rejected = $false
        try {
            Write-BrowserProxyPolicy -InputPath $source -OutputPath $output -Endpoint $invalid
        }
        catch { $rejected = $true }
        if (-not $rejected) { throw "Invalid endpoint accepted: $invalid" }
        if ([IO.File]::ReadAllText($output) -cne $original) {
            throw 'Rejected endpoint modified an existing policy.'
        }
    }

    $mutations = @(
        { param($data) $data.policies.Proxy.Locked = $false },
        { param($data) $data.policies.Proxy.Mode = 'system' },
        { param($data) $data.policies.Proxy.UseProxyForDNS = $false },
        { param($data) $data.policies.Proxy.Passthrough = 'localhost' },
        { param($data) $data.policies.PSObject.Properties.Remove('Proxy') },
        { param($data) $data.policies.DNSOverHTTPS.Enabled = $true },
        { param($data) $data.policies.DisableTelemetry = $false },
        { param($data) $data.policies.DisableAppUpdate = $false },
        { param($data) $data.policies.Proxy.Locked = 'true' }
    )
    foreach ($mutation in $mutations) {
        $data = [IO.File]::ReadAllText($source) | ConvertFrom-Json
        & $mutation $data
        [IO.File]::WriteAllText($unsafe, ($data | ConvertTo-Json -Depth 100))
        $rejected = $false
        try {
            Write-BrowserProxyPolicy -InputPath $unsafe -OutputPath $output -Endpoint $endpoint
        }
        catch { $rejected = $true }
        if (-not $rejected) { throw 'Unsafe privacy policy accepted.' }
        if ([IO.File]::ReadAllText($output) -cne $original) {
            throw 'Rejected policy modified an existing policy.'
        }
    }
    [IO.File]::WriteAllText($unsafe, '{invalid JSON')
    $rejected = $false
    try {
        Write-BrowserProxyPolicy -InputPath $unsafe -OutputPath $output -Endpoint $endpoint
    }
    catch { $rejected = $true }
    if (-not $rejected -or [IO.File]::ReadAllText($output) -cne $original) {
        throw 'Malformed JSON was published or modified the previous policy.'
    }
    foreach ($portNumber in @(1, 65535)) {
        $boundaryEndpoint = "127.0.0.1:$portNumber"
        Write-BrowserProxyPolicy -InputPath $source -OutputPath $output -Endpoint $boundaryEndpoint
        if (-not (Test-BrowserProxyPolicy -Path $output -Endpoint $boundaryEndpoint)) {
            throw "Valid port boundary rejected: $portNumber"
        }
    }
    if (@(Get-ChildItem -LiteralPath $temporaryRoot -Filter '*.tmp.*').Count -ne 0) {
        throw 'Failed generation leaked a temporary policy.'
    }
    Write-Host 'PowerShell proxy policy behavior tests passed.'
}
finally { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
