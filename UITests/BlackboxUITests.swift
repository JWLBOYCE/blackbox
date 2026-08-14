import XCTest

final class BlackboxUITests: XCTestCase {
    private static let isolatedHomePrefix = "Blackbox-XCUITest-Home-"
    private static let isolatedHomeMarker = ".blackbox-synthetic-ui-test-home"
    private static let isolatedHomeMarkerContents = "Blackbox synthetic UI-test preference home\n"

    private var app: XCUIApplication!
    private var dataRoot: URL!
    private var isolatedHome: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false

        try prepareFreshSyntheticApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 12), "Blackbox did not present its main window")
    }

    override func tearDownWithError() throws {
        if let app, app.state != .notRunning {
            let appearance = ProcessInfo.processInfo.environment["BLACKBOX_UI_TEST_APPEARANCE"] ?? "system"
            let width = ProcessInfo.processInfo.environment["BLACKBOX_UI_TEST_WIDTH"] ?? "default"
            let textSize = ProcessInfo.processInfo.environment["BLACKBOX_UI_TEST_DYNAMIC_TYPE_SIZE"] ?? "standard-text"
            let motion = ProcessInfo.processInfo.environment["BLACKBOX_UI_TEST_REDUCE_MOTION"] == "1" ? "reduced-motion" : "standard-motion"
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Blackbox-\(appearance)-\(width)-\(textSize)-\(motion)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
            let didTerminate = app.wait(for: .notRunning, timeout: 5)
            XCTAssertTrue(didTerminate, "Blackbox did not terminate cleanly after the UI test")
            guard didTerminate else { return }
        }
        try removeIsolatedHomeIfPresent()
    }

    func testNewFlightLiteralValuesAndSaveShortcut() {
        app.typeKey("n", modifierFlags: .command)

        replaceText(in: textField("Departure"), with: "EGLL")
        replaceText(in: textField("Arrival"), with: "EHAM")
        replaceText(in: textField("Flight number"), with: "UI100")

        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Draft saved"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "UI100", type: .staticText).exists)
    }

    func testUnsavedNavigationCancelSaveDiscardAndFailedSavePaths() throws {
        app.typeKey("n", modifierFlags: .command)
        replaceText(in: textField("Departure"), with: "EGLL")

        let initialWindowCount = app.windows.count
        app.typeKey("w", modifierFlags: .command)
        let closeAlert = dialog("Unsaved Draft")
        XCTAssertTrue(closeAlert.buttons["Save Draft & Close"].exists)
        XCTAssertTrue(closeAlert.buttons["Discard Changes & Close"].exists)
        XCTAssertFalse(closeAlert.buttons["Save Draft & Quit"].exists)
        XCTAssertFalse(closeAlert.buttons["Discard Changes & Quit"].exists)
        closeAlert.buttons["Cancel"].click()
        XCTAssertEqual(app.windows.count, initialWindowCount, "Cancelling Command-W must keep the primary window open")
        XCTAssertTrue(app.windows.firstMatch.exists, "Cancelling Command-W must preserve the primary window")
        XCTAssertEqual(textField("Departure").value as? String, "EGLL", "Cancelling Command-W must preserve literal unsaved values")

        openSection("History", subtitle: "Trash and audit trail")
        var alert = dialog("Unsaved Draft")
        alert.buttons["Cancel"].click()
        XCTAssertEqual(textField("Departure").value as? String, "EGLL")

        openSection("History", subtitle: "Trash and audit trail")
        alert = dialog("Unsaved Draft")
        alert.buttons["Save Draft"].click()
        XCTAssertTrue(app.staticTexts["Recover drafts and inspect every recorded change or reliability operation."].waitForExistence(timeout: 5))

        openSection("Flights", subtitle: "Flight entries")
        app.typeKey("n", modifierFlags: .command)
        replaceText(in: textField("Arrival"), with: "EHAM")
        openSection("History", subtitle: "Trash and audit trail")
        alert = dialog("Unsaved Draft")
        alert.buttons["Discard Changes"].click()
        XCTAssertTrue(app.staticTexts["Recover drafts and inspect every recorded change or reliability operation."].waitForExistence(timeout: 5))

        try relaunch(extraEnvironment: ["BLACKBOX_UI_TEST_SAVE_FAILURE": "1"])
        app.typeKey("n", modifierFlags: .command)
        replaceText(in: textField("Departure"), with: "EGLL")
        openSection("History", subtitle: "Trash and audit trail")
        let failedSaveAlert = dialog("Unsaved Draft")
        failedSaveAlert.buttons["Save Draft"].click()
        XCTAssertTrue(app.staticTexts["Could not save draft: injected synthetic persistence failure"].waitForExistence(timeout: 5))
        XCTAssertEqual(textField("Departure").value as? String, "EGLL")
        XCTAssertFalse(app.staticTexts["Recover drafts and inspect every recorded change or reliability operation."].exists)

        replaceText(in: textField("Departure"), with: "EGKK")
        app.typeKey("q", modifierFlags: .command)
        let failedQuitSaveAlert = dialog("Unsaved Draft")
        XCTAssertTrue(failedQuitSaveAlert.buttons["Save Draft & Quit"].exists)
        XCTAssertTrue(failedQuitSaveAlert.buttons["Discard Changes & Quit"].exists)
        XCTAssertFalse(failedQuitSaveAlert.buttons["Save Draft & Close"].exists)
        XCTAssertFalse(failedQuitSaveAlert.buttons["Discard Changes & Close"].exists)
        failedQuitSaveAlert.buttons["Save Draft & Quit"].click()
        XCTAssertNotEqual(app.state, .notRunning, "A failed Save Draft during Command-Q must cancel termination")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 3), "A failed Save Draft during Command-Q must keep the primary window open")
        XCTAssertEqual(textField("Departure").value as? String, "EGKK", "A failed Save Draft during Command-Q must preserve literal unsaved values")

        app.typeKey("q", modifierFlags: .command)
        dialog("Unsaved Draft").buttons["Discard Changes & Quit"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5), "Explicit discard must permit Blackbox to quit")
        try relaunch(extraEnvironment: [:])
    }

    func testFinalisedFlightCreatesAndFinalisesAmendment() {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(element(containing: "Departure is missing", type: .staticText).waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [.command, .shift])
        let warningAlert = dialog("Finalise Entry?")
        XCTAssertTrue(element(containing: "warning(s) remain", type: .staticText).exists)
        warningAlert.buttons["Finalise & Lock"].click()
        XCTAssertTrue(app.staticTexts["Entry finalised"].waitForExistence(timeout: 6), "Acknowledged warnings must not prevent finalisation")

        openSection("Flights", subtitle: "Flight entries")
        let importedFlight = element(containing: "BX104", type: .staticText)
        XCTAssertTrue(importedFlight.waitForExistence(timeout: 5))
        importedFlight.click()

        // Offscreen LazyVGrid rows are intentionally absent from AppKit's
        // accessibility snapshot. Stop on the first snapshot where Total
        // materialises; a corrective full swipe can overshoot the lazy row.
        let totalTimeQuery = app.descendants(matching: .any)["flight.time.total"]
        scrollEditor(untilExists: totalTimeQuery)
        let visibleTotalTime = app.descendants(matching: .any)["flight.time.total"]
        XCTAssertTrue(visibleTotalTime.waitForExistence(timeout: 5))
        XCTAssertFalse(visibleTotalTime.isEnabled, "Finalised entered times must remain immutable")

        let advancedSection = app.buttons["flight.section.advanced.toggle"]
        XCTAssertTrue(advancedSection.waitForExistence(timeout: 5))
        scrollEditor(untilHittable: advancedSection)
        advancedSection.click()
        let signatureName = app.descendants(matching: .any)["flight.signature.name"]
        XCTAssertTrue(signatureName.waitForExistence(timeout: 5), "A finalised entry's advanced section must remain inspectable")
        XCTAssertEqual(signatureName.value as? String, "Not entered")
        XCTAssertFalse(app.textFields["flight.signature.name"].exists, "Finalised signature facts must not remain editable")

        let amendment = app.buttons["Create Amendment"]
        XCTAssertTrue(amendment.waitForExistence(timeout: 5))
        XCTAssertTrue(amendment.isHittable, "Create Amendment must remain in the fixed editor action bar")
        amendment.click()
        XCTAssertTrue(app.staticTexts["Created an amendment draft. The finalised original is unchanged."].waitForExistence(timeout: 5))

        // The first finalisation above covers the keyboard shortcut. Use the
        // amendment editor's stable action identifier here so this assertion
        // tests amendment finalisation, not AppKit shortcut focus routing.
        let amendmentFinalise = app.buttons["flight.finalise.primary"]
        XCTAssertTrue(amendmentFinalise.waitForExistence(timeout: 5))
        XCTAssertTrue(amendmentFinalise.isEnabled)
        XCTAssertTrue(amendmentFinalise.isHittable)
        amendmentFinalise.click()
        let alert = dialog("Finalise Entry?")
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Finalise & Lock"].click()
        XCTAssertTrue(app.staticTexts["Amendment finalised; the original is preserved as superseded"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Create Amendment"].waitForExistence(timeout: 3))

        app.buttons["flight.viewHistory"].click()
        let historyContext = app.descendants(matching: .any)["history.context"]
        XCTAssertTrue(historyContext.waitForExistence(timeout: 6))
        XCTAssertTrue(element(containing: "amendment-chain history", type: .staticText).exists)
        let relatedFlight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.revision.flight.")).firstMatch
        XCTAssertTrue(relatedFlight.waitForExistence(timeout: 5))
        relatedFlight.click()
        XCTAssertTrue(flightsTable().waitForExistence(timeout: 6), "A history relationship must navigate to its preserved flight")
    }

    func testTrashUndoAndExplicitRestore() {
        app.typeKey("n", modifierFlags: .command)
        replaceText(in: textField("Departure"), with: "EGLL")
        replaceText(in: textField("Arrival"), with: "EHAM")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Draft saved"].waitForExistence(timeout: 5))

        app.buttons["Move to Trash"].click()
        let trashAlert = dialog("Move Draft to Trash?")
        trashAlert.buttons["Move to Trash"].click()
        XCTAssertTrue(app.staticTexts["Moved draft to Trash. Choose Undo to restore it"].waitForExistence(timeout: 5))

        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Restored draft from Trash"].waitForExistence(timeout: 5))

        openSection("History", subtitle: "Trash and audit trail")
        let trashTable = app.descendants(matching: .any)["history.trash.table"]
        XCTAssertTrue(trashTable.waitForExistence(timeout: 5))
        let trashRows = trashTable.descendants(matching: .outlineRow)
        XCTAssertGreaterThanOrEqual(trashRows.count, 2)
        let firstTrashCell = trashRows.element(boundBy: 0).descendants(matching: .cell).firstMatch
        XCTAssertTrue(firstTrashCell.waitForExistence(timeout: 3))
        XCTAssertTrue(firstTrashCell.isHittable)
        firstTrashCell.click()
        app.typeKey(.downArrow, modifierFlags: .shift)
        let restoreSelected = app.buttons["history.trash.restoreSelected"]
        XCTAssertTrue(restoreSelected.waitForExistence(timeout: 3))
        XCTAssertTrue(restoreSelected.isEnabled)
        restoreSelected.click()
        XCTAssertTrue(element(containing: "Restored 2 drafts", type: .staticText).waitForExistence(timeout: 5))
    }

    func testIndividualAndSelectedSuggestionAcceptanceAndUndo() {
        app.typeKey("n", modifierFlags: .command)
        replaceText(in: textField("Departure"), with: "EGLL")
        replaceText(in: textField("Arrival"), with: "EHAM")

        let unavailableNight = app.staticTexts["suggestions.reason.nightMinutes"]
        let unavailableRole = app.staticTexts["suggestions.reason.picMinutes"]
        XCTAssertTrue(unavailableNight.waitForExistence(timeout: 5))
        XCTAssertTrue(unavailableRole.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["suggestions.accept.nightMinutes"].isEnabled)
        XCTAssertFalse(app.buttons["suggestions.accept.picMinutes"].isEnabled)

        let departureSelection = app.descendants(matching: .any)["Select Departure coordinates"]
        let arrivalSelection = app.descendants(matching: .any)["Select Arrival coordinates"]
        XCTAssertTrue(departureSelection.waitForExistence(timeout: 5))
        XCTAssertTrue(arrivalSelection.waitForExistence(timeout: 5))
        scrollEditor(untilHittable: departureSelection)
        departureSelection.click()
        scrollEditor(untilHittable: arrivalSelection)
        arrivalSelection.click()
        let acceptSelectedCoordinates = app.buttons["Accept Selected Suggestions"]
        scrollEditor(untilHittable: acceptSelectedCoordinates)
        acceptSelectedCoordinates.click()
        XCTAssertTrue(app.staticTexts["Accepted selected suggestions"].waitForExistence(timeout: 5))

        // A later native text edit must be the first Command-Z target. The
        // second Undo reaches the older Blackbox operation; Redo walks them in
        // the opposite order. This exercises the hosted responder/window stack,
        // not only the headless UndoManager tests.
        let laterFlightNumber = textField("Flight number")
        replaceText(in: laterFlightNumber, with: "UNDO-ORDER")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertNotEqual(textField("Flight number").value as? String, "UNDO-ORDER")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Undid accepted suggestions"].waitForExistence(timeout: 5))
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Redid accepted suggestions"].waitForExistence(timeout: 5))
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertEqual(textField("Flight number").value as? String, "UNDO-ORDER")

        let suggestionFixture = flightRow(containing: "BX-NIGHT")
        XCTAssertTrue(suggestionFixture.waitForExistence(timeout: 5))
        let suggestionFixtureCell = suggestionFixture.descendants(matching: .cell).firstMatch
        XCTAssertTrue(suggestionFixtureCell.waitForExistence(timeout: 3))
        XCTAssertTrue(suggestionFixtureCell.isHittable)
        suggestionFixtureCell.click()
        let unsavedAlert = dialog("Unsaved Draft")
        unsavedAlert.buttons["Discard Changes"].click()

        let nightAccept = app.buttons["suggestions.accept.nightMinutes"]
        let roleAccept = app.buttons["suggestions.accept.copilotMinutes"]
        XCTAssertTrue(nightAccept.waitForExistence(timeout: 5))
        XCTAssertTrue(roleAccept.waitForExistence(timeout: 5))
        XCTAssertTrue(nightAccept.isEnabled, "The deterministic winter-night fixture must offer a conservative night suggestion")
        XCTAssertTrue(roleAccept.isEnabled, "The exact co-pilot mapping must offer an explicit role suggestion")

        scrollEditor(untilHittable: roleAccept)
        roleAccept.click()
        XCTAssertTrue(element(containing: "Accepted Co-pilot allocation suggestion", type: .staticText).waitForExistence(timeout: 5))
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(element(containing: "Undid Co-pilot allocation suggestion", type: .staticText).waitForExistence(timeout: 5))

        let selectNight = app.checkBoxes["suggestions.select.nightMinutes"]
        let selectCopilot = app.checkBoxes["suggestions.select.copilotMinutes"]
        let acceptSelected = app.buttons["suggestions.acceptSelected"]
        scrollEditor(untilHittable: selectNight)
        selectNight.click()
        scrollEditor(untilHittable: selectCopilot)
        selectCopilot.click()
        scrollEditor(untilHittable: acceptSelected)
        acceptSelected.click()
        XCTAssertTrue(app.staticTexts["Accepted selected suggestions"].waitForExistence(timeout: 5))
    }

    func testLogTenFieldPreviewApplyAndOperationHistory() {
        openSection("Import", subtitle: "PDF and OCR")
        app.buttons["import.chooseLogTen"].click()
        chooseInOpenPanel(dataRoot.appendingPathComponent("Import Sources/LogTenImportChanges.sql"))

        XCTAssertTrue(app.staticTexts["LogTen Import Preview"].waitForExistence(timeout: 8))
        let matchedChanges = app.buttons["import.changes.toggle"]
        XCTAssertTrue(matchedChanges.waitForExistence(timeout: 3))
        scrollUntilHittable(matchedChanges, in: "import.screen")
        matchedChanges.click()
        let change = app.descendants(matching: .any)["import.change.1001"]
        XCTAssertTrue(change.waitForExistence(timeout: 3))
        let totalFieldIdentifier = "import.field.1001.total"
        let totalField = app.checkBoxes[totalFieldIdentifier]
        XCTAssertTrue(totalField.waitForExistence(timeout: 3))
        scrollUntilHittable(totalField, in: "import.screen")
        XCTAssertTrue(waitForCheckboxState(true, of: totalField, timeout: 3))
        totalField.click()
        let excludedTotalField = app.checkBoxes[totalFieldIdentifier]
        XCTAssertTrue(waitForCheckboxState(false, of: excludedTotalField, timeout: 3))
        excludedTotalField.click()
        XCTAssertTrue(waitForCheckboxState(true, of: app.checkBoxes[totalFieldIdentifier], timeout: 3))

        let applyImport = app.buttons["import.apply"]
        scrollUntilHittable(applyImport, in: "import.screen")
        applyImport.click()
        XCTAssertTrue(element(containing: "Imported 0 additions and reviewed 1 changes", type: .staticText).waitForExistence(timeout: 8))
        openSection("History", subtitle: "Trash and audit trail")
        app.descendants(matching: .any)["Operations"].click()
        XCTAssertTrue(element(containing: "Logten Import", type: .staticText).waitForExistence(timeout: 5))
    }

    func testDocumentImportPreviewApplyAndDuplicateMatching() throws {
        let document = dataRoot.appendingPathComponent("Import Sources/SyntheticDocument.txt")
        try Data("12/08/2026 EGLL EHAM G-BBX3 1:20 SIC1:20 PAX120 231NM\n".utf8).write(to: document, options: .atomic)

        openSection("Import", subtitle: "PDF and OCR")
        app.buttons["import.chooseDocuments"].click()
        chooseInOpenPanel(document)
        XCTAssertTrue(element(containing: "1 candidates", type: .staticText).waitForExistence(timeout: 8))
        let reviewSelected = app.buttons["import.reviewSelected"]
        scrollUntilHittable(reviewSelected, in: "import.screen")
        reviewSelected.click()
        XCTAssertTrue(app.staticTexts["Document Import Preview"].waitForExistence(timeout: 5))
        let applyImport = app.buttons["import.apply"]
        scrollUntilHittable(applyImport, in: "import.screen")
        applyImport.click()
        XCTAssertTrue(element(containing: "Imported 1 additions", type: .staticText).waitForExistence(timeout: 8))

        let chooseFiles = app.buttons["import.chooseDocuments"]
        scrollUntilHittable(chooseFiles, in: "import.screen", preferredGesture: .down)
        chooseFiles.click()
        chooseInOpenPanel(document)
        XCTAssertTrue(element(containing: "1 candidates", type: .staticText).waitForExistence(timeout: 8))
        scrollUntilHittable(reviewSelected, in: "import.screen")
        reviewSelected.click()
        let unchangedMetric = app.descendants(matching: .any)["import.metric.unchanged"]
        XCTAssertTrue(unchangedMetric.waitForExistence(timeout: 5), "A repeated document batch must be matched instead of silently duplicated")
        XCTAssertEqual(unchangedMetric.value as? String, "1")
        scrollUntilHittable(applyImport, in: "import.screen")
        XCTAssertFalse(applyImport.isEnabled)
    }

    func testBackupVerificationRestorePreviewAndRehearsal() throws {
        openSection("Reports", subtitle: "CSV and print")
        let passphrase = "Synthetic-Only-2026!"
        let passphraseField = secureField("Backup passphrase")
        scrollUntilHittable(passphraseField, in: "reports.screen")
        replaceText(in: passphraseField, with: passphrase)
        let createBackup = app.buttons["reports.createBackup"]
        scrollUntilHittable(createBackup, in: "reports.screen")
        createBackup.click()
        XCTAssertTrue(element(containing: "Created and verified encrypted backup", type: .staticText).waitForExistence(timeout: 12))
        XCTAssertTrue(element(containing: "Last verified backup passed", type: .staticText).waitForExistence(timeout: 5))

        scrollUntilHittable(passphraseField, in: "reports.screen", preferredGesture: .down)
        replaceText(in: passphraseField, with: passphrase)
        let rehearseRestore = app.buttons["reports.rehearseRestore"]
        scrollUntilHittable(rehearseRestore, in: "reports.screen")
        rehearseRestore.click()
        XCTAssertTrue(element(containing: "Synthetic restore rehearsal completed", type: .staticText).waitForExistence(timeout: 12))

        guard let backup = firstFile(withExtension: "blackboxbackup", below: dataRoot) else {
            XCTFail("The verified synthetic backup artifact was not created")
            return
        }
        scrollUntilHittable(passphraseField, in: "reports.screen", preferredGesture: .down)
        replaceText(in: passphraseField, with: passphrase)
        let restoreBackup = app.buttons["reports.restoreBackup"]
        scrollUntilHittable(restoreBackup, in: "reports.screen")
        restoreBackup.click()
        chooseInOpenPanel(backup)
        XCTAssertTrue(app.staticTexts["Verified Restore Preview"].waitForExistence(timeout: 12))
        XCTAssertTrue(element(containing: "Nothing has been changed", type: .staticText).waitForExistence(timeout: 5))
        let applyRestore = app.buttons["reports.applyRestore"]
        scrollUntilHittable(applyRestore, in: "reports.screen")
        applyRestore.click()
        XCTAssertTrue(element(containing: "Restored encrypted backup. Recovery point", type: .staticText).waitForExistence(timeout: 12))
    }

    func testRestoreInjectedPostSwapFailureRollsBackOriginalDatabase() throws {
        try relaunch(extraEnvironment: ["BLACKBOX_UI_TEST_RESTORE_FAILURE_STAGE": "afterAtomicSwap"])

        openSection("Reports", subtitle: "CSV and print")
        let passphrase = "Synthetic-Rollback-2026!"
        let passphraseField = secureField("Backup passphrase")
        scrollUntilHittable(passphraseField, in: "reports.screen")
        replaceText(in: passphraseField, with: passphrase)
        let createBackup = app.buttons["reports.createBackup"]
        scrollUntilHittable(createBackup, in: "reports.screen")
        createBackup.click()
        XCTAssertTrue(element(containing: "Created and verified encrypted backup", type: .staticText).waitForExistence(timeout: 12))
        guard let backup = firstFile(withExtension: "blackboxbackup", below: dataRoot) else {
            XCTFail("The rollback test could not find its synthetic backup")
            return
        }

        openSection("Flights", subtitle: "Flight entries")
        app.typeKey("n", modifierFlags: .command)
        replaceText(in: textField("Departure"), with: "EGLL")
        replaceText(in: textField("Arrival"), with: "EHAM")
        replaceText(in: textField("Flight number"), with: "UI-RB-KEEP")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Draft saved"].waitForExistence(timeout: 5))

        openSection("Reports", subtitle: "CSV and print")
        scrollUntilHittable(passphraseField, in: "reports.screen")
        replaceText(in: passphraseField, with: passphrase)
        let restoreBackup = app.buttons["reports.restoreBackup"]
        scrollUntilHittable(restoreBackup, in: "reports.screen")
        restoreBackup.click()
        chooseInOpenPanel(backup)
        XCTAssertTrue(app.staticTexts["Verified Restore Preview"].waitForExistence(timeout: 12))
        let applyRestore = app.buttons["reports.applyRestore"]
        scrollUntilHittable(applyRestore, in: "reports.screen")
        applyRestore.click()
        XCTAssertTrue(element(containing: "Restore failed. Verified recovery point restored", type: .staticText).waitForExistence(timeout: 12))

        openSection("Flights", subtitle: "Flight entries")
        let refresh = app.buttons.matching(NSPredicate(format: "label == %@", "Refresh")).firstMatch
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.click()
        XCTAssertTrue(element(containing: "UI-RB-KEEP", type: .staticText).waitForExistence(timeout: 8), "The post-backup draft must survive the injected post-swap failure")

        openSection("History", subtitle: "Trash and audit trail")
        app.descendants(matching: .any)["Operations"].click()
        XCTAssertTrue(element(containing: "Verified recovery point restored", type: .staticText).waitForExistence(timeout: 8))
    }

    func testComparisonMissingUnreadableEmptyDifferentAndGenuineMatchStates() throws {
        openSection("Compare", subtitle: "LogTen side by side")
        XCTAssertTrue(app.staticTexts["Imported LogTen Rows Match"].waitForExistence(timeout: 8))
        let sourceFolder = dataRoot.appendingPathComponent("Import Sources", isDirectory: true)
        let source = sourceFolder.appendingPathComponent("LogTenCoreDataStore.sql")

        try replaceComparisonSource(source, with: sourceFolder.appendingPathComponent("LogTenImportChanges.sql"))
        comparisonRefreshButton().click()
        XCTAssertTrue(app.staticTexts["Review Differences"].waitForExistence(timeout: 8))

        try replaceComparisonSource(source, with: sourceFolder.appendingPathComponent("LogTenEmpty.sql"))
        comparisonRefreshButton().click()
        XCTAssertTrue(app.staticTexts["Empty Source"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Imported LogTen Rows Match"].exists)

        try replaceComparisonSource(source, with: sourceFolder.appendingPathComponent("LogTenUnreadable.sql"))
        comparisonRefreshButton().click()
        XCTAssertTrue(app.staticTexts["Comparison Failed"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Imported LogTen Rows Match"].exists)

        try replaceComparisonSource(source, with: nil)
        comparisonRefreshButton().click()
        XCTAssertTrue(app.staticTexts["Source Unavailable"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Imported LogTen Rows Match"].exists)
    }

    func testSharedFiltersAnalysisDrillDownAndMapToFlightNavigation() {
        openSection("Analysis", subtitle: "Types and places")
        XCTAssertTrue(app.descendants(matching: .any)["analysis.recordStates"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["analysis.savedGroups"].exists)
        let a320 = app.descendants(matching: .any)["analysis.type.a320"]
        XCTAssertTrue(a320.waitForExistence(timeout: 5))
        a320.click()
        XCTAssertTrue(flightsTable().waitForExistence(timeout: 6))
        XCTAssertTrue(element(containing: "Type: A320", type: .staticText).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["filters.reset"].waitForExistence(timeout: 3))
        app.buttons["filters.reset"].click()

        openSection("Flights", subtitle: "Flight entries")
        selectFilterValue(dimension: "Date range", value: "Last 12 months")
        XCTAssertTrue(element(containing: "From ", type: .staticText).waitForExistence(timeout: 5))
        selectFilterValue(dimension: "Aircraft", value: "G-BBX1")
        XCTAssertTrue(app.staticTexts["Filter: Aircraft: G-BBX1"].waitForExistence(timeout: 5))
        selectFilterValue(dimension: "Aircraft type", value: "A320")
        XCTAssertTrue(app.staticTexts["Filter: Type: A320"].waitForExistence(timeout: 5))
        selectFilterValue(dimension: "Pilot function", value: "Co-pilot")
        XCTAssertTrue(app.staticTexts["Filter: Function: Co-pilot"].waitForExistence(timeout: 5))
        selectFilterValue(dimension: "Operation", value: "MP")
        XCTAssertTrue(app.staticTexts["Filter: Operation: MP"].waitForExistence(timeout: 5))
        selectFilterValue(dimension: "Entry type", value: "Flight")
        XCTAssertTrue(app.staticTexts["Filter: Type: Flight"].waitForExistence(timeout: 5))
        selectFilterValue(dimension: "Record state", value: "Finalised")
        XCTAssertTrue(app.staticTexts["Filter: States: Draft"].waitForExistence(timeout: 5))
        app.buttons["filters.reset"].click()

        openSection("3D Map", subtitle: "Route globe")
        let openShownFlight = app.descendants(matching: .any)["map.openFlight"]
        XCTAssertTrue(openShownFlight.waitForExistence(timeout: 8))
        XCTAssertTrue(openShownFlight.isHittable, "The route menu must remain fully inside the visible map")
        let mapRange = app.descendants(matching: .any)["map.filter.range"]
        XCTAssertTrue(mapRange.waitForExistence(timeout: 5))
        mapRange.click()
        app.menuItems["12 months"].click()
        XCTAssertTrue(element(containing: "From ", type: .staticText).waitForExistence(timeout: 5))

        openShownFlight.click()
        let editableRoute = mappedRouteMenuItem(containing: "EHAM → EDDF")
        XCTAssertTrue(editableRoute.waitForExistence(timeout: 5))
        editableRoute.click()
        XCTAssertTrue(flightsTable().waitForExistence(timeout: 6))

        replaceText(in: textField("Route"), with: "DCT-SAVE")
        openSection("3D Map", subtitle: "Route globe")
        var unsavedAlert = dialog("Unsaved Draft")
        unsavedAlert.buttons["Cancel"].click()
        XCTAssertEqual(textField("Route").value as? String, "DCT-SAVE")

        openSection("3D Map", subtitle: "Route globe")
        unsavedAlert = dialog("Unsaved Draft")
        unsavedAlert.buttons["Save Draft"].click()
        XCTAssertTrue(app.descendants(matching: .any)["map.screen"].waitForExistence(timeout: 6))
        openMapRoute(containing: "EHAM → EDDF")
        XCTAssertEqual(textField("Route").value as? String, "DCT-SAVE")

        replaceText(in: textField("Route"), with: "DCT-DISCARD")
        openSection("3D Map", subtitle: "Route globe")
        unsavedAlert = dialog("Unsaved Draft")
        unsavedAlert.buttons["Discard Changes"].click()
        XCTAssertTrue(app.descendants(matching: .any)["map.screen"].waitForExistence(timeout: 6))
        openMapRoute(containing: "EHAM → EDDF")
        XCTAssertEqual(textField("Route").value as? String, "DCT-SAVE", "Discarding map navigation must retain the last saved value")
    }

    func testExportToSelectedFolderAndRevealAction() throws {
        openSection("Reports", subtitle: "CSV and print")
        XCTAssertTrue(element(containing: "CAA-format export currently includes exactly 1 finalised active record", type: .staticText).waitForExistence(timeout: 5))
        let destination = dataRoot.appendingPathComponent("Exports", isDirectory: true)
        let chooseExportFolder = app.buttons["reports.chooseExportFolder"]
        chooseExportFolder.click()
        XCTAssertTrue(
            waitForDisabled(app.windows.firstMatch, timeout: 8),
            "The native export folder panel did not attach modally"
        )
        chooseExportFolderInSystemPanel(destination)
        let exportAlert = dialog("Confirm CAA-format Export")
        XCTAssertTrue(element(containing: "exactly 1 finalised active record", type: .staticText).exists)
        XCTAssertTrue(
            element(containing: destination.path, type: .staticText).exists,
            "The native folder panel must return the exact synthetic export destination"
        )
        exportAlert.buttons["Export CAA-format Report"].click()
        XCTAssertTrue(element(containing: "Exported 1 finalised record", type: .staticText).waitForExistence(timeout: 8))
        let exportedFiles = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
        XCTAssertTrue(exportedFiles.contains { $0.pathExtension.lowercased() == "csv" })
        XCTAssertTrue(exportedFiles.contains { $0.pathExtension.lowercased() == "html" })
        app.buttons["reports.viewExportHistory"].click()
        XCTAssertTrue(app.descendants(matching: .any)["history.screen"].waitForExistence(timeout: 6))
        XCTAssertTrue(element(containing: "Exported 1 finalised active records in CAA format", type: .staticText).waitForExistence(timeout: 5))
        openSection("Reports", subtitle: "CSV and print")
        XCTAssertTrue(app.buttons["reports.revealLastExport"].isEnabled)
        app.buttons["reports.revealLastExport"].click()
    }

    func testKeyboardShortcutsAndConfiguredWindowSize() {
        let requestedWidth = Double(ProcessInfo.processInfo.environment["BLACKBOX_UI_TEST_WIDTH"] ?? "0") ?? 0
        if requestedWidth > 0 {
            let displayFrame = app.screenshot().image.size
            let windowFrame = app.windows.firstMatch.frame
            let expectedWidth = min(CGFloat(requestedWidth), displayFrame.width - 24)
            XCTAssertEqual(windowFrame.width, expectedWidth, accuracy: 8)
            XCTAssertGreaterThanOrEqual(windowFrame.minX, 0)
            XCTAssertGreaterThanOrEqual(windowFrame.minY, 0)
            XCTAssertLessThanOrEqual(windowFrame.maxX, displayFrame.width)
            XCTAssertLessThanOrEqual(windowFrame.maxY, displayFrame.height)
        }

        let initialWindowCount = app.windows.count
        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(app.windows.count, initialWindowCount, "Command-N must create a flight in the current window, not open another window")
        replaceText(in: textField("Departure"), with: "EGLL")
        replaceText(in: textField("Route"), with: "DCT-NATIVE-UNDO")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertNotEqual(
            textField("Route").value as? String,
            "DCT-NATIVE-UNDO",
            "Command-Z must retain native text-field Undo before any Blackbox operation Undo"
        )
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Draft saved"].waitForExistence(timeout: 5))
        app.typeKey("d", modifierFlags: .command)
        let recordStatus = app.staticTexts["Record status"]
        XCTAssertTrue(recordStatus.waitForExistence(timeout: 3))
        XCTAssertEqual(recordStatus.value as? String, "Unsaved draft")

        app.typeKey("f", modifierFlags: .command)
        let flightSearch = app.textFields["flights.search"]
        XCTAssertTrue(flightSearch.waitForExistence(timeout: 3))
        flightSearch.typeText("BX104")
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey(.return, modifierFlags: [.command, .shift])
        let finaliseAlert = dialog("Finalise Entry?")
        finaliseAlert.buttons["Cancel"].click()
    }

    private func copyMatrixVariable(_ key: String) {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            app.launchEnvironment[key] = value
        }
    }

    private func relaunch(extraEnvironment: [String: String]) throws {
        if app.state != .notRunning {
            app.terminate()
            let didTerminate = app.wait(for: .notRunning, timeout: 5)
            XCTAssertTrue(didTerminate, "Blackbox did not terminate before relaunch")
            guard didTerminate else {
                throw NSError(
                    domain: "BlackboxUITests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Refusing to replace test state while Blackbox is running"]
                )
            }
        }
        try removeIsolatedHomeIfPresent()
        try prepareFreshSyntheticApplication(extraEnvironment: extraEnvironment)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 12), "Blackbox did not relaunch its synthetic UI-test window")
    }

    private func prepareFreshSyntheticApplication(extraEnvironment: [String: String] = [:]) throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        isolatedHome = temporaryDirectory
            .appendingPathComponent("\(Self.isolatedHomePrefix)\(UUID().uuidString)", isDirectory: true)
        XCTAssertFalse(fileManager.fileExists(atPath: isolatedHome.path))
        try fileManager.createDirectory(at: isolatedHome, withIntermediateDirectories: false)
        try Data(Self.isolatedHomeMarkerContents.utf8)
            .write(to: isolatedHome.appendingPathComponent(Self.isolatedHomeMarker), options: .atomic)

        dataRoot = isolatedHome
            .appendingPathComponent("Blackbox-XCUITest-\(UUID().uuidString)", isDirectory: true)
        XCTAssertFalse(fileManager.fileExists(atPath: dataRoot.path))

        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["HOME"] = isolatedHome.path
        app.launchEnvironment["CFFIXED_USER_HOME"] = isolatedHome.path
        app.launchEnvironment["BLACKBOX_DATA_ROOT"] = dataRoot.path
        app.launchEnvironment["BLACKBOX_SYNTHETIC_FIXTURE"] = "deterministic"
        copyMatrixVariable("BLACKBOX_UI_TEST_APPEARANCE")
        copyMatrixVariable("BLACKBOX_UI_TEST_WIDTH")
        copyMatrixVariable("BLACKBOX_UI_TEST_HEIGHT")
        copyMatrixVariable("BLACKBOX_UI_TEST_INCREASE_CONTRAST")
        copyMatrixVariable("BLACKBOX_UI_TEST_DYNAMIC_TYPE_SIZE")
        copyMatrixVariable("BLACKBOX_UI_TEST_REDUCE_MOTION")
        for (key, value) in extraEnvironment { app.launchEnvironment[key] = value }
    }

    private func removeIsolatedHomeIfPresent() throws {
        guard let isolatedHome else { return }
        guard app == nil || app.state == .notRunning else {
            XCTFail("Refusing to remove synthetic UI-test files while Blackbox is running")
            return
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: isolatedHome.path) else {
            self.isolatedHome = nil
            return
        }

        let canonicalHome = isolatedHome.standardizedFileURL.resolvingSymlinksInPath()
        let canonicalTemporaryDirectory = fileManager.temporaryDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let marker = canonicalHome.appendingPathComponent(Self.isolatedHomeMarker)
        let markerContents = try? String(contentsOf: marker, encoding: .utf8)
        guard canonicalHome.deletingLastPathComponent() == canonicalTemporaryDirectory,
              canonicalHome.lastPathComponent.hasPrefix(Self.isolatedHomePrefix),
              markerContents == Self.isolatedHomeMarkerContents
        else {
            XCTFail("Refusing to remove an unverified synthetic UI-test home: \(canonicalHome.path)")
            return
        }

        try fileManager.removeItem(at: canonicalHome)
        self.isolatedHome = nil
        dataRoot = nil
    }

    private func openSection(_ title: String, subtitle: String) {
        let identifier = "sidebar.\(title.lowercased().replacingOccurrences(of: " ", with: "-"))"
        let identified = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if identified.waitForExistence(timeout: 2) {
            identified.click()
            return
        }
        let accessibleLabel = app.staticTexts["\(title), \(subtitle)"]
        if accessibleLabel.waitForExistence(timeout: 2) {
            accessibleLabel.click()
            return
        }
        let fallback = app.staticTexts[title].firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 3), "Missing sidebar section \(title)")
        fallback.click()
    }

    private func textField(_ label: String) -> XCUIElement {
        let identifier = "flight.field.\(label.flightAccessibilityIdentifierComponent)"
        let field = app.textFields.matching(identifier: identifier).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing text field \(identifier)")
        if !field.isHittable {
            scrollEditor(untilHittable: field)
        }
        return field
    }

    private func secureField(_ label: String) -> XCUIElement {
        let identifier = "reports.field.\(label.flightAccessibilityIdentifierComponent)"
        let field = app.secureTextFields.matching(identifier: identifier).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing secure field \(identifier)")
        return field
    }

    private func replaceText(in element: XCUIElement, with value: String) {
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeText(value)
    }

    private func selectFilterValue(dimension: String, value: String) {
        let editor = app.descendants(matching: .any)["filters.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Missing All Filters control")
        editor.click()
        let dimensionItem = app.menuItems[dimension]
        XCTAssertTrue(dimensionItem.waitForExistence(timeout: 3), "Missing \(dimension) filter dimension")
        dimensionItem.hover()
        let valueItem = app.menuItems[value]
        XCTAssertTrue(valueItem.waitForExistence(timeout: 3), "Missing \(value) in \(dimension)")
        valueItem.click()
    }

    private func openMapRoute(containing route: String) {
        let menu = app.descendants(matching: .any)["map.openFlight"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(menu.isHittable, "The route menu must remain fully inside the visible map")
        menu.click()
        let routeItem = mappedRouteMenuItem(containing: route)
        XCTAssertTrue(routeItem.waitForExistence(timeout: 5), "Missing mapped route \(route)")
        routeItem.click()
        XCTAssertTrue(flightsTable().waitForExistence(timeout: 6))
    }

    private func mappedRouteMenuItem(containing route: String) -> XCUIElement {
        app.menuItems.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND (title CONTAINS %@ OR label CONTAINS %@)",
            "map.route.",
            route,
            route
        )).firstMatch
    }

    private func scrollEditor(untilHittable element: XCUIElement) {
        let identifiedEditor = app.scrollViews["flight.editor.scroll"]
        let editor: XCUIElement
        if identifiedEditor.waitForExistence(timeout: 2) {
            editor = identifiedEditor
        } else {
            let scrollViews = app.scrollViews
            XCTAssertGreaterThan(scrollViews.count, 0, "Missing flight editor scroll container")
            editor = scrollViews.element(boundBy: max(0, scrollViews.count - 1))
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Missing flight editor scroll container")
        XCTAssertTrue(editor.isHittable, "Flight editor scroll container is outside the visible window")
        for _ in 0..<16 where !isSafelyVisible(element, in: editor) {
            guard element.exists else {
                editor.swipeUp(velocity: .slow)
                continue
            }
            let targetFrame = element.frame
            let editorFrame = editor.frame
            if !targetFrame.isEmpty, targetFrame.midY < editorFrame.midY {
                editor.swipeDown(velocity: .slow)
            } else {
                editor.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(
            isSafelyVisible(element, in: editor),
            "Could not reveal the requested element inside the flight editor viewport"
        )
    }

    /// Lazy editor content can be inspected without being a hit target. Stop as
    /// soon as the requested row materialises so a full-velocity corrective
    /// swipe cannot carry it past the opposite edge of the viewport.
    private func scrollEditor(untilExists element: XCUIElement) {
        let identifiedEditor = app.scrollViews["flight.editor.scroll"]
        let editor: XCUIElement
        if identifiedEditor.waitForExistence(timeout: 2) {
            editor = identifiedEditor
        } else {
            let scrollViews = app.scrollViews
            XCTAssertGreaterThan(scrollViews.count, 0, "Missing flight editor scroll container")
            editor = scrollViews.element(boundBy: max(0, scrollViews.count - 1))
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Missing flight editor scroll container")
        XCTAssertTrue(editor.isHittable, "Flight editor scroll container is outside the visible window")

        for _ in 0..<16 where !element.exists {
            editor.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 2), "Could not materialise the requested editor element")
    }

    private func isSafelyVisible(_ element: XCUIElement, in editor: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let targetFrame = element.frame
        let visibleEditorFrame = editor.frame.insetBy(dx: 4, dy: 10)
        guard !targetFrame.isEmpty, !visibleEditorFrame.isEmpty else { return false }
        return targetFrame.minY >= visibleEditorFrame.minY &&
            targetFrame.maxY <= visibleEditorFrame.maxY &&
            targetFrame.midX >= visibleEditorFrame.minX &&
            targetFrame.midX <= visibleEditorFrame.maxX
    }

    private enum ScrollGesture: Equatable {
        case up
        case down
    }

    private func scrollUntilHittable(
        _ element: XCUIElement,
        in containerIdentifier: String,
        preferredGesture: ScrollGesture = .up,
        maxSwipes: Int = 16
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing \(element.identifier) before scrolling")
        let screen = app.descendants(matching: .any)[containerIdentifier]
        XCTAssertTrue(screen.waitForExistence(timeout: 3), "Missing screen container \(containerIdentifier)")
        let scrollIdentifier = containerIdentifier.replacingOccurrences(of: ".screen", with: ".scroll")
        let identifiedContainer = app.scrollViews[scrollIdentifier]
        let container = identifiedContainer.waitForExistence(timeout: 1)
            ? identifiedContainer
            : detailScrollView(overlapping: element)
        XCTAssertTrue(container.waitForExistence(timeout: 3), "Missing scroll container \(containerIdentifier)")

        for _ in 0..<maxSwipes where !element.isHittable {
            let targetFrame = element.frame
            let containerFrame = container.frame
            if !targetFrame.isEmpty, targetFrame.midY < containerFrame.midY {
                container.swipeDown()
            } else if !targetFrame.isEmpty, targetFrame.midY > containerFrame.midY {
                container.swipeUp()
            } else if preferredGesture == .up {
                container.swipeUp()
            } else {
                container.swipeDown()
            }
        }
        XCTAssertTrue(element.isHittable, "Could not reveal \(element.identifier) in \(containerIdentifier)")
    }

    private func detailScrollView(overlapping element: XCUIElement) -> XCUIElement {
        let scrollViews = app.scrollViews
        XCTAssertGreaterThan(scrollViews.count, 0, "Missing a detail scroll container")
        let targetFrame = element.frame
        var best: XCUIElement?
        for index in 0..<scrollViews.count {
            let candidate = scrollViews.element(boundBy: index)
            let frame = candidate.frame
            guard candidate.exists, !frame.isEmpty else { continue }
            let horizontallyOverlaps = targetFrame.isEmpty
                || (frame.minX <= targetFrame.midX && frame.maxX >= targetFrame.midX)
            guard horizontallyOverlaps else { continue }
            if best == nil || frame.minX > best!.frame.minX { best = candidate }
        }
        return best ?? scrollViews.element(boundBy: max(0, scrollViews.count - 1))
    }

    private func dialog(_ title: String) -> XCUIElement {
        let alert = app.alerts[title]
        if alert.waitForExistence(timeout: 1) { return alert }
        let titlePredicate = NSPredicate(format: "label == %@ OR value == %@", title, title)
        let sheet = app.sheets.containing(titlePredicate).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 4), "Missing alert or sheet titled \(title)")
        return sheet
    }

    private func flightsTable() -> XCUIElement {
        app.descendants(matching: .any)["flights.table"]
    }

    private func flightRow(containing value: String) -> XCUIElement {
        flightsTable().descendants(matching: .outlineRow)
            .containing(NSPredicate(
                format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
                value,
                value
            ))
            .firstMatch
    }

    private func element(containing value: String, type: XCUIElement.ElementType) -> XCUIElement {
        app.descendants(matching: type)
            .matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", value, value))
            .firstMatch
    }

    private func comparisonRefreshButton() -> XCUIElement {
        let refresh = app.buttons["comparison.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 3), "Missing comparison refresh action")
        return refresh
    }

    private func replaceComparisonSource(_ source: URL, with fixture: URL?) throws {
        let fileManager = FileManager.default
        let sidecars = ["-wal", "-shm"].map { URL(fileURLWithPath: source.path + $0) }

        guard let fixture else {
            for url in [source] + sidecars where fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return
        }

        let staged = source.deletingLastPathComponent()
            .appendingPathComponent(".\(source.lastPathComponent).\(UUID().uuidString).replacement")
        defer { try? fileManager.removeItem(at: staged) }
        try fileManager.copyItem(at: fixture, to: staged)

        for sidecar in sidecars where fileManager.fileExists(atPath: sidecar.path) {
            try fileManager.removeItem(at: sidecar)
        }
        if fileManager.fileExists(atPath: source.path) {
            _ = try fileManager.replaceItemAt(source, withItemAt: staged)
        } else {
            try fileManager.moveItem(at: staged, to: source)
        }
    }

    private func firstFile(withExtension pathExtension: String, below root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
        for case let url as URL in enumerator where url.pathExtension.lowercased() == pathExtension.lowercased() {
            return url
        }
        return nil
    }

    private func chooseInOpenPanel(_ url: URL) {
        let panelHost = app!
        // File panels can briefly move between sheet, dialog, and window roles
        // while AppKit attaches them. The explicit NSOpenPanel used for folder
        // selection is hosted by AppKit's panel service; SwiftUI file importers
        // remain in the target application's accessibility hierarchy.
        panelHost.typeKey("g", modifierFlags: [.command, .shift])
        let locationField = panelHost.textFields["PathTextField"]
        XCTAssertTrue(locationField.waitForExistence(timeout: 8), "The open panel did not present Go to Folder")
        locationField.typeText(url.path)
        locationField.typeKey(.return, modifierFlags: [])

        // Native open/save panels expose the primary action through the stable
        // AppKit accessibility identifier. Its visible title (Open, Choose, or
        // Export Here) is not necessarily exposed as XCUIElement.label. Query
        // from the active host because Go to Folder can rebuild the panel hierarchy;
        // PathTextField may remain as a stale accessibility proxy afterwards.
        let action = panelHost.buttons.matching(identifier: "OKButton").firstMatch
        guard action.waitForExistence(timeout: 8) else {
            XCTFail("The file panel did not expose its selection action")
            return
        }
        guard waitForEnabled(action, timeout: 8) else {
            XCTFail("The file panel did not enable its selection action")
            return
        }
        if action.isHittable {
            action.click()
        } else {
            // Some hosted AppKit panel hierarchies expose the selected, enabled
            // default button with an infinite AX frame. Return invokes that
            // default action without relying on unusable geometry.
            panelHost.typeKey(.return, modifierFlags: [])
        }
        // Each caller asserts the resulting import, restore preview, or export
        // confirmation. Do not wait on the generic first sheet here: a
        // successful selection can immediately replace it with that next sheet.
    }

    /// NSOpenPanel directory selection is hosted by an AppKit XPC view service
    /// on macOS 26. XCTest cannot enumerate that service as a standalone
    /// XCUIApplication, but synthesized keys still reach its focused field and
    /// default action. The exact synthetic export postconditions prove that the
    /// real panel returned the requested directory.
    private func chooseExportFolderInSystemPanel(_ url: URL) {
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(url.path)
        for _ in 0..<2 {
            app.typeKey(.return, modifierFlags: [])
            if dialogExists("Confirm CAA-format Export", timeout: 5) { return }
        }
    }

    private func dialogExists(_ title: String, timeout: TimeInterval) -> Bool {
        let titlePredicate = NSPredicate(format: "label == %@ OR value == %@", title, title)
        return app.descendants(matching: .any).matching(titlePredicate).firstMatch
            .waitForExistence(timeout: timeout)
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return element.exists && element.isEnabled
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForDisabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return element.exists && !element.isEnabled
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForCheckboxState(_ expectedState: Bool, of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            guard element.exists, let actualState = self.checkboxState(of: element) else { return false }
            return actualState == expectedState
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func checkboxState(of element: XCUIElement) -> Bool? {
        if let value = element.value as? NSNumber {
            return value.boolValue
        }
        guard let value = element.value as? String else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "on", "checked", "included": return true
        case "0", "false", "off", "unchecked", "excluded": return false
        default: return nil
        }
    }

    private func waitForNonexistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

private extension String {
    var flightAccessibilityIdentifierComponent: String {
        lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
