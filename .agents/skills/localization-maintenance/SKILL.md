---
name: localization-maintenance
description: Add or change localized messages and locale selection. Use when editing locales/*.properties, lib/i18n.bash, lib/i18n.ps1, user-visible script text, or the supported language list.
---

# Localization maintenance

## When to use

Use this skill for any user-visible text, new message key, new locale,
locale normalization, language selection order, or documentation of
language behavior. It applies to installers, builders, router
management, and browser launchers.

## Project facts

- Supported locales are `en-US`, `es-ES`, `ru`, and `zh-CN`.
- Catalogs are `locales/<locale>.properties`. They are UTF-8, LF, data
  only, and must be key-for-key identical. The first line is a comment;
  use `key=value` records and keep values on one physical line with
  `\n` escapes for line breaks.
- Keys use stable dotted names such as `usage.header`,
  `error.checksum`, or `status.http-proxy`. Values may contain `=`;
  everything after the first `=` is the value.
- The loaders overlay the selected catalog on `en-US`, so a missing
  localized key falls back to English. A missing key also prints
  `[[key]]` to stderr and returns the key.
- Bash replaces `{0}`, `{1}`, and so on in order and prints with
  `printf '%b\n'`, so backslash escapes are interpreted. PowerShell
  replaces `{n}` literally and translates only the two-character `\n`
  sequence to the platform newline.
- Bash selection order: explicit `--language`, stored
  `I2PD_BROWSER_LANGUAGE` in `i2pd-browser.conf`, environment
  `I2PD_BROWSER_LANGUAGE` or legacy `language`, OS locale
  (`LANGUAGE` as a colon list, then `LC_ALL`, `LC_MESSAGES`, `LANG`),
  then `en-US`.
- PowerShell uses the same precedence with the .NET user/current UI
  culture for the OS step.
- Normalization strips a suffix after `.`, replaces `_` with `-`,
  lowercases, and maps `en*` to `en-US`, `es*` to `es-ES`, `ru*` to
  `ru`, and `zh`, `zh-cn`, `zh-hans`, `zh-hans-cn` to `zh-CN`. Other
  values are rejected.
- An explicitly supplied unsupported locale is an error. Unsupported
  stored, environment, or system values fall through.
- The installer and builder call `i18n_init`; the Bash launcher reads
  `browser/.i2pd-browser-locale`; the PowerShell launcher does the
  same. Missing markers fall back to `en-US`.
- Do not localize technical identifiers, commands, paths, protocol
  names, preference names, or configuration values.

## Procedure

### Change an existing message

1. Update the value in all four catalogs at the same key.
2. Preserve every `{n}` placeholder and its meaning. Do not reorder
   placeholders without updating callers.
3. If the message is used by both platforms, verify the Bash and
   PowerShell interpolation behavior is still acceptable.
4. Update callers if the key meaning or argument count changes.
5. Run both i18n tests.

### Add a message

1. Choose a dotted key that matches the existing naming style and is
   unlikely to collide.
2. Add it to all four catalogs at the same position or with the same
   ordering convention.
3. Add the caller with `i18n_message key args...` in Bash or
   `Get-I18nMessage 'key' @(args...)` in PowerShell.
4. Keep the four catalogs key-for-key identical.

### Add a locale

1. Copy `locales/en-US.properties` to the new BCP 47 filename and
   translate every value without dropping keys.
2. Add normalization support in `lib/i18n.bash` and `lib/i18n.ps1`.
3. Extend the interactive language selection in `install.bash` and
   `install.ps1`, and the usage text listing supported values.
4. Extend `tests/test-i18n.bash` and `tests/test-i18n.ps1` with the new
   locale and at least one alias.
5. Update `README.md` and the launcher/build language handling.
6. Verify Firefox ESR actually publishes the locale through Mozilla's
   redirector; the build now rejects a final URL whose locale does not
   match the request.

## Validation

```sh
bash tests/test-i18n.bash
pwsh -NoProfile -File tests/test-i18n.ps1   # if available
```

Manual catalog checks:

```sh
for locale in en-US es-ES ru zh-CN; do
  printf '%s: ' "$locale"
  grep -vcE '^(#|$)' "locales/$locale.properties"
done

# Key parity
diff -u \
  <(grep -vE '^(#|$)' locales/en-US.properties | cut -d= -f1 | sort) \
  <(grep -vE '^(#|$)' locales/es-ES.properties | cut -d= -f1 | sort)

# Placeholder parity (inspect the output, do not assume)
grep -nE '\{[0-9]+\}' locales/*.properties

# Encoding and line endings
file locales/*.properties
```

If a new locale is added to the test loops, update both test files.
Do not source or evaluate a catalog to inspect it.

## Common problems

- **Parity failures.** A key added to only one catalog makes the tests
  fail and can terminate a Bash caller under `set -e`.
- **Bash/PowerShell escape differences.** Bash interprets backslash
  escapes with `%b`; PowerShell only translates `\n`. Avoid relying on
  other backslash escapes.
- **Empty values.** Bash treats an empty value as missing; PowerShell
  treats it as present. Do not use empty values for new keys.
- **CRLF contamination.** `.gitattributes` pins catalogs to LF and the
  Bash loader strips a trailing `\r`, but a CRLF catalog can still
  break other tooling. Keep LF.
- **Hardcoded English.** Several PowerShell installer and router
  messages are still hardcoded. If you touch them, move them to the
  catalogs rather than adding more hardcoded text.
- **Build help regression.** `build/build.bash` and `build/build.ps1`
  use `usage.build-options`, not the installer's `usage.options`.
- **Unused keys.** `error.invalid-locale-build`,
  `error.locale-mismatch`, and other keys may be present without a
  caller. Check usage before deleting or relying on them.
- **Locale fallback.** Mozilla may redirect to a fallback locale. The
  builder now fails if the final URL does not contain the requested
  locale; do not remove that check to make a build pass.

## References

- `locales/en-US.properties` - source catalog.
- `locales/es-ES.properties`, `locales/ru.properties`,
  `locales/zh-CN.properties` - translations.
- `lib/i18n.bash`, `lib/i18n.ps1` - normalization, selection, loading,
  and interpolation.
- `install.bash`, `install.ps1` - language prompts and options.
- `build/build.bash`, `build/build.ps1` - build message and locale
  handling.
- `build/scripts/start-i2pd-browser.bash`,
  `build/scripts/start-i2pd-browser.ps1` - launcher locale marker.
- `tests/test-i18n.bash`, `tests/test-i18n.ps1` - catalog and selection
  tests.
- `README.md` - documented language behavior.
- Related skills: `firefox-esr-bundling`,
  `cross-platform-installers`.
