# Security Policy

## Supported Versions

The `main` branch is the supported development version.

## Reporting a Vulnerability

Please do not open public issues containing real pilot data, private databases, roster files, or screenshots with personal details.

For security reports, open a private advisory if the repository is hosted on GitHub, or contact the maintainers privately.

## Data Handling Principles

- LogTen Pro source databases are opened read-only.
- Blackbox stores data locally in SQLite.
- Real logbook databases must not be committed.
- CI must use synthetic data only.
- Exports should be treated as private pilot records.

## Sensitive File Patterns

Never publish:

```text
LogTenCoreDataStore.sql
OpenPilotLogbook.sqlite
*.sqlite
*.db
*.sql
*.pdf
*.csv
```
