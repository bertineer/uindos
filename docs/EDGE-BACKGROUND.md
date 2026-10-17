# Edge background activity

The curated default disables Edge browser Startup Boost and background mode.
It addresses browser processes that start at sign-in or remain after the last
browser window closes. It preserves Edge Update, WebView2, SmartScreen and
ordinary browser launch. Disabling these browser features may slow the first
browser launch and stops browser background applications after window closure.
It does not promise a fixed memory saving or eliminate Microsoft traffic.

Preview from an ordinary PowerShell 7 session:

```powershell
pwsh -NoProfile -File ./bin/uindos-edge-background.ps1
```

Apply from a temporarily elevated PowerShell process:

```powershell
pwsh -NoProfile -File ./bin/uindos-edge-background.ps1 -Apply
```

The command manages exactly two machine policy DWORDs under
`HKLM\SOFTWARE\Policies\Microsoft\Edge`: `StartupBoostEnabled=0` and
`BackgroundModeEnabled=0`. Preview and Apply require Windows 11 Pro/Pro N,
x64/ARM64, and a valid Microsoft Edge Stable version of at least 88 in the
machine Edge Update Clients registration. This deliberately narrow detector
does not claim to support other Edge channels or per-user installations.

Preview reads state without creating a journal or requiring `LOCALAPPDATA`.
Apply/Undo never self-elevate. An existing non-DWORD policy fails closed.
Review existing GPO/MDM ownership before Apply on any managed machine: this
command does not audit all policy authorities or supersede management.

Apply saves exact prior values/absence to private transaction journals under
`$env:LOCALAPPDATA\uindos\transactions\edge-background-v1`. Use
`-JournalDirectory <absolute-directory>` for a persistent private alternative,
and keep that same directory for Undo. A shared VM folder does not establish
host-side confidentiality; keep journals outside public Git checkouts.

```powershell
pwsh -NoProfile -File ./bin/uindos-edge-background.ps1 -Undo <transaction-guid>
```

Undo restores captured policy values and refuses conflicting external drift.
It remains available if Edge is subsequently removed. Removing a previously
absent value may leave an empty parent registry key. The command does not
close tabs, terminate browser processes, alter services, install software,
or reboot. Both policies support dynamic refresh, but policy readback alone
does not prove that already running background processes exited. Inspect
`edge://policy`, browser settings and later sign-in behavior independently.

Run `pwsh -NoProfile -File ./tests/edge-background-mock.ps1` for mocked
transactions and adapter guards. See [sources](research/EDGE-BACKGROUND.md).

The baseline optimization phase permits no new software except Git and GitHub
CLI until the Windows baseline is optimized. PowerToys, Everything, tilers and
replacement browsers remain later work. The target is less than 2 GB used
physical memory at controlled idle; report decimal GB and binary GiB explicitly,
retain security/servicing/core functionality, and do not subtract guessed agent
overhead or empty working sets to manufacture a result.
