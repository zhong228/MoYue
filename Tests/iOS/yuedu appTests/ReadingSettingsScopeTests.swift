import Foundation
import Testing
@testable import yuedu_app

/// 排版生效範圍: per reading setting, the worn theme's own value or the one every theme
/// shares. Nothing a theme keeps is lost by changing the scope — the complaint this
/// replaced was a per-theme switch that threw the theme's setup away when turned off.
@Suite("排版生效範圍", .serialized)
@MainActor
struct ReadingSettingsScopeTests {
    private var defaultID: String { GlobalSettings.defaultAppearanceThemeID }

    // MARK: - Wearing

    @Test func everythingIsSharedUntilASettingFollowsTheTheme() throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()

        var reading = AppearanceThemeReadingSettings()
        reading.fontSize = 24
        reading.scrollMode = true
        let pack = Self.theme("Pack", reading: reading)
        settings.customAppearanceThemes.append(pack)

        // The default: a theme's own values wait.
        settings.appearanceThemeID = pack.id
        #expect(settings.readerFontSize == 18)
        #expect(!settings.scrollMode)

        // One setting follows the theme; the other stays shared.
        settings.setReadingSettingsScope(.theme, for: .fontSize)
        #expect(settings.readerFontSize == 24)
        #expect(!settings.scrollMode)
        #expect(ReaderConfig.shared.fontSize == 24)

