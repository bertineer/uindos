# OneDrive preflight

`pwsh -NoProfile -File ./bin/uindos-onedrive-preflight.ps1` prints a sanitized JSON report. Add `-OutputPath <path>` to save the report locally; the destination directory must already exist. Collection is read-only, runs in the current user's context, does not require elevation, and makes no network requests.

The report inventories exact Microsoft OneDrive Win32 uninstall registrations in both machine registry views and one current-user view. It reports process presence, whether current-user OneDrive account registry metadata is present, and whether Desktop/Documents/Pictures appear under detected OneDrive roots. A running process does not prove syncing. Registry account metadata does not prove authenticated sign-in or sync health. Known-folder path placement does not prove backup completeness.

Files On-Demand state and local hydration are always reported as unknown and require manual review. The command does not scan files, inspect file contents, hydrate placeholders, unlink accounts, stop OneDrive, or uninstall anything. It does not emit uninstall command strings, account identifiers, or filesystem paths, and it never invokes a registered uninstall command. The report always requires manual review and never claims uninstall safety.

See [the research note](research/ONEDRIVE-PREFLIGHT.md) for Microsoft source applicability, interpretation limits, and the human review required before any separate uninstall proposal. There is no automatic rollback for unlinking, moving Known Folders, or uninstalling OneDrive.

Run the portable mock suite with `pwsh -NoProfile -File ./tests/onedrive-preflight-mock.ps1`. Mocks and an elevated read-only Windows 11 Pro build 26300.9711 VM run passed. The VM reported one current-user registration, a running process, account registry metadata present, and unknown sign-in, known-folder placement and hydration. That result is a preflight observation, not authorization or proof of safe removal. Normal-user live collection remains to be checked.
