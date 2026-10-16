# Contributing to uindos

uindos is an opinionated personal Windows configuration, not a universal utility. Contributions are welcome when they support its goals: privacy, removing unwanted software, performance supported by evidence, keyboard-driven desktop, working Windows Update and intact security.

## Before proposing code

1. Read README, AGENTS.md, docs/PHILOSOPHY.md, docs/ARCHITECTURE.md, docs/ROADMAP.md and docs/DECISIONS.md.
2. Open a focused issue/discussion for changes that affect the project vision, security, OS servicing, third-party software choices or default behaviors.
3. Cite Microsoft documentation for Windows policies and package servicing and pin source commit references for external scripts.
4. Include impact, supported Windows builds/editions, validation steps, exact rollback limits and update/security risk.
5. Prefer read-only probes and VM tests before integrating any destructive change.

## PR expectations

- One coherent change per PR; explain why it belongs in the default setup.
- Tests, dry-run outputs or reproducible manual validation for affected code.
- No mutable remote `iex`, disabled Defender protections, silent system changes or unreviewed copyrighted code.
- No reliance on undocumented registry hacks without explicit risk labeling.
- User data and user-installed software must not be removed inadvertently.

This is a personal project shared as-is. Community interest does not imply support for additional presets, hardware or Windows editions.
