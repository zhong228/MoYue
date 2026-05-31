import CoreText
import Foundation
import Testing
import UIKit
@testable import yuedu_app

@Suite("Paragraph review (段評) markers")
struct ParagraphReviewMarkerTests {

    /// Extracts the first href value from an `<a href="…">` in a string.
    private func firstHref(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"href=\"([^\"]*)\""#) else { return nil }
        let ns = html as NSString
        guard let m = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    @Test("rewrites the iOS paraForiOS comment marker into a ydreview anchor")
    func rewritesMarkerIntoAnchor() throws {
        let raw = #"<div rs-native>第一段文字<comment count="12" onPress="java.showReadingBrowser('https://api.example.com/cmt?book_id=1&amp;ssionid=abc','番茄段评')"></div>"#
        let rewritten = ReaderHTMLUtilities.rewriteReviewComments(raw)

        #expect(!rewritten.contains("<comment"))
        #expect(rewritten.contains("第一段文字"))

        let href = try #require(firstHref(in: rewritten))
        #expect(href.hasPrefix("ydreview://"))

        let marker = try #require(ReaderHTMLUtilities.decodeReviewHref(href))
        #expect(marker.count == "12")
        #expect(marker.title == "番茄段评")
        // &amp; in the HTML attribute must be unescaped back to a real ampersand.
        #expect(marker.url == "https://api.example.com/cmt?book_id=1&ssionid=abc")
    }

    @Test("handles lowercased onpress and an explicit closing tag")
    func handlesLowercasedAndClosedTag() throws {
        let raw = #"<div>章節<comment count="3" onpress="java.showReadingBrowser('https://x.test/y','七猫段评')"></comment></div>"#
        let rewritten = ReaderHTMLUtilities.rewriteReviewComments(raw)

        let href = try #require(firstHref(in: rewritten))
        let marker = try #require(ReaderHTMLUtilities.decodeReviewHref(href))
        #expect(marker.count == "3")
        #expect(marker.url == "https://x.test/y")
        #expect(marker.title == "七猫段评")
    }

    @Test("leaves HTML without comment markers unchanged and is idempotent")
    func leavesPlainHTMLUnchangedAndIdempotent() {
        let plain = "<p>沒有段評的普通段落</p>"
        #expect(ReaderHTMLUtilities.rewriteReviewComments(plain) == plain)

        let raw = #"<div>文字<comment count="5" onPress="java.showReadingBrowser('https://a.test/b','塔读段评')"></div>"#
        let once = ReaderHTMLUtilities.rewriteReviewComments(raw)
        let twice = ReaderHTMLUtilities.rewriteReviewComments(once)
        #expect(once == twice)
    }

    @Test("decodeReviewHref rejects non-review hrefs")
    func rejectsNonReviewHrefs() {
        #expect(ReaderHTMLUtilities.decodeReviewHref("https://example.com/page") == nil)
        #expect(ReaderHTMLUtilities.decodeReviewHref("#chapter-2") == nil)
        #expect(ReaderHTMLUtilities.reviewTarget(fromHref: "https://example.com") == nil)
    }

    @Test("reviewTarget surfaces url and title for sheet presentation")
    func reviewTargetSurfacesURLAndTitle() throws {
        let raw = #"<div>x<comment count="99+" onPress="java.showReadingBrowser('https://r.test/p?a=1&amp;b=2','QQ阅读段评')"></div>"#
        let href = try #require(firstHref(in: ReaderHTMLUtilities.rewriteReviewComments(raw)))
        let target = try #require(ReaderHTMLUtilities.reviewTarget(fromHref: href))
        #expect(target.url == "https://r.test/p?a=1&b=2")
        #expect(target.title == "QQ阅读段评")
    }
}

@Suite("Paragraph review rendering pipeline")
@MainActor
struct ParagraphReviewRenderingTests {

    /// Drives the real HTML → CoreText pipeline and verifies the marker becomes a tappable
    /// badge: an inline attachment (CTRunDelegate) carrying a `ydreview://` internal link.
    @Test("renders a tappable badge attachment carrying the ydreview link")
    func rendersBadgeAttachment() async throws {
        let raw = #"<body><p>段落文字<comment count="7" onPress="java.showReadingBrowser('https://r.test/p?x=1&amp;y=2','番茄段评')"></p></body>"#
        let html = ReaderHTMLUtilities.rewriteReviewComments(raw)

        let cfg = HTMLAttributedStringBuilder.Config(
            fontSize: 18,
            lineHeightMultiple: 1.4,
            lineSpacing: 0,
            paragraphSpacing: 8,
            firstLineIndent: 0,
            textColor: .label,
            backgroundColor: .systemBackground,
            fontFamilyName: nil,
            renderWidth: 360
        )
        let result = await HTMLAttributedStringBuilder().build(html: html, config: cfg)
        let attr = result.attributedString

        let delegateKey = NSAttributedString.Key(kCTRunDelegateAttributeName as String)
        var foundReviewLink = false
        var linkHasAttachment = false
        attr.enumerateAttribute(
            HTMLAttributedStringBuilder.internalLinkAttribute,
            in: NSRange(location: 0, length: attr.length)
        ) { value, range, _ in
            guard let href = value as? String, href.hasPrefix("ydreview://") else { return }
            foundReviewLink = true
            if attr.attribute(delegateKey, at: range.location, effectiveRange: nil) != nil {
                linkHasAttachment = true
            }
        }

        #expect(foundReviewLink)
        #expect(linkHasAttachment)
        // The body paragraph text must still be present.
        #expect(attr.string.contains("段落文字"))
    }
}
