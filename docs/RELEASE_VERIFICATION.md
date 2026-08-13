# Blackbox direct-distribution release verification

Blackbox 1.0.0 (build 1) is distributed as a Universal 2 app for macOS 14 or later with bundle identifier `uk.co.blackbox.logbook`. Release work uses synthetic records and temporary data roots only. Never launch a development, test, snapshot, or release build against `~/Library/Application Support/Blackbox`.

The CLI packaging pipeline does not build or install the app. It verifies the downloaded CI archive and XML manifest, extracts the app into temporary storage, signs that temporary copy, notarizes it, staples it, produces a final ZIP, then smoke-launches only a quarantined temporary copy with deterministic fixtures under a protected temporary data root. The CI inputs and live SQLite files remain unchanged.

## User-controlled prerequisites

The release operator supplies these outside the repository:

- A clean Git checkout at the exact source commit used to build the app.
- The CI-produced `.xcarchive.zip`, XML manifest plist, human-readable JSON manifest, and shard-evidence index downloaded from the same successful workflow run. The packaging script verifies the archive and evidence-index hashes and sizes, source commit, exact Xcode build, all seven XCUITest artifact digests, test/privacy gates, release metadata, and every Mach-O architecture before signing the app extracted from that archive.
- A valid **Developer ID Application** identity with its private key in the login Keychain. A Developer ID Installer identity is not required because the deliverable is an app ZIP, not a package installer.
- A validated `notarytool` Keychain profile. Create it interactively so the Apple Account, Team ID, app-specific password, and 2FA response never enter the repository or shell history:

  ```bash
  xcrun notarytool store-credentials blackbox-notary-local
  ```

Do not put Apple credentials, API private keys, `.p12` files, certificates, identities, or notarization passwords in environment files, command-line arguments, Git, or release manifests. `BLACKBOX_NOTARY_PROFILE` is only the non-secret Keychain item name.

## Record the immutable live-data baseline

Quit Blackbox. Before any release work, store the baseline outside the checkout and outside Application Support:

```bash
mkdir -p "$TMPDIR/blackbox-release-evidence"
/bin/bash script/release_live_hashes.sh capture \
  --root "$HOME/Library/Application Support/Blackbox" \
  --manifest "$TMPDIR/blackbox-release-evidence/live-hashes-before.txt"
```

The helper reads the SQLite, WAL, and SHM as opaque bytes with `shasum`; it never opens SQLite. The main database must exist. A missing WAL or SHM is represented as `MISSING` and must remain missing. The baseline is created once and is never overwritten.

Verify it at any checkpoint with:

```bash
/bin/bash script/release_live_hashes.sh verify \
  --root "$HOME/Library/Application Support/Blackbox" \
  --manifest "$TMPDIR/blackbox-release-evidence/live-hashes-before.txt"
```

## Build and test gates

All development and acceptance commands must use a new temporary `BLACKBOX_DATA_ROOT`. Before packaging, retain evidence for:

- Full SwiftPM tests, executable unit checks, smoke checks, migration rollback/failure-injection tests, and the 3,100-flight plus import/history/analysis/map performance thresholds.
- All thirteen workflows in `Blackbox.xctestplan` under CI's exact Xcode 26.6 (17F113), across Light/Dark and regular/compact configurations. CI runs those four configurations as four independent shards. It runs the focused `BlackboxAccessibility.xctestplan` workflow for Increase Contrast at both widths and large-text/reduced-motion as three more independent shards. Every shard receives a fresh temporary root and retains its own `.xcresult`, console log, hash manifest, and immutable artifact digest.
- A completed human keyboard-only and VoiceOver sign-off using [ACCESSIBILITY_VERIFICATION.md](ACCESSIBILITY_VERIFICATION.md). XCUITest and screenshots are supporting evidence; they do not certify this manual gate.
- Synthetic restore rehearsal and database `integrity_check` results.
- `git diff --check`, a clean working tree, and the tracked/untracked release privacy scan.
- The same live SQLite/WAL/SHM baseline verification after all tests.

