# OneDrive policy and reinstall claims

Reviewed 2026-10-17 for Windows 11 Pro x64 26H2 build 26300.9711.

[Microsoft System CSP — DisableOneDriveFileSync](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-system#disableonedrivefilesync)
supports the device policy on Pro from Windows 10 1703 onward. Its Group Policy
mapping is `PreventOnedriveFileSync` in `SkyDrive.admx`, at
`SOFTWARE\Policies\Microsoft\Windows\OneDrive\DisableFileSyncNGSC`.
The documented enabled state is DWORD1; it restricts file storage/sync and
related shell/app integration. Installation prevention is not its stated
contract. [Microsoft's startup troubleshooting](https://support.microsoft.com/en-us/onedrive/onedrive-won-t-start)
also identifies this policy as a cause of OneDrive not starting/syncing.

The installed build's `SkyDrive.admx` confirms machine scope, registry name
and enabled DWORD1/disabled DWORD0. SHA-256 of that template:
`F1B5CF320D6E733814554AE297B09FC43DA9EBBFA74F9782631645D8C8379D42`.
The registry transaction implementation is derived from repository commit
`3792e5b2a3eb1ae7472076f3f6c993d4d29977ac` (Widgets adapter and core engine).
No remote mutable script or third-party implementation is executed.

Two separately suggested registry names were not added:

- `HKLM\SOFTWARE\Microsoft\EdgeUpdate\DoNotUpdateToEdgeWithChromium`:
  current [Edge Update documentation](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-update-policies)
  references the old Blocker Toolkit in its legacy migration discussion. No
  current contract was established that this value prevents modern Windows 11
  browser reinstallation. The installed browser remains after a refused native
  uninstall. Preserve its updates and the shared WebView2 updater.
- `HKCU\Software\Microsoft\OneDrive\PreventDiscoveryOnLaunch`: no current
  Microsoft policy contract or matching installed ADMX definition was found.
  Its behavior and any reinstall-prevention effect remain unverified. Registry
  existence alone would not validate that assumption.

Neither setting is silently replaced with a similarly named policy. The
documented `PreventNetworkTrafficPreUserSignIn` is a different machine policy
with a different purpose; it is not an installer prohibition.

Exact policy Apply/repeat/Undo and readback can be validated independently of
client installation. The fresh VM's OneDrive client was already removed before
this policy work. Effective UI/sync, reboot and post-update persistence therefore
remain separate acceptance questions. No permanent-reinstall-blocking or
zero-network-traffic claim follows from this registry value.
