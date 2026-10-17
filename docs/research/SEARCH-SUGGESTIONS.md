# Search suggestions policy: support and acceptance

Researched 2026-10-17 UTC for Windows 11 Pro build 26300.9711. This is one
user policy, independent of service tuning, Start pin layout and app removal.

## Source and scope

[Microsoft ADMX_WindowsExplorer / DisableSearchBoxSuggestions](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-windowsexplorer#disablesearchboxsuggestions)
lists user scope, Pro support and Windows 11 21H2 or later. Its documented
purpose is suppressing File Explorer's recent-query suggestions and future
query-history storage. The mapping is
`HKCU\Software\Policies\Microsoft\Windows\Explorer\DisableSearchBoxSuggestions`,
DWORD 1 enabled / 0 disabled. Disabling this convenience is an intentional cost.

Start web-result suppression is an empirical, build-specific outcome to test,
not part of that documented policy promise. This command cannot certify that
no query data leaves Windows or that every Search surface is covered.

The installed `C:\Windows\PolicyDefinitions\WindowsExplorer.admx` on the VM
agrees with this mapping (policy at lines 347–355, class User). The local
en-US ADML describes the same File Explorer behavior. Exact source identity:
ADMX SHA256 `DD68B2E4BDEF20A500F78C2808EC62493A3D9AAFAAEDD5C6F480466A91879CB0`.
The current Learn page's MicrosoftDocs Edit link returned 404, so no public
commit permalink was available. The installed, hashed source and current
official documentation are the applicability evidence; no third-party tweak
implementation is copied or executed.

[Microsoft Search / DoNotUseWebResults](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-search#donotusewebresults)
maps the dedicated web-results control to machine `ConnectedSearchUseWeb` and
explicitly excludes Pro. uindos does not add it as an effective Pro policy.
The installed Search ADMX marks `DisableWebSearch` as a legacy Windows Desktop
Search policy; neither is added alongside this single user setting.

## Implementation and recovery boundaries

The command gates Windows 11 Pro/Pro N x64 or ARM64, build 22000 or later.
Only this exact action/target/DWORD 1 is permitted as desired state. The
adapter captures DWORD type and prior bits (or absence); other registry types
fail before mutation. Int64 values reloaded from JSON must fit the captured
signed Int32 representation before restoration. Invalid inputs fail closed.

The CLI's Apply/Undo require a temporary elevated policy writer for the same user and
session as the normal Explorer desktop. Preview
is read-only and creates no journal. Private journals are saved before writes;
repeat Apply is unchanged. Undo preserves external drift as needs-review.
An originally absent value is removed, but an empty created key may remain.
Search history not recorded while the policy is enabled cannot be recreated
by Undo. Existing saved-query data is not deleted by uindos.

No service, scheduled task, firewall rule, package, index, shell process,
security control or Windows Update setting is changed. Local Search and
Explorer remain available. The command does not refresh Group Policy, restart
SearchHost/Explorer, sign out or reboot. Test UI after configuration; later
session refresh may be needed. Registry readback alone is insufficient.

## Tests

Cross-platform mocks exercise preview, consent, repeat Apply, absent and
existing-DWORD JSON Undo, drift, target/type/range rejection and bad journal
identity. Windows tests read the actual adapter and intercept provider writes
to test integer normalization without changing registry state. The CLI's
non-elevated-Apply refusal is also checked before any journal is created.

VM acceptance must compare a harmless unmatched query before/after in Start
and Win+S, verify local app search, repeat Apply, exact Undo and final state.
File Explorer filename search remains a separate regression check. Neither
mock tests nor screenshots establish network privacy or servicing behavior.

Initial same-user non-elevated Preview passed, but Apply failed and the
transaction rolled back, preserving original absence. Read-only ACL inspection
found the policy parent key grants the normal user ReadKey and Administrators
FullControl. This is distinct from the earlier TaskbarDa value-specific refusal.
No ACL or ownership change is required or performed. The initial
non-elevated-only implementation guard was corrected to permit only the narrow
elevated same-user policy command; ordinary desktop processes stay normal.

The dot-sourced adapter is an internal trusted engine component; the CLI owns
the elevation/session guard. Direct use of internal functions is not a separate
authorization interface.

## Actual VM acceptance — 2026-10-17 UTC

Normal-user Preview passed with the value absent and one pending change.
The corrected CLI's normal-user Apply guard refuses before entering the
transaction engine. Elevated same-user/session Apply wrote DWORD 1; repeat
Apply returned unchanged with no new transaction. Undo restored original
absence exactly, with zero conflicts. The setting was intentionally reapplied
after that test and left at DWORD 1.

Baseline Start Search displayed web results for a harmless unmatched query.
After Apply, the existing Search flyout still displayed web suggestions.
A normal-user test helper verified SearchHost owner/session and stopped only
that process; opening Search relaunched it. The query then showed no results
and no Web category. Win+S found local PowerShell apps. Undo plus the same
manual refresh brought web results back; final reapply plus refresh reproduced
the no-results outcome. This supports the effect on this VM after Search
refresh, without claiming an officially guaranteed web-blocking contract.

File Explorer found two matching documentation files in a known repository
folder. The initial FocusedElement locator failed after the search; a
supplemental native-window-handle UI Automation read found both rows, confirmed
by screenshot. SearchHost root/PID enumeration also returned zero UIA roots;
before/after Search results are established by inspected screenshots, not by
those empty element arrays.

Mock and Windows read-only suites passed, as did transaction mocks. CLI plan
created no journal; elevated-only context and normal-user refusal were checked.
Defender AV/realtime/tamper remained enabled; WSearch remained Running. No
service/security/update setting, ACL, package, index or other account changed.
Reboot persistence, content-search coverage, network traffic and update
installation are untested. No reboot/sign-out or Explorer restart ran.
