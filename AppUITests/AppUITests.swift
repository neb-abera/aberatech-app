import XCTest

/// Every screen and button, driven through the app with abera.tech in
/// memory (`-demo`, App/Demo.swift), and Apple Health through the
/// simulator's real HealthKit.
@MainActor
final class AppUITests: XCTestCase {
    /// Runs first, by name, and only launches: the first launch under
    /// XCUITest on a fresh simulator can take a minute.
    func test0WarmUp() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        _ = app.tabBars.buttons["Requests"].waitForExistence(timeout: 120)
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo"] + arguments
        app.launch()
        return app
    }

    /// Taps a tab until it shows as selected. On iOS 27 (2026-11-22) a tap
    /// made while a system sheet was still closing was lost.
    private func open(_ tab: String, in app: XCUIApplication) {
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 15), app.debugDescription)
        for _ in 0..<3 {
            button.tap()
            if poll(3, { button.isSelected }) { return }
        }
        XCTFail("the \(tab) tab did not open:\n\(app.debugDescription)")
    }

    private func poll(_ timeout: TimeInterval, _ holds: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if holds() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return holds()
    }

    private func request(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons["request-\(title)"].firstMatch
    }

    // MARK: Sign-in

    func testSigningInOpensHerRequests() {
        let app = launch("-demo-signed-out")
        let signIn = app.buttons["sign-in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 15))
        signIn.tap()
        XCTAssertTrue(
            request(app, "Rake the leaves to the tree box").waitForExistence(timeout: 15), app.debugDescription)
    }

    func testSigningOutReturnsToSignIn() {
        let app = launch()
        open("Me", in: app)
        let who = app.descendants(matching: .any)["signed-in-as"].firstMatch
        XCTAssertTrue(who.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(who.label.contains("Heb") || (who.value as? String) == "Heb", who.debugDescription)
        app.buttons["sign-out"].tap()
        XCTAssertTrue(app.buttons["sign-in"].waitForExistence(timeout: 10))
    }

    // MARK: Requests

    func testHerRequestsShowTheirStatus() {
        let app = launch()
        let rake = request(app, "Rake the leaves to the tree box")
        XCTAssertTrue(rake.waitForExistence(timeout: 15))
        XCTAssertTrue(rake.label.contains("Received"), rake.label)
        XCTAssertTrue(request(app, "Fix the bathroom faucet").label.contains("In progress"))
        XCTAssertTrue(request(app, "Book the flight to Kansas City").label.contains("Done"))
        let fence = request(app, "Paint the fence")
        XCTAssertTrue(fence.label.contains("Not doing") && fence.label.contains("Hiring it out"), fence.label)
    }

    func testAddingARequestPutsItOnTheList() {
        let app = launch()
        let add = app.buttons["add-request"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        let title = app.textFields["request-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Buy leaf bags")
        app.buttons["save-request"].tap()
        let added = request(app, "Buy leaf bags")
        XCTAssertTrue(added.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(added.label.contains("Received"), added.label)
    }

    func testARequestWithNoTitleSaysWhy() {
        let app = launch()
        XCTAssertTrue(app.buttons["add-request"].waitForExistence(timeout: 15))
        app.buttons["add-request"].tap()
        XCTAssertTrue(app.buttons["save-request"].waitForExistence(timeout: 5))
        app.buttons["save-request"].tap()
        XCTAssertTrue(app.staticTexts["Add a title."].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testEditingARequestChangesItsTitle() {
        let app = launch()
        let faucet = request(app, "Fix the bathroom faucet")
        XCTAssertTrue(faucet.waitForExistence(timeout: 15))
        faucet.tap()
        let title = app.textFields["request-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        // A tap past the end of the text puts the cursor after it.
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        title.typeText(" and the shower")
        app.buttons["save-request"].tap()
        XCTAssertTrue(
            request(app, "Fix the bathroom faucet and the shower").waitForExistence(timeout: 10), app.debugDescription)
    }

    func testRemovingARequestTakesItOffTheListInOneTap() {
        let app = launch()
        let faucet = request(app, "Fix the bathroom faucet")
        XCTAssertTrue(faucet.waitForExistence(timeout: 15))
        faucet.tap()
        let remove = app.buttons["remove-request"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(poll(10) { !faucet.exists }, app.debugDescription)
    }

    func testAFinishedRequestCannotBeEdited() {
        let app = launch()
        let flight = request(app, "Book the flight to Kansas City")
        XCTAssertTrue(flight.waitForExistence(timeout: 15))
        flight.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["save-request"].exists)
        XCTAssertFalse(app.buttons["remove-request"].exists)
    }

    // MARK: Fitness and wish list

    func testFitnessShowsEachGoalWithItsForecastAndTheWeight() {
        let app = launch()
        open("Fitness", in: app)
        let bench = app.descendants(matching: .any)["goal-Bench Press"].firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(bench.label.contains("Now 207 lb, goal 248 lb"), bench.label)
        XCTAssertTrue(bench.label.contains("Forecast 227 lb"), bench.label)
        XCTAssertTrue(bench.label.contains("2% chance"), bench.label)
        let weight = app.descendants(matching: .any)["latest-weight"].firstMatch
        XCTAssertTrue(weight.exists)
        XCTAssertTrue(weight.label.contains("170.0 lb"), weight.label)
    }

    func testTheWishListShowsWhatIsWanted() {
        let app = launch()
        open("Wish list", in: app)
        let shoes = app.descendants(matching: .any)["wish-Running shoes"].firstMatch
        XCTAssertTrue(shoes.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Nike Pegasus 42"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["wish-AI camera"].exists)
    }

    // MARK: Apple Health

    func testAHouseholdPhoneHasNoAppleHealthSection() {
        let app = launch()
        open("Me", in: app)
        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["send-weights"].exists)
    }

    /// The Health sheet iOS shows the first time: turn every category on,
    /// then Allow. Its labels have moved between iOS releases: "Turn On
    /// All" on iOS 26, "Select All 2 Topics" on iOS 27 (2026-11-22). Its
    /// cell identifier, or either label, counts, in the app or in
    /// Springboard. False when no sheet came within the timeout.
    private func allowHealth(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let label = NSPredicate(
            format: "identifier == 'UIA.Health.AuthSheet.AllCategoryButton' "
                + "OR label BEGINSWITH[c] 'Turn On All' OR label BEGINSWITH[c] 'Select All'")
        let inApp = app.descendants(matching: .any).matching(label).firstMatch
        let inSpringboard = springboard.descendants(matching: .any).matching(label).firstMatch
        guard poll(timeout, { inApp.exists || inSpringboard.exists }) else { return false }
        let host = inApp.exists ? app : springboard
        (inApp.exists ? inApp : inSpringboard).tap()
        // iOS 26 labels the confirm button Allow. iOS 27 (2026-11-22) labels
        // it Continue, gives it the identifier UIA.Health.Allow.Button, and
        // puts it below the fold, so the sheet is scrolled until it shows.
        let allow = host.buttons.matching(
            NSPredicate(format: "identifier == 'UIA.Health.Allow.Button' OR label == 'Allow'")
        ).firstMatch
        for _ in 0..<4 where !(allow.exists && allow.isHittable) { host.swipeUp() }
        XCTAssertTrue(allow.isHittable, host.debugDescription)
        allow.tap()
        // iOS 27 then asks how much history to share, and its Allow stays
        // off until one is picked. The app sends the last 30 days, so the
        // test picks that. iOS 26 has no such page.
        let history = host.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Past 30 Days'")).firstMatch
        if history.waitForExistence(timeout: 5) {
            history.tap()
            let confirm = host.buttons["Allow"].firstMatch
            XCTAssertTrue(poll(5) { confirm.exists && confirm.isEnabled }, host.debugDescription)
            confirm.tap()
            XCTAssertTrue(poll(10) { !history.exists }, host.debugDescription)
        }
        let sheet = host.descendants(matching: .any).matching(label).firstMatch
        XCTAssertTrue(poll(10) { !sheet.exists }, host.debugDescription)
        return true
    }

    /// A weigh-in in Apple Health reaches abera.tech through the simulator's
    /// real HealthKit and the Health sheet a person sees. On 2026-11-21
    /// Neb's Lose It weigh-ins reached Apple Health and never abera.tech.
    func testAnAppleHealthWeighInIsSentToAberaTech() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // A fresh permission state, so iOS shows the Health sheet on every
        // run. Without it the sheet came on some runs and not others.
        app.resetAuthorizationStatus(for: .health)
        app.launchArguments = ["-demo", "-demo-owner", "-demo-health"]
        app.launch()
        // The launch refresh asks first. When that sheet does not come,
        // Send weigh-ins now asks again from the open screen.
        var allowed = allowHealth(app, timeout: 30)

        open("Me", in: app)
        let send = app.buttons["send-weights"]
        // On the iOS 27 simulator launch took 16 s on 2026-11-22, and the
        // launch sheet came after the 8 s wait and covered this screen.
        if !allowed && !send.waitForExistence(timeout: 5) { allowed = allowHealth(app, timeout: 20) }
        XCTAssertTrue(send.waitForExistence(timeout: 10), app.debugDescription)
        send.tap()
        if !allowed { allowed = allowHealth(app, timeout: 20) }
        if !allowed {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            XCTFail("no Health sheet:\n\(app.debugDescription)\nSpringboard:\n\(springboard.debugDescription)")
            return
        }

        let status = app.staticTexts["weight-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
        // The launch refresh may have sent it already: then this tap finds abera.tech up to date.
        XCTAssertTrue(
            poll(10) {
                status.label.hasPrefix("Sent to abera.tech: 1 new") || status.label == "Up to date with abera.tech."
            }, "\(status.label)\n\(app.debugDescription)")

        send.tap()
        XCTAssertTrue(poll(10) { status.label == "Up to date with abera.tech." }, status.label)
    }
}
