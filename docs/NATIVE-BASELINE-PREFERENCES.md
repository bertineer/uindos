# Native Windows preferences

This record covers user-selected Settings and File Explorer options on Windows
11 Pro 26H2, build 26300.9711. Start, Taskbar, and Start folder choices were
applied, restored to their captured choices, reapplied and verified after
reopening Settings. These are native preference procedures, not a combined
production runner.

| Area | Requested setting | Status |
| --- | --- | --- |
| Taskbar | Resume badge: Off | Applied/read back; this is the taskbar UI choice only. |
| Start | Pinned section Off; All apps On | Applied/read back. |
| Start | Recently added apps Off | Applied/read back. |
| Start | Recent/suggested files section Off | Applied/read back. |
| Start | Tips and app recommendations Off | Applied/read back. |
| Start | Menu size Small | Applied/read back. |
| Start | Account-related notifications Off | Applied/read back. |
| Start | Recently opened items in Start, Jump Lists, and File Explorer Off | Applied/read back. |
| Start folders | Settings and Network On; File Explorer, Documents, Downloads, Music, Pictures, Videos and Personal folder Off | Applied/read back. |
| Windows Update | “Get the latest updates as soon as they're available” Off | Already Off; read-only verification, no update setting changed. |
| File Explorer | Open File Explorer to This PC | Applied through Folder Options; Home restoration and final This PC reopen checks passed. |
| File Explorer | Hide Gallery navigation item | Per-user experiment passed on this build; see [scope and recovery limits](research/GALLERY-NAVIGATION-2026-10-17.md). |

Turning off recent-item display does not promise deletion or reconstruction of
recent-file history. Undo restores captured UI choices only when the user has
not changed them since Apply. Private journals retain prior choices; they are
not public evidence artifacts.

The VM uses a local account. Account-dependent features may not appear in this
context. Turning off the Taskbar Resume badge does not prove all cross-device
Resume capabilities are unavailable. No memory savings or security/update
service changes are claimed. The early-delivery switch being Off preserves
normal security updates and is not a Windows version hold or a promise that
future cumulative updates contain no new features.

Start's final screenshot showed the compact All apps view and only Network
and Settings shortcuts beside Power. The fresh pin export remained empty.
The recent/suggested-files and Jump List preferences showed linked behavior
during restoration; the journal retained the initial guard stop and a separate
read-only check confirmed all captured prior choices before final reapplication.

Final regression checks found PowerShell through local Search, no visible web
results for one unmatched query, and two expected Explorer filename matches.
Start still exported zero pins and the taskbar inventory showed no app pins.
Baseline10 completed all 13 probes: AppX counts stayed 95 current-user / 91
all-user / 27 provisioned, with seven Win32 entries. Defender antivirus,
real-time and tamper protection, all firewalls and Secure Boot remained enabled;
service startup modes matched the captured pre-change inventory. BitLocker was
fully encrypted with protection Off, its previously observed state.
No new online Windows Update scan or idle-memory capture was performed.

For the separately documented Share app preference, see
[Share app suggestions](SHARE-SUGGESTIONS.md).