An app extracted from the verified CI archive can also be inspected without signing credentials:

```bash
/bin/bash script/verify_release_input.sh --app /absolute/path/to/Blackbox.app
/bin/bash script/release_privacy_scan.sh \
  --repository "$PWD" \
  --app /absolute/path/to/Blackbox.app
```

The privacy gate rejects likely personal database, import, roster, document, backup, spreadsheet, image, certificate, private-key, provisioning-profile, credential, and environment-file artifacts. It also rejects SQLite content hidden behind another filename and absolute user-home paths embedded in packaged code or text. Its repository exceptions are limited to the named public product screenshots, application icon assets, bundled map imagery and airport reference, the `.env.example` template, and the two SQLite integration source files.

## Download and verify a successful CI evidence set

Run these commands from a clean checkout of the exact tested commit. Replace the
run ID; the remaining artifact names are fixed by the workflow. This downloads
only synthetic CI evidence into a new temporary directory. It does not build or
launch Blackbox and does not access Application Support. The seven XCUITest
artifacts are deliberately separate so no shard can silently substitute for a
missing configuration.

```bash
release_run_id=1234567890
release_repository=JWLBOYCE/blackbox
release_evidence_dir="$(mktemp -d "${TMPDIR%/}/blackbox-ci-evidence.XXXXXX")"

test "$(gh run view "$release_run_id" --repo "$release_repository" \
  --json status --jq .status)" = completed
test "$(gh run view "$release_run_id" --repo "$release_repository" \
  --json conclusion --jq .conclusion)" = success
test "$(gh run view "$release_run_id" --repo "$release_repository" \
  --json headSha --jq .headSha)" = "$(git rev-parse HEAD)"

evidence_artifacts=(
  Blackbox-principal-screen-snapshots
  Blackbox-XCUITest-Light-Regular
  Blackbox-XCUITest-Light-Compact
  Blackbox-XCUITest-Dark-Regular
  Blackbox-XCUITest-Dark-Compact
  Blackbox-Accessibility-XCUITest-Increase-Contrast-Regular
  Blackbox-Accessibility-XCUITest-Increase-Contrast-Compact
  Blackbox-Accessibility-XCUITest-Large-Text-Reduced-Motion
  Blackbox-synthetic-verification-report
  Blackbox-unsigned-universal2-release-input
)

for artifact_name in "${evidence_artifacts[@]}"; do
  test "$(gh api \
    "repos/$release_repository/actions/runs/$release_run_id/artifacts?per_page=100" \
    --jq "[.artifacts[] | select(.name == \"$artifact_name\" and .expired == false)] | length")" = 1
  gh run download "$release_run_id" --repo "$release_repository" \
    --name "$artifact_name" \
    --dir "$release_evidence_dir/$artifact_name"
done
```

Verify the report, the GitHub artifact digests, and reproducible file-tree
hashes. `xcresulttool` requires full Xcode, so retain the `.xcresult` unchanged
locally and inspect it on the Xcode CI runner or another approved full-Xcode
Mac; the local Command Line Tools can still verify its recorded byte tree.

```bash
release_report="$release_evidence_dir/Blackbox-synthetic-verification-report/Blackbox-verification-report.md"
test -s "$release_report"
grep -F -- "- Automated test status: \`passed\`" "$release_report"
grep -F -- "- Automated release-input status: \`passed\`" "$release_report"
grep -F -- "- Commit: \`$(git rev-parse HEAD)\`" "$release_report"
grep -F -- "actions/runs/$release_run_id" "$release_report"

report_value() {
  grep -F -- "- $1:" "$release_report" | cut -d'`' -f2
}

api_artifact_digest() {
  gh api "repos/$release_repository/actions/runs/$release_run_id/artifacts?per_page=100" \
    --jq ".artifacts[] | select(.name == \"$1\" and .expired == false) | .digest"
}

