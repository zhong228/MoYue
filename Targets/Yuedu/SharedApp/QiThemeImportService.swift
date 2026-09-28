import Foundation
import UIKit

extension AppearanceCustomizationBundle {
    /// Builds a bundle from already-translated parts rather than from a live snapshot.
    ///
    /// `QiThemeImportService` uses this so a foreign pack lands through the *same*
    /// `importAppearanceCustomization` path as one of our own bundles, rather than a
    /// second apply route written for QiReader. It fills only `themes`: the bundle's own
    /// fields are the *user's* look, restored as the layer every theme falls back to,
    /// and nothing in a pack is the user's own.
    init(
        themes: [AppearanceThemeExportFile],
        pageBackgrounds: [String: PageBackgroundPayload]?,
        tabIcons: [TabIcon]?,
        launchImageLight: ImagePayload?,
        launchImageDark: ImagePayload?,
        readerBackground: ReaderBackground?
    ) {
        self.format = Self.formatIdentifier
        self.version = 1
        self.themes = themes
        self.pageBackgrounds = pageBackgrounds
        self.tabIcons = tabIcons
        self.launchImageLight = launchImageLight
        self.launchImageDark = launchImageDark
        self.readerBackground = readerBackground
        self.regexHighlightConfiguration = nil
        self.readerStyleAssetIDs = nil
        self.legacyDialogueHex = nil
    }
}

/// What the reading half of an import does — the question the pre-import alert asks.
/// Either way a pack's reading setup is also kept on its theme, for 排版生效範圍.
enum ReadingSettingsDisposition: Equatable, Sendable {
    /// 跟隨主題: the settings the pack speaks for follow the theme from now on, so the
    /// pack's theme wears its own and every other theme keeps what it had.
    case followTheme
    /// 取代全域設定: the pack's setup replaces the shared one every theme falls back on.
    case replaceGlobal
}

/// Applies a parsed QiReader `.qitheme` pack.
///
/// Lives in the app target because it has to touch app-level stores (`GlobalSettings`,
/// tab icons, fonts, covers) alongside `ReaderSettingsImportService`. It owns no parsing
/// and no storage of its own: `QiThemeImporter` understands the file, the existing import
/// functions do the writing, and this type only sequences them and reports what happened.
@MainActor
enum QiThemeImportService {
    struct Outcome {
        var appearance = AppearanceImportSummary()
        /// The theme the pack became, as stored after import.
        var theme: AppearanceCustomTheme?
        /// The pack's reading setup, as applied — nil when the pack carried none.
        var reading: AppearanceThemeReadingSettings?
        var readingDisposition: ReadingSettingsDisposition?
        var installedFontName: String?
        /// The installed font also became the reading face.
        var readerUsesInstalledFont = false
        var importedCoverCount = 0
        var notes: [String] = []
    }

    static func load(_ data: Data) async throws -> QiThemeImport {
        try await QiThemeImporter.parse(data)
    }

    /// What the pack would change about reading, for the question asked before anything
    /// is written. Nothing is stored: the bubble and background are counted by presence.
    static func readingParts(of theme: QiThemeImport) -> [ReadingSetupPart] {
        var ignored: [String] = []
        var parts = Set(ReadingSetupPart.parts(in: readingPlan(theme, notes: &ignored).readingSettings))
        if theme.font != nil, readerAdoptsBundledFont(theme) { parts.insert(.font) }
        if theme.bubble != nil { parts.insert(.commentBubble) }
        if theme.readerBackground != nil { parts.insert(.background) }
        return ReadingSetupPart.allCases.filter(parts.contains)
    }

