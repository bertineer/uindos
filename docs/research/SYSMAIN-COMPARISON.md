# SysMain: comparison protocol and source applicability

Status: read-only preflight implemented; no service change or performance trial
has run. Tested observation: Windows 11 Pro x64 26300.9711, SysMain Running,
Automatic, Start DWORD2, DelayedAutoStart absent, immediate dependencies FileInfo
and RpcSs, no registered dependents. Registered dependency lists do not reveal
every application or OS consumer.

Microsoft's [VDI configuration guidance](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration)
says to evaluate SysMain per environment. Its storage and nonpersistent-desktop
assumptions do not establish a benefit on this persistent VM. The previous
73.2 MiB host working set is not a savings estimate. Preserve security,
servicing, local Search, input and the Explorer fallback throughout testing.

The preflight uses fixed, read-only [Win32_Service](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-service)
and [Get-Service](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-service)
queries, plus a registry subkey opened with writable=false. Microsoft's
[OpenSubKey API](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registrykey.opensubkey)
documents that read/write distinction. Registry values are read without
environment expansion, with exact types and absence preserved. These APIs
establish state, not service tuning advice. The allowed platform range is Pro
or Pro N x64/ARM64 build22000+, with only the stated x64 VM tested on-device.

## Proposed comparison

1. Keep SysMain enabled. Coordinate a fresh restart, sign in and launch the
   existing private sampler before opening the agent. Record preflight, build,
   boot time and relevant background activity. Use 120 seconds settling followed
   by 61 samples at five-second intervals. Preserve a unique private manifest,
   stdout/stderr and report; verify completion and timing before accepting A.
2. After capture, check cold/warm launch behavior for the same chosen apps and
   file workflow, with storage observations. Fix the workload and observation
   method before collecting A; do not improvise a different B workload. Keep
   launches outside the quiet memory window and distinguish first observed
   launch from a proven cold-cache measurement. Do not flush caches or trim RAM.
3. Only after reviewing A, design and review the one-service trial with exact
   prior startup configuration (including delayed-start absence), runtime state
   and guarded restoration. Supported service administration is separate from
   this read-only command; no blanket service list or unattended reboot.
4. Coordinate the trial boot, verify only the intended SysMain configuration
   differs, and repeat identical measurements and Search/Explorer, Store/WinGet,
   security and servicing checks. Background workload differences invalidate a
   causal comparison. Do not equate a registry readback with effective behavior.
5. Restore exact captured configuration/state, and verify after coordinated
   restart where required. Stop on drift, unknown consumers, restore failure or
   regression. An exploratory pair of runs does not establish repeatability;
   restore rather than retain an unproven default.

The old quiet-session checkpoint predates the current shell preferences and
cannot replace A. No new controlled-idle result, below-2GB claim or SysMain
savings is established by this preflight. The private coordinated launcher
captures enabled A only; it performs no service change. The actual trial writer
and its recovery validation remain separate future work.
