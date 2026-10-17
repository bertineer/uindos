# One-time Start pin reset

The command proposes an empty Start pinned list using the documented Configure
Start Pins user policy. It removes pins, not applications. Preview is the default:

```powershell
pwsh -NoProfile -File ./bin/uindos-start-reset.ps1
```

This first implementation accepts Windows 11 Pro/Pro N x64 or ARM64, build
26300 with UBR 9711 or later in that build family, excluding detected preview
builds. This is a narrow validation boundary, not Microsoft's full support range.
The native read-only preview passed on Pro x64 26300.9711. A live elevated
Apply as the same Explorer user/session completed with status `applied`; the
repeat returned `unchanged` in the same operation. Both owned values were read
back with their exact registry kinds and data, and the journal recorded both
steps as applied. In the same session, Start showed an empty Pinned surface,
All apps remained visible, and local Start search returned installed apps.
These observations establish current-session behavior only; persistence after
a later sign-in remains **pending VM acceptance**.

## Recovery limit and application

Resetting replaces the current pinned layout. The exported layout is private
evidence, **not an exact layout rollback**. In the current VM, WhatsApp and
LinkedIn have pins but their package families are unregistered. An export may
not reconstruct those pins. `UndoPolicy` restores policy values only; it cannot
promise the original pin layout. Obtain informed acknowledgment of this limit
before applying. A PR merge alone is not that acknowledgment.

After that acknowledgment, use a temporary elevated PowerShell process belonging
to the same Windows user and session as Explorer. The command never elevates
itself. Use a new private operation directory with an existing parent on durable
storage; for this VM that means the persistent Z: drive:

```powershell
./bin/uindos-start-reset.ps1 -Apply -AcknowledgeLayoutReset `
    -StateDirectory Z:\uindos-work\private\start-reset-OPERATION
```

The command exports the current layout and package families, hashes both private
files, saves owner-bound operation metadata, then journals the exact registry
prior state before writing. It writes only these HKCU values, in this order:

| Key: Software\Policies\Microsoft\Windows\Explorer | Kind | Desired value |
| --- | --- | --- |
| ConfigureStartPinsJSON | REG_EXPAND_SZ | `{"applyOnce":true,"pinnedList":[]}` |
| ConfigureStartPins | REG_DWORD | `1` |

An initial Apply refuses any existing Start layout policy. Repeat Apply requires
the same operation directory, valid backup hashes and journal, and the exact
owned policy pair. It returns `unchanged` without another export or transaction.
After Undo or failure, do not reuse the directory for a new reset. Interrupted
operations retain their evidence; inspect the single transaction journal rather
than deleting evidence and retrying. Backup/metadata failure occurs before
policy writes. Engine write failure attempts guarded policy rollback and reports
any conflict. A final pair-readback failure also requires journal review.

The conservative guard blocks domain/cloud join, MDM enrollment signals, local
user/machine registry Group Policy files, conflicting HKLM/HKCU layout policy,
checked PolicyManager Start values, and unknown/incomplete probes. An owned
policy pair never waives other HKCU layout policies. This checks specific local
signals; passing is not proof that all possible management authority is absent.
No management state is overwritten. A cross-session per-user mutex serializes uindos mutations;
the engine refuses observed registry drift, but cannot lock out external writers.

Keep `operation.json`, `backup/layout.json`, `backup/families.json` and the
`transactions` directory together and private. They may contain user identities,
paths and app inventory. Private storage is the operator's responsibility: the
command does not set ACLs or guarantee isolation on a host-mounted share. Select
a parent whose access is appropriate; the VM's Z: share exposes host-managed
storage whose host permissions cannot be established from the guest ACL alone.
Operation directories inside Git worktrees are refused. The command prints sanitized counts and fixed desired
policy, not raw backups or prior policy contents. Do not commit this directory.

## Policy-only Undo

Use the transaction GUID returned by Apply and the same operation directory:

```powershell
./bin/uindos-start-reset.ps1 -UndoPolicy TRANSACTION-GUID `
    -StateDirectory Z:\uindos-work\private\start-reset-OPERATION
```

Undo validates the operation's owner, backup hashes and fixed journal scope,
then reverses the policy steps: disable/remove the flag before restoring/removing
the JSON value. The initial values must have been absent. It preserves later
policy edits and reports `needs-review` on drift. Undo is not blocked just because
the OS has since updated or management appeared; it still touches only the two
owned user values. It does not import a layout, install absent apps or edit caches.

## Validation and remaining acceptance

Portable tests cover catalog/build gates, raw ExpandString and DWORD journal
roundtrips, authority uncertainty, acknowledgment, immutable backup/journal
ownership, failure rollback, repeat Apply and drift-safe policy Undo. Windows
adapter tests read native state and intercept writes; they do not mutate policy.
Native previews passed as both normal and elevated versions of the same Explorer
user. The normal-user run verified unchanged policy state and no temporary export
directories left behind; the original inventory collector still runs unelevated.

The accepted live Apply created its fresh private backups, metadata and journal
before mutation. An immediate post-Apply export reported
zero pins, and the UI checks above confirmed the empty Pinned surface in the same
session. Explorer filename search also returned the expected results. A later
coordinated reboot/sign-in retained zero pins in a normal-user export, and Start's
All apps view remained available. See the
[post-reboot checkpoint](research/POST-REBOOT-CHECKPOINT-2026-10-17.md).
Subsequent user pin customization remains untested. Live policy Undo
has not been run because it could affect the apply-once lifecycle; its
policy-only recovery boundary remains documented above. Whether
removing/reapplying the same apply-once payload runs again remains unproven. Do
not edit internal one-time markers to force it.

There are no package removals, service/security/Windows Update changes, taskbar
changes, scheduled tasks or persistent privileged helpers. Source applicability
and the installed ADMX evidence are recorded in [research](research/START-RESET.md).
