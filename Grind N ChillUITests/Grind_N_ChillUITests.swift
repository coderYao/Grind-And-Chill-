//
//  Grind_N_ChillUITests.swift
//  Grind N ChillUITests
//
//  Created by Shuyang Yao on 2/10/26.
//

import XCTest

final class Grind_N_ChillUITests: XCTestCase {
    private enum TestCategoryUnit {
        case time
        case count
        case money

        var label: String {
            switch self {
            case .time:
                return "Time"
            case .count:
                return "Count"
            case .money:
                return "Money"
            }
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if let run = testRun as? XCTestCaseRun, run.failureCount > 0 {
            let sanitizedName = Self.sanitizedTestName(from: name)
            let timestamp = Self.timestampForAttachment()

            MainActor.assumeIsolated {
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "Failure-\(sanitizedName)-\(timestamp)"
                attachment.lifetime = .keepAlways
                XCTContext.runActivity(named: attachment.name ?? "Failure Screenshot") { activity in
                    activity.add(attachment)
                }
            }
        }

        try super.tearDownWithError()
    }

    @MainActor
    func testCategoryCreateEditDeleteFlow() throws {
        let app = makeApp()
        app.launch()
        navigateToTab("Categories", in: app)

        let originalTitle = "UI Focus"
        let updatedTitle = "UI Focus Updated"

        addCategory(named: originalTitle, in: app)
        XCTAssertTrue(app.staticTexts[originalTitle].waitForExistence(timeout: 2))

        app.staticTexts[originalTitle].tap()
        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.clearAndTypeText(updatedTitle)
        app.navigationBars.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts[updatedTitle].waitForExistence(timeout: 2))

