Set-StrictMode -Version Latest

$script:I2pdBrowserLocales = @('en-US', 'es-ES', 'ru', 'zh-CN')
$script:I2pdBrowserLanguage = 'en-US'
$script:I18nMessages = @{}

function ConvertTo-I2pdBrowserLocale {
    param([string]$Locale)
    $value = (($Locale -split '\.')[0] -replace '_', '-').ToLowerInvariant()
    if ($value -eq 'en' -or $value -like 'en-*') { return 'en-US' }
    if ($value -eq 'es' -or $value -like 'es-*') { return 'es-ES' }
    if ($value -eq 'ru' -or $value -like 'ru-*') { return 'ru' }
    if ($value -in @('zh', 'zh-cn', 'zh-hans', 'zh-hans-cn')) {
        return 'zh-CN'
    }
    return $null
}

function Get-I2pdBrowserLocaleConfigFile {
    if ($env:I2PD_BROWSER_CONF) { return $env:I2PD_BROWSER_CONF }
    return (Join-Path $script:I2PD_BROWSER_ROOT 'i2pd-browser.conf')
}

function Get-I2pdBrowserStoredLocale {
    $file = Get-I2pdBrowserLocaleConfigFile
    if (-not (Test-Path $file)) { return '' }
    $match = Select-String -Path $file `
        -Pattern '^\s*I2PD_BROWSER_LANGUAGE\s*=\s*(.*)$' |
        Select-Object -Last 1
    if ($match) { return $match.Matches[0].Groups[1].Value.Trim() }
    return ''
}

function Get-I2pdBrowserSystemLocale {
    $cultures = @(
        [Globalization.CultureInfo]::GetUserDefaultUICulture.Name
        [Globalization.CultureInfo]::CurrentUICulture.Name
    )
    foreach ($culture in $cultures) {
        $normalized = ConvertTo-I2pdBrowserLocale $culture
        if ($normalized) { return $normalized }
    }
    return 'en-US'
}

function Select-I2pdBrowserLocale {
    param([string]$Explicit = '')
    if ($Explicit) { return (ConvertTo-I2pdBrowserLocale $Explicit) }
    $stored = ConvertTo-I2pdBrowserLocale (Get-I2pdBrowserStoredLocale)
    if ($stored) { return $stored }
    $configured = if ($env:I2PD_BROWSER_LANGUAGE) {
        $env:I2PD_BROWSER_LANGUAGE
    } else { $env:language }
    $configured = ConvertTo-I2pdBrowserLocale $configured
    if ($configured) { return $configured }
    return (Get-I2pdBrowserSystemLocale)
}

function Import-I2pdBrowserCatalog {
    param([string]$Locale)
    $script:I18nMessages = @{}
    foreach ($catalog in @(
            (Join-Path $script:I2PD_BROWSER_ROOT 'locales/en-US.properties'),
            (Join-Path $script:I2PD_BROWSER_ROOT "locales/$Locale.properties")
        )) {
        if (-not (Test-Path $catalog)) { continue }
        foreach ($line in [IO.File]::ReadAllLines(
                $catalog, [Text.UTF8Encoding]::new($false))) {
            if (-not $line -or $line.StartsWith('#')) { continue }
            $separator = $line.IndexOf('=')
            if ($separator -le 0) { continue }
            $key = $line.Substring(0, $separator)
            if ($key -match '\s') { continue }
            $script:I18nMessages[$key] = $line.Substring($separator + 1)
        }
    }
}

function Initialize-I2pdBrowserI18n {
    param([string]$Explicit = '')
    $locale = Select-I2pdBrowserLocale $Explicit
    if (-not $locale) { return $false }
    $script:I2pdBrowserLanguage = $locale
    Import-I2pdBrowserCatalog $locale
    return $true
}

function Get-I18nMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [string[]]$Arguments = @()
    )
    if (-not $script:I18nMessages.ContainsKey($Key)) {
        [Console]::Error.WriteLine("[[$Key]]")
        return $Key
    }
    $message = $script:I18nMessages[$Key]
    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $message = $message.Replace("{$index}", $Arguments[$index])
    }
    return $message.Replace('\n', [Environment]::NewLine)
}
