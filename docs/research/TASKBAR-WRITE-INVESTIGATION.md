# Taskbar write investigation — Windows 11 Pro build 26300.9711

Investigation date: 2026-10-16. This note accompanies a diagnostics improvement,
not a demonstrated fix for the Widgets preference. Initial inspection was
read-only; the operator subsequently authorized the bounded write comparisons
below and confirmed host snapshot inventory. Every attempted value write
was followed by an independent check that the original absent state remained.

## Observations and limits

- Local and remote `main` both pointed to
  `d56985966582f871384fddcfdc0952ef128f5008` at inspection.
- The handoff records an actual `UnauthorizedAccessException` from the
  taskbar adapter's `New-ItemProperty` call for `TaskbarDa`. Its transaction
  rolled back. The access denial was subsequently reproduced locally in
  both PowerShell versions.
- Read-only checks in PowerShell 7.6.7 and Windows PowerShell 5.1.26100.9711
  found Windows Pro build 26300, UBR 9711, 64-bit processes, the same user,
  and **elevated, high-integrity** tokens. These are not normal-user tests.
- Both engines found `TaskbarDa` and `ShowTaskViewButton` absent, with
  `SearchboxTaskbarMode` present as DWORD `2`. The taskbar preview proposes
  three changes and performs no writes.
- Both engines opened the Advanced and Search keys with
  `OpenSubKey(path, true)` and with explicit `RegistryRights.SetValue`.
  All handles were disposed without setting values. Handle acquisition is
  evidence of a successful open, not proof that a specific write is allowed.
- PowerShell 7 ACL inspection showed inherited current-user FullControl on
  both keys. Advanced's owner differed from the current user. An owner
  difference alone does not establish a cause for the write failure.
- Initial Windows PowerShell 5.1 `Get-Acl` checks returned
  `ItemNotFoundException` (`0x80131501`) with `-LiteralPath`. Follow-up
  `-Path` and direct `RegistryKey.GetAccessControl()` checks succeeded.
  Refreshed diagnostics now include ACLs for both engines. This was a
  diagnostic invocation issue, not a demonstrated write-failure cause.

## Authorized write comparisons

All attempts used the same elevated account and existing Advanced key. Each
probe required the target value to be absent, saved evidence before writing,
and guarded cleanup against unexpected state changes.

| Engine and method | Target | Observed result | Final state |
| --- | --- | --- | --- |
| Windows PowerShell 5.1, New-ItemProperty -LiteralPath | TaskbarDa | UnauthorizedAccessException, 0x80070005 | absent |
| PowerShell 7.6.7, New-ItemProperty -LiteralPath | TaskbarDa | UnauthorizedAccessException, 0x80070005 | absent |
| PowerShell 7.6.7, New-ItemProperty -Path | TaskbarDa | UnauthorizedAccessException, 0x80070005 | absent |
| PowerShell 7.6.7, RegistryKey.SetValue | TaskbarDa | UnauthorizedAccessException, 0x80070005 (inner exception) | absent |
| PowerShell 7.6.7, New-ItemProperty -LiteralPath | ShowTaskViewButton | DWORD 0 written and observed; deleted to restore prior absence | absent |

This proves that a **TaskbarDa value write is denied while a sibling value
in the same key is writable**. Direct SetValue failure rules out a failure
confined to the New-ItemProperty cmdlet; both engine failures rule out a
failure confined to PowerShell 7. The Windows restriction mechanism remains
**unknown**: neither a specific protecting component nor its rationale has
been identified. No ownership, ACL, security control, package or Explorer
cache was changed. The separate DISM/AppX COM issue does not explain this.

## Source inspection and applicability

The adapter writes an allowlisted HKCU DWORD through `New-ItemProperty -Force`.
PowerShell's provider opens the key with write access before setting the
value. Source inspected at the **v7.6.7 peeled commit**
[`c10ef6d557c0d6fe661836f78dbd6fc355261326`](https://github.com/PowerShell/PowerShell/blob/c10ef6d557c0d6fe661836f78dbd6fc355261326/src/System.Management.Automation/namespaces/RegistryProvider.cs):
`NewProperty`, `GetRegkeyForPath`, and their error handling. This explains
the code path; it does not prove which OS check rejected the historical write.

Microsoft documents the taskbar Settings Widgets toggle, and states that
hiding the icon leaves Win+W available. This is a visibility preference,
not device-wide Widgets disablement.
[Microsoft Support: Widgets](https://support.microsoft.com/en-us/windows/experience/personalization/stay-up-to-date-with-widgets-in-windows).

`AllowNewsAndInterests=0` is documented for device scope on Windows 11 Pro
21H2 and later, mapped to
`HKLM\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests`.
Microsoft describes coverage of Widgets including taskbar content. A future
implementation would require bounded elevation, exact prior-state backup,
verification and guarded undo. This investigation has **not** applied it or
verified taskbar, Win+W, or lock-screen behavior. The distinct
`DisableWidgetsBoard` and `DisableWidgetsOnLockScreen` entries are currently
documented as Insider Preview settings; do not silently promote them to
stable-build defaults.
[Microsoft Learn: NewsAndInterests CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-newsandinterests).

## Minimum code change and rollback

Preserve sanitized action ID, error stage, exception category and error code
when Apply fails, while retaining the existing rollback and nonzero failure.
Do not expose original exception messages, stack traces, registry data or
profile paths. Mock tests must prove denial reporting and rollback together.
This does not require elevation or modifying Windows settings. Reverting
the code change restores prior reporting; existing transaction undo remains
the recovery mechanism for applied registry settings.

Do not silently skip Widgets or report the entire taskbar transaction as
successful. Partitioning Widgets from Search/Task View needs a separate
explicit execution/reporting contract and is deferred until the control
mechanism is validated. Moving Widgets to a machine policy is a distinct
change of scope, not an automatic fallback during an HKCU write failure.

## Windows VM acceptance checklist

1. Confirm the exact VM, user, normal-user token, build, and host snapshot
   inventory. Capture a fresh private baseline before registry experiments.
2. Run taskbar preview and read-only key/ACL/handle checks in both engines.
   Keep baseline files and raw registry journals out of public commits.
3. With explicit approval and a confirmed snapshot, compare the Settings
   Widgets control with a bounded single-value write test. Capture exact
   prior existence, registry kind and data first; restore in `finally` and
   independently read back the prior state. If restoration fails, stop and
   report needs-review. Do not force a write through ACL/ownership changes.
4. If considering the device policy, test it separately with scoped admin
   Apply and guarded Undo. Check taskbar weather, Win+W, and lock-screen
   Widgets individually, including sign-in/reboot persistence. Coordinate
   sign-out/reboot with the operator before interrupting the agent session.
5. Verify repeated Apply idempotence and exact Undo. Recheck Explorer,
   Start, Win+S/local search, Task View and Settings; preserve Widgets packages.
6. Check Defender/tamper, firewall, UAC, Secure Boot, Windows Update scan,
   Store/WinGet and WebView2. Record unavailable or untested checks honestly.

The write comparisons above passed their restoration checks. Settings-toggle,
normal-user and UI acceptance remain pending. This diagnostics change does
not itself change the taskbar catalog or introduce the device Widgets policy.
