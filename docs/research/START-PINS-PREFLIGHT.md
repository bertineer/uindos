# Start pins: evidence before reset

Researched 2026-10-17 UTC on Windows 11 Pro build 26300.9711. The current
change inventories Start pins without changing their layout or installing apps.

## Supported export and policy limits

[Microsoft Start layout documentation](https://learn.microsoft.com/en-us/windows/configuration/start/layout)
describes Windows 11 JSON export using inbox Windows PowerShell:
`Export-StartLayout -Path <private-file.json>`. The older
`-UseDesktopApplicationID` example is for the Windows 10 XML path. On this VM,
that switch threw NotImplemented; the Windows 11 command without it succeeded
for the normal Explorer account. Both observations are retained privately.

The same Microsoft guide documents context-menu unpinning. Its one-time Start
layout policy needs supported recent Windows builds and takes effect at sign-in.
The exported JSON is evidence for a future restore proposal; it is not a paired
transactional Undo API. Removing a policy does not establish original-layout
restoration, especially for pins whose apps are not registered. No reset is
included until application, restoration and refresh behavior are validated.

The installed `StartMenu.admx` maps ConfigureStartPins and its JSON data to the
Explorer policy key. Source SHA256:
`DD419E65E02E78E370C93B34AA63C05DD958F25B0189CBD00462107D351716C7`.
No policy is applied by this preflight.

[Microsoft taskbar policy documentation](https://learn.microsoft.com/en-us/windows/configuration/taskbar/pinned-apps)
distinguishes default/policy pins from user-created pins. Replace-style policy
is not a reliable bulk remover of existing user pins. A Start export also
does not inventory taskbar pins. Counting `.lnk` files misses packaged taskbar
apps; the VM's two shortcut files are not a complete taskbar count.

## Detection boundaries

Only two fixed package identities are correlated: WhatsApp and LinkedIn.
Exact exported pin identity and current-user package-family registration are
independent observations. A pin is not proof that an app is installed; absence
from current-user registration is not proof of absence for every account,
provisioning state, web app or installer mechanism. No pin is clicked, launched,
downloaded or treated as an uninstall target.

The normal desktop user is required so export and package registration describe
the same Explorer account/session. PowerShell 7 invokes the checked-in export
helper through inbox Windows PowerShell. No remote code is downloaded or run.
Raw layouts may contain private desktop-shortcut paths and app identifiers.
The default report contains counts and the two fixed target observations only.

Temporary diagnostic files are necessary for Export-StartLayout. They are
cleaned up by exact filename inside a verified temporary GUID directory.
An explicitly supplied new private directory preserves the raw layout and
family inventory instead. This is read-only for Windows configuration, not
zero filesystem activity. Raw export files must be reviewed before sharing.

## VM evidence and remaining work

Initial metadata collection succeeded in a verified non-elevated Explorer user
context: ten Start pins, including the exact WhatsApp and LinkedIn identities;
neither package family was registered for that user. Neither appeared in
Get-StartApps or the inspected Win32 registrations. No prior Start-layout
policies were found in the checked policy locations. These are observations,
not a claim that every possible app registration was inspected.

The screenshot showed ten visible pins. Foreground-window UIA identified a
SearchHost surface rather than a full pinned-list tree, so the export and
screen observation are the pin evidence. A later coordinate context-menu probe
opened Start settings rather than an app menu and proves no unpin behavior.
No pin or package was removed, no cache database was edited, and no sign-out,
reboot or shell restart occurred.

Next work is separate Start reset/restore validation and supported taskbar UI
cleanup. No automatic rollback, pin removal, policy reset or app uninstall is
promised by this command.

The shipped preflight was then exercised through its PowerShell 7 CLI in the
verified normal Explorer user's session. Both default temporary mode and
explicit retained-evidence mode succeeded with the same ten-pin result.
Default mode left no additional temporary GUID directory; retained mode saved
the two expected artifacts without printing the private directory path.
Comparing parsed layout exports before/after collection found no changes.
Elevated collection failed with nonzero exit status and cleaned up its
temporary directory. Reusing the existing evidence directory was refused;
both retained files' hashes remained unchanged. Portable mock tests passed;
native collection on other builds/architectures remains untested.
