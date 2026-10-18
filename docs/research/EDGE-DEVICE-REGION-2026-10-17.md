# Edge removal: operator-supplied DeviceRegion experiment

Windows 11 Pro x64 26H2 build 26300.9711, 2026-10-17 at 23:59 UTC.
The operator proposed a renamed inbox PowerShell executable to change
`DeviceRegion` and enable native Edge removal while preserving WebView2.
This was an explicitly scoped VM experiment, not a production command.

## What the proposed command changes

The proposed command would change one machine device-region DWORD to `0xb0` (176), which
Microsoft's [geographic table](https://learn.microsoft.com/en-us/windows/win32/intl/table-of-geographical-locations)
identifies as Netherlands. The captured prior value was DWORD244 (United
States). It does not add the United States to an eligibility list, change the
user's home-region setting or itself invoke an Edge uninstaller.

The installed `IntegratedServicesRegionPolicySet.json` contains an
`Edge is uninstallable.` rule, disabled by default, whose enabled-region list
contains `NL` and excludes `US`. This list uses country codes, not numeric244.
The file is owned by TrustedInstaller. No file edit, ownership/ACL change,
driver/service disablement or SYSTEM/TrustedInstaller execution was attempted.

Microsoft's [EEA Windows announcement](https://blogs.windows.com/windows-insider/2023/11/16/previewing-changes-in-windows-to-comply-with-the-digital-markets-act-in-the-european-economic-area/)
documents native Edge removal separately from the AD-domain-only
[deployment policy](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-update-policies#uninstall).
The domain condition must not be generalized to every native EEA uninstall.
Directly changing this registry value through a renamed interpreter is not
established as a Microsoft-supported region-selection mechanism.

## Actual result

A private dry run and parser check passed. Before the live experiment, the
controller verified the exact VM build, original DWORD244, an absent temporary
executable path, no browser processes, valid Microsoft executable signatures,
the previously recorded setup/recovery hashes and enabled Defender signals.
It recorded exact prior state and component evidence before making a copy.

The controller created one temporary inbox PowerShell copy and gated its
execution on a matching file hash. It ran the fixed `reg.exe ADD` operation
for DWORD176 in the existing elevated
context. **The registry command returned 1 with `ERROR: Access is denied.`**
The native browser uninstaller was gated on successful region readback and
therefore **never ran**. Edge remains installed; this is distinct from the
[earlier native uninstall attempt](CLIENT-UNINSTALL-2026-10-17.md), which
returned93.

Final independent readback found exact original DWORD244. No restoration write
was needed because the proposed write failed. The controller gated deletion on
a matching copy hash, removed only that copy, and verified absence. WebView2 and
updater executable hashes/signatures, runtime registration, updater service
Start values and the region-policy-file hash matched before/after. Defender
AV, real-time protection and tamper signals remained enabled. No protection
mechanism was identified from this denial alone, and no alternate bypass or
retry followed. Raw reports and child stdout/stderr remain private.

## Answers and remaining limits

Temporarily enabling EEA eligibility, uninstalling the browser and restoring
the original region is a testable proposal, but this attempt failed at its
first registry write. It provides no evidence that uninstall would succeed or
that the browser would remain absent after returning to US, reboot or update.
Microsoft describes [EEA-specific reinstall-prompt behavior](https://blogs.windows.com/windows-insider/2025/06/02/updates-to-windows-for-the-digital-markets-act/);
it is not a persistence guarantee for this proposed workaround.

Adding `US` to the installed rule would be a different, unsupported system-file
modification. It was not attempted under the project's no-ownership/ACL and
no-TrustedInstaller-bypass constraints. No service experiment, new software,
full baseline, reboot, sign-out or host snapshot action occurred. Existing
private recovery evidence remains; no RAM saving or Edge removal is claimed.
