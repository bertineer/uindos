# PR #5 policy verification and risk inventory

Researched 2026-10-16. Source references and Windows edition limitations are part of the implementation contract. The source documents the intention and applicability; CI checks execution of the code, **not** empirical Windows privacy outcomes.

## Policy A: Tailored experiences

Official: [Experience CSP — AllowTailoredExperiencesWithDiagnosticData](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowtailoredexperienceswithdiagnosticdata). The user-scoped policy supports Windows 11 Pro. Group Policy name: "Do not use diagnostic data for tailored experiences"; key `Software\Policies\Microsoft\Windows\CloudContent`, value `DisableTailoredExperiencesWithDiagnosticData`, enabled=1.

Documented limitation: this reduces personalization derived from diagnostic data, **not** the presence of recommendations, Windows diagnostics or Microsoft traffic. Windows may still show tips and offers.

## Policy B: Third-party suggestions in Spotlight

Official: [Experience CSP — AllowThirdPartySuggestionsInWindowsSpotlight](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowthirdpartysuggestionsinwindowsspotlight). The user-scoped policy supports Windows 11 Pro. Group Policy name: "Do not suggest third-party content in Windows Spotlight"; same key, `DisableThirdPartySuggestions`=1.

Documented limitation: Microsoft feature and service suggestions may persist. The policy does **not** universally disable Windows Spotlight or the Windows lock screen.

## Preference C: Advertising ID

The official [Privacy CSP — DisableAdvertisingId](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy#disableadvertisingid) describes a **device** policy `HKLM\Software\Policies\Microsoft\Windows\AdvertisingInfo\DisabledByGroupPolicy` (DWORD 1), supported on Windows Pro, and the Windows Settings UI allows users to disable advertising-ID personalization. v1 intentionally **does not set the HKLM policy** to avoid administrator privileges and broader scope.

The per-user `HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo\Enabled`=0 implementation is inherited conceptually from [Win11Debloat](https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Regfiles/Disable_Telemetry.reg). **This exact per-user registry location is not established as an officially supported Windows 11 Pro policy through the referenced Microsoft CSP documentation.** Treat as best-effort, with GUI and outcome verification still required. Its change only affects the current user and does not prevent Microsoft account-targeted advertising.

## Test matrix (not yet completed)

| Check | Method | Acceptance |
| --- | --- | --- |
| Pro x64 24H2/25H2/26H2 | Check OS gates and policies in a disposable VM on available supported builds | Targeted actions identified; no unsupported policy claims |
| Preview with missing DWORD values | Run `bin/uindos-privacy.ps1` without flags | No HKCU writes, no journal directory |
| Apply and replay | Run `-Apply` twice | Exact 3 values set; second call returns unchanged |
| Undo | Run `-Undo <actual GUID>` | Original values and types restored; external changes preserved |
| Machine/user boundaries | Inspect registry and Defender/service status | No HKLM, update, Defender, Edge, or other user changes |
| Group Policy precedence | Compare resultant policy / Settings UI after GP refresh | Report any overridden or ignored user value, do not misreport effective state |
| Update resilience | Install a normal cumulative update and re-run read-only preview | No Windows Update regression; explicit detection of drift |
| Reboot/sign out | Re-run preview, observe user UI | No false policy persistence guarantee |

## Prior-DWORD journal restoration — 2026-10-17

PowerShell 7.6.7 on the Windows 11 Pro build 26300.9711 VM reproduces
`('{"value":7}' | ConvertFrom-Json).value` as `System.Int64`. The original
Privacy Write guard accepted only `System.Int32`, so Undo of a previously
existing DWORD failed while Undo of an originally absent value succeeded.
See the official [ConvertFrom-Json reference](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-7.6);
the numeric runtime type here is an observed result, not a promised cross-version
JSON contract.

The [RegistryKey.GetValue API](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registrykey.getvalue)
and [pinned .NET implementation](https://github.com/dotnet/runtime/blob/d099f075e45d2aa6007a22b71b45a08758559f80/src/libraries/Microsoft.Win32.Registry/src/Microsoft/Win32/RegistryKey.Windows.cs)
provide the registry representation context: DWORD data is read as a signed
32-bit integer. This source is explanatory, not proof that the VM runs that
exact .NET revision. The adapter already captures DWORDs as `[int]`; restoring
the signed range preserves every prior DWORD bit without allowing QWORD data.

The fix accepts only Int32 or Int64 within signed Int32 bounds, then passes an
Int32 to the DWORD provider write. The fixed three desired defaults and target
allowlist are unchanged. It requires no elevation, service modification or
journal migration. Existing private journals remain compatible; guarded Undo
still refuses external drift.

Regression coverage: saved/reloaded prior values 7, -1, Int32.MinValue and
Int32.MaxValue restore exactly through the transaction engine; invalid types
and out-of-range values are rejected. Real-adapter tests intercept the registry
provider boundary and confirm Int32 reaches it. Mock/privacy Windows read-only
and transaction suites passed locally. No live privacy Apply/Undo ran for this
fix; effective policy, Group Policy precedence and reboot acceptance remain
separate VM work.

## Security constraints for future expansions

Do not broaden the production adapter through a generic path prefix or by allowing arbitrary `HKCU` writes. Any new rule needs an explicit ID/path/name/type/value allowlist and separate acceptance tests. Store journals under the current user's profile and never upload them. No broad download, stop service, or shell exec capability is introduced.

**Not implemented:** device advertising ID Group Policy, privacy settings for other accounts, disabling optional diagnostics, task/deprovisioning operations, Edge and Copilot removal, post-update reconciliation. Those remain in the roadmap.