        settings.appearanceThemeID = defaultID
        #expect(settings.readerFontSize == 18)
        #expect(ReaderConfig.shared.fontSize == 18)
        settings.appearanceThemeID = pack.id
        #expect(settings.readerFontSize == 24)
    }

    /// The report: a theme's reading setup has to survive being switched off and on.
    @Test func sharingASettingAndFollowingAgainBringsTheThemesValueBack() throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()

        var reading = AppearanceThemeReadingSettings()
        reading.fontSize = 24
        let pack = Self.theme("Pack", reading: reading)
        settings.customAppearanceThemes.append(pack)
        settings.setReadingSettingsScope(.theme, for: .fontSize)
        settings.appearanceThemeID = pack.id
        #expect(settings.readerFontSize == 24)

        // Shared: the one every theme uses, and an edit now belongs to it.
        settings.setReadingSettingsScope(.global, for: .fontSize)
        #expect(settings.readerFontSize == 18)
        settings.readerFontSize = 20

        // Following again: the theme's own, untouched.
        settings.setReadingSettingsScope(.theme, for: .fontSize)
        #expect(settings.readerFontSize == 24)
        #expect(Self.ownReading(of: pack.id)?.fontSize == 24)

        settings.appearanceThemeID = defaultID
        #expect(settings.readerFontSize == 20)
    }

    // MARK: - Editing

    @Test func anEditGoesWhereItsSettingComesFrom() throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()

        let plain = Self.theme("Plain", reading: nil)
        settings.customAppearanceThemes.append(plain)
        settings.setReadingSettingsScope(.theme, for: .fontSize)
        settings.appearanceThemeID = plain.id

        settings.readerFontSize = 21
        settings.letterSpacing = 1.5
        let own = try #require(Self.ownReading(of: plain.id))
        #expect(own.fontSize == 21)
        // Per field: the theme says nothing about what it was not given.
        #expect(own.letterSpacing == nil)
        #expect(settings.globalReadingSettings.fontSize == 18)
        #expect(settings.globalReadingSettings.letterSpacing == 1.5)

        settings.appearanceThemeID = defaultID
        #expect(settings.readerFontSize == 18)
        #expect(settings.letterSpacing == 1.5)
        settings.appearanceThemeID = plain.id
        #expect(settings.readerFontSize == 21)
    }

    /// Built-in themes have no extras, but following the theme has to mean the same
    /// thing on them: 默認 with 護眼綠 and another preset with 白色.
    @Test func aBuiltInThemeKeepsItsOwnValuesToo() throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()
        ReaderConfig.shared.theme = .white
        settings.setReadingSettingsScope(.theme, for: .background)

        ReaderConfig.shared.theme = .green
        #expect(settings.themeReadingSettings(themeID: defaultID)?.readerTheme == ReaderTheme.green.rawValue)
        #expect(settings.globalReadingSettings.readerTheme == ReaderTheme.white.rawValue)

        let other = try #require(AppearanceThemePreset.freeSolidPresets.first { $0.id != defaultID })
        settings.appearanceThemeID = other.id
        #expect(ReaderTheme.loadPersisted() == .white)
        #expect(ReaderConfig.shared.theme == .white)

        settings.appearanceThemeID = defaultID
        #expect(ReaderTheme.loadPersisted() == .green)
        #expect(ReaderConfig.shared.theme == .green)
    }

    @Test func resettingTheScopeKeepsEveryThemesValues() throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()

        var reading = AppearanceThemeReadingSettings()
        reading.fontSize = 24
        let pack = Self.theme("Pack", reading: reading)
        settings.customAppearanceThemes.append(pack)
        settings.appearanceThemeID = pack.id
        settings.setReadingSettingsScope(.theme, for: .fontSize)
        settings.setReadingSettingsScope(.theme, for: .lineSpacing)
        #expect(settings.readingSettingsScope.themeItems == [.fontSize, .lineSpacing])

        settings.readingSettingsScope = .default
        #expect(settings.readingSettingsScope.themeItems.isEmpty)
        #expect(settings.readerFontSize == 18)
        #expect(Self.ownReading(of: pack.id)?.fontSize == 24)
    }

    @Test func aRowSetToTheDefaultMovesWithTheDefault() {
        var scope = ReadingSettingsScopeConfiguration.default
        scope.setScope(.theme, for: .font)
        scope.setScope(.global, for: .fontSize)
        #expect(scope.themeItems == [.font])

        scope.defaultScope = .theme
        // 字體 was set on its own; 字體大小 only ever said what the default said.
        #expect(scope.scope(of: .font) == .theme)
        #expect(scope.scope(of: .fontSize) == .theme)
        #expect(scope.scope(of: .background) == .theme)
    }

    /// A theme that only keeps reading values speaks for no appearance setting, so
    /// selecting it must not write its absent card background over the user's.
    @Test func readingValuesAloneSpeakForNoAppearanceSetting() {
        var extras = AppearanceThemeExtras()
        var reading = AppearanceThemeReadingSettings()
        reading.fontSize = 20
        extras.reading = reading
        #expect(extras.isEmpty)
    }

    // MARK: - The shared setup

    /// Before 排版生效範圍 the user's own reading setup lived in the appearance baseline
    /// while a custom theme was selected; that is what the shared setup starts from.
    @Test func theSharedSetupStartsFromTheOldBaseline() throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()

        var own = settings.currentReadingSettingsSnapshot()
        own.fontSize = 19
        var baseline = settings.currentAppearanceExtrasSnapshot()
        baseline.reading = own
        settings.appearanceExtrasBaseline = baseline
        ReadingSettingsStoresSnapshot.clear()

        #expect(settings.globalReadingSettings.fontSize == 19)
    }

    // MARK: - Imports

    @Test func aPackImportedToFollowTheThemeWearsItsSetupOnlyOnItsTheme() async throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()

        let outcome = try await QiThemeImportService.apply(Self.pack(textSize: 26), reading: .followTheme)
        let theme = try #require(outcome.theme)
        fixture.imported.append(theme.id)
        #expect(outcome.readingDisposition == .followTheme)
        #expect(theme.extras?.reading?.fontSize == 26)
        #expect(settings.readingSettingsScope.scope(of: .fontSize) == .theme)
        #expect(settings.readerFontSize == 26)

        let overview = CustomizationImportOverview(qiTheme: outcome)
        #expect(overview.readingPlacement == .followsTheme(name: theme.name))
        #expect(overview.readingItems.map(\.id).contains(ReadingSetupPart.layout.titleKey))

        settings.appearanceThemeID = defaultID
        #expect(settings.readerFontSize == 18)
    }

    @Test func aPackImportedToReplaceGlobalBecomesTheSharedSetup() async throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()

        let outcome = try await QiThemeImportService.apply(Self.pack(textSize: 26), reading: .replaceGlobal)
        let theme = try #require(outcome.theme)
        fixture.imported.append(theme.id)
        #expect(outcome.readingDisposition == .replaceGlobal)
        // Still the theme's own too, for when a setting is set to follow it.
        #expect(theme.extras?.reading?.fontSize == 26)
        #expect(settings.readingSettingsScope.themeItems.isEmpty)
        #expect(settings.globalReadingSettings.fontSize == 26)
        #expect(settings.readerFontSize == 26)
        #expect(CustomizationImportOverview(qiTheme: outcome).readingPlacement == .global)

        settings.appearanceThemeID = defaultID
        #expect(settings.readerFontSize == 26)
    }

    /// A reading-settings file lands like an edit: the settings that follow the theme on
    /// the worn one, the rest in 全域 — and the sheet says so.
    @Test func aReadingSettingsFileLandsSettingBySetting() throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()
        settings.setReadingSettingsScope(.theme, for: .fontSize)

        var file = AppearanceThemeReadingSettings()
        file.fontSize = 30
        file.lineHeightMultiple = 2.0
        #expect(CustomizationImportOverview.ReadingPlacement.current(for: file)
            == .split(themeName: settings.readingSettingsThemeName))

        try settings.writeReadingSettings(file, origin: .userImport)
        #expect(settings.themeReadingSettings(themeID: defaultID)?.fontSize == 30)
        #expect(settings.globalReadingSettings.fontSize == 18)
        #expect(settings.globalReadingSettings.lineHeightMultiple == 2.0)
    }

    @Test func theQuestionNamesTheWholeReadingSetup() throws {
        var pack = Self.pack(textSize: 20)
        pack.chapterTitleStyle = .default
        let parts = QiThemeImportService.readingParts(of: pack)
        #expect(parts.contains(.layout))
        #expect(parts.contains(.chapterTitle))

        let prompt = CustomizationImportPrompt.themePack(named: pack.name, readingParts: parts)
        #expect(prompt.choices.options.map(\.disposition) == [.followTheme, .replaceGlobal])
        #expect(prompt.choices.options.first?.isPreferred == true)
        for part in parts {
            #expect(prompt.message.contains(localized(part.titleKey)))
        }

        // A look with nothing about reading asks nothing.
        let lookOnly = QiThemeImport(name: "Look", themeFile: nil)
        #expect(QiThemeImportService.readingParts(of: lookOnly).isEmpty)
    }

    // MARK: - Files

    @Test func anExportedThemeLeavesItsReadingValuesBehind() {
        var extras = AppearanceThemeExtras()
        extras.tabIconSize = 30
        var reading = AppearanceThemeReadingSettings()
        reading.fontSize = 22
        extras.reading = reading
        let file = AppearanceThemeExportFile(customTheme: Self.theme("Export", extras: extras))
        #expect(file.extras?.reading == nil)
        #expect(file.extras?.tabIconSize == 30)
    }

    @Test func aFieldThisBuildCannotReadCostsOnlyThatField() throws {
        let json = #"{"fontSize": 20, "barLayout": {"version": "not a number"}, "scrollMode": true}"#
        let decoded = try JSONDecoder().decode(AppearanceThemeReadingSettings.self, from: Data(json.utf8))
        #expect(decoded.fontSize == 20)
        #expect(decoded.scrollMode == true)
        #expect(decoded.barLayout == nil)
    }

    // MARK: - Helpers

    private static func ownReading(of themeID: String) -> AppearanceThemeReadingSettings? {
        GlobalSettings.shared.themeReadingSettings(themeID: themeID)
    }

    private static func theme(_ name: String, reading: AppearanceThemeReadingSettings?) -> AppearanceCustomTheme {
        var extras = AppearanceThemeExtras()
        extras.reading = reading
        return theme(name, extras: reading == nil ? nil : extras)
    }

    private static func theme(_ name: String, extras: AppearanceThemeExtras?) -> AppearanceCustomTheme {
        AppearanceCustomTheme(name: name, backgroundHex: 0xFFFFFF, textHex: 0,
                              barHex: 0xFFFFFF, accentHex: 0x123456, dialogueHex: 0, extras: extras)
    }

    /// A pack with one reading value, and a theme to carry it.
    private static func pack(textSize: Int) -> QiThemeImport {
        let config = try? JSONSerialization.data(withJSONObject: ["textSize": textSize])
        return QiThemeImport(
            name: "Reading Fixture",
            themeFile: AppearanceThemeExportFile(customTheme: theme("Reading Fixture", extras: nil)),
            layoutConfig: config
        )
    }

    /// Saves and restores field by field rather than through the machinery under test.
    @MainActor
    private final class Fixture {
        private let settings: GlobalSettings
        private let lightID: String
        private let darkID: String
        private let themes: [AppearanceCustomTheme]
        private let baseline: AppearanceThemeExtras?
        private let stores = ReadingSettingsStoresSnapshot()
        private let readerTheme: ReaderTheme
        /// Everything else a test may have written into the live settings.
        private let reading: AppearanceThemeReadingSettings
        var imported: [String] = []

        init(_ settings: GlobalSettings) {
            self.settings = settings
            lightID = settings.appearanceThemeID
            darkID = settings.appearanceDarkThemeID
            themes = settings.customAppearanceThemes
            baseline = settings.appearanceExtrasBaseline
            readerTheme = ReaderTheme.loadPersisted()
            reading = settings.currentReadingSettingsSnapshot()
        }

        /// 默認, everything shared, and a known shared setup, so each test reads the
        /// mechanism rather than whatever the simulator was left in.
        func reset() {
            settings.appearanceThemeID = GlobalSettings.defaultAppearanceThemeID
            settings.appearanceDarkThemeID = GlobalSettings.defaultAppearanceThemeID
            settings.appearanceExtrasBaseline = nil
            settings.customAppearanceThemes = themes
            ReadingSettingsStoresSnapshot.clear()
            settings.readerFontSize = 18
            settings.lineHeightMultiple = 1.6
            settings.letterSpacing = 0
            settings.scrollMode = false
            settings.readerFollowSystemTheme = false
            settings.appearanceBindReaderTheme = false
            ReaderConfig.shared.syncFromGlobalSettings()
            // Captured now, from the values above.
            _ = settings.globalReadingSettings
        }

        func restore() {
            settings.appearanceThemeID = GlobalSettings.defaultAppearanceThemeID
            settings.appearanceDarkThemeID = GlobalSettings.defaultAppearanceThemeID
            for id in imported {
                settings.deleteCustomAppearanceTheme(id: id)
            }
            settings.appearanceExtrasBaseline = nil
            settings.customAppearanceThemes = themes
            readerTheme.persist()
            try? settings.writeReadingSettings(reading, origin: .theme)
            // After the live values: writing those records them as edits.
            stores.restore()
            settings.appearanceExtrasBaseline = baseline
            settings.appearanceThemeID = lightID
            settings.appearanceDarkThemeID = darkID
            ReaderConfig.shared.syncFromGlobalSettings()
        }
    }
}
