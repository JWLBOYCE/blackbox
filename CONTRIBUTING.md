# Contributing

Thanks for helping improve Blackbox.

## Rules

- Do not commit real pilot logbook data.
- Do not attach real roster PDFs, exports, screenshots, or databases.
- Use synthetic examples in tests and issues.
- Keep times in `HH:MM`.
- Keep distances in nautical miles.
- Treat LogTen Pro imports as read-only source imports.
- Add or update smoke tests for mapping, import, CAA checks, or time calculations.

## Local Checks

```bash
swift build
swift run OpenPilotLogbookCoreSmokeTests
./script/build_and_run.sh --check
```

Before opening a pull request:

```bash
git status --short
git ls-files | rg 'sqlite|\\.db|\\.sql|LogTen|roster|\\.pdf|\\.csv' | rg -v '^Sources/OpenPilotLogbookCore/Resources/airports\\.csv$' || true
```

The second command should not show private logbook files.

## Pull Requests

Include:

- what changed
- why it changed
- how it was tested
- screenshots for UI changes
- privacy/security considerations if data import/export changed
