# Blackbox keyboard and accessibility verification

This is the release checklist for keyboard-only, VoiceOver, scalable-text, contrast, and motion behaviour. It uses deterministic synthetic records in a temporary data root. It must never be run against the production Application Support database.

## Current status and evidence boundary

The committed XCUITest suite and snapshot runner provide automated regression evidence, but they do not certify the manual accessibility gate.

| Evidence | What it covers | What it does not prove |
| --- | --- | --- |
| `Blackbox.xctestplan` | All thirteen scripted workflows in Light/Dark at regular/compact widths (52 workflow executions), run by CI as four independent configuration shards | Real VoiceOver speech, rotor order, Full Keyboard Access, or human usability |
| `BlackboxAccessibility.xctestplan` | A focused keyboard, window-size, and configured-surface workflow in Increase Contrast at both widths and in large-text/reduced-motion (3 executions), run as three independent shards | Complete workflow coverage in those extra configurations or human accessibility usability |
| `UITests/BlackboxUITests.swift` | Stable identifiers, expected controls and statuses, shortcuts, dialogs, file panels, restoration, rollback, and deterministic synthetic fixtures | That every control has the best spoken description or that focus order is logical |
| `script/build_and_run.sh --check` | Seventy-two synthetic principal-screen images: 12 destinations x Light/Dark/Increase Contrast x regular/compact | Keyboard reachability, spoken output, or interaction quality |
| This walkthrough | Human verification of the behaviours automation cannot establish | Nothing until a tester records and signs the results |

Each of the seven CI shards retains a separate `.xcresult`, console log, and hash manifest under an immutable artifact name. The release aggregator rejects a missing, duplicated, failed, wrong-configuration, wrong-commit, wrong-Xcode, or hash-mismatched shard before producing an unsigned archive. An automated CI pass still does not mark any unchecked manual item below as passed. A manual pass does not replace the automated test, snapshot, privacy, database-integrity, signing, or notarization gates.

## Safe manual test setup

1. Quit every installed copy of Blackbox and verify the previously captured live-data hash manifest as described in [RELEASE_VERIFICATION.md](RELEASE_VERIFICATION.md).
2. Download the unsigned CI archive only from the expected commit, verify its SHA-256 against the CI manifest, and extract it to a temporary directory. Do not install or replace the production app.
3. Launch the extracted app as a validated UI-test process. `manual_root` must not already exist; the app creates and marks it before seeding through production repository operations:

   ```bash
   app_path=/absolute/path/to/Blackbox.app
   manual_root="${TMPDIR%/}/Blackbox-XCUITest-manual-$(uuidgen)"
   test -x "$app_path/Contents/MacOS/Blackbox"
   test ! -e "$manual_root"
   env \
     BLACKBOX_DATA_ROOT="$manual_root" \
     BLACKBOX_SYNTHETIC_FIXTURE=deterministic \
     "$app_path/Contents/MacOS/Blackbox" --ui-testing
   ```

4. Keep the terminal open. If the launch rejects the root or fixture, stop; never substitute the live Application Support path.
5. After the walkthrough, quit the temporary app and verify the live-data hashes again. The release fails if the database, WAL, or SHM existence or hash differs from the baseline.

Record the temporary root basename in the evidence report. It contains synthetic data only and may be retained with the test evidence or left for normal temporary-storage cleanup.

## Test configurations

Run every workflow below once with Full Keyboard Access and once with VoiceOver. Use at least Light Regular for one pass and Dark Compact for the other. In addition, inspect every principal destination with Increase Contrast, the largest supported text setting, and Reduce Motion enabled. Restore the operator's system accessibility settings afterward.

Before starting, record:

- Source commit and CI run URL.
- Extracted app and archive SHA-256 values.
- macOS version, hardware, display scaling, and keyboard layout.
- Tester and date.
- Appearance, window size, text size, contrast, and motion settings.
- Live-data hash manifest location and successful before-test verification.

Use these result values only: `PASS`, `FAIL`, or `BLOCKED`. Blank means not performed.

