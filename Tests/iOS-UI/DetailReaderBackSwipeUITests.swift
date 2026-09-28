import XCTest
import StoreKitTest

/// Prepare with scripts/navigation_swipe_fixture.py and serve localhost:18765.
/// These tests deliver actual touches to the production Explore/detail/reader.
final class DetailReaderBackSwipeUITests: XCTestCase {
    private var storeKitSession: SKTestSession?

    @MainActor
    private func configureStoreKit() throws {
        let configuration = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Configuration/YueduPro.storekit")
        let session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        storeKitSession = session
    }

    @MainActor
    func testDetailReaderLoadsAndReturns() throws {
        try exerciseNativeEntry(fromSearch: false)
    }

    @MainActor
    func testSearchDetailReaderLoadsAndReturns() throws {
        try exerciseNativeEntry(fromSearch: true)
    }

    @MainActor
    private func exerciseNativeEntry(fromSearch: Bool) throws {
        continueAfterFailure = false
        try configureStoreKit()
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-yd_root_tab_visible_ids", "(explore, settings)",
                               "-discover.selectedSourceId", "C5DED179-61D0-49C4-BDB7-93A7B3DAD8F4",
                               "-yd_page_turn_style", "滑動", "-yd_scroll_mode", "NO"]
        app.launch()
        if fromSearch {
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 15), app.debugDescription)
            search.tap()
            search.typeText("navigation\n")
        }
        let book = app.staticTexts["Navigation Swipe Fixture"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 20), app.debugDescription)
        book.tap()
        let read = app.buttons.matching(NSPredicate(format: "label IN %@", ["Read Now", "Continue Reading"])).firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 15), app.debugDescription)
        for _ in 0..<2 {
            read.tap()
            let content = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Reserved edge navigation")).firstMatch
            XCTAssertTrue(content.waitForExistence(timeout: 30), "The reader must finish loading after a detail push.\n\(app.debugDescription)")
            XCTAssertFalse(read.exists, "Opening must stay in the reader")
            // iOS 17 uses UIKit's narrow physical-edge recognizer; the 30 pt
            // content-pop reservation is available starting with iOS 26.
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 1, dy: app.frame.height * 0.5))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
            XCTAssertTrue(read.waitForExistence(timeout: 8), app.debugDescription)
            XCTAssertFalse(content.exists)
        }
    }

    @MainActor
    func testDetailMangaReaderLoadsAndReturns() throws {
        try exerciseMangaEntry(fromSearch: false)
    }

    @MainActor
    func testSearchDetailMangaReaderLoadsAndReturns() throws {
        try exerciseMangaEntry(fromSearch: true)
    }

    /// A manga opens in FixedPageReaderView, pushed onto the detail's own stack.
    /// That reader once wrapped itself in a second NavigationStack there, and
    /// manga stopped opening from a book detail (Technotes/iOS17ReaderNavigationWatchdog.md).
    @MainActor
    private func exerciseMangaEntry(fromSearch: Bool) throws {
        continueAfterFailure = false
        try configureStoreKit()
        let app = XCUIApplication()
        // Search starts from the text source's Explore, where only search can reach the manga.
        let discoverSource = fromSearch ? "C5DED179-61D0-49C4-BDB7-93A7B3DAD8F4" : "42017D70-DAD6-4EDE-845E-C5DBAC606CA4"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-yd_root_tab_visible_ids", "(explore, settings)",
                               "-discover.selectedSourceId", discoverSource]
        app.launch()
        if fromSearch {
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 15), app.debugDescription)
            search.tap()
            search.typeText("manga fixture\n")
        }
        let book = app.staticTexts["Navigation Manga Fixture"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 20), app.debugDescription)
        book.tap()
        let read = app.buttons.matching(NSPredicate(format: "label IN %@", ["Read Now", "Continue Reading"])).firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 15), app.debugDescription)
        let progress = app.sliders["Progress"]
        for entry in 1...2 {
            // Read Now stays disabled until the detail has loaded the contents.
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: read)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed, app.debugDescription)
            read.tap()
            waitForMangaPage(app)
            XCTAssertFalse(read.exists, "Opening must stay in the reader")
            showMangaControls(app, expecting: "Page 1 / 3")
            attachScreenshot(app, named: "Manga reader - \(fromSearch ? "search" : "explore") detail - entry \(entry)")
            if entry == 1 {
                // With the controls up, a tap on a turning zone only puts them away.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
                waitForMangaControlsHidden(app, because: "A turning tap must put the controls away")
                showMangaControls(app, expecting: "Page 1 / 3")
                // A swipe turns the page and puts them away too. Right to left: the
                // next page comes in from the left, under a drag to the right.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
                waitForMangaControlsHidden(app, because: "Turning the page must put the controls away")
                showMangaControls(app, expecting: "Page 2 / 3")
            }
            app.navigationBars.buttons["Back"].tap()
            XCTAssertTrue(read.waitForExistence(timeout: 8), "Back must return to the same detail.\n\(app.debugDescription)")
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: progress)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed, app.debugDescription)
        }
    }

    /// The shelf opens a manga with its card push, whose bar belongs to the shelf's
    /// UIKit navigation controller rather than to a SwiftUI stack. The book is added
    /// right before the app leaves the foreground and is killed: the shelf saves on a
    /// debounce, and leaving the foreground has to write it (it once lost the book).
    @MainActor
    func testShelfMangaOpensOnThePage() throws {
        continueAfterFailure = false
        try configureStoreKit()
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-yd_root_tab_visible_ids", "(explore, settings)",
                               "-discover.selectedSourceId", "42017D70-DAD6-4EDE-845E-C5DBAC606CA4"]
        app.launch()
        let discovered = app.staticTexts["Navigation Manga Fixture"].firstMatch
        XCTAssertTrue(discovered.waitForExistence(timeout: 20), app.debugDescription)
        discovered.tap()
        let add = app.buttons["Bookmarked"]
        let remove = app.buttons["Remove from Library"]
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label IN %@", ["Bookmarked", "Remove from Library"])).firstMatch.waitForExistence(timeout: 15))
        if add.exists {
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: add)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
            add.tap()
            XCTAssertTrue(remove.waitForExistence(timeout: 10), app.debugDescription)
        }
        XCUIDevice.shared.press(.home)
        let left = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.state == .runningBackground || app.state == .runningBackgroundSuspended
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [left], timeout: 10), .completed)
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-yd_root_tab_visible_ids", "(bookshelf, settings)", "-bookLayoutIsGrid", "NO"]
        app.launch()
        let book = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Navigation Manga Fixture")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15), app.debugDescription)
        book.tap()
        waitForMangaPage(app)
        showMangaControls(app, expecting: "Page 1 / 3")
        attachScreenshot(app, named: "Manga reader - shelf")
        app.navigationBars.buttons["Back"].tap()
        XCTAssertTrue(book.waitForExistence(timeout: 8), "Back must return to the shelf.\n\(app.debugDescription)")
    }

    /// The fixed-page reader opens on the page, with no controls over it.
    @MainActor
    private func waitForMangaPage(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.images["fixed_page_image"].waitForExistence(timeout: 30),
                      "The first page's image must be on screen.\n\(app.debugDescription)", file: file, line: line)
        XCTAssertFalse(app.sliders["Progress"].exists,
                       "The manga reader must open on the page, without its controls", file: file, line: line)
    }

    /// A tap in the middle brings the controls up. The progress slider speaks the
    /// page indicator (第 %d / %d 頁); chapter 1 has three pages.
    @MainActor
    private func showMangaControls(_ app: XCUIApplication, expecting indicator: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // `exists` first: reading `value` of a missing element fails the test outright.
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND value == %@", indicator), object: app.sliders["Progress"])
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 10), .completed,
                       "The controls must show \(indicator).\n\(app.debugDescription)", file: file, line: line)
    }

    @MainActor
    private func waitForMangaControlsHidden(_ app: XCUIApplication, because reason: String,
                                            file: StaticString = #filePath, line: UInt = #line) {
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.sliders["Progress"])
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed,
                       "\(reason).\n\(app.debugDescription)", file: file, line: line)
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// With the menu up, a tap on a page-turn zone only puts the menu away, as in
    /// Apple Books and legado; the next tap turns the page.
    @MainActor
    func testTapWithMenuUpOnlyPutsMenuAway() throws {
        continueAfterFailure = false
        try configureStoreKit()
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-yd_root_tab_visible_ids", "(explore, settings)",
                               "-discover.selectedSourceId", "C5DED179-61D0-49C4-BDB7-93A7B3DAD8F4",
                               "-yd_appearance_reader_interface", "classic",
                               "-yd_page_turn_style", "滑動", "-yd_scroll_mode", "NO"]
        app.launch()
        let book = app.staticTexts["Navigation Swipe Fixture"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 20), app.debugDescription)
        book.tap()
        let read = app.buttons.matching(NSPredicate(format: "label IN %@", ["Read Now", "Continue Reading"])).firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 15), app.debugDescription)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: read)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed, app.debugDescription)
        read.tap()
        let content = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Reserved edge navigation")).firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 30), app.debugDescription)
        let originalPage = content.label
        let menu = app.buttons["reader_back_button"]
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5), app.debugDescription)
        // The middle row's right third turns to the next page.
        let nextPageZone = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        nextPageZone.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed, app.debugDescription)
        XCTAssertEqual(content.label, originalPage, "The tap that puts the menu away must not also turn the page")
        nextPageZone.tap()
        let pageChanged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            content.exists && content.label != originalPage
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pageChanged], timeout: 5), .completed, "With the menu away, the tap turns the page")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5), app.debugDescription)
        menu.tap()
        XCTAssertTrue(read.waitForExistence(timeout: 8), app.debugDescription)
    }

    @MainActor func testSlideTurnHidesMenu() throws { try exerciseMenuHidesOnPageTurn(style: "滑動") }
    @MainActor func testCoverTurnHidesMenu() throws { try exerciseMenuHidesOnPageTurn(style: "覆蓋翻頁") }
    @MainActor func testCurlTurnHidesMenu() throws { try exerciseMenuHidesOnPageTurn(style: "仿真翻書") }
    @MainActor func testInstantTurnHidesMenu() throws { try exerciseMenuHidesOnPageTurn(style: "無動畫") }
    @MainActor func testScrollHidesMenu() throws { try exerciseMenuHidesOnPageTurn(style: "滑動", scroll: true) }

    /// Turning the page with the menu up puts the menu away, whichever gesture
    /// turned it: each page-turn style has its own (UIKit's swipe, the cover pan,
    /// the instant pan), and scroll mode turns by dragging.
    @MainActor
    private func exerciseMenuHidesOnPageTurn(style: String, scroll: Bool = false) throws {
        continueAfterFailure = false
        try configureStoreKit()
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-yd_root_tab_visible_ids", "(explore, settings)",
                               "-discover.selectedSourceId", "C5DED179-61D0-49C4-BDB7-93A7B3DAD8F4",
                               "-yd_appearance_reader_interface", "classic",
                               "-yd_page_turn_style", style, "-yd_scroll_mode", scroll ? "YES" : "NO"]
        app.launch()
        let book = app.staticTexts["Navigation Swipe Fixture"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 20), app.debugDescription)
        book.tap()
        let read = app.buttons.matching(NSPredicate(format: "label IN %@", ["Read Now", "Continue Reading"])).firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 15), app.debugDescription)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: read)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed, app.debugDescription)
        read.tap()
        let content = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Reserved edge navigation")).firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 30), app.debugDescription)
        let originalPage = content.label
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let menu = app.buttons["reader_back_button"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), app.debugDescription)
        // Across the middle of the page, clear of the menu's bars and the back-swipe edge.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: scroll ? 0.5 : 0.8, dy: scroll ? 0.6 : 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: scroll ? 0.5 : 0.2, dy: scroll ? 0.4 : 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed,
                       "Turning the page must put the menu away.\n\(app.debugDescription)")
        if !scroll {
            let pageChanged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                content.exists && content.label != originalPage
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [pageChanged], timeout: 5), .completed, "The drag must also turn the page")
        }
        // The menu still comes back on a tap; leaving through it releases the trial book.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5), app.debugDescription)
        menu.tap()
        XCTAssertTrue(read.waitForExistence(timeout: 8), app.debugDescription)
    }

    @MainActor
    func testClassicReaderControlsFromExploreAreAccessible() throws {
        continueAfterFailure = false
        try configureStoreKit()
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-yd_root_tab_visible_ids", "(explore, settings)",
                               "-discover.selectedSourceId", "C5DED179-61D0-49C4-BDB7-93A7B3DAD8F4",
                               "-yd_appearance_reader_interface", "classic",
                               "-yd_page_turn_style", "滑動", "-yd_scroll_mode", "NO"]
        app.launch()
        let book = app.staticTexts["Navigation Swipe Fixture"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 20), app.debugDescription)
        book.tap()
        let read = app.buttons.matching(NSPredicate(format: "label IN %@", ["Read Now", "Continue Reading"])).firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 15), app.debugDescription)
        read.tap()
        let content = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Reserved edge navigation")).firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 30), app.debugDescription)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["reader_back_button"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.textFields["Enter URL or search"].exists, "The covered browser must leave the accessibility tree")
        for label in ["Contents", "Settings", "Next"] {
            let button = app.buttons[label].firstMatch
            XCTAssertTrue(button.exists, app.debugDescription)
            XCTAssertTrue(button.isHittable, app.debugDescription)
        }
        app.buttons["Contents"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Chapter 2"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testShelfListExposesOneBookButtonAndOpensReader() throws {
        continueAfterFailure = false
        try configureStoreKit()
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-yd_root_tab_visible_ids", "(explore, settings)",
                               "-discover.selectedSourceId", "C5DED179-61D0-49C4-BDB7-93A7B3DAD8F4"]
        app.launch()
        let discovered = app.staticTexts["Navigation Swipe Fixture"].firstMatch
        XCTAssertTrue(discovered.waitForExistence(timeout: 20), app.debugDescription)
        discovered.tap()
        let remove = app.buttons["Remove from Library"]
        let add = app.buttons["Bookmarked"]
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label IN %@", ["Bookmarked", "Remove from Library"])).firstMatch.waitForExistence(timeout: 15))
        if add.exists {
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: add)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
            add.tap()
            XCTAssertTrue(remove.waitForExistence(timeout: 10), app.debugDescription)
        }
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-yd_root_tab_visible_ids", "(bookshelf, settings)",
                               "-bookLayoutIsGrid", "NO", "-yd_appearance_reader_interface", "classic"]
        app.launch()
        let book = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Navigation Swipe Fixture，Regression"))
        XCTAssertTrue(book.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(book.count, 1, "A list book must expose one combined activation target")
        book.firstMatch.tap()
        let content = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Reserved edge navigation")).firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 30), app.debugDescription)
    }

    @MainActor
    func testTTSPanelAndRoleDestinationLoad() throws {
        continueAfterFailure = false
        try configureStoreKit()
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-yd_root_tab_visible_ids", "(explore, settings)",
                               "-discover.selectedSourceId", "C5DED179-61D0-49C4-BDB7-93A7B3DAD8F4",
                               "-yd_appearance_reader_interface", "classic"]
        app.launch()
        let book = app.staticTexts["Navigation Swipe Fixture"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 20), app.debugDescription)
        book.tap()
        let read = app.buttons.matching(NSPredicate(format: "label IN %@", ["Read Now", "Continue Reading"])).firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 15), app.debugDescription)
        read.tap()
        let content = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Reserved edge navigation")).firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 30), app.debugDescription)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let listen = app.buttons["Audiobook"].firstMatch
        XCTAssertTrue(listen.waitForExistence(timeout: 5), app.debugDescription)
        listen.tap()
        let roles = app.buttons["Multi-voice narration"].firstMatch
        XCTAssertTrue(roles.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(roles.isHittable)
        roles.tap()
        XCTAssertTrue(app.navigationBars["Multi-voice narration"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons["Reset"].firstMatch.exists, app.debugDescription)
    }

    @MainActor func testSlideEdgeBack() throws { try exerciseReader(style: "滑動") }
    @MainActor func testCoverEdgeBack() throws { try exerciseReader(style: "覆蓋翻頁") }
    @MainActor func testCurlEdgeBack() throws { try exerciseReader(style: "仿真翻書") }
    @MainActor func testInstantEdgeBack() throws { try exerciseReader(style: "無動畫") }
    @MainActor func testScrollEdgeBack() throws { try exerciseReader(style: "滑動", scroll: true) }

    @MainActor
    private func exerciseReader(style: String, scroll: Bool = false) throws {
        continueAfterFailure = false
        try configureStoreKit()
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-yd_root_tab_visible_ids", "(explore, settings)",
                               "-discover.selectedSourceId", "C5DED179-61D0-49C4-BDB7-93A7B3DAD8F4",
                               "-yd_page_turn_style", style, "-yd_scroll_mode", scroll ? "YES" : "NO"]
        app.launch()
        let book = app.staticTexts["Navigation Swipe Fixture"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 20), app.debugDescription)
        book.tap()
        let read = app.buttons.matching(NSPredicate(format: "label IN %@", ["Read Now", "Continue Reading"])).firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 15), app.debugDescription)
        read.tap()
        let content = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Reserved edge navigation")).firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 30), app.debugDescription)
        let originalPage = content.label
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let shortDrag = app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
        // The hold belongs to the user's gesture: releasing a short, stationary
        // drag must cancel, preserving the same reader and reading position.
        edge.press(forDuration: 0.05, thenDragTo: shortDrag, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        XCTAssertEqual(content.label, originalPage)
        XCTAssertFalse(read.exists)

        // Interior pans must still turn pages / scroll, without navigating back.
        let interior = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7))
        let next = app.coordinate(withNormalizedOffset: CGVector(dx: scroll ? 0.8 : 0.2, dy: scroll ? 0.35 : 0.7))
        interior.press(forDuration: 0.05, thenDragTo: next)
        XCTAssertFalse(read.exists)
        if !scroll {
            let pageChanged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                content.exists && content.label != originalPage
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [pageChanged], timeout: 5), .completed, "Interior pan must turn the page")
        }

        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        // Also exercise the reserved strip away from the physical screen edge.
        let reservedStrip = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 28, dy: app.frame.height * 0.5))
        reservedStrip.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(read.waitForExistence(timeout: 8), "Edge drag must pop to the original detail.\n\(app.debugDescription)")
        XCTAssertFalse(content.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Returned to detail - \(style) - scroll \(scroll)"
        attachment.lifetime = .keepAlways
        add(attachment)
        // SwiftUI's route must also be reconciled, so reopening works normally.
        read.tap()
        XCTAssertTrue(content.waitForExistence(timeout: 15))
        edge.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(read.waitForExistence(timeout: 8))
    }
}