        let updatedCell = app.staticTexts[updatedTitle]
        XCTAssertTrue(updatedCell.exists)
        updatedCell.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))
        deleteButton.tap()

        XCTAssertTrue(app.staticTexts["Category deleted."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts[updatedTitle].waitForNonExistence(timeout: 2))
    }

    @MainActor
    func testTimerSessionCreatesHistoryEntry() throws {
        let app = makeApp()
        app.launch()
        navigateToTab("Categories", in: app)
        addCategory(named: "Timer Test", in: app)

        navigateToTab("Session", in: app)
        XCTAssertTrue(app.buttons["Start Session"].waitForExistence(timeout: 2))
        app.buttons["Start Session"].tap()

        let stopButton = app.buttons["Stop & Save"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 2))
        stopButton.tap()

        XCTAssertTrue(app.staticTexts["Session saved."].waitForExistence(timeout: 2))

        navigateToTab("History", in: app)
        XCTAssertTrue(app.staticTexts["Timer • 1m"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCountCategoryManualEntryUsesCountConversion() throws {
        let app = makeApp()
        app.launch()
        navigateToTab("Categories", in: app)
        addCategory(
            named: "Hydration Count",
            unit: .count,
            usdPerCount: "2.50",
            in: app
        )

        navigateToTab("Session", in: app)
        app.buttons["session.saveManual"].tap()
        XCTAssertTrue(app.staticTexts["Manual entry saved."].waitForExistence(timeout: 2))

        navigateToTab("History", in: app)
        XCTAssertTrue(waitForStaticText(containing: "Manual", in: app, timeout: 6))
        XCTAssertTrue(app.staticTexts["$2.50"].waitForExistence(timeout: 6))
    }

    @MainActor
    func testMoneyCategoryManualEntryUsesDirectAmount() throws {
        let app = makeApp()
        app.launch()
        navigateToTab("Categories", in: app)
        addCategory(
            named: "Coffee Spend",
            unit: .money,
            in: app
        )

        navigateToTab("Session", in: app)
        let amountField = app.textFields["session.manualAmount"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 2))
        amountField.clearAndTypeText("7.25")
        app.buttons["session.saveManual"].tap()
        XCTAssertTrue(app.staticTexts["Manual entry saved."].waitForExistence(timeout: 2))
    }

    @MainActor
    func testTimeCategoryHourlyRateManualEntryUsesCustomRate() throws {
        let app = makeApp()
        app.launch()
        navigateToTab("Categories", in: app)
        addCategory(
            named: "Deep Work Rate",
            unit: .time,
            useHourlyRate: true,
            hourlyRate: "30",
            in: app
        )

        navigateToTab("Session", in: app)
        XCTAssertTrue(app.buttons["session.start"].exists)
        app.buttons["session.saveManual"].tap()
        XCTAssertTrue(app.staticTexts["Manual entry saved."].waitForExistence(timeout: 2))
    }

    @MainActor
    private func addCategory(
        named title: String,
        unit: TestCategoryUnit = .time,
        useHourlyRate: Bool = false,
        hourlyRate: String = "18",
        usdPerCount: String = "1.00",
        in app: XCUIApplication
    ) {
        let addButton = app.navigationBars.buttons["Add"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 4))
        if addButton.isHittable {
            addButton.tap()
        } else {
            addButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let titleField = app.textFields["categoryEditor.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 4))
        titleField.tap()
        titleField.typeText(title)

        if unit != .time {
            let unitPicker = app.segmentedControls["categoryEditor.unit"]
            XCTAssertTrue(unitPicker.waitForExistence(timeout: 2))
            unitPicker.buttons[unit.label].tap()
        }

        if unit == .time, useHourlyRate {
            let conversionPicker = app.segmentedControls["categoryEditor.timeConversion"]
            XCTAssertTrue(conversionPicker.waitForExistence(timeout: 2))
            conversionPicker.buttons["Hourly Rate"].tap()

            let rateField = app.textFields["categoryEditor.rate"]
            XCTAssertTrue(rateField.waitForExistence(timeout: 2))
            rateField.clearAndTypeText(hourlyRate)
        }

        if unit == .count {
            let countField = app.textFields["categoryEditor.usdPerCount"]
            XCTAssertTrue(countField.waitForExistence(timeout: 2))
            countField.clearAndTypeText(usdPerCount)
        }

        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Categories"].waitForExistence(timeout: 4))
    }

    @MainActor
    private func navigateToTab(_ tabName: String, in app: XCUIApplication) {
        let button = app.tabBars.buttons[tabName]
        XCTAssertTrue(button.waitForExistence(timeout: 8))

        for _ in 0 ..< 5 {
            dismissKeyboardIfPresent(in: app)

            if button.isHittable {
                button.tap()
            } else {
                button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }

            if app.navigationBars[tabName].waitForExistence(timeout: 2) {
                return
            }
        }

        XCTFail("Could not navigate to \(tabName) tab.")
    }

    @MainActor
    private func waitForStaticText(
        containing text: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let element = app.staticTexts.matching(predicate).firstMatch
        return element.waitForExistence(timeout: timeout)
    }

    @MainActor
    private func dismissKeyboardIfPresent(in app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }

        let doneButton = app.toolbars.buttons["Done"]
        if doneButton.exists && doneButton.isHittable {
            doneButton.tap()
            return
        }

        let returnButton = app.keyboards.buttons["return"]
        if returnButton.exists && returnButton.isHittable {
            returnButton.tap()
            return
        }

        app.tap()
    }

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset-store",
            "-ui-testing-disable-cloudkit",
            "-ui-testing-disable-animations",
            "-settings.hasCompletedOnboarding",
            "YES",
            "-settings.usdPerHour",
            "18"
        ]
        return app
    }

    private static func sanitizedTestName(from rawName: String) -> String {
        let base = rawName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        return base.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: "_")
    }

    private static func timestampForAttachment() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}

private extension XCUIElement {
    @MainActor
    func clearAndTypeText(_ text: String) {
        tap()

        guard let currentValue = value as? String else {
            typeText(text)
            return
        }

        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
        typeText(deleteString + text)
    }

    @MainActor
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
