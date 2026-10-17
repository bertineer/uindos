# Search suggestions

The curated current-user policy sets
`HKCU\Software\Policies\Microsoft\Windows\Explorer\DisableSearchBoxSuggestions`
to DWORD 1. Microsoft documents this policy for File Explorer search-history
suggestions on Pro. Its effect on Start web results must be tested separately
on the installed Windows build. See [sources and limits](research/SEARCH-SUGGESTIONS.md).

Use PowerShell 7 on Windows 11 Pro/Pro N x64 or ARM64, build 22000 or later:

```powershell
# Read-only plan; no journal is created.
pwsh -NoProfile -File ./bin/uindos-search-suggestions.ps1

# Apply/Undo: temporary elevated PowerShell for the same desktop account.
pwsh -NoProfile -File ./bin/uindos-search-suggestions.ps1 -Apply

# Replace with the transaction GUID returned by Apply.
pwsh -NoProfile -File ./bin/uindos-search-suggestions.ps1 -Undo <transaction-guid>
```

The default private journal directory is
`%LOCALAPPDATA%\uindos\transactions\search-suggestions-v1`. An optional
`-JournalDirectory` can select a private persistent location; use the same
directory for Apply and Undo. Do not publish journals.

The normal Explorer desktop stays non-elevated. Policy-key permissions on the
tested VM require a temporary elevated writer; the command never elevates
itself or changes permissions/ownership. Apply/Undo reject a different user or
session from Explorer. Preview works without elevation.

The command backs up the exact prior DWORD or absence, verifies registry
readback and returns unchanged on repeat Apply. Guarded Undo refuses external
drift with needs-review and exit 2. Empty created keys may remain. Undo cannot
recover query history that Windows did not record while the policy was enabled.
Existing history is not deleted by this command.

Start, Explorer, local Search and indexing remain installed and running. The
command performs no shell restart or sign-out. Observe behavior separately
after Apply; a later sign-in may be needed. No claim of zero telemetry follows
from this setting.

Tests: `tests/search-suggestions-mock.ps1` and
`tests/search-suggestions-windows-readonly.ps1`. The Windows test intercepts
provider writes and does not change the production setting.

## VM observation — 2026-10-17 UTC

On Windows 11 Pro build 26300.9711 / PowerShell 7.6.7, normal-user Preview,
elevated same-user Apply, repeat Apply (unchanged), exact-absence Undo and
final reapply passed. A refreshed Search flyout showed no web results for a
previously web-backed unmatched Start query. Win+S still found PowerShell
applications, and File Explorer still found a known documentation filename.
Undo plus Search refresh brought web results back; final reapply plus refresh
suppressed them again.

The existing Search process initially continued showing web suggestions.
Only the current user's SearchHost process was manually refreshed during
testing; the shipped command never stops it. No Explorer restart, sign-out or
reboot occurred. Reboot persistence, other builds and broader query/network
behavior remain unverified. Defender AV/realtime/tamper stayed enabled, and
Windows Search stayed running. See the [detailed acceptance limits](research/SEARCH-SUGGESTIONS.md).
