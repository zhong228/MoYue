import Foundation

/// Feature flag controlling which rule engine is used for book source parsing.
enum ParserSettings {
    /// When true, uses ModernRuleEngine; when false, falls back to legacy RuleEngine.
    static var useModernParser: Bool {
        get { UserDefaults.standard.bool(forKey: "useModernParser") }
        set { UserDefaults.standard.set(newValue, forKey: "useModernParser") }
    }
}
