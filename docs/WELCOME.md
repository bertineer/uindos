# User-level Windows 11 welcome and suggestion preferences

**Status:** PR #12, requires VM observation after sign-in and Windows feature updates. These are **best-effort user preferences**, not supported Enterprise-only policies on Windows 11 Pro.

| User preference | Exact registry DWORD set to 0 |
| --- | --- |
| Show Windows welcome experience after updates | `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SubscribedContent-310093Enabled` |
| Get tips and suggestions when using Windows | `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SubscribedContent-338389Enabled` |
| Suggest ways to finish setting up this device | `HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement\ScoobeSystemSettingEnabled` |

Microsoft documents the user-facing Settings > System > Notifications > Additional settings UI. The registry mappings are supported by independent Windows customization research and by Microsoft's VDI documentation for ScoobeSystemSettingEnabled. Do **not** claim these controls completely disable Windows OOBE or all welcome experiences. Initial Windows setup, security notifications and Windows Update remain fully functional.

Run on Windows 11 Pro from PowerShell 7 **under the intended user account**:

```powershell
# Read-only preview
pwsh -NoProfile -File ./bin/uindos-welcome.ps1
# Journaled apply
pwsh -NoProfile -File ./bin/uindos-welcome.ps1 -Apply
# Restore exact previous values, if unchanged by others
pwsh -NoProfile -File ./bin/uindos-welcome.ps1 -Undo <transaction-guid>
```

The journal is in `%LOCALAPPDATA%\uindos\transactions\welcome-v1`. No files, services, packages, HKLM keys or other-user profiles are modified. The fixed allowlist prevents arbitrary registry changes. Apply and Undo use the existing idempotent transaction engine, supporting previously absent and nonzero values. An unchanged plan is a no-op. UI reflection may require sign-out.

Acceptance on Windows 11 Pro 26H2: preview, apply, observe Settings checkboxes and post-update welcome behavior, repeat/undo, inspect journal, check login/Windows Update/Defender/Store/notifications remain functional. Registry readback is **not** proof of the UI effect; recheck after upgrades.

Policy note: `DisableWindowsSpotlightWindowsWelcomeExperience`, `DisableSoftLanding`, `DisableWindowsConsumerFeatures` and similar CSP/GP settings are not supported on standard Pro; they are intentionally not written here. Windows Location setting is untouched.

Sources:
- Microsoft Notifications UI: https://support.microsoft.com/en-us/windows/turn-off-notifications-about-device-setup-c88f6943-d169-23ca-5f3f-c6b927509e79
- Microsoft Pro support matrix: https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience
- Community reference mapping: https://github.com/Raphire/Win11Debloat/blob/25c3999be54e358bb7343a72223e4b1110e64e61/Regfiles/Disable_Windows_Suggestions.reg
- Microsoft VDI guidance: https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration
