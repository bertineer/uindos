# Cross-device continuation policy

The curated privacy baseline sets only machine `EnableCdp=DWORD 0` under
`HKLM\SOFTWARE\Policies\Microsoft\Windows\System`. This is the documented
**Continue experiences on this device** policy. After a coordinated reboot,
Windows should stop this device participating in cross-device continuation
and being discoverable for those experiences. Microsoft also states that
disabling this policy prevents Windows settings backup. This deliberate cloud
integration tradeoff does not delete local files or existing backups.

Preview without elevation or writes:

```powershell
pwsh -NoProfile -File ./bin/uindos-shared-experiences.ps1
```

Apply from a temporarily elevated PowerShell 7 process:

```powershell
pwsh -NoProfile -File ./bin/uindos-shared-experiences.ps1 -Apply
```

The command gates on Windows 11 Pro/Pro N x64/ARM64, build 22000 or later.
Apply refuses domain membership, an unparsed machine Registry.pol, relevant
current-device PolicyManager signals, or unreadable required authority checks.
Enrollment/provider artifacts are informational: a clear result means only
that these bounded checks observed no conflict, not a complete MDM audit.
Review management ownership independently before use on a managed device.
Existing non-DWORD target data fails closed.

Private exact-state journals default to
`$env:LOCALAPPDATA\uindos\transactions\shared-experiences-v1`. Use an absolute
`-JournalDirectory` outside the public checkout for durable private storage.
Undo from an elevated process with the same directory:

```powershell
pwsh -NoProfile -File ./bin/uindos-shared-experiences.ps1 -Undo <transaction-guid>
```

Undo restores the captured prior value or absence and refuses external drift.
It deliberately permits recovery without repeating management classification.
An empty parent key may remain. Reboot coordination is separate; this command
never reboots, restarts the shell or self-elevates.

This policy does not disable CDPSvc/CDPUserSvc, configure Phone Link's separate
policy, remove apps, modify Windows Update or security settings, or establish
RAM savings. `Connectivity/AllowConnectedDevices` and CrossDeviceResume CSP
settings are separate controls; no undocumented registry mappings are used.
Registry transaction success is distinct from post-reboot behavior acceptance.

Run `tests/shared-experiences-mock.ps1` for portable guard and transaction
checks. See [source provenance](research/SHARED-EXPERIENCES.md).

On Pro x64 26300.9711, native Apply, unchanged repeat, exact prior-absence
Undo (zero conflicts) and final reapply passed. Final readback was DWORD0;
preview without LOCALAPPDATA passed. CDP service state/start mode stayed
unchanged, and Defender AV/realtime/tamper signals remained enabled. Portable
tests cover non-admin denial, blocked/unknown authority, prior DWORD recovery,
write failure and drift. Production adapter read and intercepted-write checks
passed without extra registry changes. Reboot and paired-device behavior
acceptance remain pending; these results establish no memory savings.