    /// - Parameter disposition: where the pack's reading setup goes. Ignored for a pack
    ///   that carries none.
    @discardableResult
    static func apply(
        _ theme: QiThemeImport,
        reading disposition: ReadingSettingsDisposition
    ) async throws -> Outcome {
        var theme = theme
        let settings = GlobalSettings.shared
        var outcome = Outcome()
        outcome.notes = theme.notes

        // 1. Everything the pack changes about the *look* becomes this theme's extras,
        //    so selecting another theme — 默認 included — puts the user's own settings
        //    back. Each asset is written through its storage manager directly rather
        //    than through the `GlobalSettings` mutators: those apply the value as they
        //    store it, which would land the pack's font and icons *before*
        //    `synchronizeAppearanceThemeExtras` captured what the user had.
        var extras = AppearanceThemeExtras()
        extras.tabIcons = storeTabIcons(theme)
        extras.readerChromeIcons = storeReaderChromeIcons(theme)
        extras.tabIconSize = theme.tabIconSize.map(GlobalSettings.sanitizedRootTabIconSize)
        extras.hidesTabLabels = theme.hidesTabLabels
        extras.launchImageEnabled = theme.launchEnabled
        if let launch = theme.launchImage,
           let name = try? LaunchImageStorageManager.shared.importImage(
               data: launch.data,
               scheme: .light
           ) {
            // QiReader's splash is not per-appearance, so one file serves both slots.
            extras.launchImageLightFileName = name
            extras.launchImageDarkFileName = name
        }
        extras.defaultCoverLightFileNames = storeDefaultCovers(theme, outcome: &outcome)
        extras.forceDefaultCover = theme.bookshelf.forceDefaultCover
        extras.frostedGlass = theme.effects.frostedGlass
        extras.glassTransparency = theme.effects.glassTransparency
        extras.glowIntensity = theme.effects.glowIntensity
        extras.bookshelfGridColumnCount = theme.bookshelf.gridColumnCount
        extras.bookshelfCoverCornerRadius = theme.bookshelf.coverCornerRadius
        extras.readerInterface = theme.readerInterface?.rawValue
        extras.cardBackground = storeCardBackground(theme)

        var readerFontPostScript: String?
        if let font = theme.font {
            if let installed = installFont(font, readerFontFamilyHint: theme.readerFontFamilyHint,
                                           settings: settings, outcome: &outcome) {
                outcome.installedFontName = installed.displayName
                extras.globalFontPostScript = installed.postScriptName
                if installed.isReaderFont {
                    readerFontPostScript = installed.postScriptName
                    outcome.readerUsesInstalledFont = true
                }
            } else {
                outcome.notes.append(localized("外觀包附帶的字型無法安裝，已略過。"))
            }
        }

        // 2. Chapter-title faces the pack named but did not bundle. Runs *after* the font
        //    install above, so a title font that ships inside the pack is not flagged.
        substituteMissingChapterTitleFonts(&theme, outcome: &outcome)

        // 3. The reading half, as one reading setup — one translation, one writer.
        let reading = readingSettings(theme, readerFontPostScript: readerFontPostScript,
                                      settings: settings, outcome: &outcome)
        if let reading {
            outcome.reading = reading
            outcome.readingDisposition = disposition
        }

        // 4. Import the theme carrying those extras. Appending it selects it, and the
        //    selection is what captures the baseline and applies the extras. The reading
        //    setup always rides the theme, whatever the answer: it is the theme's own,
        //    worn for the settings that follow the theme, and 重置此主題 restores it.
        extras.reading = reading
        var themeFile = theme.themeFile
        themeFile?.extras = extras
        // The pack's page backgrounds travel on its theme file only. Also passing them as
        // the bundle's own `pageBackgrounds` wrote them into the live settings *before*
        // the theme was selected — so the baseline that selection captured already held
        // them, and choosing 默認 again kept the pack's background (山风 - 春水漾,
        // 2026-09-28). It also stored every background image twice.
        let bundle = AppearanceCustomizationBundle(
            themes: themeFile.map { [$0] } ?? [],
            pageBackgrounds: nil,
            tabIcons: nil,
            launchImageLight: nil,
            launchImageDark: nil,
            readerBackground: nil
        )
        do {
            let encoded = try JSONEncoder().encode(bundle)
            outcome.appearance = try settings.importAppearanceCustomization(from: encoded)
            if outcome.appearance.themes > 0 {
                outcome.theme = settings.customAppearanceThemes.first { $0.id == settings.appearanceThemeID }
            }
        } catch {
            AppLogger.parse("⟐ qitheme appearance apply failed", context: ["error": "\(error)"])
            outcome.notes.append(localized("外觀部分套用失敗，其餘項目仍已匯入。"))
        }

        // 5. The answer. The pack's theme is selected by now, so 跟隨主題 wears the pack's
        //    values the moment the scope changes.
        if let reading {
            switch disposition {
            case .replaceGlobal:
                try settings.replaceGlobalReadingSettings(with: reading)
            case .followTheme where outcome.theme == nil:
                // No theme came out of the import, so there is nothing to follow — and
                // quietly writing the setup into 全域 instead would be exactly what they
                // declined.
                outcome.reading = nil
                outcome.readingDisposition = nil
                outcome.notes.append(localized("外觀主題沒有匯入成功，閱讀設定沒有主題可以跟隨，已略過。"))
            case .followTheme:
                settings.followTheme(for: reading.items)
            }
        }
        return outcome
    }

