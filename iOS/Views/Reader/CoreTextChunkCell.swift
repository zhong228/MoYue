import CoreText
import UIKit

/// Displays a single CoreText chunk cell containing a self-drawing CoreTextChunkDrawView.
final class CoreTextChunkCell: UITableViewCell {
    static let reuseIdentifier = "CoreTextChunkCell"

    let drawView = CoreTextChunkDrawView()
    let overlay = InteractionOverlayView()
    private var leftConstraint: NSLayoutConstraint!
    private var rightConstraint: NSLayoutConstraint!
    private var topConstraint: NSLayoutConstraint!
    private(set) var currentChunk: CoreTextChunk?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        drawView.translatesAutoresizingMaskIntoConstraints = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(drawView)
        contentView.addSubview(overlay)
        leftConstraint = drawView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        rightConstraint = drawView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        topConstraint = drawView.topAnchor.constraint(equalTo: contentView.topAnchor)
        NSLayoutConstraint.activate([
            topConstraint,
            drawView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            leftConstraint,
            rightConstraint,
            overlay.leadingAnchor.constraint(equalTo: drawView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: drawView.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: drawView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: drawView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func bind(chunk: CoreTextChunk, horizontalInset: CGFloat, topSpacing: CGFloat) {
        leftConstraint.constant = horizontalInset
        rightConstraint.constant = -horizontalInset
        topConstraint.constant = topSpacing
        currentChunk = chunk
        drawView.chunk = chunk
        drawView.setNeedsDisplay()
        overlay.clearSelection()
    }

    /// Applies selection highlighting if the chapter range intersects this chunk.
    func applySelection(chapterIndex: Int, chapterRange: NSRange?) {
        guard let chunk = currentChunk else { overlay.clearSelection(); return }
        guard let range = chapterRange, chunk.chapterIndex == chapterIndex, range.length > 0 else {
            overlay.clearSelection()
            return
        }
        let rects = chunk.selectionRects(forChapterRange: range)
        if rects.isEmpty { overlay.clearSelection(); return }
        overlay.selectionRects = rects

        // Determine whether this chunk contains the start or end of the selection, to draw handle dots.
        let chunkStart = chunk.charRange.location
        let chunkEnd = chunk.charRange.location + chunk.charRange.length
        let selStart = range.location
        let selEnd = range.location + range.length - 1
        let containsStart = selStart >= chunkStart && selStart < chunkEnd
        let containsEnd = selEnd >= chunkStart && selEnd < chunkEnd
        overlay.startHandlePoint = containsStart ? rects.first.map { CGPoint(x: $0.minX, y: $0.maxY) } : nil
        overlay.endHandlePoint = containsEnd ? rects.last.map { CGPoint(x: $0.maxX, y: $0.maxY) } : nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        drawView.chunk?.evictFrame()
        drawView.chunk = nil
        currentChunk = nil
        overlay.clearSelection()
    }
}

/// Draws the CTFrame directly. Handles the CoreText coordinate system inversion.
final class CoreTextChunkDrawView: UIView {
    var chunk: CoreTextChunk?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let chunk = chunk else { return }

        // Image-only chunk (cover / full-page illustration): draw attachments directly.
        if chunk.isImageOnly {
            for attachment in chunk.attachments {
                attachment.image.draw(in: attachment.rect, blendMode: .normal, alpha: attachment.opacity)
            }
            return
        }

        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        chunk.materializeFrameIfNeeded()
        guard let frame = chunk.frame else { return }

        // CoreText draws from bottom-left origin; flip the coordinate system.
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1.0, y: -1.0)
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()

        // Draw images in UIKit coordinates (top-left origin). CTFrame has already reserved blank space.
        for attachment in chunk.attachments {
            attachment.image.draw(in: attachment.rect, blendMode: .normal, alpha: attachment.opacity)
        }
    }
}