## Common keyboard-only checks

Apply these checks to every workflow:

- Tab and Shift-Tab follow a logical order with no focus trap, skipped required control, or unexpected jump into decorative content.
- The focused control has a visible focus indicator in Light, Dark, and Increase Contrast.
- Space or Return activates buttons, checkboxes, disclosures, menus, tables, and alerts as expected; arrow keys operate grouped choices and table selection.
- The default and cancel actions in confirmations are clear. Destructive or irreversible-looking choices never receive an unsafe default merely because the dialog opens.
- Sidebar, toolbar, inspectors, disclosures, tables, popovers, and native file panels are usable without a pointer.
- Shortcuts have working menu equivalents and do not discard unsaved work.

## Common VoiceOver checks

Apply these checks to every workflow:

- Every interactive control speaks a concise name, role, value/state, and availability; repeated controls remain distinguishable.
- Headings and landmarks appear in a useful rotor order. Tables announce their purpose, selection, row context, and relevant values.
- Decorative map or visual elements do not obscure the useful controls; route and status information has a non-visual equivalent.
- Focus moves to newly presented alerts, previews, or editors and returns to a sensible control when they close.
- Save, finalise, amendment creation, Trash/Restore, suggestion acceptance, import completion, restore rollback, and validation failures produce one understandable announcement without noisy duplication.
- Warnings, draft/finalised state, selection, success, and failure are not communicated by colour alone.

## Workflow walkthroughs

### 1. New flight and Save Draft

- [ ] Keyboard-only result:
- [ ] VoiceOver result:

Use Command-N, enter literal departure, arrival, flight number, time, counts, remarks, coordinates, role, and simulator values, then use Command-S. Confirm the typed values remain unchanged, the draft state is explicit, and “Draft saved” is announced. Verify editor sections disclose in a logical order and entered values are distinguishable from suggestions.

### 2. Unsaved navigation: Cancel, Save, and Discard

- [ ] Keyboard-only result:
- [ ] VoiceOver result:

Create an unsaved draft and navigate away three times, exercising Cancel, Save Draft, and Discard Changes. Confirm focus enters the alert on a safe action, each choice is spoken unambiguously, Cancel returns to the edited field, Save retains the values, and Discard affects only the unsaved draft changes.

### 3. Finalise, immutable view, and amendment

- [ ] Keyboard-only result:
- [ ] VoiceOver result:

Finalise a draft with acknowledged warnings, confirm structural errors block finalisation, and verify the finalised view is announced as immutable. Create and finalise an amendment. Confirm the original remains available, the relationship and superseded state are spoken, and the finalise/amendment outcomes are announced.

### 4. Trash, Undo, multi-select Restore, and related flight

- [ ] Keyboard-only result:
- [ ] VoiceOver result:

Create two drafts, move both to Trash, undo one move, then open History > Trash. Select multiple remaining synthetic drafts with the keyboard, restore them explicitly, and open a related flight. Confirm selected count, row state, Undo, Restore, and completion are announced. Confirm no permanent-delete action exists.

### 5. Individual and selected suggestions

- [ ] Keyboard-only result:
- [ ] VoiceOver result:

Review distance, coordinates, night, and role suggestions. Confirm inputs, method, provenance, confidence, proposed value, and any reason no safe suggestion exists are reachable and spoken. Accept one suggestion, accept a selected batch, then undo both. Confirm non-zero entered values are never overwritten without an explicit accepted action.

### 6. LogTen import preview and operation history

- [ ] Keyboard-only result:
- [ ] VoiceOver result:

Use the native open panel, inspect additions/changes/duplicates/conflicts/unchanged/omissions, toggle individual fields, and choose duplicate/conflict outcomes. Confirm Blackbox/source/result values and the resulting draft or amendment action are clear. Apply the plan, verify the completion announcement, then open its operation and revision history.

### 7. Document import and duplicate resolution

- [ ] Keyboard-only result:
- [ ] VoiceOver result:

