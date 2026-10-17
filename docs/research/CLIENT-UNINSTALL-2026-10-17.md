# Client removal validation — 2026-10-17

Windows 11 Pro x64 26H2 build 26300.9711, fresh-install VM. These are observed
results, not a general uninstaller or permission to erase personal/synced files.
No software was installed, no reboot/sign-out occurred, and no ACL, security,
service-startup or ownership bypass was used.

## OneDrive: client removed

The exact current-user registration identified Microsoft OneDrive
26.183.0920.0005, publisher Microsoft Corporation. The installed version's
`OneDriveSetup.exe` had a valid Microsoft signature. Its SHA-256 was
`2BA7C8C6735294AD2398C37147924288B91CD7B22AC980664D990A08F347D3C3`.
A byte-identical copy of this existing installer was retained privately before
uninstalling. The inbox System32 setup was older (25.087.0506.0001), so its
presence alone was not treated as exact-version recovery.

Separate bounded metadata inspection found only `desktop.ini` in the local
OneDrive sync folder, no reparse points, and no Desktop/Documents/Pictures
redirection into that folder. Its desktop metadata was preserved. This finding
applies to this VM only: account registry metadata does not establish sign-in,
backup completeness or hydration on another installation.

The exact Microsoft-signed installed setup was invoked with `/uninstall`,
matching its registered argument, without evaluating the registry command as
shell code. Exit code was zero. Independent existing preflight then reported
zero matching registrations and no OneDrive process; the client executable
was absent. The uninstaller removed its account metadata. No forced task kill
was needed. System32's setup and the retained current-version installer remain.

The local sync folder and application leftovers remain. A subsequent recursive
cleanup command was rejected by the tool's automatic approval review as
"blocked by policy" before execution. It made no filesystem changes. No files
were moved out of sync roots and no cloud contents were accessed/deleted.
No claim is made about future-user installation or post-update reinstallation.
Reinstall and account/sync reconstruction were not tested.

Microsoft documents [uninstalling OneDrive through Installed apps](https://support.microsoft.com/en-us/onedrive/turn-off-disable-or-uninstall-onedrive)
and [reinstalling OneDrive](https://support.microsoft.com/en-us/onedrive/reinstall-onedrive).
Client removal and deleting local folders are different operations; the latter
can destroy local-only or unsynced data. This experiment does not implement
a production OneDrive removal command. Existing [preflight](../ONEDRIVE-PREFLIGHT.md)
remains read-only and deliberately conservative.

## Edge: native installer refused removal

Installed Edge Stable was 155.0.4283.60. The VM was not domain joined and had
U.S. Windows home region; ARP marked the browser `NoRemove=1`.
Microsoft's [Edge Update uninstall policy](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-update-policies)
documents domain-joined/EEA eligibility. It did not establish a supported removal
route for this VM. [Edge dependencies](https://support.microsoft.com/en-us/edge/apps-and-widgets-that-depend-on-microsoft-edge)
also require separate compatibility assessment even when WebView2 remains.

The user explicitly requested a force-uninstall attempt. Before the attempt,
the exact installed browser setup's Microsoft signature, version and SHA-256
were checked. A signed full installer for the same version was copied from
the existing Edge Update cache to persistent private recovery storage and its
copy hash verified. This is a recovery candidate; reinstall was not tested.

One browser-targeted invocation used the installed setup with `--uninstall`,
`--msedge`, `--channel=stable`, `--system-level`, `--verbose-logging` and the
requested `--force-uninstall`. No profile-deletion flag was supplied.
It returned **93**. The contemporaneous SystemTemp installer log reported
that uninstall was blocked for this product. The browser executable and
Edge Update client registration remained. Seven previously background-only
browser processes exited; process exit is not browser removal.

The WebView2 runtime executable hash/signature, runtime version registration,
Edge updater executable hash/signature and both updater service Start values
were identical before/after. Defender AV, real-time and tamper signals remained
enabled. WebView2 and Edge share an update mechanism despite separate app
registrations; do not delete/disable the shared updater to remove the browser.
See [Microsoft's WebView2 management documentation](https://learn.microsoft.com/en-us/deployedge/webview2-enterprise).

No further force flag, eligibility override, protected-file deletion or registry
bypass was attempted. Browser removal remains unresolved. A later proposal
must explicitly address support, recovery and dependent-app regression rather
than reporting a nonzero installer exit as success.

## Evidence and limits

Private persistent journals, signed recovery installers, metadata reports and
native drivers are retained outside Git. No raw user paths, logs, account
identifiers or sync state are published here. Start post-boot export remained
empty, but post-boot Search UI and later customization remain separate checks.
Physical-memory savings, controlled idle and the under-2-GB target must be
measured independently; neither client absence nor summed working sets proves
that target or a particular privacy outcome.

Two 12-sample windows at five-second intervals were collected during this
active agent session. The earlier window used 3.510–3.525 GB physical memory
at 16.67–23.68% CPU. After OneDrive removal and the refused Edge attempt closed
its browser processes, the later window peaked at 3.424 GB (3.189 GiB), with
18.46–26.56% CPU. Neither window was idle or met either 2-GB interpretation.
They do not isolate the causal savings of an individual change. A separate
short attribution sample found Windows Terminal consuming about 16% of machine
CPU. A delayed collector was prepared for a later operator-coordinated check
with the agent terminal closed; it was not launched during this work.
