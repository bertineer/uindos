# Supported Widgets policy and taskbar separation

Evidence date: 2026-10-16. Target: Windows 11 Pro 26H2 build 26300.9711,
PowerShell 7.6.7, existing elevated token in the disposable VM.

## Decision and sources

Use the documented device policy `AllowNewsAndInterests=0` at
`HKLM\SOFTWARE\Policies\Microsoft\Dsh`, with a separate admin Apply/Undo
command. Microsoft lists Pro support from Windows 11 21H2. The local
`NewsAndInterests.admx` maps the same value. Keep the Widgets runtime packages.
[Microsoft policy applicability and mapping](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-newsandinterests).

Separate current-user Search/Task View preferences from this device policy.
New taskbar plans exclude `TaskbarDa`, while the full allowlist retains it
for validation/Undo of historical journals. The CLI explicitly points users
to the separate Widgets command; it does not report the old preference as
successfully applied.

## Proven write boundary

TaskbarDa writes failed with UnauthorizedAccessException (0x80070005) in
PowerShell 5.1 and 7. Both provider path forms and direct RegistryKey.SetValue
failed. A sibling ShowTaskViewButton write in the same Advanced key succeeded
and was restored. This establishes a value-specific write refusal, not its
protecting mechanism. Writable handles and a current-user FullControl ACL
do not prove a particular value write will succeed. No permissions, ownership,
security controls, packages or Explorer caches were changed to force it.

## Actual VM results

- Widgets policy: Apply set DWORD 0; repeat Apply returned unchanged; Undo
  returned undone and independently restored the originally absent value.
  The newly created empty Dsh key remained, as documented by the value-level
  transaction contract.
- New taskbar defaults: both values applied; repeat Apply returned unchanged;
  Undo restored Task View absence and Search DWORD 2 exactly.
- Both sets of defaults were then reapplied. Both plans reported zero
  remaining changes. TaskbarDa stayed absent.
- UI Automation found visible WidgetsButton, SearchButton and TaskViewButton
  before the final Apply. It found none of those controls afterwards in the
  same primary taskbar tree, without sign-out or restarting Explorer. This
  verifies the observed taskbar change, not every Widgets surface.
- Defender antivirus, real-time protection and tamper protection, all firewall
  profiles, UAC and Secure Boot remained enabled. Both Widgets runtime
  package identities remained installed.
- Windows/Linux mock suites cover policy gating, allowlists, idempotence,
  exact prior-value Undo, denied writes and historical taskbar journals.
  Remote CI results are recorded in the PR; local mocks passed.

## Pending acceptance and recovery

Normal-user preview/Apply behavior, Win+W, lock-screen Widgets, sign-in/reboot
persistence, an actual Windows Update scan and Store downloads were not tested
here. Validate these separately; neither registry state nor button absence
proves all of them. The distinct board/lock-screen policies remain marked
as preview in the current CSP documentation and are excluded.

Use each command's own transaction ID and journal for guarded Undo. Do not
reset values to assumed defaults or delete the Dsh key wholesale. Undo can
leave a newly created empty policy key. A host snapshot is a recovery
fallback and may discard later VM state; identify duplicate snapshot names
by UUID. Keep private baseline/journal/UI evidence out of public commits.
