import Combine
import CoreGraphics
import UIKit

struct ReaderLocation: Hashable, Codable {
    let spineIndex: Int
    let charOffset: Int

    static func chapterStart(_ spineIndex: Int) -> Self {
        Self(spineIndex: spineIndex, charOffset: 0)
    }

    static func chapterEnd(_ spineIndex: Int) -> Self {
        Self(spineIndex: spineIndex, charOffset: .max)
    }

    init(spineIndex: Int, charOffset: Int) {
        self.spineIndex = spineIndex
        self.charOffset = charOffset
    }

    init(_ position: CoreTextReadingPosition) {
        self.spineIndex = position.spineIndex
        self.charOffset = position.charOffset
    }

    var coreTextPosition: CoreTextReadingPosition {
        CoreTextReadingPosition(spineIndex: spineIndex, charOffset: charOffset)
    }
}

enum ReaderPagingStyle: Hashable, Codable {
    case none
    case slide
    case curl
    case cover
    case custom(String)

    init(pageTurnStyle: PageTurnStyle) {
        switch pageTurnStyle {
        case .slide: self = .slide
        case .cover: self = .cover
        case .curl: self = .curl
        case .none: self = .none
        }
    }

    var pageTurnStyle: PageTurnStyle? {
        switch self {
        case .slide: return .slide
        case .cover: return .cover
        case .curl: return .curl
        case .none: return .none
        case .custom: return nil
        }
    }
}

enum ReaderReadingDirection: String, Codable {
    case ltr
    case rtl
}

enum ReaderSpreadMode: String, Codable {
    case singlePage
    case doublePage
    case auto
}

struct ReaderAppearance: Equatable {
    var theme: ReaderTheme
    var fontSize: CGFloat
    var lineHeightMultiple: CGFloat
    var lineSpacing: CGFloat
    var paragraphSpacing: CGFloat
    var letterSpacing: CGFloat
    var marginH: CGFloat
    var marginV: CGFloat
    var footerHeight: CGFloat
    var writingMode: ReaderWritingMode

    init(
        theme: ReaderTheme,
        fontSize: CGFloat,
        lineHeightMultiple: CGFloat,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        letterSpacing: CGFloat,
        marginH: CGFloat,
        marginV: CGFloat,
        footerHeight: CGFloat,
        writingMode: ReaderWritingMode
    ) {
        self.theme = theme
        self.fontSize = fontSize
        self.lineHeightMultiple = lineHeightMultiple
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.letterSpacing = letterSpacing
        self.marginH = marginH
        self.marginV = marginV
        self.footerHeight = footerHeight
        self.writingMode = writingMode
    }

    init(settings: ReaderRenderSettings, theme: ReaderTheme) {
        self.init(
            theme: theme,
            fontSize: settings.fontSize,
            lineHeightMultiple: settings.lineHeightMultiple,
            lineSpacing: settings.lineSpacing,
            paragraphSpacing: settings.paragraphSpacing,
            letterSpacing: settings.letterSpacing,
            marginH: settings.marginH,
            marginV: settings.marginV,
            footerHeight: settings.footerHeight,
            writingMode: settings.writingMode
        )
    }
}

struct ReaderPresentationState: Equatable {
    var location: ReaderLocation
    var direction: ReaderReadingDirection
    var spreadMode: ReaderSpreadMode
    var viewportSize: CGSize
    var appearance: ReaderAppearance
    var pagingStyle: ReaderPagingStyle
}

@MainActor
final class ReaderSessionStore: ObservableObject {
    @Published private(set) var state: ReaderPresentationState

    init(initialState: ReaderPresentationState) {
        self.state = initialState
    }

    func move(to location: ReaderLocation) {
        state.location = location
    }

    func updateAppearance(_ appearance: ReaderAppearance) {
        state.appearance = appearance
    }

    func updateViewport(_ size: CGSize) {
        state.viewportSize = size
    }

    func switchPagingStyle(_ style: ReaderPagingStyle) {
        state.pagingStyle = style
    }

    func updateDirection(_ direction: ReaderReadingDirection) {
        state.direction = direction
    }

    func updateSpreadMode(_ spreadMode: ReaderSpreadMode) {
        state.spreadMode = spreadMode
    }
}
