# Windows 11 Pro post-merge acceptance — 2026-10-16

Target: Windows 11 Pro 26H2 x64 build 26300.9711, PowerShell 7.6.7 and inbox
Windows PowerShell 5.1. Main at inspection:
`36ad9d8e5676e3c3620eefed8597fb301b2d4045` (PRs #13 and #14 merged).
Private baseline, journals and screen captures are retained outside Git.

## Passed and observed

| Check | Evidence and practical limit |
| --- | --- |
| Baseline 05 | All 13 probes ok; 93 current-user AppX, 92 all-user, 27 provisioned, 7 Win32 entries. Captured before the final Widgets/taskbar Apply. Aggregate counts are observations, not proof of causation. |
| Post-merge baseline 06 | Fresh collection after the acceptance checks passed 13/13 probes, with 93 current-user and 27 provisioned AppX. Defender antivirus/realtime/tamper, all firewall profiles and Secure Boot remained enabled. |
| Widgets/taskbar transaction cycle | Apply, repeat Apply unchanged, exact-value Undo, then reapply passed on the VM. Original Task View absence and Search DWORD 2 were restored during Undo. Widgets policy absence was restored; its new empty key can remain. |
| Current managed registry state | Widgets, taskbar and welcome previews show zero pending changes. Two privacy-v1 defaults remain pending; preview success is not an assertion that every default has been applied. |
| Taskbar UI | Widgets/weather, Search and Task View controls were present before final Apply and absent afterwards. No Explorer restart or sign-out was needed. |
| Win+W | Four keyboard events were accepted; no Widgets board appeared in the captured desktop. Win+S was a positive control for the keyboard test. This is a current-session observation. |
| Local Search | Win+S opened Search, and typing PowerShell returned Windows PowerShell and PowerShell applications. Search suggestions/web results remain present; web-search suppression is separate work. |
| Normal-user previews | Explorer-launched helper verified a non-elevated token and the same user as Explorer. Widgets, taskbar, welcome and privacy CLIs all returned read-only plans. No token manipulation, scheduled task or UAC change was used. |
| Notifications UI | Expanded Additional settings: finish-setup suggestions and Windows tips both reported Off through UI Automation. The post-update welcome checkbox was not found by this inspection; its effectiveness is not established. |
| Online Windows Update scan | Windows Update Agent Search completed with result code 2 (succeeded), zero warnings and one available update. Only update search was requested; no download/install API was called. |
| Software/shell availability | Explorer, StartMenuExperienceHost and SearchHost responded. WinGet returned v1.29.380. Store downloading was not exercised. |
| Security and dependencies | After taskbar changes, Defender antivirus/realtime/tamper, all firewall profiles, UAC and Secure Boot were enabled. Widgets runtime package identities remained installed. BitLocker baseline was fully encrypted with protection Off. |

The first automated Search window-title locator failed to identify the Search
flyout. A screen capture then confirmed the flyout and local application
results. The locator failure is not recorded as a product failure or used
alone as proof of shortcut behavior.

## Source and test methods

- [Windows Update Agent Search](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search): online search using existing configured service selection and `IsInstalled=0 and IsHidden=0` criteria.
- [SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput): keyboard event count plus UI observation, not event count alone.
- [Widgets user controls](https://support.microsoft.com/en-us/windows/experience/personalization/stay-up-to-date-with-widgets-in-windows): distinguishes hiding the taskbar icon from board access.
- UI Automation read Settings controls and taskbar state; only the Additional settings expander was opened. No notification switches were changed.

## Pending and boundaries

- Actual lock-screen Widgets, sign-in/reboot persistence, post-update welcome,
  Store download/update delivery and interruption recovery remain pending.
- Privacy-v1 has two configured-state changes pending. Do not infer reduced
  diagnostic traffic or eliminated advertising from current settings.
- The online scan proves that scan succeeded, not that every future update
  installs successfully. No servicing/security control was disabled.
- No reboot, sign-out, snapshot restore, OneDrive unlink/uninstall, user-file
  scan, folder move or cloud-file action was performed in this acceptance pass.
- Earlier Widgets/taskbar write tests used elevation; this pass additionally
  verified non-elevated previews. It does not claim non-elevated HKLM writes.
