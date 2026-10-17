# Start pin preflight

Run PowerShell 7 as the normal Explorer user:

```powershell
pwsh -NoProfile -File ./bin/uindos-start-pins-preflight.ps1
```

The sanitized JSON reports Start pin counts by identifier type and whether the
two known WhatsApp/LinkedIn pin identities have matching current-user package
registration. A pin and an installed app are separate observations. The
report always requires manual review; it does not authorize app removal.

The collector supports Windows 11 Pro/Pro N x64 or ARM64, build 22000 or later.
It uses the checked-in helper and inbox Windows PowerShell to export the
current layout and enumerate current-user package families. It requires the
same non-elevated account/session as Explorer and never self-elevates.

Export-StartLayout needs diagnostic files. Default collection creates private
temporary artifacts and removes its exact files and empty temporary directory.
It makes no Windows configuration changes. To retain raw private evidence,
provide a new absolute directory:

```powershell
pwsh -NoProfile -File ./bin/uindos-start-pins-preflight.ps1 -PrivateExportDirectory Z:\private-start-pins
```

The destination must not exist. Directory permissions are inherited; choose
a suitable private location. Artifacts can reveal desktop-shortcut paths and
app identifiers; review them before sharing. Restoration from this diagnostic
evidence still needs validation. The default JSON does not expose arbitrary
pin paths or the full package-family inventory. A failed or incomplete
collection returns a nonzero exit status instead of reporting app absence.

The command does not unpin, install, launch or uninstall apps, apply a layout
policy, change registry/cache databases or restart shell processes. It does
not inventory taskbar pins; taskbar shortcut files alone are incomplete.

The [source and recovery research](research/START-PINS-PREFLIGHT.md) explains
why Start reset/restore and taskbar cleanup remain separate changes. Run
`tests/start-pins-preflight-mock.ps1` for portable parser and privacy checks.

Mock checks and native collection on Windows 11 Pro build 26300.9711 /
PowerShell 7.6.7 passed. Both temporary cleanup and retained private export
were verified in a non-elevated same-Explorer-user session. The VM reported
ten pins, including WhatsApp and LinkedIn with no matching current-user
package-family registration; the exported layout remained unchanged. Elevated
collection and an existing evidence directory were refused with nonzero exit
status, and existing evidence files were unchanged. Other builds and any
reset/restore operation remain untested.
