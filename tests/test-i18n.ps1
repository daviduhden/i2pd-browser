<#
.SYNOPSIS
    Checks localization behavior without starting the browser or router.
.DESCRIPTION
    Verifies catalog key parity, locale normalization, configuration
    preservation, and the selected-language loader using temporary state.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tmp = Join-Path ([IO.Path]::GetTempPath()) (
    'i2pd-browser-i18n-' + [Guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $env:I2PD_BROWSER_ROOT = $root
    $env:I2PD_BROWSER_CONF = Join-Path $tmp 'i2pd-browser.conf'
    . (Join-Path $root 'lib/i18n.ps1')

    function Assert-Equal([string]$Actual, [string]$Expected) {
        if ($Actual -ne $Expected) {
            throw "Expected '$Expected', got '$Actual'."
        }
    }

    foreach ($locale in @('en-US', 'es-ES', 'ru', 'zh-CN')) {
        $path = Join-Path $root "locales/$locale.properties"
        if (-not (Test-Path $path)) { throw "Missing $path" }
        $englishKeys = Get-Content (Join-Path $root 'locales/en-US.properties') |
            Where-Object { $_ -and -not $_.StartsWith('#') } |
            ForEach-Object { ($_ -split '=', 2)[0] } | Sort-Object
        $localeKeys = Get-Content $path |
            Where-Object { $_ -and -not $_.StartsWith('#') } |
            ForEach-Object { ($_ -split '=', 2)[0] } | Sort-Object
        if (Compare-Object $englishKeys $localeKeys) {
            throw "Catalog keys differ for $locale"
        }
        [void](Initialize-I2pdBrowserI18n $locale)
        if (-not (Get-I18nMessage 'language.selected' @($locale))) {
            throw "Empty catalog message for $locale"
        }
    }
    Assert-Equal (ConvertTo-I2pdBrowserLocale 'en_GB') 'en-US'
    Assert-Equal (ConvertTo-I2pdBrowserLocale 'es_MX') 'es-ES'
    Assert-Equal (ConvertTo-I2pdBrowserLocale 'ru_RU') 'ru'
    Assert-Equal (ConvertTo-I2pdBrowserLocale 'zh-Hans-CN') 'zh-CN'
    if (ConvertTo-I2pdBrowserLocale 'de-DE') {
        throw 'Unsupported locale was accepted.'
    }

    @(
        'I2P_ROUTER=i2pd'
        'I2PD_BROWSER_LANGUAGE=es-ES'
        'CUSTOM_SETTING=preserved'
    ) | Set-Content -Path $env:I2PD_BROWSER_CONF -Encoding utf8
    $script:I2PD_BROWSER_ROOT = $root
    . (Join-Path $root 'lib/router.ps1')
    [void](Set-RouterConf -Name i2pd -Source system -Language ru)
    Assert-Equal (Get-RouterConfLanguage) 'ru'
    if (-not (Get-Content $env:I2PD_BROWSER_CONF -Raw).Contains(
            'CUSTOM_SETTING=preserved')) {
        throw 'Configuration preservation failed.'
    }
    Write-Host 'PowerShell i18n tests passed'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
