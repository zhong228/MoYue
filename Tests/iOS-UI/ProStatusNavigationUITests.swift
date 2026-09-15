import StoreKitTest
import XCTest

/// Drives Settings → account → 「閱讀Pro」 against the local StoreKit configuration.
///
/// The row chooses between the paywall and `YueduProView` from the entitlements
/// StoreKit reports at launch, so the routing and the status page's
/// subscription-management link are only observable with real transactions.
/// `SKTestSession` supplies them from `Configuration/YueduPro.storekit`, the file
/// the scheme's Run action uses, with no purchase dialogs or Apple Account.
final class ProStatusNavigationUITests: XCTestCase {
    private static let monthlyID = "com.zhangruilin.yuedureader.pro.monthly"
    private static let lifetimeID = "com.zhangruilin.yuedureader.pro.lifetime"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFreeUserOpensThePaywall() throws {
        let session = try makeStoreKitSession()
        defer { session.clearTransactions() }

        let app = openProRow(expectsPro: false)
        XCTAssertTrue(
            app.buttons["paywall_purchase_button"].waitForExistence(timeout: 10),
            "a free user should land on the paywall"
        )
        XCTAssertFalse(app.descendants(matching: .any)["pro_status_summary"].exists)
        attach("pro-row-free-paywall")
    }

    @MainActor
    func testMonthlySubscriberCanManageAndUpgrade() throws {
        let session = try makeStoreKitSession()
        defer { session.clearTransactions() }
        try session.buyProduct(productIdentifier: Self.monthlyID)

        let app = openProRow(expectsPro: true)
        assertStatusPage(app)
        XCTAssertEqual(app.buttons["pro_status_plan_action"].label, "Upgrade to Lifetime")
        XCTAssertTrue(
            reveal(app.buttons["pro_status_manage_subscription"], in: app),
            "a monthly subscriber must reach subscription management"
        )
        XCTAssertTrue(app.buttons["pro_status_restore"].exists)
        attach("pro-status-monthly")
    }

    @MainActor
    func testLifetimeOwnerHasNothingToManageOrBuy() throws {
        let session = try makeStoreKitSession()
        defer { session.clearTransactions() }
        try session.buyProduct(productIdentifier: Self.lifetimeID)

        let app = openProRow(expectsPro: true)
        assertStatusPage(app)
        XCTAssertTrue(reveal(app.buttons["pro_status_restore"], in: app), "restore should stay available")
        // Same section as restore, so it would be materialized if it were shown.
        XCTAssertFalse(app.buttons["pro_status_manage_subscription"].exists)
        XCTAssertFalse(app.buttons["pro_status_plan_action"].exists)
        attach("pro-status-lifetime")
    }

    @MainActor
    func testMonthlyAlongsideLifetimeKeepsTheCancellationReminder() throws {
        let session = try makeStoreKitSession()
        defer { session.clearTransactions() }
        try session.buyProduct(productIdentifier: Self.monthlyID)
        try session.buyProduct(productIdentifier: Self.lifetimeID)

        let app = openProRow(expectsPro: true)
        assertStatusPage(app)
        XCTAssertFalse(app.buttons["pro_status_plan_action"].exists)
        XCTAssertTrue(
            reveal(app.buttons["pro_status_manage_subscription"], in: app),
            "monthly held next to lifetime still needs a way to cancel"
        )
        XCTAssertTrue(
            app.staticTexts["Remember to cancel the monthly plan after upgrading, or it will keep billing."].exists
        )
        attach("pro-status-monthly-and-lifetime")
    }

    @MainActor
    private func makeStoreKitSession() throws -> SKTestSession {
        // Tests/iOS-UI/<this file> → repository root.
        let configuration = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Configuration/YueduPro.storekit")
        let session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    @MainActor
    private func openProRow(expectsPro: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // The notification prompt can land on top of the shelf on a fresh install.
        let notNow = app.buttons["Don’t Allow"]
        if notNow.waitForExistence(timeout: 2) { notNow.tap() }

        let settings = app.tabBars.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 20), "settings tab should exist")
        settings.tap()

        let account = app.buttons["settings_account_row"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 10), "the account row should exist")
        account.tap()

        let proRow = app.buttons["settings_pro_row"].firstMatch
        XCTAssertTrue(proRow.waitForExistence(timeout: 10), "the Yuedu Pro row should exist")
        if expectsPro {
            // Entitlements resolve after launch. Wait for the row to show them rather
            // than tapping into whichever destination the unresolved state picks.
            let unlocked = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS %@", "Enabled"),
                object: proRow
            )
            XCTAssertEqual(XCTWaiter.wait(for: [unlocked], timeout: 20), .completed, "StoreKit should unlock Pro")
        }
        proRow.tap()
        return app
    }

    /// The summary row is the first row of `YueduProView`, so it is on screen as
    /// soon as the page is pushed. The failure names the visible navigation bar to
    /// tell "not pushed" apart from "pushed but missing a row".
    @MainActor
    private func assertStatusPage(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let summary = app.descendants(matching: .any)["pro_status_summary"].firstMatch
        XCTAssertTrue(
            summary.waitForExistence(timeout: 10),
            "the status page should be pushed; visible navigation bar: \(app.navigationBars.firstMatch.identifier)",
            file: file,
            line: line
        )
    }

    /// SwiftUI does not expose a Form row to XCTest until it is near the viewport,
    /// so scroll toward rows that can sit below the fold on small screens or large text.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<4 where !element.exists {
            app.swipeUp()
        }
        return element.exists
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
