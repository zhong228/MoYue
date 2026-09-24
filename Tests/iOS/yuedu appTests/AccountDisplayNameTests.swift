import XCTest
@testable import yuedu_app

@MainActor
final class AccountDisplayNameTests: XCTestCase {
    func testPendingEditSurvivesRecreationAndIsAccountScoped() throws {
        let suite = "AccountDisplayNameTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let edits = AccountDisplayNameEdits(defaults: defaults)
        edits.save("New name", for: "account-a")
        let restored = AccountDisplayNameEdits(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(restored.pendingName(for: "account-a"), "New name")
        XCTAssertNil(restored.pendingName(for: "account-b"))
    }

    func testOldUploadCannotAcknowledgeNewerEdit() throws {
        let suite = "AccountDisplayNameTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let edits = AccountDisplayNameEdits(defaults: defaults)
        edits.save("First", for: "uid")
        let uploading = edits.edit(for: "uid")
        edits.save("Second", for: "uid")
        edits.acknowledge(uploading, for: "uid")
        XCTAssertEqual(edits.pendingName(for: "uid"), "Second")
        edits.acknowledge(edits.edit(for: "uid"), for: "uid")
        XCTAssertNil(edits.pendingName(for: "uid"))
    }

    func testRenameSurvivesAuthRefreshAndStaleProfileUntilAcknowledged() {
        withAccount { settings, uid in
            settings.updateAccountDisplayName("  Edited name  ")
            XCTAssertEqual(settings.accountDisplayName, "Edited name")
            XCTAssertEqual(UserDefaults.standard.string(forKey: "yd_account_display_name"), "Edited name")
            settings.applyAccountUser(user(uid, name: "Provider name"))
            settings.applyFirebaseProfile(profile(uid, name: "Old cloud name"))
            XCTAssertEqual(settings.accountDisplayName, "Edited name")

            let edits = AccountDisplayNameEdits()
            let inFlight = edits.edit(for: uid)
            edits.acknowledge(inFlight, for: uid)
            // A pull that started before this acknowledgement is now stale.
            settings.applyFirebaseProfile(profile(uid, name: "Old cloud name"),
                preservingDisplayName: inFlight != edits.edit(for: uid))
            XCTAssertEqual(settings.accountDisplayName, "Edited name")
            // A later independent pull may accept edits from another device.
            settings.applyFirebaseProfile(profile(uid, name: "Other device"))
            XCTAssertEqual(settings.accountDisplayName, "Other device")
            settings.applyAccountUser(user(uid, name: "Provider name"))
            XCTAssertEqual(settings.accountDisplayName, "Other device")
        }
    }

    func testPendingNameSurvivesSignOutAndDoesNotLeakToAnotherAccount() {
        withAccount { settings, uid in
            settings.updateAccountDisplayName("Offline name")
            settings.applyAccountUser(nil)
            settings.applyAccountUser(user("different-account", name: "Another user"))
            settings.applyFirebaseProfile(profile(uid, name: "Late old response"))
            XCTAssertEqual(settings.accountDisplayName, "Another user")
            settings.applyAccountUser(user(uid, name: "Provider name"))
            XCTAssertEqual(settings.accountDisplayName, "Offline name")
        }
    }

    func testBlankRenameDoesNotQueueAnUpload() {
        withAccount { settings, uid in
            settings.updateAccountDisplayName(" \n ")
            XCTAssertEqual(settings.accountDisplayName, "Initial")
            XCTAssertNil(AccountDisplayNameEdits().pendingName(for: uid))
        }
    }

    private func user(_ uid: String, name: String) -> AccountUser {
        AccountUser(uid: uid, email: "test@example.invalid", displayName: name,
                    photoURL: nil, providerIds: ["password"], emailVerified: true)
    }

    private func profile(_ uid: String, name: String) -> UserProfile {
        UserProfile(uid: uid, displayName: name, email: "test@example.invalid", provider: "Email")
    }

    private func withAccount(_ body: (GlobalSettings, String) -> Void) {
        let settings = GlobalSettings.shared
        let saved = (settings.accountDisplayName, settings.accountEmail, settings.accountProvider,
                     settings.accountUserIdentifier, settings.accountPhotoURL, settings.isLoggedIn,
                     settings.accountAvatarData)
        let preferences = ReaderPreferences.current()
        let uid = "nickname-test-\(UUID())"
        defer {
            settings.accountDisplayName = saved.0
            settings.accountEmail = saved.1
            settings.accountProvider = saved.2
            settings.accountUserIdentifier = saved.3
            settings.accountPhotoURL = saved.4
            settings.isLoggedIn = saved.5
            settings.accountAvatarData = saved.6
            preferences.apply()
            UserDefaults.standard.removeObject(forKey: "yd_account_display_name_edit.\(uid)")
        }
        settings.applyAccountUser(user(uid, name: "Initial"))
        body(settings, uid)
    }
}
