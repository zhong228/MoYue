import Testing
import SwiftUI
import UIKit
@testable import yuedu_app

/// What each setting on 外觀主題 › 顏色與字體 reaches, redesigned after Apple's HIG
/// (2026-09-29): 強調色 what can be tapped or is selected, 背景 the page as set, the
/// text levels iOS's own three.
@Suite("Appearance colour scope", .serialized)
@MainActor
struct AppearanceColorScopeTests {
    /// The symbol leading a settings row wears 強調色 in every theme, 默認 included —
    /// read from the tint when it draws, not from the app-theme global, which left rows
    /// SwiftUI did not rebuild black beside red ones.
    @Test("a settings row's symbol wears the tint, with no app theme recorded")
    func rowSymbolWearsTheTint() throws {
        let saved = AppearanceThemePreset.activeAppThemes
        defer { AppearanceThemePreset.activeAppThemes = saved }
        AppearanceThemePreset.activeAppThemes = ActiveAppThemes()

        let row = Label("Row", systemImage: "square.fill")
            .labelStyle(IconConsistentLabelStyle())
            .foregroundStyle(Color.black)
            .tint(Color(red: 1, green: 0, blue: 0))
        let symbol = try #require(Self.pixel(at: CGPoint(x: 14, y: 14), of: row))
        #expect(symbol.red > 0.9 && symbol.green < 0.1 && symbol.blue < 0.1, "symbol drew \(symbol)")
    }

    /// An action or destructive row colours its title; its symbol matches the title.
    @Test("an action row's symbol keeps its title's colour")
    func actionRowSymbolMatchesTitle() throws {
        let row = Label("Row", systemImage: "square.fill")
            .labelStyle(IconConsistentLabelStyle(themesIcon: false))
            .foregroundStyle(Color(red: 0, green: 0, blue: 1))
            .tint(Color(red: 1, green: 0, blue: 0))
        let symbol = try #require(Self.pixel(at: CGPoint(x: 14, y: 14), of: row))
        #expect(symbol.blue > 0.9 && symbol.red < 0.1, "symbol drew \(symbol)")
    }

    /// 背景 is the page, exactly: the accent no longer tints it.
    @Test("the page is the theme's background, whatever the accent")
    func pageIsTheBackground() {
        for preset in [AppearanceThemePreset.classic] + AppearanceThemePreset.freeSolidPresets {
            #expect(preset.appPageBackground.rgbHex == preset.background.rgbHex, "\(preset.id)")
            let dark = preset.palette(for: .dark)
            #expect(dark.appPageBackground.rgbHex == dark.background.rgbHex, "\(preset.id) dark")
        }
    }

    /// Cards lift toward white off every built-in page, and step down off a white one,
    /// which has nowhere lighter to go.
    @Test("cards stay distinct from the page, a white one included")
    func cardsStayDistinctFromThePage() {
        for preset in [AppearanceThemePreset.classic] + AppearanceThemePreset.freeSolidPresets {
            #expect(Self.brightness(preset.appCardBackground) > Self.brightness(preset.appPageBackground), "\(preset.id)")
        }
        var white = AppearanceThemePreset.classic.customCopy(name: "White")
        white.backgroundHex = 0xFFFFFF
        let preset = AppearanceThemePreset.preset(from: white)
        #expect(preset.appPageBackground.rgbHex == 0xFFFFFF)
        #expect(Self.brightness(preset.appCardBackground) < Self.brightness(preset.appPageBackground))
        #expect(preset.appCardBackground.rgbHex != preset.appSecondaryBackground.rgbHex)
    }

    /// Disabled text is 弱文字 — and, with no theme, exactly the system's tertiary label.
    @Test("disabled text is the tertiary text level")
    func disabledTextIsTertiary() {
        var themed = AppearanceThemePreset.freeSolidPresets[0]
        themed.authoredTextColors = AppearanceThemeTextColors(primary: .red, secondary: .green, tertiary: .blue)
        let light = UITraitCollection { traits in
            traits.userInterfaceStyle = .light
            traits[AppThemesTrait.self] = ActiveAppThemes(light: themed, dark: nil)
        }
        #expect(UIColor(DSColor.textDisabled).resolvedColor(with: light).rgbHex == UIColor.blue.rgbHex)

        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let drawn = Self.components(UIColor(DSColor.textDisabled).resolvedColor(with: traits))
            let system = Self.components(UIColor.tertiaryLabel.resolvedColor(with: traits))
            #expect(abs(drawn.alpha - system.alpha) < 0.01 && abs(drawn.red - system.red) < 0.01, "\(style.rawValue)")
        }
    }

    // MARK: - Helpers

    struct RGBA: CustomStringConvertible {
        var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
        var description: String {
            String(format: "(%.2f, %.2f, %.2f, %.2f)", red, green, blue, alpha)
        }
    }

    /// One pixel of `view` drawn at scale 1 on a clear background, un-premultiplied.
    static func pixel<Content: View>(at point: CGPoint, of view: Content) -> RGBA? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage,
              Int(point.x) < image.width, Int(point.y) < image.height else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: -point.x, y: point.y - CGFloat(image.height) + 1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let alpha = CGFloat(bytes[3]) / 255
        guard alpha > 0 else { return RGBA(red: 0, green: 0, blue: 0, alpha: 0) }
        return RGBA(
            red: CGFloat(bytes[0]) / 255 / alpha,
            green: CGFloat(bytes[1]) / 255 / alpha,
            blue: CGFloat(bytes[2]) / 255 / alpha,
            alpha: alpha
        )
    }

    static func components(_ color: UIColor) -> RGBA {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    static func brightness(_ color: UIColor) -> CGFloat {
        let rgba = components(color)
        return (rgba.red + rgba.green + rgba.blue) / 3
    }
}
