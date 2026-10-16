# Taskbar visibility and pinned-app policies

The taskbar command manages only current-user Search and Task View visibility preferences. Widgets use a separate device policy command; this split keeps the TaskbarDa write failure from blocking unrelated per-user settings. Neither command deletes packages, disables Windows Search, nor modifies app pins.

## Usage (PowerShell 7, normal user)

```powershell
pwsh -NoProfile -File ./bin/uindos-taskbar.ps1
pwsh -NoProfile -File ./bin/uindos-taskbar.ps1 -Apply
pwsh -NoProfile -File ./bin/uindos-taskbar.ps1 -Undo <transaction-guid>
```

The command defaults to a read-only plan. Apply journals exact prior values under %LOCALAPPDATA%\uindos\transactions\taskbar-v1; undo restores the prior absent or DWORD state unless another actor changed it. Sign out/in if Explorer has not refreshed the taskbar. Group policy may override these personal preferences. Older taskbar-v1 journals that include `TaskbarDa` remain valid for Undo; new taskbar plans do not target it. Use [Widgets policy](WIDGETS.md) separately.

## Removing pinned applications

Clearing current-user taskbar and Start pins is a separate concern from hiding taskbar UI elements. This module deliberately does **not** delete Explorer Taskband binary values, Start menu shell-state databases (start2.bin) or pinned shortcut folders. Such methods are build-sensitive and can corrupt an existing Windows profile.

Microsoft supports an empty Start pinned list via Configure Start Pins policy (JSON pinnedList: [], optionally applyOnce: true on recent 24H2+ builds). A deployed policy may need a sign-out and does not guarantee restoration of preexisting user pins when removed. This must be backed up and validated separately on the disposable VM before automation.

Windows taskbar PinListPlacement=Replace XML is supported for managed layouts, but Microsoft states that previously **user-pinned** apps can remain on upgraded/existing profiles. Do not claim an XML policy fully clears an existing user's taskbar. Avoid the NoPinningToTaskbar policy because it prevents users from changing pins but does not clear them.

For now, use right-click > Unpin from Start and right-click > Unpin from taskbar for existing user pins, without requiring a permanently enforced policy.

Sources:
- https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11
- https://support.microsoft.com/en-us/windows/experience/personalization/stay-up-to-date-with-widgets-in-windows
- https://learn.microsoft.com/en-us/windows/configuration/start/layout
- https://learn.microsoft.com/en-us/windows/configuration/taskbar/pinned-apps
