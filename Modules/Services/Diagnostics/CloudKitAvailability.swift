import Foundation

/// Whether this build may touch CloudKit at all.
///
/// CloudKit is entitlement-gated: creating a `CKContainer(identifier:)` in a
/// process whose signatures lack the matching iCloud container entitlement calls
/// `os_crash` (EXC_BREAKPOINT / SIGTRAP) **inside the CloudKit framework** and
/// kills the app on the spot — that is the startup crash LiveContainer users hit
/// from the first build, because LiveContainer runs the app unsigned and the
/// `LiveProcess` host carries none of the app's iCloud entitlements.
///
/// Every CloudKit entry point (`ICloudSyncManager`, `SubscriptionICloudMirror`)
/// must check `isAvailable` first and degrade (iCloud sync off, mirror read
/// returns nil) instead of constructing a container. Signed builds installed via
/// Xcode / TestFlight / App Store keep the real entitlement and CloudKit works
/// unchanged.
enum CloudKitAvailability {
    /// True when this process may touch CloudKit safely.
    ///
    /// iOS exposes no public API to read the running process's own entitlement
    /// (`SecTask*` is macOS-only, which does not compile on iOS), so we
    /// approximate with the iCloud identity token: it is non-`nil` only in a
    /// process that is entitled for iCloud **and** has the user signed in. That
    /// is deliberately conservative:
    ///
    /// - LiveContainer (unsigned, no entitlement) → always `nil` → CloudKit
    ///   never constructed → no `os_crash`, which is exactly the crash being
    ///   fixed.
    /// - A signed build with the user signed out of iCloud → `nil` → CloudKit
    ///   work is skipped until sign-in, when it becomes available again; a
    ///   `CKContainer` would not have crashed there, it would just report
    ///   `.noAccount`, so skipping is functionally equivalent without the risk.
    static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}