# Read-only Windows baseline — M2

**Status: candidate implementation.** This command inspects Windows. It does not debloat, change registry values, uninstall apps, download files or alter Windows Update.

## Run

Install PowerShell 7 through a trusted channel, clone uindos, inspect the scripts, then run from the repository root:

~~~powershell
pwsh -NoProfile -File ./bin/uindos-baseline.ps1
pwsh -NoProfile -File ./bin/uindos-baseline.ps1 -OutputPath ./baseline.json
~~~

The first command prints JSON and **does not write a report file**. The second saves a report to the path you explicitly provide; the directory must already exist. No telemetry upload or network request is performed by uindos.

The command ordinarily runs without administrator rights. A non-admin session marks privileged probes **unsupported** instead of prompting for elevation. An optional elevated run in an isolated Windows 11 test VM provides all-users AppX, provisioned AppX, Secure Boot and BitLocker observations without altering their state.

## What is collected

The versioned JSON report, **uindos.baseline/v1**, contains per-probe objects with a status (**ok**, **unsupported**, **error**, **not-collected**), an array of data records, and a sanitized explanation.

The probes collect:

- Windows edition, version, build, revision, and architecture.
- Current-user and, if permitted, all-user AppX packages; provisioned AppX for future users; and Win32 uninstall-registry inventory.
- Selected diagnostic, advertising, Copilot, SmartScreen, UAC and Windows Update registry policy **values**.
- Selected Windows Update, Defender and diagnostic-service states, Defender and firewall profiles.
- System-volume BitLocker state, Secure Boot state, system-drive size/free bytes and ten recent hotfix entries.

**Deliberate omissions:** computer and account names, serial numbers, SIDs, installed file paths, Wi-Fi information, IP addresses, BitLocker recovery keys, activation IDs, complete event logs and the configured WSUS URL. However, installed program names and publishers can still be identifying. Reports remain local and should be reviewed before sharing.

## Interpretations and limits

- A configured registry key is **not** proof Windows honors the setting on the current edition. Diagnostic-data-off is not an available Windows 11 Pro policy guarantee.
- [Get-AppxPackage](https://learn.microsoft.com/en-us/powershell/module/appx/get-appxpackage) enumerates current-user installed packages; all-user queries require administrator privileges. [Get-AppxProvisionedPackage](https://learn.microsoft.com/en-us/powershell/module/dism/get-appxprovisionedpackage) describes what Windows provisions for newly created users, not existing installations.
- [Confirm-SecureBootUEFI](https://learn.microsoft.com/en-us/powershell/module/secureboot/confirm-securebootuefi) needs elevation and a supported UEFI environment. Unavailable results must not be mistaken for Secure Boot disabled.
- [Get-BitLockerVolume](https://learn.microsoft.com/en-us/powershell/module/bitlocker/get-bitlockervolume) reports encryption/protection state only; recovery material is never requested.
- Installed Win32 programs are based on uninstall-registry entries, not an exhaustive disk search.
- Get-HotFix is a **partial** servicing view, not a reliable Windows Update health check.
- This phase does **not** benchmark performance, measure telemetry, assess true policy effectiveness, or make any system changes.

## Tests

Run dependency-free, mock-only smoke tests with PowerShell 7 on Linux or Windows:

~~~powershell
pwsh -NoProfile -File ./tests/baseline-smoke.ps1
~~~

The GitHub workflow runs mock tests on Windows and Ubuntu. The Windows job also executes a **read-only live collector** against the hosted runner and checks its OS/service probes and JSON structure without publishing inventory data. Hosted-runner validation is not a substitute for testing the supported Windows 11 Pro configuration in a dedicated VM.

### Manual Windows VM gate

Before merging as a validated collector:

1. On a disposable Windows 11 Pro VM, run unelevated. Verify that the JSON parses, ordinary probes succeed, and privileged probes are reported unsupported.
2. Repeat with an elevated PowerShell session. Verify that all-users/provisioned lists and Secure Boot/BitLocker read results correspond to independent OS observations.
3. Check no registry, service, task, installed package or system security setting was changed; ordinary Windows Update, Defender, Explorer and Store remain functional.
4. Inspect every output property for personally identifying fields. Record errors, Windows build, PowerShell version and exact steps in [research/VALIDATION.md](research/VALIDATION.md).
5. Only then mark the Windows-tested acceptance gate as passed.

### Source files

- **bin/uindos-baseline.ps1** — minimal command line, JSON and optional local file export.
- **src/core/Baseline.ps1** — injectable read-only providers, sanitized error statuses and report schema.
- **src/core/Probes.ps1** — individual Windows read collectors.
- **tests/baseline-smoke.ps1** — independent PowerShell 7 tests with no external test framework.

The initial design deliberately avoids a Windows service, installation process, elevated runtime, tweak catalog or persistent background agent.
