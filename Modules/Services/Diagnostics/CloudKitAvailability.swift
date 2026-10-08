import Foundation
import Security

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
    /// True only when the running process is entitled to use our iCloud container.
    static var isAvailable: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        guard let identifiers = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-container-identifiers" as CFString,
            nil
        ) as? [String] else { return false }
        return identifiers.contains(ICloudSyncManager.containerIdentifier)
    }
}