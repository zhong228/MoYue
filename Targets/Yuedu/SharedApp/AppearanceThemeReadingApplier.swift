import Combine
import Foundation

extension Notification.Name {
    /// Reading settings were written from outside the reader — a theme switch, a change of
    /// 排版生效範圍, or an import. `ReaderConfig` mirrors most of them and reloads on this,
    /// so an open reader and the next one opened both see the new values.
    static let readingSettingsDidApply = Notification.Name("yd.readingSettingsDidApply")
}

/// 排版生效範圍: which reading settings follow the theme and which are shared.
///
/// Two stores and one choice per setting:
/// - **全域** (`globalReadingSettings`): one complete reading setup every theme shares.
/// - **each theme's own** (`themeReadingSettings(themeID:)`): sparse — only the settings
///   edited under that theme while they followed it, or brought in by its pack. A custom
///   theme keeps them in its extras, so they travel with it and 重置此主題 restores the
///   pack's; a built-in theme keeps them here.
/// - **the scope** (`readingSettingsScope`): per setting, which of the two the reader wears.
///
/// What is on screen is always 全域 with the worn theme's own values laid over it for the
/// settings that follow the theme. An edit goes back to wherever its setting comes from.
/// Nothing is ever dropped by changing the scope: a theme's own values stay stored while
/// their setting is shared, and come back when it follows the theme again.
///
/// This replaced a per-theme switch (閱讀設定隨主題切換) that bound a theme's whole reading
/// setup or none of it, and threw the setup away when switched off (2026-09-28).
extension GlobalSettings {
    enum ReadingSettingsWriteOrigin {
        /// Selecting a theme, changing the scope: which setup this device wears, not an
        /// edit — so no iCloud merge clock is stamped.
        case theme
        /// The user importing a file into their setup: an edit like any other.
        case userImport
    }

    private static let readingScopeKey = "yd_reading_settings_scope"
    private static let globalReadingKey = "yd_reading_settings_global"
    private static let builtInThemeReadingKey = "yd_reading_settings_builtin_themes"

    /// Where the scope and the two stores live, for a test that has to put them back.
    static let readingSettingsStoreKeys = [readingScopeKey, globalReadingKey, builtInThemeReadingKey]

    // MARK: - 排版生效範圍

