import CoreGraphics
import Testing
import UIKit
@testable import yuedu_app

@MainActor
struct ReaderPresentationContractTests {
    @Test("maps app page turn styles to paging adapter descriptors")
    func mapsPageTurnStyleToAdapterDescriptor() {
        let slide = PageViewControllerPagingAdapterDescriptor(pageTurnStyle: .slide)
        #expect(slide.style == .slide)
        #expect(slide.transitionStyle == .scroll)
        #expect(!slide.disablesBuiltInSwipe)
        #expect(!slide.usesCoverOverlay)
        #expect(slide.spineLocation(isRTL: true) == .min)

        let curl = PageViewControllerPagingAdapterDescriptor(pageTurnStyle: .curl)
        #expect(curl.style == .curl)
        #expect(curl.transitionStyle == .pageCurl)
        #expect(!curl.disablesBuiltInSwipe)
        #expect(curl.spineLocation(isRTL: true) == .max)

        let cover = PageViewControllerPagingAdapterDescriptor(pageTurnStyle: .cover)
        #expect(cover.style == .cover)
        #expect(cover.transitionStyle == .scroll)
        #expect(cover.disablesBuiltInSwipe)
        #expect(cover.usesCoverOverlay)

        let none = PageViewControllerPagingAdapterDescriptor(pageTurnStyle: .none)
        #expect(none.style == .none)
        #expect(none.transitionStyle == .scroll)
        #expect(none.disablesBuiltInSwipe)
        #expect(!none.usesCoverOverlay)
    }

    @Test("session store keeps reader presentation state as a single update surface")
    func sessionStoreUpdatesPresentationState() {
        let appearance = ReaderAppearance(
            theme: .sepia,
            fontSize: 18,
            lineHeightMultiple: 1.4,
            lineSpacing: 2,
            paragraphSpacing: 6,
            letterSpacing: 0,
            marginH: 24,
            marginV: 28,
            footerHeight: 20,
            writingMode: .horizontal
        )
        let store = ReaderSessionStore(
            initialState: ReaderPresentationState(
                location: .chapterStart(0),
                direction: .ltr,
                spreadMode: .singlePage,
                viewportSize: CGSize(width: 320, height: 480),
                appearance: appearance,
                pagingStyle: .slide
            )
        )

        store.move(to: ReaderLocation(spineIndex: 3, charOffset: 42))
        store.switchPagingStyle(.curl)
        store.updateDirection(.rtl)
        store.updateViewport(CGSize(width: 390, height: 844))

        #expect(store.state.location == ReaderLocation(spineIndex: 3, charOffset: 42))
        #expect(store.state.pagingStyle == .curl)
        #expect(store.state.direction == .rtl)
        #expect(store.state.viewportSize == CGSize(width: 390, height: 844))
    }
}
