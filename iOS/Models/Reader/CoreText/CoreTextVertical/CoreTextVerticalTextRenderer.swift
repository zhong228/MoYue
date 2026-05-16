import UIKit
import CoreText

/// Vertical writing mode (vertical-rl) text rendering.
///
/// CoreText handles glyph rotation and right-to-left column progression
/// automatically when kCTFrameProgressionAttributeName = .rightToLeft
/// and kCTVerticalFormsAttributeName = true are set.
/// We simply call CTFrameDraw — CoreText does the rest.
///
/// Text selection, tap, and long-press are not supported in vertical mode.
/// CoreTextPageView.makeInteractionContext() returns nil for isVertical.
enum CoreTextVerticalTextRenderer {

    /// Draw a CTFrame configured for vertical-rl text.
    /// Caller must have already applied the CoreText → UIKit coordinate flip.
    static func draw(_ frame: CTFrame, in ctx: CGContext) {
        CTFrameDraw(frame, ctx)
    }
}
