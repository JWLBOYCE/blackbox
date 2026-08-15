# Mac App Store listing — Blackbox 1.0

This is the reviewed English (U.K.) copy deck for App Store Connect. It uses only features present in version 1.0 and only synthetic records in screenshots.

## Product identity

- Name: `Blackbox Pilot Logbook`
- Subtitle: `Private. Local. Auditable.`
- Primary language: `English (U.K.)`
- Primary category: `Productivity`
- Secondary category: `Travel`
- Bundle ID: `uk.co.blackbox.logbook`
- SKU: `blackbox-macos-1`
- Version: `1.0.0`
- Build: `1`
- Privacy policy URL: `https://github.com/JWLBOYCE/blackbox/blob/main/PRIVACY.md`
- Support URL: `https://github.com/JWLBOYCE/blackbox/blob/main/docs/SUPPORT.md`
- Marketing URL: `https://github.com/JWLBOYCE/blackbox#readme`

## Promotional text

Your flying, on your Mac. Import, review, analyse and export a professional logbook with local-only storage and encrypted backups.

## Description

Blackbox turns a flight history into a clear, private workspace built for the Mac.

Keep flight and simulator records together, understand experience across aircraft and routes, review recency, and prepare portable reports — without creating an account or sending a logbook to a hosted service.

YOUR LOGBOOK, UNDER YOUR CONTROL

• Local-only SQLite storage inside the app's sandbox
• No account, advertising, analytics, tracking, or cloud backend
• Encrypted local backups with verification and staged restore
• User-selected import, export, and backup locations

IMPORT WITH CONFIDENCE

• Read-only previews for LogTen Pro databases
• PDF, image, CSV, and text extraction with a human review queue
• Clear additions, changes, duplicates, and conflicts before applying
• Verified recovery backup before an approved import changes the logbook

SEE THE FLYING BEHIND THE NUMBERS

• Interactive 3D route globe with filterable sectors
• Analysis by aircraft type, people, places, time, and distance
• Searchable history, logbook pages, aircraft, and crew views
• Configurable landing, night-landing, and instrument-time indicators

RECORDS THAT STAY AUDITABLE

• Explicit draft, finalise, amendment, and recoverable Trash workflows
• PIC, PICUS, co-pilot, dual, instructor, FSTD, IFR, cross-country, and night time
• Duplicate detection, operation history, and provenance-labelled suggestions
• CSV, printable HTML, and CAA-format report exports

Blackbox's checks and reports support human review. They are not regulatory, licensing, operator, or authority certification. Airport and route graphics are informational and must not be used for navigation.

## Keywords

`pilot,logbook,aviation,flight,hours,currency,CAA,roster,backup,report,crew,aircraft`

## Review notes

Blackbox requires no account or demo credentials. The first launch creates an empty local database inside the app container. To exercise import, choose a user-owned PDF, image, text, CSV, or LogTen Pro SQLite database through the system file picker. Import previews are read-only until the reviewer explicitly approves them. Exports and encrypted backups are written only to a folder selected through the system picker.

The app has no network client entitlement and no hosted service. The route globe uses bundled static NASA Visible Earth imagery and a bundled public-domain OurAirports dataset. Synthetic screenshots contain generated demonstration records only.

## Screenshot sequence

1. Dashboard — `Your flying, at a glance`
2. Flights — `Record every sector with clarity`
3. Route map — `See the routes behind your hours`
4. Analysis — `Understand your experience`
5. Reports — `Export and back up with confidence`

All screenshots must be generated at 2880 × 1800 with `./script/build_and_run.sh --app-store-screenshots` and inspected before upload.

## Declarations requiring Account Holder confirmation

- App privacy: proposed `No, we do not collect data from this app`, based on the version 1.0 source and dependency audit.
- Content rights: proposed confirmation that the publisher owns or has rights to all content; evidence is in `THIRD_PARTY_NOTICES.md`.
- Age rating: proposed answers are `None` / `No` for all content, communication, social, gambling, loot-box, advertising, and unrestricted-web-access questions.
- Encryption: version 1.0 uses Apple-provided CryptoKit AES-GCM and CommonCrypto PBKDF2-HMAC-SHA256 solely for user-created local encrypted backups. The Account Holder approved the exempt-encryption declaration (`ITSAppUsesNonExemptEncryption = false`), so no App Store Connect documentation is expected.
- Business configuration approved by the Account Holder: free in all supported territories, with automatic release after Apple approval.
