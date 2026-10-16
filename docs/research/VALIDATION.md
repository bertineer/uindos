# Validation plan and acceptance matrix

**Status: prescribed tests, NOT performed.** No claims of Windows compatibility or performance should be made before the results are added with OS build, VM/hardware configuration and timestamps.

## Test environments

First target: clean **Windows 11 Pro x64** on a supported build, with a second VM for an existing upgraded installation. Later: Home and Enterprise as explicit extension targets, not automatically inferred from Pro results.

| Environment | Purpose |
| --- | --- |
| Clean Win11 Pro supported release (local account) | Baseline, default package state, privacy and servicing support |
| Clean Win11 Pro supported release (Microsoft account) | Account-linked consumer experiences, sync and ads |
| Pro upgraded from previous supported feature release | Detect inherited apps, settings and package re-provisioning |
| Win11 Enterprise VM (research only) | Confirm edition-specific diagnostic and consumer controls |
| Physical test desktop (later) | Graphics, multi-monitor, fullscreen gaming, input hooks and real power/performance |
| Physical laptop (later) | Precision touchpad, Modern Standby, sleep, power, mobility |

A VM cannot establish gaming-frame-time or laptop-power improvements for actual hardware.

## Required baseline data

Collect pre/post structured snapshots of Windows edition/build, update history, pending reboot, package/capability inventories (all users and provisioned), installed Win32 apps, startup tasks, scheduled tasks, registry policy state, Defender/SmartScreen/BitLocker/firewall/Secure Boot status, disk usage, idle CPU/RAM after fixed settle time, and relevant OS service status. Do not collect or upload personal files or user-identifying data.

Record the exact Windows build, project git commit, test snapshot ID and reproducible commands in every result.

## Hard pass/fail gates

1. **Windows servicing:** Windows Update scan/download/install works; Defender signatures update; no redirected WSUS localhost policy; required services/tasks are not disabled by uindos. Confirm `DISM /Online /Cleanup-Image /ScanHealth` and `sfc /verifyonly` after modifications.
2. **Security baseline:** UAC, Defender realtime/tamper protection, downloaded-file SmartScreen, firewall, secure boot, disk-encryption state and memory integrity remain at their recorded baseline (unless user-specific state does not support feature).
3. **Application compatibility:** browser launches as non-admin; WebView2-dependent example app launches; Store/WinGet app installation works; Explorer fallback and Windows Settings remain available; all predefined power actions work.
4. **Packages:** unwanted apps absent for relevant existing users and provisioning as claimed; critical frameworks/Store dependency packages remain.
5. **Update resilience:** apply a supported cumulative update and, separately, feature upgrade in disposable VMs. Re-run read-only inspection, assess regressions and reconcile only explicitly managed settings.
6. **Rollback:** demonstrate exact prior-value restoration for registry changes; package re-installation or irreversibility documented; an interrupted install never silently indicates success.
7. **Integrity of downloads:** URLs pinned to expected versions, signatures and/or SHA-256 hashes verified, update delays and provenance tracked; no remote `iex` execution.
8. **No elevated desktop:** window manager, browser, terminal and launcher run at normal user integrity and survive login/reboot without persistent elevated tasks.

## Privacy measurement

- Establish a repeatable idle and active-use network-capture window and documented network/account state.
- Attribute processes/destinations where feasible; classify diagnostic, advertising/consumer, update, activation, cloud security, time sync and unknown traffic.
- Compare counts/bytes/connections for nonessential traffic; document noisy domains, resolver caching and encryption attribution limitations.
- Do **not** call DNS blocking or disabled diagnostics 'zero telemetry' unless the test meaningfully establishes exactly that limited claim.
- Account for OS edition restrictions: an effective setting must be measured or documented, not merely present as a registry value.

## Performance measurement

- Track installation footprint by package/component, not just free disk space immediately after deleting caches.
- Measure idle CPU/RAM with fixed boot/settle period, startup completion, launch latency, and (physical GPU) 1% lows / frametimes in identical reproducible scenarios.
- Compare security on/off only as an **experimental controlled benchmark**, not as a recommended production default.
- Attribute regressions and maintenance costs; don't include permanent timer tweaks or blanket disabled services without measurable benefit.

## Documentation of outcomes

Every scenario should log: **not-run**, **pass**, **fail**, **unsupported**, or **requires-manual-review**. Provide reproduction steps and Windows build IDs for failures. Never replace a test failure with a silent ignore/catch.

## Smallest next implementation PR

Build a **read-only inventory command** with mockable collection providers, JSON report and explicit unsupported outcomes. It must not change system state, require admin for ordinary queries, download software or collect identifiers/secrets.
