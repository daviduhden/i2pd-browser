# Internationalization conventions

- User-visible script text belongs in `locales/*.properties`; use a
  stable dotted key and keep the four catalogs key-for-key identical.
- Catalogs are UTF-8 data files. Do not source, dot-source or evaluate
  them; use `i18n_message` in Bash and `Get-I18nMessage` in
  PowerShell.
- Preserve technical identifiers, commands, paths, protocols and
  configuration values. Use `{0}`, `{1}`, and so on for interpolated
  values.
- Update both `lib/i18n.bash` and `lib/i18n.ps1`, documentation, and
  the i18n tests when adding a locale or changing locale selection.
- Do not loosen Firefox preferences, policies, proxy controls, update
  restrictions or telemetry restrictions for localization.
