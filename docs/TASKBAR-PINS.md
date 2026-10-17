# Existing taskbar pins

Taskbar app pins are separate from Search/Task View visibility and the Widgets
policy. Removing a pin does not uninstall an application. Running applications
still appear on the taskbar even when no apps are pinned.

For the fresh baseline, use Windows' native taskbar context menu and choose
**Unpin from taskbar** for each unwanted app. Microsoft documents this in
[Customize the Taskbar in Windows](https://support.microsoft.com/en-us/windows/experience/personalization/customize-the-taskbar-in-windows).
Keep Start, the notification area and Explorer fallback available.

Before changes, record app identities/order and preserve any relevant shortcuts
privately. To restore pins, use Windows' **Pin to taskbar** controls for the same
apps and arrange them in the saved order. Neither a layout export nor a registry
backup is a universal layout-restore API. Do not reset Taskband data, delete
shell caches, restart Explorer or uninstall an app to remove its icon.

## Native VM acceptance — 2026-10-17

On Windows 11 Pro x64 build 26300.9711, the current normal Explorer user's
taskbar had three pins: File Explorer, Microsoft Edge and Microsoft Store.
Terminal was running but unpinned. Exact app identities/order, existing shortcut
files and a read-only Taskband export were preserved outside Git.

The normal, non-elevated observer verified its user/session against Explorer,
focused each known taskbar app, opened its native jump list and invoked only
the verified **Unpin from taskbar** control. Each removal was checked before
continuing. All three pins were removed; final UI Automation reported zero
pinned app buttons. Screenshot review showed only the running Explorer and
Terminal buttons beside Start. Their windows remained available. Current-user
package-family sets were identical before/after; no apps were removed.

No registry data was imported/deleted, no service/process was stopped, and no
shell restart, sign-out, reboot or software installation occurred. Private
backups/screenshots and the VM-specific driver are retained outside Git.
Repinning/reordering was not performed as a rollback test; these observations
do not claim automatic exact-layout recovery, other-user cleanup or persistence
across a future sign-in/update. Start pin reset is a separate operation.

This is a validated manual cleanup procedure, not a production all-user pin
reset command. Policy-created pins and user-created pins need distinct handling
in a future combined runner. No physical-memory saving is claimed from icons
being unpinned.