Choose the deterministic synthetic document, review parsed fields and validation, apply selected fields, then import the same document again. Confirm the second pass is identified as unchanged or duplicate, requires an explicit resolution where applicable, and cannot silently create the same flight twice.

### 8. Backup, restore rehearsal, verified restore, and rollback

- [ ] Keyboard-only result:
- [ ] VoiceOver result:

Create and verify a synthetic encrypted backup, inspect last-verified status and recovery-point location, and run the restore rehearsal. Open the restore preview and confirm it says nothing has changed. Complete a verified restore, then repeat with the test-only post-swap failure fixture and confirm the rollback announcement, retained synthetic sentinel flight, failed-operation detail, and recovery outcome.

### 9. Comparison states

- [ ] Keyboard-only result:
- [ ] VoiceOver result:

Exercise genuine match, difference, empty, unreadable, and missing-source fixtures. Confirm each state has text and an appropriate accessible value, not colour alone. A match badge must be absent for empty, failed, unavailable, and loading states.

### 10. Shared filters, analysis drill-down, and map navigation

- [ ] Keyboard-only result:
- [ ] VoiceOver result:

Apply date, aircraft, function, operation, entry-type, state, and text filters. Confirm chips, result count, included states, and Reset Filters are reachable and spoken consistently across Flights, Analysis, Map, and exports. Drill down from a total, open a shown route, and confirm the matching flight opens. Repeat with unsaved edits and exercise Cancel, Save, and Discard before route navigation.

### 11. Export destination and Reveal in Finder

- [ ] Keyboard-only result:
- [ ] VoiceOver result:

Confirm the exact record count and states included before export. Choose a temporary destination with the native folder panel, export the CAA-format report, activate Reveal in Finder, and inspect the export operation history. Confirm the wording describes internal/logbook checks and does not claim regulatory certification.

### 12. Shortcuts and menu/navigation coverage

- [ ] Keyboard-only result:
- [ ] VoiceOver result:

Exercise New, Save, Search, Duplicate, Finalise, Undo, and sidebar navigation through shortcuts and menu equivalents. Confirm disabled commands expose their state, shortcuts do not bypass validation or confirmation, focus remains visible, and VoiceOver identifies the current destination and editor state.

### 13. History search and contextual navigation

- [ ] Keyboard-only result:
- [ ] VoiceOver result:

Open History directly and through View History links from a flight, import, restore, and report. Search Revisions, inspect field-level before/after values, origin, batch, and date, navigate the amendment chain, then inspect operation verification/failure/recovery details and Reveal in Finder where available. Confirm Trash, Operations, and Revisions are usable through headings and rotor navigation.

## Cross-cutting visual and motion review

- [ ] Light Regular and Light Compact principal screens reviewed.
- [ ] Dark Regular and Dark Compact principal screens reviewed.
- [ ] Increase Contrast Regular and Compact principal screens reviewed.
- [ ] Largest supported text: no clipped labels, unreachable controls, overlapping text, or horizontal truncation that hides facts.
- [ ] Reduce Motion: non-essential animation is removed while progress and state changes remain understandable.
- [ ] Targets are comfortably selectable, adjacent controls are not easily confused, and icon-only controls have labels/tooltips.
- [ ] State, warning, selection, and validation meaning remains understandable without colour.
- [ ] The 72 automated snapshot images and all retained XCUITest screenshots contain synthetic identities only.

## Sign-off

Do not sign this section while any result is blank, `FAIL`, or `BLOCKED`.

- Automated CI run conclusion:
- Snapshot artifact reviewed by:
- Keyboard-only walkthrough completed by/date:
- VoiceOver walkthrough completed by/date:
- Accessibility defects and issue links:
- Final live-data hash verification result:
- Release gate: `PASS` / `FAIL` / `BLOCKED`

Signing, notarization, stapling, Gatekeeper, and quarantined synthetic smoke-launch results are recorded separately in [RELEASE_VERIFICATION.md](RELEASE_VERIFICATION.md).