release_input_dir="$release_evidence_dir/Blackbox-unsigned-universal2-release-input"
evidence_index="$release_input_dir/Blackbox-evidence-artifact-digests.plist"
plutil -lint "$evidence_index"
test "$(plutil -extract evidenceSchema raw -o - "$evidence_index")" = 1
test "$(plutil -extract sourceCommit raw -o - "$evidence_index")" = "$(git rev-parse HEAD)"
test "$(plutil -extract runID raw -o - "$evidence_index")" = "$release_run_id"

while read -r artifact_name digest_key; do
  test "$(plutil -extract "artifactDigests.$digest_key" raw -o - "$evidence_index")" = \
    "$(api_artifact_digest "$artifact_name")"
done <<'EVIDENCE_ARTIFACTS'
Blackbox-principal-screen-snapshots principal_screen_snapshots
Blackbox-XCUITest-Light-Regular XCUITest_Light_Regular
Blackbox-XCUITest-Light-Compact XCUITest_Light_Compact
Blackbox-XCUITest-Dark-Regular XCUITest_Dark_Regular
Blackbox-XCUITest-Dark-Compact XCUITest_Dark_Compact
Blackbox-Accessibility-XCUITest-Increase-Contrast-Regular Accessibility_XCUITest_Increase_Contrast_Regular
Blackbox-Accessibility-XCUITest-Increase-Contrast-Compact Accessibility_XCUITest_Increase_Contrast_Compact
Blackbox-Accessibility-XCUITest-Large-Text-Reduced-Motion Accessibility_XCUITest_Large_Text_Reduced_Motion
EVIDENCE_ARTIFACTS

test "$(report_value 'Release-input upload digest')" = \
  "$(api_artifact_digest Blackbox-unsigned-universal2-release-input)"

snapshot_dir="$release_evidence_dir/Blackbox-principal-screen-snapshots"
test "$(find "$snapshot_dir" -type f -name '*.png' \
  | wc -l | tr -d ' ')" = 72
snapshot_tree_sha256="$(cd "$snapshot_dir" && \
  find . -type f -name '*.png' -print0 \
    | sort -z \
    | xargs -0 shasum -a 256 \
    | shasum -a 256 \
    | awk '{print $1}')"
test "$snapshot_tree_sha256" = "$(report_value 'Snapshot tree SHA-256')"

verify_ui_shard() {
  artifact_name="$1"
  expected_suite="$2"
  expected_configuration="$3"
  expected_methods="$4"
  artifact_dir="$release_evidence_dir/$artifact_name"
  manifest="$(find "$artifact_dir" -type f -name "$artifact_name.evidence.plist" -print -quit)"
  test -n "$manifest"
  plutil -lint "$manifest"
  test "$(plutil -extract suite raw -o - "$manifest")" = "$expected_suite"
  test "$(plutil -extract configuration raw -o - "$manifest")" = "$expected_configuration"
  test "$(plutil -extract expectedTestMethods raw -o - "$manifest")" = "$expected_methods"
  test "$(plutil -extract testConfigurationCount raw -o - "$manifest")" = 1
  test "$(plutil -extract testOutcome raw -o - "$manifest")" = success
  test "$(plutil -extract sourceCommit raw -o - "$manifest")" = "$(git rev-parse HEAD)"
  evidence_dir="$(dirname "$manifest")"
  result_bundle="$evidence_dir/$(plutil -extract resultBundleName raw -o - "$manifest")"
  console_log="$evidence_dir/$(plutil -extract consoleLogName raw -o - "$manifest")"
  test -d "$result_bundle"
  test -s "$console_log"
  result_tree_sha256="$(cd "$result_bundle" && \
    find . -type f -print0 | sort -z | xargs -0 shasum -a 256 \
      | shasum -a 256 | awk '{print $1}')"
  test "$result_tree_sha256" = "$(plutil -extract resultBundleTreeSHA256 raw -o - "$manifest")"
  test "$(shasum -a 256 "$console_log" | awk '{print $1}')" = \
    "$(plutil -extract consoleLogSHA256 raw -o - "$manifest")"
}

