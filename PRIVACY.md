# Blackbox Privacy Policy

Effective: 14 August 2026

Blackbox is a local-first macOS flight logbook published by Boyce Property Services Ltd. It is designed to keep pilot records on the user's Mac.

## Data collection

Blackbox does not collect, transmit, sell, or share personal data. It has no account system, advertising, analytics, tracking, telemetry, or hosted backend, and it does not include third-party software development kits that collect user data.

## Data stored on the Mac

Flight records, preferences, operation history, and recovery information are stored locally in Blackbox's application container. Blackbox accesses a document, LogTen Pro database, export folder, or backup folder outside that container only after the user selects it with the macOS file picker. Persistent folder access is represented by a security-scoped bookmark stored on the Mac.

Users can create encrypted local backups and export reports to a folder they choose. Backup passphrases are used locally and are not transmitted or stored by Blackbox. Removing Blackbox and its application data removes the app's locally managed records; exported files and backups remain wherever the user saved them.

## Permissions

The Mac App Store build uses App Sandbox. Its only requested file-system permission is read/write access to files and folders explicitly selected by the user, including persistent app-scoped bookmarks for those selections.

## Third-party services and data

Blackbox does not send user records to third parties. The app bundles NASA Visible Earth imagery and public-domain OurAirports airport data for its offline route view; these static resources do not receive user data. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Support and privacy questions

For support, use the guidance in [docs/SUPPORT.md](docs/SUPPORT.md). Do not include flight records, names, roster information, databases, screenshots containing personal information, or backup passphrases in a public issue. Security and privacy reports can be submitted privately through the repository's GitHub Security Advisory page.

If Blackbox's data practices change, this policy and the App Store privacy declaration will be updated before the changed version is released.