    var readingSettingsScope: ReadingSettingsScopeConfiguration {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.readingScopeKey) else {
                return .default
            }
            do {
                return try JSONDecoder().decode(ReadingSettingsScopeConfiguration.self, from: data)
            } catch {
                AppLogger.error("⟐ reading scope unreadable, using the default", error: error)
                return .default
            }
        }
        set {
            guard newValue != readingSettingsScope else { return }
            objectWillChange.send()
            do {
                UserDefaults.standard.set(try JSONEncoder().encode(newValue), forKey: Self.readingScopeKey)
            } catch {
                AppLogger.error("⟐ reading scope not stored", error: error)
                return
            }
            synchronizeReadingSettings()
        }
    }

    func setReadingSettingsScope(_ scope: ReadingSettingsScope, for item: ReadingSettingsScopeItem) {
        var configuration = readingSettingsScope
        configuration.setScope(scope, for: item)
        readingSettingsScope = configuration
    }

    // MARK: - The two stores

    /// The reading setup every theme shares — complete, so wearing it sets every field.
    ///
    /// Created on first read from the user's own setup: the appearance baseline held it
    /// while a custom theme was selected under the per-theme switch this replaced;
    /// otherwise it is what is on screen.
    var globalReadingSettings: AppearanceThemeReadingSettings {
        get {
            if let data = UserDefaults.standard.data(forKey: Self.globalReadingKey) {
                do {
                    return try JSONDecoder().decode(AppearanceThemeReadingSettings.self, from: data)
                } catch {
                    AppLogger.error("⟐ shared reading setup unreadable, recaptured", error: error)
                }
            }
            let captured = appearanceExtrasBaseline?.reading ?? currentReadingSettingsSnapshot()
            storeGlobalReadingSettings(captured)
            return captured
        }
        set {
            storeGlobalReadingSettings(newValue)
        }
    }

    private func storeGlobalReadingSettings(_ reading: AppearanceThemeReadingSettings) {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(reading), forKey: Self.globalReadingKey)
        } catch {
            AppLogger.error("⟐ shared reading setup not stored", error: error)
        }
    }

    /// The theme whose own values are worn for the settings that follow the theme: the
    /// custom theme that owns the rest of the appearance extras, else the selected preset.
    var readingSettingsThemeID: String {
        activeExtrasOwnerThemeID ?? appearanceThemeID
    }

    /// The name shown for `readingSettingsThemeID`.
    var readingSettingsThemeName: String {
        AppearanceThemePreset.preset(id: readingSettingsThemeID, customThemes: customAppearanceThemes)?
            .localizedName ?? readingSettingsThemeID
    }

    func themeReadingSettings(themeID: String) -> AppearanceThemeReadingSettings? {
        if let theme = customAppearanceThemes.first(where: { $0.id == themeID }) {
            return theme.extras?.reading
        }
        return builtInThemeReadingSettings[themeID]
    }

    private func setThemeReadingSettings(_ reading: AppearanceThemeReadingSettings, themeID: String) {
        if let index = customAppearanceThemes.firstIndex(where: { $0.id == themeID }) {
            var extras = customAppearanceThemes[index].extras ?? AppearanceThemeExtras()
            extras.reading = reading
            customAppearanceThemes[index].extras = extras
        } else {
            var stored = builtInThemeReadingSettings
            stored[themeID] = reading
            builtInThemeReadingSettings = stored
        }
    }

    /// Built-in presets have no extras of their own to carry these.
    private var builtInThemeReadingSettings: [String: AppearanceThemeReadingSettings] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.builtInThemeReadingKey) else {
                return [:]
            }
            do {
                return try JSONDecoder().decode([String: AppearanceThemeReadingSettings].self, from: data)
            } catch {
                AppLogger.error("⟐ built-in themes' reading settings unreadable", error: error)
                return [:]
            }
        }
        set {
            do {
                UserDefaults.standard.set(try JSONEncoder().encode(newValue), forKey: Self.builtInThemeReadingKey)
            } catch {
                AppLogger.error("⟐ built-in themes' reading settings not stored", error: error)
            }
        }
    }

    // MARK: - Wearing

    /// Puts 全域, with the worn theme's own values for the settings that follow it, on
    /// screen. Called when the theme or the scope changes; cheap when nothing does, since
    /// the writer assigns only what differs.
    func synchronizeReadingSettings() {
        do {
            try applyReadingSettings(origin: .theme)
        } catch {
            // `.theme` writes report a failed header/footer store by logging and carry
            // on; nothing else throws. Kept explicit so a future throwing field cannot
            // vanish here.
            AppLogger.error("⟐ reading setup not fully applied", error: error)
        }
    }

    private func applyReadingSettings(origin: ReadingSettingsWriteOrigin) throws {
        // Every write lands in a `didSet` that would otherwise record it as an edit.
        let wasApplying = isApplyingAppearanceExtras
        isApplyingAppearanceExtras = true
        defer { isApplyingAppearanceExtras = wasApplying }

        var worn = globalReadingSettings
        let themeItems = readingSettingsScope.themeItems
        if !themeItems.isEmpty, let own = themeReadingSettings(themeID: readingSettingsThemeID) {
            worn = worn.overlaid(with: own.restricted(to: themeItems))
        }
        try writeReadingSettings(worn, origin: origin)
    }

    // MARK: - Recording edits

    /// Records an edited reading setting where it comes from. Every covered `didSet` calls
    /// this with the one field it set; it is a no-op while a setup is being applied.
    ///
    /// A setting that follows the theme is recorded on the worn theme, per field, so the
    /// theme keeps saying nothing about the rest. A shared one goes into 全域.
    func recordReadingSettingEdit(_ mutate: (inout AppearanceThemeReadingSettings) -> Void) {
        guard !isApplyingAppearanceExtras else { return }
        var edit = AppearanceThemeReadingSettings()
        mutate(&edit)
        let items = edit.items
        guard !items.isEmpty else { return }

        let themeItems = items.intersection(readingSettingsScope.themeItems)
        let sharedItems = items.subtracting(themeItems)
        if !sharedItems.isEmpty {
            let shared = globalReadingSettings
            let updated = shared.overlaid(with: edit.restricted(to: sharedItems))
            if updated != shared { globalReadingSettings = updated }
        }
        if !themeItems.isEmpty {
            let themeID = readingSettingsThemeID
            let own = themeReadingSettings(themeID: themeID) ?? AppearanceThemeReadingSettings()
            let updated = own.overlaid(with: edit.restricted(to: themeItems))
            if updated != own { setThemeReadingSettings(updated, themeID: themeID) }
        }
    }

    // MARK: - Imports

    /// 跟隨主題 for a pack's settings: the rows its reading setup speaks for follow the
    /// theme from now on, for every theme.
    func followTheme(for items: Set<ReadingSettingsScopeItem>) {
        guard !items.isEmpty else { return }
        var configuration = readingSettingsScope
        for item in items {
            configuration.setScope(.theme, for: item)
        }
        readingSettingsScope = configuration
    }

    /// 取代全域設定: `reading` becomes the shared setup for every setting it speaks for,
    /// whatever the scope says, and is worn at once. Throws when the header/footer cannot
    /// be stored, with nothing changed on screen.
    func replaceGlobalReadingSettings(with reading: AppearanceThemeReadingSettings) throws {
        let previous = globalReadingSettings
        globalReadingSettings = previous.overlaid(with: reading)
        do {
            try applyReadingSettings(origin: .userImport)
        } catch {
            globalReadingSettings = previous
            synchronizeReadingSettings()
            throw error
        }
    }

    /// Where an import of reading settings into the current setup lands: the name of the
    /// worn theme when any of `items` follows it, nil when all of them are shared.
    func readingImportThemeName(for items: Set<ReadingSettingsScopeItem>) -> String? {
        items.isDisjoint(with: readingSettingsScope.themeItems) ? nil : readingSettingsThemeName
    }

    // MARK: - Snapshot

    /// Every field filled in, from the live settings. 全域 starts from this.
    func currentReadingSettingsSnapshot() -> AppearanceThemeReadingSettings {
        var snapshot = AppearanceThemeReadingSettings()
        snapshot.fontPostScript = selectedReaderFontPostScript ?? ""
        snapshot.fontSize = readerFontSize
        snapshot.isBold = readerFontBold
        snapshot.textColorOverrides = readerTextColorOverrides
        snapshot.lineHeightMultiple = lineHeightMultiple
        snapshot.letterSpacing = letterSpacing
        snapshot.paragraphSpacingMultiplier = paragraphSpacingMultiplier
        snapshot.pageMarginH = pageMarginH
        snapshot.pageMarginV = pageMarginV
        snapshot.pageMarginTop = pageMarginTop
        snapshot.pageMarginBottom = pageMarginBottom
        snapshot.pageTurnStyle = pageTurnStyle.rawValue
        snapshot.scrollMode = scrollMode
        snapshot.barLayout = readerBarLayout
        snapshot.headerVisible = readerHeaderVisible
        snapshot.footerVisible = readerFooterVisible
        snapshot.headerTopPadding = readerHeaderTopPadding
        snapshot.headerTextGap = readerHeaderTextGap
        snapshot.headerHorizontalPadding = readerHeaderHorizontalPadding
        snapshot.footerHorizontalPadding = readerFooterHorizontalPadding
        snapshot.footerBottomPadding = footerBottomPadding
        snapshot.footerTextGap = footerTextGap
        snapshot.chapterTitleStyle = chapterTitleStyle
        // `ReaderConfig.theme` is the owner of this one; its sink persists every change
        // as it happens, so the stored value is the live one.
        snapshot.readerTheme = ReaderTheme.loadPersisted().rawValue
        snapshot.followsSystemTheme = readerFollowSystemTheme
        snapshot.bindsAppearanceReaderTheme = appearanceBindReaderTheme
        snapshot.boundLightReaderTheme = appearanceBoundLightReaderTheme
        snapshot.boundDarkReaderTheme = appearanceBoundDarkReaderTheme
        snapshot.customBackground = currentCustomBackgroundSettings
        snapshot.commentBubble = currentCommentBubbleSettings
        snapshot.dialogueBubbleStyle = dialogueBubbleStyle
        snapshot.regexHighlights = regexHighlightConfiguration
        snapshot.textUnderline = currentTextUnderlineSettings
        return snapshot
    }

    var currentCustomBackgroundSettings: AppearanceThemeReadingSettings.CustomBackground {
        AppearanceThemeReadingSettings.CustomBackground(
            mode: readerCustomBackgroundMode.rawValue,
            colorHex: readerCustomBackgroundColorHex,
            imageFileName: readerCustomBackgroundImageFileName
        )
    }

    var currentCommentBubbleSettings: AppearanceThemeReadingSettings.CommentBubble {
        AppearanceThemeReadingSettings.CommentBubble(
            followsSourceSVG: commentBubbleFollowsSourceSVG,
            presetMode: commentBubblePresetMode.rawValue,
            customStyleID: commentBubbleSelectedCustomStyleID,
            scale: commentBubbleScale,
            textScale: commentBubbleTextScale
        )
    }

    var currentTextUnderlineSettings: AppearanceThemeReadingSettings.TextUnderline {
        AppearanceThemeReadingSettings.TextUnderline(
            isEnabled: readerTextUnderlineDecorationEnabled,
            colorHex: readerTextUnderlineDecorationColorHex,
            style: readerTextUnderlineStyle.rawValue,
            thickness: readerTextUnderlineThickness,
            offset: readerTextUnderlineOffset
        )
    }

    // MARK: - Writing

    /// Lays `reading` over the live settings: every non-nil field is written, every nil
    /// one is left as it is. The one writer for a reading setup — wearing a theme and
    /// imports both land here — and it assigns only what differs, so re-applying the
    /// same setup costs no relayout.
    ///
    /// The header/footer goes first and, for an import, vetoes the rest when it cannot
    /// be stored: a type size that changed while the bars silently did not is worse than
    /// a reported failure. A theme switch logs the failure and carries on, since it has
    /// no one to report to and the rest of the setup is still right.
    func writeReadingSettings(
        _ reading: AppearanceThemeReadingSettings,
        origin: ReadingSettingsWriteOrigin
    ) throws {
        let stamps = origin == .userImport
        var changed = false
        func assign<Value: Equatable>(_ path: ReferenceWritableKeyPath<GlobalSettings, Value>, _ value: Value?) {
            guard let value, self[keyPath: path] != value else { return }
            self[keyPath: path] = value
            changed = true
        }

        if let layout = reading.barLayout, layout != readerBarLayout {
            if writeReaderBarLayout(layout, stampsSyncClock: stamps) {
                changed = true
            } else {
                AppLogger.error("⟐ reading setup: header/footer layout not stored", context: [
                    "origin": "\(origin)",
                ])
                if origin == .userImport { throw ReaderOverlayLayoutPersistenceError.writeFailed }
            }
        }

        if let font = reading.fontPostScript {
            let value: String? = font.isEmpty ? nil : font
            if selectedReaderFontPostScript != value {
                selectedReaderFontPostScript = value
                changed = true
            }
        }
        assign(\.readerFontSize, reading.fontSize)
        assign(\.readerFontBold, reading.isBold)
        assign(\.readerTextColorOverrides, reading.textColorOverrides)
        assign(\.lineHeightMultiple, reading.lineHeightMultiple)
        assign(\.letterSpacing, reading.letterSpacing)
        assign(\.paragraphSpacingMultiplier, reading.paragraphSpacingMultiplier)
        assign(\.pageMarginH, reading.pageMarginH)
        assign(\.pageMarginV, reading.pageMarginV)
        assign(\.pageMarginTop, reading.pageMarginTop)
        assign(\.pageMarginBottom, reading.pageMarginBottom)
        assign(\.pageTurnStyle, reading.pageTurnStyle.flatMap(PageTurnStyle.init(rawValue:)))
        assign(\.scrollMode, reading.scrollMode)
        assign(\.readerHeaderVisible, reading.headerVisible)
        assign(\.readerFooterVisible, reading.footerVisible)
        assign(\.readerHeaderTopPadding, reading.headerTopPadding)
        assign(\.readerHeaderTextGap, reading.headerTextGap)
        assign(\.readerHeaderHorizontalPadding, reading.headerHorizontalPadding)
        assign(\.readerFooterHorizontalPadding, reading.footerHorizontalPadding)
        assign(\.footerBottomPadding, reading.footerBottomPadding)
        assign(\.footerTextGap, reading.footerTextGap)
        assign(\.chapterTitleStyle, reading.chapterTitleStyle)

        // 綁定閱讀主題 before 跟隨系統: turning the binding on switches 跟隨系統 off in its
        // own `didSet`, which must not overwrite the value the setup asks for.
        assign(\.appearanceBindReaderTheme, reading.bindsAppearanceReaderTheme)
        assign(\.readerFollowSystemTheme, reading.followsSystemTheme)
        assign(\.appearanceBoundLightReaderTheme, reading.boundLightReaderTheme)
        assign(\.appearanceBoundDarkReaderTheme, reading.boundDarkReaderTheme)
        if let raw = reading.readerTheme, let theme = ReaderTheme(rawValue: raw),
           theme != ReaderTheme.loadPersisted() {
            // Stored rather than set on `ReaderConfig`, which owns the live value and
            // reloads it from here on the notification below.
            theme.persist()
            changed = true
        }
        if let background = reading.customBackground {
            if let mode = ReaderCustomBackgroundMode(rawValue: background.mode) {
                assign(\.readerCustomBackgroundMode, mode)
            }
            if readerCustomBackgroundColorHex != background.colorHex {
                readerCustomBackgroundColorHex = background.colorHex
                changed = true
            }
            if readerCustomBackgroundImageFileName != background.imageFileName {
                readerCustomBackgroundImageFileName = background.imageFileName
                changed = true
            }
        }

        if let bubble = reading.commentBubble {
            assign(\.commentBubbleFollowsSourceSVG, bubble.followsSourceSVG)
            assign(\.commentBubbleScale, bubble.scale)
            assign(\.commentBubbleTextScale, bubble.textScale)
            let mode = ReaderCommentBubblePresetMode(rawValue: bubble.presetMode) ?? .builtin
            if commentBubblePresetMode != mode || commentBubbleSelectedCustomStyleID != bubble.customStyleID {
                applyCommentBubbleChoice(
                    presetMode: mode,
                    customStyleID: bubble.customStyleID,
                    stampsSyncClock: stamps
                )
                changed = true
            }
        }
        assign(\.dialogueBubbleStyle, reading.dialogueBubbleStyle)
        assign(\.regexHighlightConfiguration, reading.regexHighlights)
        if let underline = reading.textUnderline {
            assign(\.readerTextUnderlineDecorationEnabled, underline.isEnabled)
            assign(\.readerTextUnderlineDecorationColorHex, underline.colorHex)
            assign(\.readerTextUnderlineStyle, ReaderTextUnderlineStyle(rawValue: underline.style))
            assign(\.readerTextUnderlineThickness, underline.thickness)
            assign(\.readerTextUnderlineOffset, underline.offset)
        }

        guard changed else { return }
        NotificationCenter.default.post(name: .readingSettingsDidApply, object: self)
    }
}