verify_ui_shard Blackbox-XCUITest-Light-Regular full-workflow 'Light Regular' 13
verify_ui_shard Blackbox-XCUITest-Light-Compact full-workflow 'Light Compact' 13
verify_ui_shard Blackbox-XCUITest-Dark-Regular full-workflow 'Dark Regular' 13
verify_ui_shard Blackbox-XCUITest-Dark-Compact full-workflow 'Dark Compact' 13
verify_ui_shard Blackbox-Accessibility-XCUITest-Increase-Contrast-Regular focused-accessibility 'Increase Contrast Regular' 1
verify_ui_shard Blackbox-Accessibility-XCUITest-Increase-Contrast-Compact focused-accessibility 'Increase Contrast Compact' 1
verify_ui_shard Blackbox-Accessibility-XCUITest-Large-Text-Reduced-Motion focused-accessibility 'Large Text Reduced Motion' 1

release_archive="$release_input_dir/Blackbox-unsigned-universal2.xcarchive.zip"
release_manifest="$release_input_dir/Blackbox-unsigned-universal2.manifest.plist"
test -f "$release_archive"
test -f "$release_manifest"
plutil -lint "$release_manifest" "$evidence_index"
test "$(shasum -a 256 "$release_archive" | awk '{print $1}')" = \
  "$(plutil -extract artifactSHA256 raw -o - "$release_manifest")"
test "$(stat -f '%z' "$release_archive")" = \
  "$(plutil -extract artifactBytes raw -o - "$release_manifest")"
test "$(plutil -extract sourceCommit raw -o - "$release_manifest")" = \
  "$(git rev-parse HEAD)"
test "$(plutil -extract runID raw -o - "$release_manifest")" = "$release_run_id"
test "$(plutil -extract evidenceArchitecture raw -o - "$release_manifest")" = \
  seven-independent-xcuitest-shards
test "$(plutil -extract uiShardCount raw -o - "$release_manifest")" = 4
test "$(plutil -extract uiWorkflowExecutionCount raw -o - "$release_manifest")" = 52
test "$(plutil -extract accessibilityUIShardCount raw -o - "$release_manifest")" = 3
test "$(plutil -extract accessibilityUIExecutionCount raw -o - "$release_manifest")" = 3
test "$(shasum -a 256 "$evidence_index" | awk '{print $1}')" = \
  "$(plutil -extract evidenceIndexSHA256 raw -o - "$release_manifest")"
test "$(stat -f '%z' "$evidence_index")" = \
  "$(plutil -extract evidenceIndexBytes raw -o - "$release_manifest")"
