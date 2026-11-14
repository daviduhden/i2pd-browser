# PID identity regression fixtures. Process APIs return in-memory doubles;
# this script never kills, starts or inspects a real router process.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'i2pd-router-identity-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporaryRoot)
try {
    $script:I2PD_BROWSER_ROOT = $root
    $env:I2PD_BROWSER_CONF = Join-Path $temporaryRoot 'selection.conf'
    . (Join-Path $root 'lib/router.ps1')
    $script:BACKEND_DIR = Join-Path $temporaryRoot 'router'
    $script:BACKEND_PID_FILE = Join-Path $temporaryRoot '.router.pid'
    $script:ExpectedExecutable = Join-Path $temporaryRoot 'router.exe'
    $script:NativeCommandLine = '"' + $script:ExpectedExecutable + '" --datadir="' + $script:BACKEND_DIR + '"'
    $script:FakeProcess = [pscustomobject]@{
        Id = 42; Path = $script:ExpectedExecutable
        StartTime = [DateTime]::Parse('2026-01-01T00:00:00Z').ToUniversalTime()
    }
    $script:Killed = $false
    $script:FakeProcess | Add-Member ScriptMethod Kill { $script:Killed = $true }
    $script:FakeProcess | Add-Member ScriptMethod WaitForExit { param($Timeout) return $true }
    function Get-BackendExecutable { return $script:ExpectedExecutable }
    function Get-Process {
        param([int]$Id, [string]$ErrorAction)
        if ($Id -ne 42) { throw 'Unknown fixture PID.' }
        return $script:FakeProcess
    }
    function Get-CimInstance {
        param([string]$ClassName, [string]$Filter, [string]$ErrorAction)
        return [pscustomobject]@{ CommandLine = $script:NativeCommandLine }
    }
    function Write-IdentityFixture {
        param([hashtable]$Changes = @{})
        $identity = @{
            ProcessId = 42
            StartTicks = $script:FakeProcess.StartTime.ToUniversalTime().Ticks.ToString()
            Executable = $script:ExpectedExecutable
            CommandLine = $script:NativeCommandLine
            Root = $script:BACKEND_DIR
        }
        foreach ($key in $Changes.Keys) { $identity[$key] = $Changes[$key] }
        [IO.File]::WriteAllText($script:BACKEND_PID_FILE, ($identity | ConvertTo-Json))
    }

    foreach ($invalid in @(
            @{ProcessId = 43}, @{StartTicks = '1'},
            @{Executable = 'other.exe'}, @{CommandLine = 'other command'},
            @{Root = (Join-Path $temporaryRoot 'another-installation')})) {
        Write-IdentityFixture $invalid
        if ($null -ne (Get-RouterManagedProcess)) { throw 'Unowned or reused PID accepted.' }
        if (Stop-RouterManagedProcess) { throw 'Unowned process was stopped.' }
        if ($script:Killed) { throw 'Rejected identity reached process termination.' }
    }
    foreach ($legacy in @('42', '{invalid JSON')) {
        [IO.File]::WriteAllText($script:BACKEND_PID_FILE, $legacy)
        if ($null -ne (Get-RouterManagedProcess)) { throw 'Legacy or malformed identity accepted.' }
    }
    Write-IdentityFixture
    if ($null -eq (Get-RouterManagedProcess)) { throw 'Valid process identity rejected.' }
    if (-not (Stop-RouterManagedProcess) -or -not $script:Killed) {
        throw 'Verified process did not follow the managed stop path.'
    }
    if (Test-Path -LiteralPath $script:BACKEND_PID_FILE) {
        throw 'Successful managed stop retained a stale PID identity.'
    }
    Write-Host 'PowerShell router identity tests passed.'
}
finally { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
