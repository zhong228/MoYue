import SwiftUI
import UIKit
import CoreText

struct CoreTextVerticalLabel: UIViewRepresentable {
    let text: String
    var fontSize: CGFloat = 24
    var weight: UIFont.Weight = .bold
    var textColor: UIColor = .label
    var maxCharacters: Int? = nil

    func makeUIView(context: Context) -> CoreTextVerticalLabelView {
        let view = CoreTextVerticalLabelView()
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ view: CoreTextVerticalLabelView, context: Context) {
        if let maxCharacters, text.count > maxCharacters {
            view.text = String(text.prefix(max(0, maxCharacters - 1))) + "\u{2026}"
        } else {
            view.text = text
        }

        view.fontSize = fontSize
        view.weight = weight
        view.textColor = textColor
        view.setNeedsDisplay()
    }
}

final class CoreTextVerticalLabelView: UIView {
    var text: String = ""
    var fontSize: CGFloat = 24
    var weight: UIFont.Weight = .bold
    var textColor: UIColor = .label

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !text.isEmpty else { return }

        context.saveGState()
        defer { context.restoreGState() }

        context.textMatrix = .identity

        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let ctFont = font as CTFont

        let x = bounds.midX
        var y: CGFloat = 0
        let advance = ceil(fontSize * 1.15)

        for scalar in text.map(String.init) {
            let advanceY = adjustedAdvance(for: scalar)

            let attr = NSAttributedString(
                string: scalar,
                attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: ctFont,
                    kCTForegroundColorAttributeName as NSAttributedString.Key: textColor.cgColor,
                    kCTVerticalFormsAttributeName as NSAttributedString.Key: true
                ]
            )

            let line = CTLineCreateWithAttributedString(attr)

            let lineBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            let drawX = x - lineBounds.width / 2 - lineBounds.origin.x
            let drawY = bounds.height - y - fontSize

            context.textPosition = CGPoint(x: drawX, y: drawY)
            CTLineDraw(line, context)

            y += advanceY

            if y + fontSize > bounds.height {
                break
            }
        }
    }

    private func adjustedAdvance(for scalar: String) -> CGFloat {
        switch scalar {
        case "\u{3001}", "\u{3002}", "\u{FF0C}", "\u{FF0E}":  // 、。，．
            return ceil(fontSize * 0.65)
        default:
            return ceil(fontSize * 1.15)
        }
    }
}