```

Finally, inspect the unsigned app without credentials or execution:

```bash
release_extract_dir="$(mktemp -d "${TMPDIR%/}/blackbox-ci-archive.XXXXXX")"
ditto -x -k "$release_archive" "$release_extract_dir"
release_input_app="$release_extract_dir/Blackbox-Unsigned.xcarchive/Products/Applications/Blackbox.app"
/bin/bash script/verify_release_input.sh --app "$release_input_app" --require-unsigned
/bin/bash script/release_privacy_scan.sh --repository "$PWD" --app "$release_input_app"
```

Keep all ten downloaded artifact directories together with the workflow URL.
They expire from GitHub after 14 days, so retaining only the release archive is
not sufficient release evidence.

## Sign, notarize, staple, and package

Use the certificate name or SHA-1 identity reported by `security find-identity -v -p codesigning`. Do not use an Apple Development, Apple Distribution, ad-hoc, or self-signed identity.

```bash
BLACKBOX_CI_ARCHIVE_PATH=/absolute/path/to/Blackbox-unsigned-universal2.xcarchive.zip \
BLACKBOX_CI_MANIFEST_PATH=/absolute/path/to/Blackbox-unsigned-universal2.manifest.plist \
BLACKBOX_CI_EVIDENCE_INDEX_PATH=/absolute/path/to/Blackbox-evidence-artifact-digests.plist \
BLACKBOX_DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID1234)' \
BLACKBOX_NOTARY_PROFILE=blackbox-notary-local \
BLACKBOX_LIVE_DATA_ROOT="$HOME/Library/Application Support/Blackbox" \
BLACKBOX_LIVE_HASH_MANIFEST="$TMPDIR/blackbox-release-evidence/live-hashes-before.txt" \
./script/package_release.sh
```

The script enforces, in order:

1. Clean Git state; exact CI archive hash, size, commit, Xcode 26.6 (17F113), all seven independently hashed XCUITest shards, the evidence-index hash, automated-gate evidence, and release metadata; a valid Developer ID Application identity and authenticated Keychain notary profile; Universal 2 coverage for every Mach-O item; repository/artifact privacy; and the pre-work live hashes.
2. Inside-out signing of native binaries and nested code, then the outer app with hardened runtime, secure timestamp, and `Config/Blackbox.entitlements`. Signing never uses `codesign --deep`.
3. Strict deep signature verification, notarization through the named Keychain profile, and retrieval of the complete notarization result and log.
4. Stapling, staple validation, Gatekeeper assessment, and creation of the final ZIP only after the ticket is attached.
5. Extraction and re-verification of the final ZIP, followed by a quarantined synthetic-only smoke launch from a temporary copy. The launch must create only the protected synthetic root, emit a snapshot, and pass SQLite integrity and exact fixture-state checks.
6. SHA-256 checksum creation, privacy recheck, and the post-work live hash gate. The live hashes are checked immediately before and after the smoke; the exit trap also repeats the live gate after any packaging failure.

Successful output under `dist/release/1.0.0-build1/` consists of:

- `Blackbox-1.0.0-macOS-universal.zip` — the stapled app.
- A `.sha256` checksum.
- A JSON manifest recording the source commit and CI workflow/Xcode/input-artifact provenance, bundle/version/build, architectures, final artifact hash/size, signing Team ID, notarization submission, and every completed release gate.
- The Apple notarization result and full notarization log.

Retain separately, without embedding them in the distributable ZIP, the CI `.xcresult`, 72 principal-screen snapshots, CI verification report, downloaded CI manifests, completed accessibility sign-off, and live-hash baseline/verification evidence.

The release is invalid if the script exits non-zero or the success manifest is absent, even if a partial ZIP or notary log remains for diagnosis. Do not install the app or launch it against live data as part of packaging.

The release is also invalid while the accessibility checklist contains a blank, failed, or blocked required result. Signing and notarization do not turn an unperformed manual accessibility check into a pass.

## Final independent inspection

Extract the final ZIP into a new temporary directory and independently retain the output of:

```bash
codesign --verify --deep --strict --verbose=4 /temporary/path/Blackbox.app
codesign --display --verbose=4 --entitlements :- /temporary/path/Blackbox.app
xcrun stapler validate /temporary/path/Blackbox.app
spctl --assess --type execute --verbose=4 /temporary/path/Blackbox.app
(cd /absolute/path/to/release-directory && \
  shasum -a 256 -c Blackbox-1.0.0-macOS-universal.zip.sha256)
```

Review the notarization log for warnings rather than relying on `Accepted` alone. Re-run the live baseline verification after the independent inspection. A release fails if the live SQLite, WAL, or SHM state differs in existence or SHA-256 from the captured baseline.

## Current environment blockers

As of 2026-08-13, this Mac has no valid Developer ID Application identity and therefore cannot sign a direct-distribution release. No signing or notarization credential was created or used by the implementation work. Full Xcode is intentionally supplied only by the pinned GitHub Actions runner; the operator's Apple Developer membership, Account Holder authorization, Keychain private key, and notarization profile remain user-controlled release prerequisites.
