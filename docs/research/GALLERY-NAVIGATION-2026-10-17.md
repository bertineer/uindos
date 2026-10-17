# Gallery navigation experiment — 2026-10-17

On Windows 11 Pro 26H2 x64 build 26300.9711, the requested Gallery navigation
entry was hidden for the current user. This is an experiment with a local
registry mapping, not a Microsoft-supported Gallery policy or a portable default.
No generic production command is added.

## Identity and scope

The installed machine class
`HKLM\SOFTWARE\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}`
had `System.IsPinnedToNameSpaceTree=DWORD 1`. Its `LocalizedString` resource
resolved through the native `SHLoadIndirectString` API to **Gallery**.
The matching current-user class key was absent before the experiment.

The experiment created only
`HKCU\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}`
with `System.IsPinnedToNameSpaceTree=DWORD 0`. It preserved the machine class,
namespace registration, Gallery component and photo files. It performed no
package removal, Explorer restart, ownership/ACL change or service change.

Microsoft documents the shell pinning property's meaning, but its page does
not document this writable Gallery override on Windows 11. No Gallery-only
policy or native hide command was established in the reviewed sources/UI.
The installed class identity and subsequent UI cycle provide local evidence;
they do not establish support on other Windows builds.
[Property documentation](https://learn.microsoft.com/en-us/windows/win32/properties/props-system-ispinnedtonamespacetree).

## Observed cycle and rollback

The normal-user driver checked its Explorer user/session, exact build, machine
class identity and prior absence. It reused uindos's transaction engine from
revision `fb29ce1` with a private adapter restricted to this single value.

- Read-only preview showed one proposed change.
- Apply wrote DWORD0; a new Explorer window opened This PC with Gallery absent.
- Repeat returned unchanged.
- Undo restored exact value absence with zero conflicts. The newly created
  empty user class key was also removed, restoring its prior absence. Gallery
  reappeared in a newly opened Explorer window.
- Final application wrote DWORD0 again; readback matched, and Gallery was
  absent in a new window. This PC, drives and the shared drive remained visible.

The visual results were reviewed from private screenshots. Automated native
navigation-tree enumeration was inconclusive and is not counted as passing.
Existing windows can retain their previous navigation view; the checks above
used new windows. Later reboot/update persistence remains unverified.

Private journals retain the active final transaction and exact prior absence.
Undo must validate the current value against the journal and preserve external
drift. Remove the created user key only if it is still empty and was absent
originally. Do not remove the machine class or other namespace registrations.
The old transaction used in the completed Undo is not the active final one.

This changes navigation visibility, not the opening view or photo storage.
The separate **Open File Explorer to This PC** native option was also verified.
No RAM saving or network/privacy guarantee follows from hiding the entry.
