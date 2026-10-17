# Privacy defaults v1 — Windows 11 Pro

**Implementation status:** PR #5. This is the first **real but deliberately narrow** Windows-settings change in uindos. It is not a complete privacy configuration, a debloater, a telemetry blocker or a desktop installer.

## Opinionated changes

Exactly three DWORD values, current user only:

| Purpose | Registry path (HKCU) | Value name | Desired DWORD | Source / interpretation |
| --- | --- | --- | --- | --- |
| Stop using Windows diagnostic data for tailored experiences | `Software\Policies\Microsoft\Windows\CloudContent` | `DisableTailoredExperiencesWithDiagnosticData` | 1 | [Microsoft Experience CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowtailoredexperienceswithdiagnosticdata); documented user policy, Pro supported |
| Disable third-party Spotlight suggestions | `Software\Policies\Microsoft\Windows\CloudContent` | `DisableThirdPartySuggestions` | 1 | [Microsoft Experience CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowthirdpartysuggestionsinwindowsspotlight); documented user policy, Pro supported |
| Disable the current user's Windows advertising ID preference | `Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo` | `Enabled` | 0 | Best-effort preference, commonly used by [Win11Debloat](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Regfiles/Disable_Telemetry.reg); **not equivalent to the [machine-wide advertising ID policy](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy#disableadvertisingid)** |

Windows 11 can still show recommendations after disabling tailored experiences, and the advertising ID setting does not remove advertisements or establish diagnostic-data-off.

**Scope:** Windows 11 Pro and Pro N, x64 and ARM64, build >= 22000. The tool intentionally refuses Windows Home/Enterprise/Server and Windows 10 until individually validated, even though some underlying policies may be supported there.

## Commands

Use PowerShell 7 from a normal, non-elevated session **for the account you want to configure**:

~~~powershell
# Preview only; prints JSON. No journal or registry writes.
pwsh -NoProfile -File ./bin/uindos-privacy.ps1

# Explicitly apply the three fixed settings after reviewing the plan.
pwsh -NoProfile -File ./bin/uindos-privacy.ps1 -Apply

# Undo using the GUID returned by Apply (subject to drift/conflicts).
pwsh -NoProfile -File ./bin/uindos-privacy.ps1 -Undo 00000000-0000-0000-0000-000000000001
~~~

The GUID shown above is an illustrative placeholder; replace it with the actual transaction ID. Never use a placeholder ID expecting it to work.

`-Apply` is required to write. There is no consent-by-default or hidden schedule. Windows user Group Policy refreshes or user settings may change a value later. Re-running a preview will show the current state; automatic post-update reconciliation is a future milestone.

## Verification and rollback

The tool:
- Confirms the Windows version/edition before planning or applying.
- Enforces exact action ID, registry key, value name, registry kind and desired value; denies all other targets.
- Captures each original value **and type** before writing.
- Journals each transaction in `%LOCALAPPDATA%\uindos\transactions\privacy-v1\<transactionId>.json` prior to changing anything.
- Rechecks the snapshot before each write, verifies the resulting DWORD, and treats an unchanged system as a no-op.
- Restores saved values on explicit Undo or attempts rollback after failed apply. It will not overwrite an externally modified value: instead it reports `needs-review`. An originally absent value is removed on undo, but an empty key created by uindos may remain.

**Do not publish journals**; they may reveal policy values and the previous state. The journal is not an atomic Windows transaction or tamperproof. A forced termination can leave a partial installation requiring manual recovery. Undo returns a nonzero exit status when conflicts need review.

Registry readback only verifies registry state—not whether all Windows experiences honor the change. Test on a disposable Windows 11 Pro VM before running on a primary machine.

Undo accepts saved DWORD integers after JSON journal reload, which produces
`Int64` values on the tested PowerShell 7.6.7 runtime. The adapter validates the
signed 32-bit range before converting back to `Int32`, preserving the original
DWORD bits, including high-bit values. Strings, fractional numbers, booleans
and out-of-range integers are rejected before a registry write.

## Security boundaries

The adapter cannot write HKLM, disable Windows Update or Defender, remove Edge/WebView2, alter firewall rules, touch BitLocker, remove AppX packages or change other users' profiles. No service, scheduled task, remote download or permanent elevated process is created.

Only the current-user advertising-ID **preference** is changed, not a machine-level Group Policy. Because Windows advertising settings and UI change between builds, this particular preference is marked **best-effort** and requires real-device verification.

## Tests

`pwsh -NoProfile -File ./tests/privacy-mock.ps1` runs Windows-agnostic tests with an in-memory adapter; no registry changes.

`pwsh -NoProfile -File ./tests/privacy-windows-readonly.ps1` checks Windows registry reads and rejects unauthorized write targets; it **does not modify** the three production privacy settings. GitHub CI runs both.

The mock suite covers existing DWORD Undo through a saved/reloaded journal,
including both signed 32-bit limits. The Windows suite also invokes the real
Write delegate with registry provider calls intercepted to verify normalization
and rejection without changing registry state. These tests passed on the
Windows 11 Pro build 26300.9711 VM with PowerShell 7.6.7; live privacy
Apply/Undo and effective policy behavior remain pending.

A dedicated Windows 11 Pro VM must still validate effective behavior, apply/undo, Group Policy precedence, current-user scope, and Settings UI observability. Details: [research/PRIVACY-DEFAULTS.md](research/PRIVACY-DEFAULTS.md).

## Limitations and next steps

These are three **small** initial defaults. Removing Edge, Copilot, app bloat, consumer tasks, search cloud integrations, and avoiding Microsoft account pressure are separate future PRs. uindos does not claim zero telemetry and will not disable core system security merely to make that claim.
