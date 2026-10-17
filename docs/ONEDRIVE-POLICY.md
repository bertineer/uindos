# OneDrive file-storage policy

The curated Windows 11 Pro baseline disables OneDrive file storage using one
documented machine policy: `HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive`,
`DisableFileSyncNGSC=DWORD 1`. It blocks OneDrive sync and related integration
for users on the device. It does not uninstall the client or guarantee that
Windows, an update, another account or a user cannot install it again.

This is separate from [read-only client inventory](ONEDRIVE-PREFLIGHT.md).
It does not inspect, download, move or delete synced/local files, unlink an
account, run an installer, stop services/processes or restart the shell.

Preview in an ordinary PowerShell 7 session:

```powershell
pwsh -NoProfile -File ./bin/uindos-onedrive-policy.ps1
```

Apply from a temporarily elevated PowerShell process:

```powershell
pwsh -NoProfile -File ./bin/uindos-onedrive-policy.ps1 -Apply
```

Preview requires neither elevation nor `LOCALAPPDATA` and creates no journal.
Apply/Undo require existing temporary elevation; the command never self-elevates.
The curated gate is Windows 11 Pro/Pro N x64/ARM64, build 22000 or later.
OneDrive does not need to be installed to set or undo the policy. Existing
non-DWORD data fails closed. Review management ownership separately on managed
machines; the command does not audit every GPO/MDM authority.

Exact prior value/absence is retained in private journals at
`$env:LOCALAPPDATA\uindos\transactions\onedrive-policy-v1`. Override with
`-JournalDirectory <absolute-directory>` for persistent private storage, and
use the same directory for Undo:

```powershell
pwsh -NoProfile -File ./bin/uindos-onedrive-policy.ps1 -Undo <transaction-guid>
```

Undo restores captured policy state and refuses external drift. It does not
restore an uninstalled application or deleted files. Raw journals belong outside
public Git checkouts; shared VM storage alone does not establish confidentiality.
An empty parent key may remain after restoring prior value absence.

Setting readback and transaction tests are distinct from effective shell/sync
behavior or later reboot/update persistence. With the client already absent,
this work cannot demonstrate a live sync-blocking result without reinstalling
and configuring it. No application is installed to manufacture that test.

Run `tests/onedrive-policy-mock.ps1` for portable transaction checks. See
[policy provenance and rejected reinstall assumptions](research/ONEDRIVE-POLICY.md).

On Pro x64 build 26300.9711, native Apply, unchanged repeat, exact prior-absence
Undo and final reapply passed. Final readback was DWORD1. Preview without
`LOCALAPPDATA` passed in the elevated test context; non-elevated authorization
guards are mocked, not a separately completed native observer test for this
module. Defender AV, real-time and tamper signals remained enabled before/after.
Effective client/shell behavior and later reboot/update persistence are pending.