    // MARK: - Pieces

    /// The pack's layout and chapter title as a reading-settings plan, through the app's
    /// one layout parser.
    static func readingPlan(_ theme: QiThemeImport, notes: inout [String]) -> ReaderSettingsImportPlan {
        var layout: ReaderLayoutPreset?
        if let config = theme.layoutConfig {
            do {
                layout = try ReaderLayoutPresetImporter.decode(data: config)
            } catch {
                AppLogger.parse("⟐ qitheme layout decode failed", context: ["error": "\(error)"])
                notes.append(localized("排版參數無法讀取，其餘項目仍已匯入。"))
            }
        }
        return ReaderSettingsImportPlan(
            layout: layout,
            chapterTitleStyle: theme.chapterTitleStyle,
            regexHighlights: nil,
            dialogueBubbleStyle: nil,
            contentName: theme.name
        )
    }

    /// The whole reading half of the pack as one setup, or nil when it carries none.
    /// Stores what has to exist on disk first — the bubble in the shared library, the
    /// background picture — without wearing either: whether they are worn now is the
    /// disposition's call.
    private static func readingSettings(
        _ theme: QiThemeImport,
        readerFontPostScript: String?,
        settings: GlobalSettings,
        outcome: inout Outcome
    ) -> AppearanceThemeReadingSettings? {
        var reading = readingPlan(theme, notes: &outcome.notes).readingSettings
        if let readerFontPostScript { reading.fontPostScript = readerFontPostScript }
        if let bubble = theme.bubble {
            settings.storeCommentBubbleCustomStyle(bubble.style)
            reading.commentBubble = AppearanceThemeReadingSettings.CommentBubble(
                followsSourceSVG: false,
                presetMode: ReaderCommentBubblePresetMode.custom.rawValue,
                customStyleID: bubble.style.id,
                scale: GlobalSettings.sanitizedCommentBubbleScale(
                    bubble.scale ?? settings.commentBubbleScale
                ),
                textScale: GlobalSettings.sanitizedCommentBubbleTextScale(
                    bubble.textScale ?? settings.commentBubbleTextScale
                )
            )
        }
        if let image = theme.readerBackground {
            do {
                let name = try ReaderCustomBackgroundStorageManager.shared.importBackground(data: image.data)
                reading.customBackground = AppearanceThemeReadingSettings.CustomBackground(
                    mode: ReaderCustomBackgroundMode.image.rawValue,
                    colorHex: settings.readerCustomBackgroundColorHex,
                    imageFileName: name
                )
                // What picking a background picture by hand does: 跟隨系統 and 綁定閱讀主題
                // would otherwise repaint the reader over it.
                reading.followsSystemTheme = false
                reading.bindsAppearanceReaderTheme = false
            } catch {
                AppLogger.parse("⟐ qitheme reader background unreadable", error: error)
                outcome.notes.append(localized("閱讀背景圖無法讀取，已略過。"))
            }
        }
        return reading.isEmpty ? nil : reading
    }

