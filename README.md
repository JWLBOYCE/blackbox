# Blackbox

Blackbox is a native macOS flight records app for pilots who need a local, CAA-ready replacement workflow for LogTen Pro data.

It imports LogTen Pro SQLite data read-only, keeps times in `HH:MM`, stores distances as nautical miles, calculates day/night splits from route position, renders a 3D route globe, and provides CAA-style checks and printable exports.

## Current Features

- Native SwiftUI macOS app.
- Read-only LogTen Pro import from `LogTenCoreDataStore.sql`.
- Side-by-side LogTen comparison screen.
- CAA/FCL.050-oriented validation checks.
- Position-based day/night calculation using airport coordinates.
- Captain, First Officer, and Instructor / Other crew fields.
- Flight and simulator entry modes.
- PIC, PICUS, co-pilot, dual, instructor, FSTD, IFR/instrument, and cross-country time fields.
- Route globe using bundled airport coordinates and NASA Blue Marble imagery.
- CSV and printable HTML exports.
- Encrypted local backup and restore.
- Recency monitoring for last-12-months, 90-day landings, night landings, and instrument time.
- Duplicate flight detection.
- Manual airport coordinate overrides.
- Roster import policy that ignores ground duties and normalizes IATA tokens to ICAO where possible.
- Local-only SQLite storage.

## Privacy

This repository must never contain a real pilot logbook, roster PDF, export, or working database.

The `.gitignore` blocks common private files including:

- `LogTenCoreDataStore.sql`
- `OpenPilotLogbook.sqlite`
- `*.sqlite`, `*.db`, `*.sql`
- `*.blackboxbackup`
- PDFs, spreadsheets, CSVs, and generated app output

Before publishing, always run:

```bash
git status --short
git ls-files | rg 'sqlite|\\.db|\\.sql|LogTen|roster|\\.pdf|\\.csv' | rg -v '^Sources/OpenPilotLogbookCore/Resources/airports\\.csv$' || true
```

## Build

Requirements:

- macOS 14+
- Swift 5.9+

Build:

```bash
swift build
```

Run the unit test suite:

```bash
swift run OpenPilotLogbookCoreUnitTests
```

Run data smoke tests:

```bash
swift run OpenPilotLogbookCoreSmokeTests
```

Build and render app-check snapshots:

```bash
./script/build_and_run.sh --check
```

Create the local app bundle:

```bash
./script/build_and_run.sh
```

## Importing From LogTen Pro

See [docs/LOGTEN_IMPORT.md](docs/LOGTEN_IMPORT.md).

Short version:

1. Quit LogTen Pro.
2. Locate or copy `LogTenCoreDataStore.sql`.
3. Open Blackbox.
4. Go to `Import`.
5. Click `Import LogTen Pro`.
6. Select `LogTenCoreDataStore.sql`.

Blackbox opens that file read-only, creates a timestamped backup of the current Blackbox working database, then imports using the documented mappings.

## Contributing

Contributions are welcome, but privacy and aviation-record correctness matter here. Read:

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)
- [docs/REPOSITORY_PROTECTION.md](docs/REPOSITORY_PROTECTION.md)
- [docs/GITHUB_PUBLISHING.md](docs/GITHUB_PUBLISHING.md)

Do not submit real logbook data in issues, pull requests, screenshots, fixtures, or tests.

Pull requests must pass `Swift CI / build-and-test`, which runs build, unit tests, smoke tests, in-app snapshots, and the private-data guard.

## License

Blackbox is source-available under the PolyForm Noncommercial 1.0.0 licence. It may be used, studied, and improved for non-commercial purposes. Commercial use requires a separate licence from the copyright holder. See [LICENSE](LICENSE).
