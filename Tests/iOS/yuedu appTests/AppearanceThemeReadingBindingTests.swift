import Foundation
import Testing
@testable import yuedu_app

/// 閱讀設定隨主題切換: a theme bound to a reading setup wears it while selected and hands
/// the user's own back when left; a theme that is not bound never touches reading.
@Suite("Theme-bound reading settings", .serialized)
@MainActor
struct AppearanceThemeReadingBindingTests {
    private var defaultID: String { GlobalSettings.defaultAppearanceThemeID }

    @Test func aBoundThemeWearsItsSetupAndLeavingRestoresTheUsersOwn() throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()
        _ = ReaderConfig.shared  // subscribed before the switch, as in the running app

        var reading = AppearanceThemeReadingSettings()
        reading.fontSize = 24
        reading.scrollMode = true
        let pack = Self.theme("Pack", reading: reading)
        settings.customAppearanceThemes.append(pack)

        settings.appearanceThemeID = pack.id
        #expect(settings.readerFontSize == 24)
        #expect(settings.scrollMode)
        // Not spoken for: stays the user's own.
        #expect(settings.lineHeightMultiple == 1.6)
        // The reader's mirror reloads before the switch returns.
        #expect(ReaderConfig.shared.fontSize == 24)

        settings.appearanceThemeID = defaultID
        #expect(settings.readerFontSize == 18)
        #expect(!settings.scrollMode)
        #expect(ReaderConfig.shared.fontSize == 18)
    }

    @Test func editsUnderABoundThemeStayWithThatTheme() throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()

        var reading = AppearanceThemeReadingSettings()
        reading.fontSize = 24
        let pack = Self.theme("Pack", reading: reading)
        settings.customAppearanceThemes.append(pack)
        settings.appearanceThemeID = pack.id

        settings.letterSpacing = 1.5
        let stored = try #require(settings.customAppearanceThemes.first { $0.id == pack.id }?.extras?.reading)
        #expect(stored.letterSpacing == 1.5)
        // Per field: the edit must not pin everything else to what was on screen.
        #expect(stored.lineHeightMultiple == nil)

        settings.appearanceThemeID = defaultID
        #expect(settings.letterSpacing == 0)
        settings.appearanceThemeID = pack.id
        #expect(settings.letterSpacing == 1.5)
    }

    /// The case the baseline write-through exists for: without it, a font size changed
    /// under a colour-only custom theme would silently revert on the next switch.
    @Test func editsUnderAnUnboundCustomThemeAreTheUsersOwn() throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()

        let plain = Self.theme("Plain", reading: nil)
        settings.customAppearanceThemes.append(plain)
        settings.appearanceThemeID = plain.id
        settings.readerFontSize = 21

        #expect(settings.customAppearanceThemes.first { $0.id == plain.id }?.extras?.reading == nil)
        settings.appearanceThemeID = defaultID
        #expect(settings.readerFontSize == 21)
    }

    @Test func bindingCapturesTheSetupOnScreenAndUnbindingHandsTheUsersOwnBack() throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()

        let plain = Self.theme("Plain", reading: nil)
        settings.customAppearanceThemes.append(plain)
        settings.appearanceThemeID = plain.id
        settings.readerFontSize = 20

        settings.setThemeBindsReadingSettings(true, themeID: plain.id)
        #expect(settings.themeBindsReadingSettings(id: plain.id))
        #expect(settings.readingSettingsOwnerTheme?.id == plain.id)
        let captured = try #require(settings.customAppearanceThemes.first { $0.id == plain.id }?.extras?.reading)
        #expect(captured.fontSize == 20)
        #expect(settings.readerFontSize == 20)

        settings.readerFontSize = 26
        settings.appearanceThemeID = defaultID
        #expect(settings.readerFontSize == 20)
        settings.appearanceThemeID = plain.id
        #expect(settings.readerFontSize == 26)

        settings.setThemeBindsReadingSettings(false, themeID: plain.id)
        #expect(!settings.themeBindsReadingSettings(id: plain.id))
        #expect(settings.readingSettingsOwnerTheme == nil)
        #expect(settings.readerFontSize == 20)
    }

    /// An upgrade: a custom theme was already selected, with a baseline written before
    /// reading could follow a theme. The user's own setup must be captured before a bound
    /// theme lays its own over it, or leaving that theme would restore nothing.
    @Test func aBaselineFromBeforeTheUpgradeIsCompletedFirst() throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()

        let plain = Self.theme("Plain", reading: nil)
        var reading = AppearanceThemeReadingSettings()
        reading.fontSize = 30
        let bound = Self.theme("Bound", reading: reading)
        settings.customAppearanceThemes.append(contentsOf: [plain, bound])
        settings.appearanceThemeID = plain.id
        var legacy = try #require(settings.appearanceExtrasBaseline)
        legacy.reading = nil
        settings.appearanceExtrasBaseline = legacy
        settings.readerFontSize = 19

        settings.appearanceThemeID = bound.id
        #expect(settings.readerFontSize == 30)
        settings.appearanceThemeID = defaultID
        #expect(settings.readerFontSize == 19)
    }

    @Test func theReadingBackgroundFollowsTheTheme() throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()
        ReaderConfig.shared.theme = .white

        var reading = AppearanceThemeReadingSettings()
        reading.readerTheme = ReaderTheme.green.rawValue
        reading.followsSystemTheme = false
        let pack = Self.theme("Green", reading: reading)
        settings.customAppearanceThemes.append(pack)

        settings.appearanceThemeID = pack.id
        #expect(ReaderTheme.loadPersisted() == .green)
        #expect(ReaderConfig.shared.theme == .green)

        settings.appearanceThemeID = defaultID
        #expect(ReaderTheme.loadPersisted() == .white)
        #expect(ReaderConfig.shared.theme == .white)
    }

    @Test func aFieldThisBuildCannotReadCostsOnlyThatField() throws {
        let json = #"{"fontSize": 20, "barLayout": {"version": "not a number"}, "scrollMode": true}"#
        let decoded = try JSONDecoder().decode(AppearanceThemeReadingSettings.self, from: Data(json.utf8))
        #expect(decoded.fontSize == 20)
        #expect(decoded.scrollMode == true)
        #expect(decoded.barLayout == nil)
    }

    @Test func anExportedThemeLeavesItsReadingSetupBehind() {
        var extras = AppearanceThemeExtras()
        extras.tabIconSize = 30
        var reading = AppearanceThemeReadingSettings()
        reading.fontSize = 22
        extras.reading = reading
        let file = AppearanceThemeExportFile(customTheme: Self.theme("Export", extras: extras))
        #expect(file.extras?.reading == nil)
        #expect(file.extras?.tabIconSize == 30)
    }

    // MARK: - Import

    @Test func aPackImportedToFollowItsThemeWearsItsSetupOnlyWhileSelected() async throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()

        let outcome = try await QiThemeImportService.apply(Self.pack(textSize: 26), reading: .bindToTheme)
        #expect(outcome.readingDisposition == .bindToTheme)
        let theme = try #require(outcome.theme)
        #expect(theme.extras?.reading?.fontSize == 26)
        #expect(settings.readerFontSize == 26)

        let overview = CustomizationImportOverview(qiTheme: outcome)
        #expect(overview.readingPlacement == .theme(name: theme.name))
        #expect(overview.readingItems.map(\.id).contains(ReadingSetupPart.layout.titleKey))

        settings.appearanceThemeID = defaultID
        #expect(settings.readerFontSize == 18)
    }

    @Test func aPackImportedToReplaceBecomesTheUsersOwnSetup() async throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }
        fixture.reset()

        let outcome = try await QiThemeImportService.apply(Self.pack(textSize: 26), reading: .replaceCurrent)
        #expect(outcome.readingDisposition == .replaceCurrent)
        #expect(outcome.theme?.extras?.reading == nil)
        #expect(settings.readerFontSize == 26)
        #expect(CustomizationImportOverview(qiTheme: outcome).readingPlacement == .own)

        settings.appearanceThemeID = defaultID
        #expect(settings.readerFontSize == 26)
    }

    @Test func theQuestionNamesTheWholeReadingSetup() throws {
        var pack = Self.pack(textSize: 20)
        pack.chapterTitleStyle = .default
        let parts = QiThemeImportService.readingParts(of: pack)
        #expect(parts.contains(.layout))
        #expect(parts.contains(.chapterTitle))

        let prompt = CustomizationImportPrompt.themePack(named: pack.name, readingParts: parts)
        #expect(prompt.choices.options.map(\.disposition) == [.bindToTheme, .replaceCurrent])
        #expect(prompt.choices.options.first?.isPreferred == true)
        for part in parts {
            #expect(prompt.message.contains(localized(part.titleKey)))
        }

        // A look with nothing about reading asks nothing.
        let lookOnly = QiThemeImport(name: "Look", themeFile: nil)
        #expect(QiThemeImportService.readingParts(of: lookOnly).isEmpty)
    }

    // MARK: - Helpers

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

    /// Saves and restores field by field rather than through the snapshot under test.
    @MainActor
    private final class Fixture {
        private let settings: GlobalSettings
        private let lightID: String
        private let darkID: String
        private let themes: [AppearanceCustomTheme]
        private let baseline: AppearanceThemeExtras?
        private let fontSize: Double
        private let lineHeight: Double
        private let letterSpacing: Double
        private let scrollMode: Bool
        private let followsSystem: Bool
        private let bindsReaderTheme: Bool
        private let readerTheme: ReaderTheme
        /// Everything else an imported pack may have written into the user's own setup.
        /// Restored last, through the writer, only as a safety net for the simulator.
        private let reading: AppearanceThemeReadingSettings

        init(_ settings: GlobalSettings) {
            self.settings = settings
            lightID = settings.appearanceThemeID
            darkID = settings.appearanceDarkThemeID
            themes = settings.customAppearanceThemes
            baseline = settings.appearanceExtrasBaseline
            fontSize = settings.readerFontSize
            lineHeight = settings.lineHeightMultiple
            letterSpacing = settings.letterSpacing
            scrollMode = settings.scrollMode
            followsSystem = settings.readerFollowSystemTheme
            bindsReaderTheme = settings.appearanceBindReaderTheme
            readerTheme = ReaderTheme.loadPersisted()
            reading = settings.currentReadingSettingsSnapshot()
        }

        /// A built-in theme and a known reading setup, so each test reads the mechanism
        /// rather than whatever the simulator was left in.
        func reset() {
            settings.appearanceThemeID = GlobalSettings.defaultAppearanceThemeID
            settings.appearanceDarkThemeID = GlobalSettings.defaultAppearanceThemeID
            settings.appearanceExtrasBaseline = nil
            settings.customAppearanceThemes = themes
            settings.readerFontSize = 18
            settings.lineHeightMultiple = 1.6
            settings.letterSpacing = 0
            settings.scrollMode = false
            settings.readerFollowSystemTheme = false
            settings.appearanceBindReaderTheme = false
            ReaderConfig.shared.syncFromGlobalSettings()
        }

        func restore() {
            settings.appearanceThemeID = GlobalSettings.defaultAppearanceThemeID
            settings.appearanceDarkThemeID = GlobalSettings.defaultAppearanceThemeID
            settings.appearanceExtrasBaseline = nil
            settings.customAppearanceThemes = themes
            settings.readerFontSize = fontSize
            settings.lineHeightMultiple = lineHeight
            settings.letterSpacing = letterSpacing
            settings.scrollMode = scrollMode
            settings.appearanceBindReaderTheme = bindsReaderTheme
            settings.readerFollowSystemTheme = followsSystem
            readerTheme.persist()
            try? settings.writeReadingSettings(reading, origin: .theme)
            settings.appearanceExtrasBaseline = baseline
            settings.appearanceThemeID = lightID
            settings.appearanceDarkThemeID = darkID
            ReaderConfig.shared.syncFromGlobalSettings()
        }
    }
}
