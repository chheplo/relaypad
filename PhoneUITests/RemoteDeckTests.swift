import XCTest

final class RemoteDeckTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchEnvironment["RELAYPAD_TEST_PREFERENCES"] = "com.sachibk.relaypad.tests." + UUID().uuidString
        app.launch()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 2), permission.label.contains("local network") {
            permission.buttons["Allow"].tap()
        }
    }

    func testLandscapeDeckAndHeaderWhenPhoneRotates() {
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

    func testAboutShowsOnlyThePublicVersion() throws {
        app.buttons["settings.open"].tap()
        let row = app.descendants(matching: .any)["about.version"].firstMatch
        for _ in 0..<8 where !row.isHittable {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        let version = try XCTUnwrap(Bundle(for: type(of: self)).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertEqual(row.label, "Version, \(version)")
        XCTAssertTrue(app.staticTexts["Developer, Pratik Desai (@chheplo)"].exists)
        XCTAssertTrue(app.buttons["about.repository"].exists)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "About Relaypad"
        image.lifetime = .keepAlways
        add(image)
    }

    func testShortcutRemappingSurvivesRelaunch() {
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
