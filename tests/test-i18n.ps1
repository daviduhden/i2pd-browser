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
    $script:I2PD_BROWSER_ROOT = $root
    $env:I2PD_BROWSER_CONF = Join-Path $tmp 'i2pd-browser.conf'
    . (Join-Path $root 'lib/i18n.ps1')

    function Assert-Equal([string]$Actual, [string]$Expected) {
        if ($Actual -cne $Expected) {
            throw "Expected '$Expected', got '$Actual'."
        }
    }

    function Read-TestCatalog([string]$Path) {
        $catalog = @{}
        foreach ($line in [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)) {
            if (-not $line -or $line.StartsWith('#')) { continue }
            $parts = $line -split '=', 2
            if ($parts.Count -ne 2 -or $catalog.ContainsKey($parts[0])) {
                throw "Malformed or duplicate catalog key in $Path"
            }
            if (-not $parts[1]) { throw "Empty catalog value in $Path" }
            $catalog[$parts[0]] = $parts[1]
        }
        return $catalog
    }

    $english = Read-TestCatalog (Join-Path $root 'locales/en-US.properties')
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
        $localized = Read-TestCatalog $path
        foreach ($key in $english.Keys) {
            $expected = ([regex]::Matches($english[$key], '\{[0-9]+\}') |
                ForEach-Object Value | Sort-Object) -join '|'
            $actual = ([regex]::Matches($localized[$key], '\{[0-9]+\}') |
                ForEach-Object Value | Sort-Object) -join '|'
            Assert-Equal $actual $expected
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
    if (Initialize-I2pdBrowserI18n 'de-DE') {
        throw 'Unsupported explicit locale initialized successfully.'
    }

    # Missing translated keys use English; interpolation preserves literal
    # backslashes and ampersands in user-supplied paths.
    $catalogDirectory = Join-Path $tmp 'locales'
    [void][IO.Directory]::CreateDirectory($catalogDirectory)
    $englishFixture = [IO.File]::ReadAllText((Join-Path $root 'locales/en-US.properties'))
    $englishFixture += "`nfallback.only=English fallback {0}\n`n"
    [IO.File]::WriteAllText((Join-Path $catalogDirectory 'en-US.properties'),
        $englishFixture, [Text.UTF8Encoding]::new($false))
    Copy-Item (Join-Path $root 'locales/es-ES.properties') $catalogDirectory
    $script:I2PD_BROWSER_ROOT = $tmp
    [void](Initialize-I2pdBrowserI18n 'es-ES')
    Assert-Equal (Get-I18nMessage 'fallback.only' @('C:\a&b')) (
        'English fallback C:\a&b' + [Environment]::NewLine)
    $script:I2PD_BROWSER_ROOT = $root

    $env:I2PD_BROWSER_LANGUAGE = 'zh-Hans'
    Assert-Equal (Select-I2pdBrowserLocale) 'zh-CN'

    @(
        'I2P_ROUTER=i2pd'
        'I2PD_BROWSER_LANGUAGE=es-ES'
        'CUSTOM_SETTING=preserved'
    ) | Set-Content -Path $env:I2PD_BROWSER_CONF -Encoding utf8
    Assert-Equal (Select-I2pdBrowserLocale) 'es-ES'
    Assert-Equal (Select-I2pdBrowserLocale 'ru') 'ru'
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
