# Mac App Store release runbook

Blackbox uses a separate `AppStore` build configuration and `Blackbox-AppStore` scheme. The existing `Release` configuration remains the unsandboxed, Developer ID distribution path.

## Prerequisites

- Active Apple Developer team `BSWQ8N2UB5`.
- Registered App ID `uk.co.blackbox.logbook`.
- A valid Apple Distribution certificate and its private key in the login Keychain.
- App Store Connect app record for Blackbox, macOS, version 1.0.0, build 1.
- Accepted agreements and completed tax/banking setup if the app will be paid.
- Account Holder confirmation for price, availability, content rights, age rating, privacy, and encryption answers.

Credentials, app-specific passwords, 2FA codes, private keys, and App Store Connect API keys must never be stored in the repository, shell history, CI, or release notes.

## Build and inspect

```bash
./script/archive_app_store.sh /absolute/fresh/path/Blackbox-1.0.0-build1.xcarchive
```

The verifier requires the production bundle ID/version/build, arm64 and x86_64 slices, the approved Team ID, a strict valid signature, App Sandbox, user-selected read/write access, and app-scoped security bookmarks. It rejects a distribution archive with `get-task-allow` enabled.

Inspect the archived app independently:

```bash
codesign -dvvv --entitlements :- /absolute/path/Blackbox-1.0.0-build1.xcarchive/Products/Applications/Blackbox.app
```

## Upload

The safest interactive route is Xcode Organizer: select the archive, choose Distribute App, App Store Connect, Upload, and allow Xcode to manage the distribution certificate and provisioning profile. Review every validation message before uploading.

For an already authenticated Xcode account, the checked-in export options can perform the same upload:

```bash
xcodebuild -exportArchive \
  -archivePath /absolute/path/Blackbox-1.0.0-build1.xcarchive \
  -exportOptionsPlist Config/AppStoreExportOptions.plist \
  -exportPath /absolute/fresh/export/path \
  -allowProvisioningUpdates
```

Uploading is not submission. Wait for processing, associate build 1 with version 1.0.0, resolve export compliance, complete all metadata and declarations, save, and only then submit the version to App Review.

## Verification boundary

Do not claim App Store submission until App Store Connect shows the version in `Waiting for Review`, `In Review`, or a later review state. Do not claim release until Apple shows `Ready for Distribution` and the intended territories and release setting are confirmed.
