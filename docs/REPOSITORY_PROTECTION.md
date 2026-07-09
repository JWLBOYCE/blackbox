# Repository Protection

Use these settings before inviting contributors.

## Recommended Visibility

Public is fine for the source code, but never publish real logbook data.

## Branch Protection

Protect `main` with:

- Require a pull request before merging.
- Require at least one approval.
- Dismiss stale approvals when new commits are pushed.
- Require review from Code Owners.
- Require status checks to pass.
- Require branches to be up to date before merging.
- Require conversation resolution.
- Block force pushes.
- Block branch deletion.
- Restrict who can push directly to `main`.

## Required Status Checks

Use the included GitHub Actions workflow:

```text
Swift CI / build-and-test
```

That single required check runs:

- `swift build`
- `swift run OpenPilotLogbookCoreUnitTests`
- `swift run OpenPilotLogbookCoreSmokeTests`
- `./script/build_and_run.sh --check`
- private-data filename guard

## Repository Rulesets

Add rules to block files matching:

```text
*.sqlite
*.db
*.sql
LogTenCoreDataStore*
OpenPilotLogbook.sqlite*
*.pdf
*.csv
*.numbers
*.xlsx
*.xls
```

Allow only `Sources/OpenPilotLogbookCore/Resources/airports.csv` from the CSV rule.

## Secrets

No secrets are required to build the app. Do not add personal logbook databases, signing certificates, Apple IDs, or API keys to repository secrets.

## Contribution Hygiene

Ask contributors to use synthetic test data only. Issues and pull requests containing real pilot records should be deleted or redacted.
