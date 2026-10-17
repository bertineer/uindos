# Edge background policy provenance

Reviewed 2026-10-17 for Windows 11 Pro x64 build 26300.9711 and installed Edge
Stable 155. The implementation reuses the allowlisted registry transaction
design from repository commit `3792e5b2a3eb1ae7472076f3f6c993d4d29977ac`
(`Widgets.ps1`, `RegistryAdapter.ps1`, `Transactions.ps1`). No third-party
implementation or binary is downloaded or executed.

Microsoft primary policy references, read before implementation:

- [StartupBoostEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/StartupBoostEnabled):
  Windows Edge 88+, mandatory policy DWORD in `SOFTWARE\Policies\Microsoft\Edge`.
  Disable with zero to prevent Startup Boost. Dynamic refresh supported.
- [BackgroundModeEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/BackgroundModeEnabled):
  Windows Edge 77+, mandatory policy DWORD at the same path. Disable with zero
  to turn off background mode. Dynamic refresh supported. Background browser
  applications and session cookies otherwise may remain active after closing
  the last browser window.

Both references identify `MSEdge.admx` and the exact matching registry names.
The Microsoft Learn edit links pointed to unavailable GitHub source pages on
this review, so no documentation source commit is invented. The URLs are
living references; verify them when updating the supported behavior.

Live discovery found `msedge.exe --no-startup-window --win-session-start`
with no visible browser top-level window. This is a concrete candidate for
reduced background work. Shared working sets cannot be summed into unique
RAM savings. Edge policy settings do not disable the WebView2 runtime or its
update path, and no Edge Update policies/services are targeted.

Do not substitute service deletion for the policy pair. Service triage identified
CrossDeviceResume as an application, and left `whesvc` responsibilities uncertain.
Microsoft's [Connectivity CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-connectivity)
documents broader CDP disablement and an Insider-only Resume policy with reboot
requirements; these are separate compatibility questions. Event Log, local
Search/indexing, input, Defender and update infrastructure remain preserved.

Validation must distinguish exact policy Apply/repeat/Undo from effective
browser behavior, sign-in persistence, controlled-idle resource measurements
and actual network privacy. These two policies do not establish zero telemetry.