    /// Whether the reading preset names the face the pack bundles. Compared against the
    /// manifest's declared name before install and against the installed font's real
    /// names after it (`installFont`).
    private static func readerAdoptsBundledFont(_ theme: QiThemeImport) -> Bool {
        guard let requested = theme.readerFontFamilyHint?
            .trimmingCharacters(in: .whitespacesAndNewlines), !requested.isEmpty else {
            return true
        }
        guard let declared = theme.font?.declaredPostScriptName else { return false }
        return requested.compare(declared, options: .caseInsensitive) == .orderedSame
    }

    /// Stores each tab icon and returns the `"<tab>.<slot>"` map the extras carry.
    /// One artwork per tab, written to both slots: QiReader has no light/dark split,
    /// and leaving dark on the default SF Symbol looks like a half-applied theme.
    private static func storeTabIcons(_ theme: QiThemeImport) -> [String: String]? {
        var icons: [String: String] = [:]
        for icon in theme.tabIcons {
            guard let tab = RootTabItem(rawValue: icon.tabID) else { continue }
            for slot in RootTabIconSlot.allCases {
                guard let asset = try? RootTabIconStorageManager.shared.importIcon(
                    data: icon.image.data,
                    originalFileName: icon.image.fileName,
                    tab: tab,
                    slot: slot
                ) else { continue }
                icons["\(tab.rawValue).\(slot.rawValue)"] = asset.fileName
            }
        }
        return icons.isEmpty ? nil : icons
    }

    /// Stores each reading-toolbar icon and returns the `itemID → file` map the extras
    /// carry — the same shape the reader's 按鈕圖示 page records. The icons belong to the
    /// theme like the tab icons do, so leaving the theme puts the user's own back.
    private static func storeReaderChromeIcons(_ theme: QiThemeImport) -> [String: String]? {
        var icons: [String: String] = [:]
        for icon in theme.readerChromeIcons {
            do {
                let asset = try ReaderChromeIconStorage.shared.importIcon(
                    data: icon.image.data,
                    originalFileName: icon.image.fileName,
                    itemID: icon.itemID
                )
                icons[icon.itemID] = asset.fileName
            } catch {
                AppLogger.parse("⟐ qitheme reader toolbar icon unreadable", error: error, context: [
                    "item": icon.itemID,
                ])
            }
        }
        return icons.isEmpty ? nil : icons
    }

    private static func storeDefaultCovers(
        _ theme: QiThemeImport,
        outcome: inout Outcome
    ) -> [String]? {
        var names: [String] = []
        for cover in theme.defaultCovers {
            guard let name = try? DefaultCoverStorageManager.shared.importImage(
                data: cover.data,
                scheme: .light
            ) else { continue }
            names.append(name)
        }
        outcome.importedCoverCount = names.count
        return names.isEmpty ? nil : names
    }

    private static func storeCardBackground(_ theme: QiThemeImport) -> AppearanceCardBackground? {
        guard let card = theme.cardBackground else { return nil }
        var light = card.light
        var dark = card.dark
        if let data = theme.cardBackgroundImage?.data,
           let name = try? AppearanceCardBackgroundImageStore.shared.importImage(data: data) {
            light.imageFileName = name
        }
        if let data = theme.darkCardBackgroundImage?.data,
           let name = try? AppearanceCardBackgroundImageStore.shared.importImage(data: data) {
            dark.imageFileName = name
        }
        let resolved = AppearanceCardBackground(isEnabled: card.isEnabled, light: light, dark: dark)
        return resolved.isEmpty ? nil : resolved
    }

    private struct InstalledFont {
        var displayName: String
        var postScriptName: String
        /// The reading preset names this face, so it becomes the reading font too.
        var isReaderFont: Bool
    }

