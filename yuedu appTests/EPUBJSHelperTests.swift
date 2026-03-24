import XCTest
@testable import yuedu_app

final class EPUBJSHelperTests: XCTestCase {
    
    func testJSSnapshotHandshakeContract() throws {
        // This test simulates calling the HTML generation
        // to verify that the minimal JS contract is injected for the Hybrid Snapshot engine.
        // We will look for explicit `Promise.all` for images / fonts and the `renderReady` message block.
        
        let reader = LiveWebReader()
        // Wait, LiveWebReader's buildChapterHTML is private.
        // We will test it indirectly if needed, or we can just access it if we make it internal or move it.
        // For now, let's create a dummy struct containing the JS string generator for testing purposes.
        let contractJS = reader.testing_getJSContractString()
        
        XCTAssertTrue(contractJS.contains("Promise.all(imagePromises)"), "JS must explicitly wait for image.decode()")
        XCTAssertTrue(contractJS.contains("document.fonts.ready"), "JS must explicitly wait for fonts")
        XCTAssertTrue(contractJS.contains("window.webkit.messageHandlers.renderReady.postMessage"), "JS must call renderReady rather than old paginationReady")
        XCTAssertTrue(contractJS.contains("function gotoPage(index)"), "JS must implement gotoPage(index)")
        XCTAssertTrue(contractJS.contains("function getPaginationMetrics()"), "JS must implement getPaginationMetrics()")
    }
}
