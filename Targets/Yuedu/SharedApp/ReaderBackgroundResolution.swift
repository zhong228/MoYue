import SwiftUI

/// What the reader wears for one appearance: a built-in reading background, painted over
/// by a saved one or by the appearance theme's palette.
struct ReaderBackgroundResolution: Equatable {
    /// The built-in background the reader sits on. Its chrome reads this: 黑色 is dark.
    var theme: ReaderTheme
    var customBackground: ReaderCustomBackground?
    /// 跟隨外觀主題 under 綁定閱讀主題: the appearance theme's palette repaints the page.
    var paintsWithAppearanceTheme: Bool
}

extension GlobalSettings {
    /// The one place the three ways of choosing a reading background — a pick in the
    /// reader, 跟隨裝置深淺色, 綁定閱讀主題 — are resolved, for the reader and for what
    /// 閱讀設定 says about the background on screen.
    ///
    /// 綁定閱讀主題 comes first: it exists to decide the background per appearance. It used
    /// to come second, after any custom background — so a theme pack's reading picture
    /// kept the reader on it in dark mode whatever 深色閱讀主題 said (2026-09-29).
    ///
    /// - Parameter wornTheme: the reader's own background, as a pick or 跟隨裝置深淺色 set it.
    func readerBackgroundResolution(
        appearance: ColorScheme,
        wornTheme: ReaderTheme
    ) -> ReaderBackgroundResolution {
        if appearanceBindReaderTheme {
            switch boundReaderTheme(for: appearance) {
            case .followAppearanceTheme:
                // The theme's own reading background — a pack's picture — is what the theme
                // looks like in the reader; only a theme without one is painted with its
                // palette. The pick used to paint the palette over a pack's picture, and
                // before 綁定閱讀主題 came first here, the picture hid that it did.
                if let background = wornReaderCustomBackground {
                    return ReaderBackgroundResolution(
                        theme: background.isDark ? .night : ReaderTheme.lastLightTheme,
                        customBackground: background,
                        paintsWithAppearanceTheme: false
                    )
                }
                return ReaderBackgroundResolution(
                    theme: ReaderTheme.forSystem(dark: appearance == .dark),
                    customBackground: nil,
                    paintsWithAppearanceTheme: true
                )
            case .reading(let theme):
                return ReaderBackgroundResolution(theme: theme, customBackground: nil, paintsWithAppearanceTheme: false)
            case .custom(let id):
                guard let background = readerCustomBackground(id: id) else {
                    // Deleted — here, or on another device before this one synced.
                    return ReaderBackgroundResolution(
                        theme: ReaderTheme.forSystem(dark: appearance == .dark),
                        customBackground: nil,
                        paintsWithAppearanceTheme: false
                    )
                }
                return ReaderBackgroundResolution(
                    theme: background.isDark ? .night : ReaderTheme.lastLightTheme,
                    customBackground: background,
                    paintsWithAppearanceTheme: false
                )
            }
        }
        // A saved background shows over a built-in of its own tone only. 夜間 over a light
        // one, or back to light from a dark one, shows the built-in — and the saved one
        // returns with its tone, as the one custom background did before.
        guard let background = wornReaderCustomBackground,
              background.isDark == (wornTheme == .night) else {
            return ReaderBackgroundResolution(theme: wornTheme, customBackground: nil, paintsWithAppearanceTheme: false)
        }
        return ReaderBackgroundResolution(theme: wornTheme, customBackground: background, paintsWithAppearanceTheme: false)
    }
}
