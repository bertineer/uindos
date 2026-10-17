# Post-reboot services and Edge removal review

Windows 11 Pro x64 26H2 build 26300.9711, after the October 17 reboot at
21:31:18.5 UTC. This review collected read-only evidence. It changed no service,
policy, package, region, permissions or security control and attempted no new
uninstall. Raw inventories, dependencies and file evidence remain private.

## Services: observations and decisions

The 21:44 UTC inventory contained 269 services: 85 running and 184 stopped,
with 78 distinct nonzero service PIDs. All running services were inventoried
with their immediate SCM dependencies and process associations. This is an
active agent session, not a controlled idle measurement.

| Service | Observed state / start mode | Host working set, MiB | Review decision |
| --- | --- | ---: | --- |
| SysMain | Running / Automatic | 73.2 | First performance experiment candidate; retain until comparable measurements and launch tests are prepared. |
| DiagTrack | Running / Automatic | 45.5 | Separate diagnostic-privacy investigation; no measured performance benefit established. |
| CDPSvc | Running / Automatic | 16.3 | Retain pending cross-device feature assessment; existing EnableCdp policy is a different control. |
| CDPUserSvc instance | Running / Automatic | 21.6 | Assess with CDPSvc; do not target a generated user-service suffix as a persistent setting. |
| whesvc | Running / Automatic | 20.6 | Retain; the generic description does not establish callers or a justified disable scope. |
| lfsvc | Running / Manual | Not used for a saving claim | Preserve the user's existing location choice. |

CDPSvc and whesvc have delayed automatic start enabled. Read-only trigger
queries succeeded for all six rows: CDPSvc and lfsvc reported start triggers;
the others reported none. Ten Disabled services matched the earlier private
inventory, so that set predates this review. No startup configuration changed
as part of this work.

The five candidate PIDs each mapped to one service in this snapshot. Their
working sets still contain shared pages and host/runtime overhead; they are
not recoverable-memory estimates. No registered dependents were returned for
those candidates, which does not exclude application or shell API consumers.

Keep Windows Update/BITS/Orchestrator/WaaSMedic, cryptographic services,
Defender/security, Event Log, input/text, Start/Explorer/local Search,
Store/App Installer and the WebView2 update path. BITS, WaaSMedic, ClipSVC and
the two Edge updater services were stopped at capture; that does not establish
they are dispensable or disabled. CrossDeviceResume and the Start/text-input
hosts must not be confused with identically named SCM services.

Microsoft's [VDI guidance](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration)
requires scenario-specific evaluation. Its nonpersistent-desktop assumptions
do not establish a benefit for this persistent Pro VM. Microsoft's
[per-user service guidance](https://learn.microsoft.com/en-us/windows/application-management/per-user-services-in-windows)
also explains why generated instances change across sign-ins. A broad service
disable bundle is not justified by this inventory.

### Smallest useful next performance experiment

SysMain is the first proposed performance trial, not an applied optimization.
Capture exact startup configuration (including delayed start), current state,
and build before any change; retain a guarded restoration procedure. Complete
the pending post-reboot shell acceptance and establish comparable pre/post
quiet-session captures. Change only SysMain, coordinate any restart, and
measure used/available physical memory, CPU/storage activity and cold/warm app
launch behavior. Recheck local Search, Explorer, Store/WinGet, security and
servicing. Restore on regression or absent useful benefit. No service-disable
adapter or experiment is implemented by this documentation change.

The earlier 61-sample capture remains an operator-attested post-login quiet
session with unknown background update/scan activity and `idleClaim=false`.
Its peak was 2.484 GB / 2.314 GiB. It predates further shell preferences and
this reboot, so it cannot be paired with today's active-session process
snapshot to calculate a causal saving. See the
[checkpoint record](POST-REBOOT-CHECKPOINT-2026-10-17.md).

## Edge: removal remains blocked

The fresh 21:45 UTC review found Edge Stable 155.0.4283.60 still registered,
its browser executable present, `NoRemove=1`, U.S. home region and no Active
Directory domain membership. The installed setup SHA-256 is identical to the
setup used in the [earlier refused removal](CLIENT-UNINSTALL-2026-10-17.md).
That single attempt returned 93 and its contemporaneous log explicitly reported
that the product was sticky and uninstall was not allowed. Reboot does not
establish changed eligibility, and the same command was not retried.

Microsoft's current [Edge Update uninstall policy](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-update-policies#uninstall)
requires an EEA, domain-joined Windows device. It does not provide a supported
policy removal route for this VM. Removal remains unresolved within the
project's existing recovery and protection constraints. This review adds no
eligibility override, NoRemove edit, protected-file deletion or updater block.

At this point there were zero `msedge` processes. Both
[background policies](../EDGE-BACKGROUND.md) remained DWORD0. WebView2 and the
Edge updater had valid signatures and the same executable hashes as the
earlier removal evidence; Defender AV, real-time protection and tamper signals
were enabled. Point-in-time process absence is not browser removal or proof
of future startup behavior.

Microsoft documents that [Edge and WebView2 share an update mechanism](https://learn.microsoft.com/en-us/deployedge/webview2-enterprise),
so disabling the updater would also compromise the preserved runtime's update
path. Browser-dependent PWAs and widgets require separate
[compatibility assessment](https://support.microsoft.com/en-us/edge/apps-and-widgets-that-depend-on-microsoft-edge)
even if WebView2 is retained. No new download, installation or recovery test
was performed. The existing private same-version installer and prior rollback
records remain; no new host snapshot is assumed.
