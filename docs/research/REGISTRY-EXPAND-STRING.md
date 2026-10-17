# Exact expandable-string registry state

Researched 2026-10-17 UTC. The installed StartMenu ADMX declares the future
ConfigureStartPins JSON text value as expandable. The transaction engine
therefore needs to represent `ExpandString` before that policy can be managed
without losing its type or literal data. This change adds that representation
and isolated tests; it does not configure Start.

[RegistryValueKind](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registryvaluekind)
maps ExpandString to REG_EXPAND_SZ, distinct from ordinary REG_SZ. Default
registry reads can substitute environment variables.
[RegistryValueOptions](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registryvalueoptions)
provides DoNotExpandEnvironmentNames to retain the literal stored text.
The [pinned .NET registry source](https://github.com/dotnet/runtime/blob/d099f075e45d2aa6007a22b71b45a08758559f80/src/libraries/Microsoft.Win32.Registry/src/Microsoft/Win32/RegistryKey.Windows.cs#L659)
shows the conditional expansion. This revision explains the API behavior; it
is not a claim that the VM runs that exact .NET build. No source is copied.

The engine treats ExpandString as string data and preserves its separate kind
through plan, verification, journal reload and guarded Undo. The sandbox
adapter reads unexpanded text. For example, `%USERPROFILE%\before` must remain
that literal value in a backup, rather than a path expanded for the process
that performed the read. Later environment changes must not alter the stored
prior state or cause false drift. A change to REG_SZ with identical text is
still a type change and must be handled as such.

The sandbox path boundary remains HKCU\Software\uindos\EngineTest. Existing
production policy adapters retain their own fixed allowlists and kind checks.
Binary and MultiString data remain unsupported. No new policy, service, shell
restart, app install or persistent environment setting is introduced.

Tests cover literal variable tokens, quoted JSON/backslashes/Unicode, exact
prior type/value, JSON journal roundtrip, no-op Apply, absence Undo and type
drift. The live Windows test uses only a fresh random sandbox child and a
task-specific process environment variable, then cleans up its key/journal.
It changes no system environment variables. Start policy application and layout
restoration remain separate work.

On Windows 11 Pro build 26300.9711 / PowerShell 7.6.7, the live sandbox test
passed from a verified non-elevated Explorer-user session. Raw ExpandString
Apply, unchanged repeat and exact prior restoration after changing the
task-specific process variable passed; the ordinary GetValue control expanded
that variable as expected. No additional sandbox child or journal directory
remained. The portable transaction mocks and eight affected policy/appearance
mock suites also passed. This establishes registry-state behavior, without
testing a Start reset or any layout reconstruction.
