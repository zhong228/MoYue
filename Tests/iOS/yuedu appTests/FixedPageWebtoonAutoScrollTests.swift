import Foundation
import Testing
@testable import yuedu_app

struct FixedPageWebtoonAutoScrollTests {
    @Test("auto-scroll covers the same distance per second at 60Hz and 120Hz")
    func autoScrollSpeedIgnoresRefreshRate() {
        let at60 = FixedPageWebtoonViewController.autoScrollStep(speedSetting: 3, frameInterval: 1.0 / 60)
        let at120 = FixedPageWebtoonViewController.autoScrollStep(speedSetting: 3, frameInterval: 1.0 / 120)
        // A 60Hz frame keeps the step the setting was tuned against: 0.8pt per unit.
        #expect(abs(at60 - 2.4) < 0.0001)
        #expect(abs(at60 * 60 - at120 * 120) < 0.0001)
        // The setting's floor still applies.
        #expect(abs(FixedPageWebtoonViewController.autoScrollStep(speedSetting: 0, frameInterval: 1.0 / 60) - 0.8) < 0.0001)
    }
}
