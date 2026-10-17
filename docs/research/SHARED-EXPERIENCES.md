# Cross-device participation policy provenance

Reviewed 2026-10-17. Target: a fresh Windows 11 Pro installation, before cloud
accounts and daily-use applications. Expected benefit is reducing optional
cross-device participation; no causal RAM or traffic reduction is established.

- Microsoft's [ADMX_GroupPolicy EnableCDP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-grouppolicy#enablecdp)
  documents machine scope, Pro support on Windows 11 21H2 (22000) and later,
  the `Software\Policies\Microsoft\Windows\System` / `EnableCdp` mapping,
  participation/discoverability effects and reboot requirement.
- The VM's `C:\Windows\PolicyDefinitions\GroupPolicy.admx`, SHA-256
  `E30ACB08B99096293A4A10C3EC16D21D30806BC6BD3259FE6BD7DDA29D635CFC`,
  maps EnableCDP to that machine DWORD: enabled 1, disabled 0.
- Microsoft's [Windows settings backup overview](https://learn.microsoft.com/en-us/windows/configuration/windows-backup/)
  states that disabling EnableCDP or AllowConnectedDevices prevents settings
  backup. This broad cloud integration loss is part of the selected default.
- Microsoft's [Connectivity CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-connectivity)
  defines AllowConnectedDevices separately: disabling it makes the CDP service
  unavailable after reboot. That service contract must not be attributed to
  EnableCDP. AllowPhonePCLinking uses separate EnableMmx; it is not configured.
  DisableCrossDeviceResume is user scope and Insider Preview only, requires
  reboot, and has no registry mapping on that page. No mapping is guessed.

Implementation reuses the MIT-licensed local transaction engine and patterns
from OneDrivePolicy at repository revision
`a43ee886e4e2a99f80acfe5e2caa703bdd683c69`; no external code or binary is bundled.
The module owns exactly one machine value, preserves its prior kind/data or
absence, rejects other targets, and retains the engine's recovery/drift checks.
Apply is guarded by bounded domain/local-policy/current PolicyManager probes;
artifact counts alone cannot prove active management or absence of management.

Before Apply, native read-only inspection on Pro x64 26300.9711 found EnableCdp
absent, domain membership false, machine Registry.pol absent and the relevant
current-device PolicyManager roots absent. Enrollment/provider artifacts exist,
so the device is not categorically described as unmanaged. CDPSvc and the
current CDPUserSvc instance were running; neither is changed by this module.

Validation must distinguish portable transaction/guard tests, exact native
readback and rollback, post-reboot discoverability/continuation acceptance,
Windows settings backup loss, and controlled-idle performance. No reboot or
paired-device acceptance is implied by writing the registry value. Preserve
Defender, servicing, local Search and Explorer throughout validation.