    private static func installFont(
        _ font: QiThemeImport.FontImport,
        readerFontFamilyHint: String?,
        settings: GlobalSettings,
        outcome: inout Outcome
    ) -> InstalledFont? {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("qitheme-font-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        guard (try? FileManager.default.createDirectory(
            at: staging,
            withIntermediateDirectories: true
        )) != nil else {
            return nil
        }
        let fileURL = staging.appendingPathComponent(font.originalFileName, isDirectory: false)
        // Installed into the library but *not* selected — the theme's extras (and, for the
        // reading face, the reading setup) decide when it is in use, so the baselines
        // still capture the user's own choices.
        guard (try? font.data.write(to: fileURL, options: .atomic)) != nil,
              let info = try? settings.importUserFont(from: fileURL) else {
            return nil
        }
        // The reading preset names its own face. When it is the one bundled here, adopt it
        // as the reader font too; when it names a font the pack did not ship, say so rather
        // than silently pointing the reader at the wrong face.
        let requested = readerFontFamilyHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        var isReaderFont = true
        if let requested, !requested.isEmpty,
           requested.compare(info.postScriptName, options: .caseInsensitive) != .orderedSame,
           requested.compare(info.familyName, options: .caseInsensitive) != .orderedSame {
            isReaderFont = false
            outcome.notes.append(String(
                format: localized("閱讀字型「%@」未隨外觀包附帶，正文仍使用原本的字型。"),
                requested
            ))
        }
        return InstalledFont(
            displayName: info.displayName,
            postScriptName: info.postScriptName,
            isReaderFont: isReaderFont
        )
    }

    /// A chapter-title style can name faces the pack never shipped — 江湖侠客 asks for two
    /// (`YUWEIXSJ2019`, `KyoMadoka`) it does not include.
    ///
    /// Leaving the dead name in place is worse than clearing it: `UserReaderFontResolver`
    /// resolves `postScriptName ?? selectedPostScriptName`, so an *unavailable* name falls
    /// all the way through to `UIFont.systemFont` and never reaches the reader's own font —
    /// a 武俠 ink-painting title rendered in system sans. Clearing it lets the layer inherit
    /// the reader font, which for a pack like this is the serif it just installed: much
    /// closer to what the author drew the artwork around. The substitution is reported, so
    /// it is never a silent change of appearance.
    private static func substituteMissingChapterTitleFonts(
        _ theme: inout QiThemeImport,
        outcome: inout Outcome
    ) {
        guard var style = theme.chapterTitleStyle, !style.followsBodyFont else { return }
        func isMissing(_ name: String?) -> Bool {
            guard let name, !name.isEmpty else { return false }
            return UIFont(name: name, size: 12) == nil
        }

        var missing: Set<String> = []
        for name in [style.nameFontPostScript, style.numberFontPostScript] where isMissing(name) {
            missing.insert(name!)
        }
        for layer in style.design?.layers ?? [] {
            for name in [
                layer.lightStyle.ruleStyle.text.fontPostScriptName,
                layer.darkStyle.ruleStyle.text.fontPostScriptName,
            ] where isMissing(name) {
                missing.insert(name!)
            }
        }
        guard !missing.isEmpty else { return }

        if isMissing(style.nameFontPostScript) { style.nameFontPostScript = nil }
        if isMissing(style.numberFontPostScript) { style.numberFontPostScript = nil }
        if var design = style.design {
            for index in design.layers.indices {
                if isMissing(design.layers[index].lightStyle.ruleStyle.text.fontPostScriptName) {
                    design.layers[index].lightStyle.ruleStyle.text.fontPostScriptName = nil
                }
                if isMissing(design.layers[index].darkStyle.ruleStyle.text.fontPostScriptName) {
                    design.layers[index].darkStyle.ruleStyle.text.fontPostScriptName = nil
                }
            }
            style.design = design
        }
        theme.chapterTitleStyle = style.sanitized()

        outcome.notes.append(String(
            format: localized("章節標題使用的字型未隨外觀包附帶：%@，已改用閱讀字型顯示。"),
            missing.sorted().joined(separator: localized("、"))
        ))
    }
}
