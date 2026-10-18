# Post-reboot shell acceptance — 2026-10-18 UTC

Windows 11 Pro x64 26300.9711; current boot 2026-10-17 21:31:18.5 UTC.
These are bounded observations after the operator's reboot, not a new memory
benchmark or a general update-persistence guarantee. No preference was changed.

Normal-user observers matched the ordinary Explorer user/session. Native
readbacks retained Small Start, Pinned Off, recent-app/file/tip/account and
Jump List preferences Off, All On, Settings/Network folder shortcuts On and
the other seven shortcuts Off. The separate Recent layout toggle remains On;
it was not one of the earlier changed controls. Taskbar Resume and Share app
suggestions remain Off. Fresh Start export contains zero pins; taskbar shows
only running applications and zero pinned app buttons. The compact Start and
folder icons were visually reviewed.

Folder Options still selected This PC, and a separately opened ordinary
Explorer window visibly opened This PC. Gallery was absent from that new
window's navigation pane. The scoped per-user Gallery experiment remains
separate from a supported general policy. The observer preserved preexisting
Explorer windows and closed only the newly opened test window.

Local PowerShell app results appeared. One unmatched synthetic query showed
No results found and no visible web results; this does not establish a network
or universal web-search guarantee. Explorer filename search returned both
expected SEARCH-SUGGESTIONS.md files.

The Search flyout displayed an indexing-off banner while WSearch was Running
with automatic delayed start. Native Indexing Options independently reported
Indexing complete and 27,716 indexed items. The banner's cause is unresolved;
service state alone was not used as proof of catalog health. A separate COM
activation attempt could not obtain catalog status in either PowerShell host;
that limitation does not establish index damage. No reindex, catalog reset or
service change was attempted.

Fresh baseline11 completed all 13 probes. Current/all-user/provisioned AppX
counts remained95/91/27; Win32 entries remained7. Defender AV/realtime/tamper,
all firewalls and Secure Boot were enabled. BitLocker remained fully encrypted
with Protection Off, the recorded pre-existing state. This collector does not
perform an online Windows Update health scan, Store download or memory test.

Private screenshots, raw reports and observer scripts remain outside Git.
Later update persistence, paired-device/backup behavior, fresh comparable idle
captures and the proposed SysMain trial remain pending. See the
[comparison protocol](SYSMAIN-COMPARISON.md).
