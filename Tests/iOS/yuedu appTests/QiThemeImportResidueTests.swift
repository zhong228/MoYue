import Foundation
import Testing
@testable import yuedu_app

/// Importing a QiReader pack and then choosing 默認 again must leave the app exactly as it
/// was before the import. Reported 2026-09-28 with 山风 - 春水漾: after the first import,
/// switching back to 默認 kept the pack's page background.
@Suite("QiReader pack leaves nothing behind", .serialized)
@MainActor
struct QiThemeImportResidueTests {
    private static let global = AppearancePageBackgroundScope.global.rawValue

    /// The pack's page background belongs to its theme. It used to be written into the
    /// live settings first, as if it were the user's own look, so the baseline captured
    /// when the theme got selected already held it.
    @Test func leavingAnImportedPackGivesTheUsersPageBackgroundBack() async throws {
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }

        let own = AppearancePageBackgroundConfig(
            lightPrimaryHex: 0x111111, lightSecondaryHex: nil,
            darkPrimaryHex: nil, darkSecondaryHex: nil
        )
        settings.appearancePageBackgrounds = [Self.global: own]

        var extras = AppearanceThemeExtras()
        extras.pageBackgrounds = [Self.global: AppearancePageBackgroundConfig(
            lightPrimaryHex: 0xABCDEF, lightSecondaryHex: nil,
            darkPrimaryHex: nil, darkSecondaryHex: nil
        )]
        let file = AppearanceThemeExportFile(customTheme: AppearanceCustomTheme(
            name: "Residue Fixture", backgroundHex: 0xFFFFFF, textHex: 0, barHex: 0xFFFFFF,
            accentHex: 0x123456, dialogueHex: 0, extras: extras
        ))
        var pack = QiThemeImport(name: "Residue Fixture", themeFile: file)
        // Where the importer puts a pack's backgrounds: on the theme file and here.
        pack.pageBackgrounds = file.pageBackgrounds ?? [:]

        let outcome = try await QiThemeImportService.apply(pack, reading: .bindToTheme)
        let theme = try #require(outcome.theme)
        fixture.imported.append(theme.id)
        #expect(settings.appearancePageBackgrounds[Self.global]?.lightPrimaryHex == 0xABCDEF)

        settings.appearanceThemeID = GlobalSettings.defaultAppearanceThemeID
        #expect(settings.appearancePageBackgrounds == [Self.global: own])
    }

    /// The report itself, with the pack it was made with: import, choose 默認, and nothing
    /// of the pack's look or reading setup may still be on screen.
    @Test func chunshuiyangLeavesNothingBehindOnceDefaultIsChosen() async throws {
        let url = URL(fileURLWithPath: "/Users/zhangruilin/Downloads/山风 - 春水漾.qitheme")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let settings = GlobalSettings.shared
        let fixture = Fixture(settings)
        defer { fixture.restore() }

        let appearanceBefore = settings.currentAppearanceExtrasSnapshot()
        let readingBefore = settings.currentReadingSettingsSnapshot()

        let pack = try await QiThemeImportService.load(Data(contentsOf: url))
        let outcome = try await QiThemeImportService.apply(pack, reading: .bindToTheme)
        let theme = try #require(outcome.theme)
        fixture.imported.append(theme.id)
        // Worn while selected…
        #expect(settings.appearancePageBackgrounds != appearanceBefore.pageBackgrounds)

        // …and gone once 默認 is chosen again.
        settings.appearanceThemeID = GlobalSettings.defaultAppearanceThemeID
        let appearanceAfter = settings.currentAppearanceExtrasSnapshot()
        #expect(appearanceAfter.pageBackgrounds == appearanceBefore.pageBackgrounds)
        #expect(appearanceAfter.tabIcons == appearanceBefore.tabIcons)
        #expect(appearanceAfter.hidesTabLabels == appearanceBefore.hidesTabLabels)
        #expect(appearanceAfter.launchImageEnabled == appearanceBefore.launchImageEnabled)
        #expect(appearanceAfter.launchImageLightFileName == appearanceBefore.launchImageLightFileName)
        #expect(appearanceAfter.defaultCoverLightFileNames == appearanceBefore.defaultCoverLightFileNames)
        #expect(appearanceAfter.forceDefaultCover == appearanceBefore.forceDefaultCover)
        #expect(appearanceAfter.globalFontPostScript == appearanceBefore.globalFontPostScript)
        #expect(appearanceAfter.frostedGlass == appearanceBefore.frostedGlass)
        #expect(appearanceAfter.glassTransparency == appearanceBefore.glassTransparency)
        #expect(appearanceAfter.glowIntensity == appearanceBefore.glowIntensity)
        #expect(appearanceAfter.bookshelfGridColumnCount == appearanceBefore.bookshelfGridColumnCount)
        #expect(appearanceAfter.bookshelfCoverCornerRadius == appearanceBefore.bookshelfCoverCornerRadius)
        #expect(appearanceAfter.readerInterface == appearanceBefore.readerInterface)
        #expect(appearanceAfter.cardBackground == appearanceBefore.cardBackground)
        #expect(appearanceAfter.readerChromeIcons == appearanceBefore.readerChromeIcons)
        #expect(appearanceAfter == appearanceBefore)
        #expect(settings.currentReadingSettingsSnapshot() == readingBefore)
    }

    /// Back to 默認 on entry, and back to where the simulator was on exit — field by field
    /// for what these tests change, and the imported themes deleted so their artwork is
    /// reclaimed.
    @MainActor
    private final class Fixture {
        private let settings: GlobalSettings
        private let lightID: String
        private let darkID: String
        private let themes: [AppearanceCustomTheme]
        private let baseline: AppearanceThemeExtras?
        private let backgrounds: [String: AppearancePageBackgroundConfig]
        private let reading: AppearanceThemeReadingSettings
        var imported: [String] = []

        init(_ settings: GlobalSettings) {
            self.settings = settings
            lightID = settings.appearanceThemeID
            darkID = settings.appearanceDarkThemeID
            themes = settings.customAppearanceThemes
            baseline = settings.appearanceExtrasBaseline
            settings.appearanceThemeID = GlobalSettings.defaultAppearanceThemeID
            settings.appearanceDarkThemeID = GlobalSettings.defaultAppearanceThemeID
            settings.appearanceExtrasBaseline = nil
            backgrounds = settings.appearancePageBackgrounds
            reading = settings.currentReadingSettingsSnapshot()
        }

        func restore() {
            settings.appearanceThemeID = GlobalSettings.defaultAppearanceThemeID
            settings.appearanceDarkThemeID = GlobalSettings.defaultAppearanceThemeID
            for id in imported {
                settings.deleteCustomAppearanceTheme(id: id)
            }
            settings.appearanceExtrasBaseline = nil
            settings.customAppearanceThemes = themes
            settings.appearancePageBackgrounds = backgrounds
            try? settings.writeReadingSettings(reading, origin: .theme)
            settings.appearanceExtrasBaseline = baseline
            settings.appearanceThemeID = lightID
            settings.appearanceDarkThemeID = darkID
        }
    }
}
