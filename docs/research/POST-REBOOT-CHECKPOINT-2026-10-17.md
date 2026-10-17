# Post-reboot checkpoint — 2026-10-17

This records one post-restart Windows 11 Pro VM observation on build
26300.9711. It combines an operator-attested quiet-session context, a completed
memory sample, and separate UI/configuration checks. It does not establish a
strict controlled-idle baseline or causal savings from any setting.

## Capture and interpretation

- The current OS boot time matched the capture report's boot time, confirming a
  fresh boot for this checkpoint.
- The non-smoke sampler was configured for 120 seconds of settling, then 61
  samples at five-second intervals. The sample timestamps span 302.725 seconds;
  the sum of measured monotonic intervals is 300.187 seconds. Both measures
  exceed five minutes.
- The first sample timestamp was about 118.54 seconds after the recorded
  process start, despite the configured 120-second settle. The UTC span and
  monotonic interval sum also differ. The cause is unknown; no clock-adjustment
  explanation is established. Both duration checks pass.
- Stdout and the report were complete and parseable, stderr was empty, and the
  sampler process was absent at review. No exit code was recorded.
- Used physical memory ranged from 2,371,174,400 to 2,484,396,032 bytes. The
  peak is 2.484 decimal GB / 2.314 binary GiB, above both the 2,000,000,000-byte
  and 2,147,483,648-byte thresholds. This checkpoint did not meet either
  threshold.
- Across 60 CPU intervals, busy time averaged 1.62%, with a 0.16% minimum and
  13.24% maximum. The collector defines no CPU stability threshold and reports
  `idleClaim=false`.

The user reports a clean restart, then signing in and running the capture; no
apps were opened and all apps were closed. No visible update or scan activity
was noticed, but background activity is unknown. This is an operator-attested
post-login quiet session, not a controlled idle benchmark. The sample includes
the desktop, shell, sampler, and any other running work. Process overhead was
not subtracted or attributed, so the result cannot support a causal savings
claim.

## UI and availability observations

- Normal-user Start export contained zero pins. Taskbar UI Automation found
  zero pinned app buttons; the reviewed taskbar view showed only the running
  Terminal button. Start remained openable and its **All apps** view was
  accessible.
- Local Search returned PowerShell results. One unmatched query showed no
  results and no visible web results. This is one query on this build, not a
  general guarantee about Search or network activity. File Explorer returned
  two matches for a known documentation filename.
- Read-only setting previews reported zero changes for the checked EnableCDP,
  Edge, OneDrive, Search, Widgets, taskbar-default, and privacy settings. The
  corresponding readbacks were EnableCDP 0, two Edge values 0, OneDrive 1,
  Search 1, and Widgets 0. Start remained DWORD 1 with its literal empty
  `REG_EXPAND_SZ` ApplyOnce payload.
- Defender antivirus, real-time protection and tamper protection, all firewall
  profiles, and Secure Boot were enabled. WebView2 version 155.0.4283.60 had a
  valid signature. Store and App Installer were present, and `winget --version`
  succeeded.
- BitLocker reported fully encrypted storage with protection Off, matching a
  previously observed state; this checkpoint did not change it.
- No fresh online Windows Update scan was run. No service, software, policy, or
  security setting was changed, and the agent did not reboot the VM. CDP-related
  services being running does not establish whether the policy is effective.

The normal-user Windows backup page showed a local account, app list and
preferences not backed up, and both **Remember my apps** and **Remember my
preferences** Off and disabled. It also displayed managed-setting and account
requirement notices. The local account is a confounding prerequisite, so this
does not isolate EnableCDP's effect. On this build, `ms-settings:crossdevice`
opened **System > Share**: Nearby sharing showed Off with disabled options,
while a generic discoverability label remained. No second-device discovery or
continuation test was performed. These UI labels do not establish network
discoverability or complete cross-device enforcement. No controls were changed.

Microsoft documents EnableCDP as a device policy for cross-device participation
on Pro and says changes take effect after reboot. Its separate Windows settings
backup overview describes organization-managed backup requirements; this
checkpoint did not verify backup behavior for a consumer account or device.
Paired-device and backup acceptance remain pending. [EnableCDP policy
documentation](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-grouppolicy#enablecdp),
[Windows settings backup overview](https://learn.microsoft.com/en-us/windows/configuration/windows-backup/).

For Search, Microsoft's documented `DisableSearchBoxSuggestions` user policy
covers File Explorer recent-query suggestions. Its observed Start web-result
effect on this build is empirical. [Windows Explorer policy scope](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-windowsexplorer#disablesearchboxsuggestions).

## Pending

Paired-device and Windows settings backup behavior need separate acceptance.
Any later service experiment needs a narrowly justified candidate, exact rollback
and comparable before/after measurements. This checkpoint remained above both
memory thresholds; no under-2-GB result has been established.
