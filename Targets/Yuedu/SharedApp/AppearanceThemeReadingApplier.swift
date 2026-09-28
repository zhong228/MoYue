import Foundation

extension Notification.Name {
    /// Reading settings were written from outside the reader — a theme switch or an
    /// import. `ReaderConfig` mirrors most of them and reloads on this, so an open
    /// reader and the next one opened both see the new values.
    static let readingSettingsDidApply = Notification.Name("yd.readingSettingsDidApply")
}

/// The reading half of a theme: 閱讀設定 following the theme it is bound to.
///
/// Rides the same machinery as the rest of `AppearanceThemeExtras` — the baseline, the
/// restore-then-apply in `synchronizeAppearanceThemeExtras`, the per-field write-back —
/// with one difference in *where an edit goes*. Every other extra is recorded on the
/// selected custom theme, bound or not. A reading edit is recorded on the theme only
/// when that theme is bound to a reading setup; otherwise it belongs to the user's own
/// setup, which the baseline holds while any custom theme is selected. Without that
/// second case the baseline would go stale under an unbound theme, and the next switch
/// would quietly put back a font size the user changed an hour ago.
extension GlobalSettings {
    enum ReadingSettingsWriteOrigin {
        /// Selecting a theme or leaving one: which setup this device wears, not an
        /// edit — so no iCloud merge clock is stamped.
        case theme
        /// The user importing a file into their current setup: an edit like any other.
        case userImport
    }

    // MARK: - Binding

    func themeBindsReadingSettings(id: String) -> Bool {
        customAppearanceThemes.first(where: { $0.id == id })?.extras?.reading != nil
    }

    /// The theme whose reading setup the reader is wearing right now, or nil when it
    /// is the user's own.
    var readingSettingsOwnerTheme: AppearanceCustomTheme? {
        guard let id = activeExtrasOwnerThemeID,
              let theme = customAppearanceThemes.first(where: { $0.id == id }),
              theme.extras?.reading != nil else {
            return nil
        }
        return theme
    }

    /// Binding starts from the reading setup on screen: the user is saying "this look
    /// belongs to this theme", the way 保存為新主題 captures the whole appearance.
    /// Unbinding drops the theme's setup, and when the theme is the selected one the
    /// user's own setup comes straight back.
    func setThemeBindsReadingSettings(_ binds: Bool, themeID: String) {
        guard let index = customAppearanceThemes.firstIndex(where: { $0.id == themeID }),
              themeBindsReadingSettings(id: themeID) != binds else {
            return
        }
        var extras = customAppearanceThemes[index].extras ?? AppearanceThemeExtras()
        extras.reading = binds ? currentReadingSettingsSnapshot() : nil
        customAppearanceThemes[index].extras = extras
        guard activeExtrasOwnerThemeID == themeID else { return }
        synchronizeAppearanceThemeExtras()
    }

    // MARK: - Recording edits

    /// Records one edited reading setting where it belongs. Every covered `didSet` calls
    /// this; it is a no-op while a theme is being applied.
    ///
    /// - A bound theme is selected: the edit is that theme's, per field, like any extra.
    /// - An unbound custom theme is selected: the edit is the user's own, so it goes
    ///   into the baseline that leaving the theme restores.
    /// - A built-in theme is selected: there is no baseline, and the live settings are
    ///   the user's own already.
    func recordReadingSettingEdit(_ mutate: (inout AppearanceThemeReadingSettings) -> Void) {
        guard !isApplyingAppearanceExtras,
              let id = activeExtrasOwnerThemeID,
              let index = customAppearanceThemes.firstIndex(where: { $0.id == id }) else {
            return
        }
        if var reading = customAppearanceThemes[index].extras?.reading {
            mutate(&reading)
            guard customAppearanceThemes[index].extras?.reading != reading else { return }
            customAppearanceThemes[index].extras?.reading = reading
            return
        }
        // The baseline's reading setup is always complete (see the capture in
        // `synchronizeAppearanceThemeExtras`). A baseline without one — written by a
        // build before reading could follow a theme — is left alone: seeding it with a
        // single field would make leaving a theme restore that field and nothing else.
        guard var baseline = appearanceExtrasBaseline, var reading = baseline.reading else { return }
        mutate(&reading)
        guard baseline.reading != reading else { return }
        baseline.reading = reading
        appearanceExtrasBaseline = baseline
    }

    // MARK: - Snapshot

    /// Every field filled in, from the live settings. The baseline's reading setup and a
    /// freshly bound theme both start from this.
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
    /// one is left as it is. The one writer for a reading setup — theme switches and
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
