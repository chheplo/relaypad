import XCTest

final class RemoteDeckTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchEnvironment["RELAYPAD_TEST_PREFERENCES"] = "com.sachibk.relaypad.tests." + UUID().uuidString
    }

    private func openDeck() {
        app.launch()
        let later = app.buttons["setup.later"]
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        later.tap()
        allowLocalNetworkIfNeeded()
    }

    private func allowLocalNetworkIfNeeded() {
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 2), permission.label.localizedCaseInsensitiveContains("local network") {
            permission.buttons["Allow"].tap()
        }
    }

    func testCompanionSetupAndReturningToConnection() {
        app.launch()
        let findMac = app.buttons["setup.findMac"]
        XCTAssertTrue(findMac.waitForExistence(timeout: 5))
        let download = app.descendants(matching: .any)["companion.download"].firstMatch
        XCTAssertTrue(download.isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["companion.share"].firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "First-launch Mac setup"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        findMac.tap()
        allowLocalNetworkIfNeeded()
        XCTAssertTrue(app.navigationBars["Connection"].waitForExistence(timeout: 5))
        XCTAssertTrue(download.isHittable)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(findMac.exists)
        app.buttons["Connection, Pair Mac"].tap()
        XCTAssertTrue(app.navigationBars["Connection"].waitForExistence(timeout: 5))
        XCTAssertTrue(download.isHittable)
    }

    func testExistingPairingSkipsMacSetupOnUpdate() {
        app.launchArguments += ["-Relaypad.LastReceiver", UUID().uuidString]
        app.launch()
        allowLocalNetworkIfNeeded()
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["setup.findMac"].exists)
    }

    func testLandscapeDeckAndHeaderWhenPhoneRotates() {
        openDeck()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            let pad = app.descendants(matching: .any)["trackpad"].firstMatch
            XCTAssertTrue(pad.waitForExistence(timeout: 5))
            let keys = (0..<7).map { app.buttons["shortcut.\($0)"] }
            XCTAssertEqual(keys.map(\.label), ["Function", "Control", "Option", "1", "2", "3", "Space"])
            for key in keys {
                XCTAssertTrue(key.isHittable)
                XCTAssertGreaterThanOrEqual(key.frame.minX, pad.frame.maxX - 2)
                XCTAssertGreaterThanOrEqual(key.frame.height, 44)
            }
            for index in 0..<3 {
                XCTAssertEqual(keys[index].frame.midY, keys[index + 3].frame.midY, accuracy: 2)
                XCTAssertLessThan(keys[index].frame.maxX, keys[index + 3].frame.minX)
            }
            let space = keys[6].frame
            XCTAssertGreaterThan(space.minY, keys[5].frame.maxY)
            XCTAssertEqual(space.minX, keys[0].frame.minX, accuracy: 2)
            XCTAssertEqual(space.maxX, keys[3].frame.maxX, accuracy: 2)
            let right = keys.map(\.frame.maxX).max()!
            let fraction = pad.frame.width / (right - pad.frame.minX)
            XCTAssertEqual(fraction, 0.80, accuracy: 0.045)
            XCTAssertTrue(app.buttons["Left click"].isHittable)
            XCTAssertTrue(app.buttons["Right click"].isHittable)
            let frame = app.windows.firstMatch.frame
            XCTAssertGreaterThan(frame.width, frame.height)
            for item in ["Keyboard", "Gestures"] {
                let button = app.buttons[item]
                XCTAssertTrue(button.isHittable)
                XCTAssertLessThanOrEqual(button.frame.maxY, pad.frame.minY + 3)
            }
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = orientation == .portrait ? "Landscape deck at launch" : "Landscape deck rotated"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    func testAboutShowsPublicVersionAndPrivacyPolicy() throws {
        openDeck()
        app.buttons["settings.open"].tap()
        let version = try XCTUnwrap(Bundle(for: type(of: self)).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let elements = app.descendants(matching: .any)
        let developer = "Developer, Pratik Desai (@chheplo)"
        let rows = [
            (elements["about.version"].firstMatch, "Version, \(version)"),
            (app.staticTexts[developer], developer),
            (elements["about.repository"].firstMatch, "GitHub project"),
            (elements["about.privacy"].firstMatch, "Privacy policy"),
            (elements["companion.download"].firstMatch, "Download Relaypad for Mac")
        ]
        let list = app.collectionViews.firstMatch
        for (row, label) in rows {
            for _ in 0..<8 where !row.exists || !row.isHittable {
                list.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(row.exists && row.isHittable, "Could not reach \(label)")
            XCTAssertEqual(row.label, label)
        }
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "About Relaypad"
        image.lifetime = .keepAlways
        add(image)
    }

    func testShortcutRemappingSurvivesRelaunch() {
        openDeck()
        app.buttons["settings.open"].tap()
        app.buttons["binding.0"].tap()
        let preset = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "New chat")).firstMatch
        for _ in 0..<6 where !preset.exists || !preset.isHittable {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(preset.isHittable)
        preset.tap()
        app.buttons["Save"].tap()
        app.terminate()
        app.launch()
        XCTAssertEqual(app.buttons["shortcut.0"].label, "New chat")
    }
}
