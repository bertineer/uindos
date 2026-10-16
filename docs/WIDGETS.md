# Widgets policy

uindos offers one device-level Widgets control for Windows 11 Pro/Pro N x64 or ARM64, build 22000 and later. Microsoft documents the `AllowNewsAndInterests` device policy at `HKLM\SOFTWARE\Policies\Microsoft\Dsh`; setting its DWORD value to `0` disables the News and Interests experience. The local Microsoft `NewsAndInterests.admx` policy template maps this setting to the same registry value.

The command previews without elevation. Apply and Undo require an already elevated PowerShell 7 process; the command never elevates itself. A transaction journal under `%LOCALAPPDATA%\uindos\transactions\widgets-v1` records the exact prior value, and Undo restores either its prior absence or DWORD value if no other actor changed it. When the policy key did not exist before Apply, Undo removes the managed value but can leave the newly created empty `Dsh` key; the transaction engine journals values, not key existence.

```powershell
pwsh -NoProfile -File ./bin/uindos-widgets.ps1
pwsh -NoProfile -File ./bin/uindos-widgets.ps1 -Apply
pwsh -NoProfile -File ./bin/uindos-widgets.ps1 -Undo <transaction-guid>
```

The supported policy is a separate route after the per-user `TaskbarDa` write was denied on the tested VM. That denial is proven; its mechanism remains unknown. On Windows 11 Pro build 26300.9711, policy Apply, repeat Apply and Undo passed, with original value absence restored. After reapplying the policy alongside the separate taskbar defaults, UI Automation no longer found the previously visible Widgets, Search or Task View buttons. No Explorer restart or sign-out was needed for that observation.

Apply/Undo tests used an existing elevated token. Subsequent non-elevated previews passed, Win+W did not open a Widgets board, and Win+S still returned local applications. Lock-screen and reboot persistence remain untested. A successful registry write alone is not proof of those outcomes. Windows 11 lock-screen and board-specific policies remain preview according to the linked CSP documentation and are not included. Widgets runtime packages were preserved. See [the initial investigation](research/WIDGETS-POLICY.md) and [post-merge acceptance](research/VM-ACCEPTANCE-2026-10-16.md).

Source: [Microsoft News and Interests Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-newsandinterests) (device scope; Pro support from Windows 11 version 21H2). The registry mapping also appears in the local `NewsAndInterests.admx` template. Local write-boundary observations are recorded in the taskbar investigation prepared with this feature.
