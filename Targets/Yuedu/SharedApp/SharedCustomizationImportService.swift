import Foundation

/// The file bytes are captured while Open In still owns security-scoped access.
/// Parsing and applying reuse the same services as the settings file pickers.
enum SharedCustomizationKind: Equatable {
    case appearanceJSON
    case nativePackage
    case qiTheme

    static func isAppearanceJSON(_ root: Any) -> Bool {
        if let object = root as? [String: Any], let format = object["format"] as? String {
            return [AppearanceThemeExportFile.formatIdentifier,
                    AppearanceThemeCollectionFile.formatIdentifier,
                    AppearanceCustomizationBundle.formatIdentifier].contains(format)
        }
        if let objects = root as? [[String: Any]], !objects.isEmpty {
            return objects.contains {
                $0["format"] as? String == AppearanceThemeExportFile.formatIdentifier
            }
        }
        return false
    }
}

struct SharedCustomizationDocument: Identifiable {
    let id = UUID()
    let data: Data
    let kind: SharedCustomizationKind
}

@MainActor
enum SharedCustomizationImportService {
    enum Plan {
        case appearance(Data)
        case reader(ReaderSettingsImportPlan)
        case qiTheme(QiThemeImport)

        var overwritesOverlayLayout: Bool {
            switch self {
            case .appearance: false
            case .reader(let plan): plan.overwritesOverlayLayout
            case .qiTheme(let theme): theme.overlayLayout != nil
            }
        }

        var canSkipOverlayLayout: Bool {
            if case .qiTheme = self { return true }
            return false
        }
    }

    static func load(_ document: SharedCustomizationDocument) async throws -> Plan {
        switch document.kind {
        case .appearanceJSON:
            return .appearance(document.data)
        case .qiTheme:
            return .qiTheme(try await QiThemeImportService.load(document.data))
        case .nativePackage:
            let payload = try await ReaderStylePackage.import(document.data, assetStore: .shared)
            if payload.kind == .appearance {
                let bundle = try payload.decode(AppearanceCustomizationBundle.self)
                guard bundle.format == AppearanceCustomizationBundle.formatIdentifier else {
                    throw AppearanceThemeImportError.invalidFile
                }
                return .appearance(payload.encodedModel)
            }
            return .reader(try ReaderSettingsImportService.plan(from: payload))
        }
    }

    static func apply(_ plan: Plan, includeOverlayLayout: Bool) async throws -> String {
        switch plan {
        case .appearance(let data):
            return try GlobalSettings.shared.importAppearanceCustomization(from: data).localizedDescription
        case .reader(let plan):
            let result = try ReaderSettingsImportService.apply(plan)
            return ([result.localizedDescription] + plan.notes).joined(separator: "\n\n")
        case .qiTheme(let theme):
            return try await QiThemeImportService.apply(
                theme, includeOverlayLayout: includeOverlayLayout
            ).localizedDescription
        }
    }
}

