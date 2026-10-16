# Transaction engine — M3 (sandbox-only prototype)

**Status:** PR #4's sandbox engine has been merged. The original test adapter is limited to \`HKCU:\Software\uindos\EngineTest\...\`. PR #5 adds a **separate, fixed-allowlist adapter** for exactly three Windows 11 Pro current-user privacy values (see [PRIVACY.md](PRIVACY.md)); there is still no Edge, Copilot, system-service, update, driver or desktop action. Do not broaden either adapter without separate review and Windows 11 Pro VM validation.

## Purpose

Establish a small, testable execution contract *before* developing invasive system modifications:

1. \`Get-UindosPlan\` inspects requested actions and their exact pre-change state. It never creates directories or writes to the registry.
2. \`Invoke-UindosApply -ConfirmChanges\` re-reads the state, persists a prepared JSON journal **before** changing anything, rechecks that the value still matches the snapshot just before each write, writes one sandbox registry value at a time, verifies the result and records each step.
3. \`Invoke-UindosUndo\` uses exact saved prior values/types and reverses steps in reverse order. If something else has changed a value in the meantime, it **refuses to overwrite the drift** and marks the journal \`needs-review\`.
4. A failing apply attempts a best-effort reverse rollback; status distinguishes \`rolled-back\` from \`needs-review\`.
5. A repeated apply to the already desired state is a no-op, without another transaction journal.

**Important:** both the sandbox adapter and the first privacy adapter are *journaled compensating transactions*, **not** an atomic Windows transaction. Registry operations can partially complete if Windows crashes or the process is terminated; a later explicit undo is required to recover. Crashes before/after a write are handled by journaling a \`writing\` phase and comparing current, desired and prior values. Partial rollback, unknown state, unverified results and drift need human review; never claim a full rollback merely because a restore point or journal exists.

## Developer-only example (sandbox)

These commands run **only against a dedicated uindos test key**. They are shown for testing the engine, not for modifying real Windows preferences.

~~~powershell
. ./src/core/Transactions.ps1
$adapter = New-UindosRegistryAdapter
$actions = @(
    [pscustomobject]@{
        id = 'test.example'
        path = 'HKCU:\Software\uindos\EngineTest\Example'
        name = 'Flag'
        kind = 'DWord'
        value = 1
    }
)
$journal = Join-Path $env:LOCALAPPDATA 'uindos\transactions-test'

# Dry run — no registry changes, no journal creation.
Get-UindosPlan -Actions $actions -Adapter $adapter

# Explicit sandbox change; journal contains the exact prior value/type.
$result = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $journal -ConfirmChanges

# Undo respects subsequent user/app drift and reports conflicts.
Invoke-UindosUndo -TransactionId $result.transactionId -Adapter $adapter -JournalDirectory $journal
~~~

M3 supports only \`String\`, \`DWord\` (nonnegative signed 32-bit range) and \`QWord\` (nonnegative signed 64-bit range). Values with other registry types are rejected **before** modification, rather than backed up incorrectly. The engine preserves existence, type and value; if uindos created an otherwise absent registry key, undo currently deletes the **value** but does not remove that empty key.

## Transaction data and privacy

The JSON journal stores \`uindos.transaction/v1\` schema, transaction ID, UTC time, action IDs, paths, desired values, exact prior values and per-step phases (\`prepared\`, \`writing\`, \`applied\`, \`restored\`, \`conflict\`). Store it in a private per-user directory and **do not commit or upload journal files**. Future production adapters must not capture passwords, tokens, BitLocker recovery keys, authentication material or personal documents.

A same-directory temporary file followed by an atomic file rename/replace protects journal integrity against torn writes in common crash cases. A file lock prevents simultaneous uindos transactions using the same journal directory. There is **no tamper-proof cryptographic protection** of journal files; undo revalidates targets against the sandbox allowlist and refuses unknown paths.

Automatic rollback is **best effort**, especially after abrupt termination, I/O failure or external configuration drift. It will not override changes made by another process.

## Test coverage

- Portable mock test: \`pwsh -NoProfile -File ./tests/transactions-mock.ps1\` on Windows or Linux.
- Live Windows *sandbox* test: \`pwsh -NoProfile -File ./tests/transactions-windows.ps1\` creates only a random child key within \`HKCU:\Software\uindos\EngineTest\` and a temporary test journal, then deletes both in a \`finally\` block.
- GitHub Actions: Windows and Ubuntu mock tests, plus a Windows hosted-runner sandbox integration test. CI must pass before merge.
- **Remaining release gate:** test on a disposable Windows 11 Pro VM with several interrupted and failed transactions; verify no changes to actual system configuration, Defender, BitLocker, update services or unrelated registry keys. The tests are not yet evidence of production registry policy behavior.

## Follow-up PR gate

Before enabling actual default uindos changes, add a **fixed, curated, source-reviewed action manifest** and a per-target Windows policy/edition gate. Production adapters must enforce least privilege, deny dangerous target paths, verify Windows Update/security compatibility and expose a recovery command. Do not add manifest-supplied PowerShell or arbitrary command execution. Integrate a normal-user/elevated helper boundary only where needed, rather than executing the whole desktop as administrator.
