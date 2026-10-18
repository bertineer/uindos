# Read-only SysMain preflight

Inspect the fixed SysMain service before considering an isolated performance
comparison. This command queries state; it cannot stop, start or configure a
service, change a registry value, or reboot Windows.

```powershell
pwsh -NoProfile -File ./bin/uindos-sysmain-preflight.ps1
```

Run from the repository root with existing PowerShell 7. Normal-user and
elevated observations on Pro x64 build 26300.9711 collected all sources. The
command does not request elevation. It accepts no service-name or change flag.

The JSON schema is `uindos.sysmain-preflight/v1`. It reports:

- Pro/Pro N applicability, architecture and exact build/revision;
- SysMain state, SCM start mode and process ID;
- exact registry Start type/data and DelayedAutoStart presence/type/data;
- immediate dependencies/dependents and SCM/registry consistency;
- individual source outcomes and an overall collection outcome.

`collection=complete` means the four reads validated and agreed. Missing,
malformed, denied or failed sources remain distinguishable from a complete
observation. Non-Windows and unsupported Windows editions/builds are reported
as unsupported. Provider exception messages, accounts, host names, binary paths
and command lines are excluded. Treat local service metadata as private when
recording a report; no upload or report file is created by default.

The exact distinction between an absent DelayedAutoStart value and DWORD0 is
retained for later recovery design. Complete collection is not permission or a
claim that disabling SysMain improves performance. A one-service PID's working
set is not recoverable RAM. No service writer or automatic rollback command is
included in this preflight.

See the [comparison protocol and source limits](research/SYSMAIN-COMPARISON.md)
and [post-reboot acceptance](research/POST-REBOOT-CHECKPOINT-2026-10-18.md).

Validation:

```powershell
pwsh -NoProfile -File ./tests/sysmain-preflight-mock.ps1
```

The portable mocks exercise incomplete/failed sources, unsupported platforms,
exact DWORD/absence handling, numeric bounds, inconsistent observations and
private-error suppression. The dedicated workflow runs them on Windows and
Ubuntu. VM observations supplement these mocks; other builds and ARM64 have
not been tested on-device.
