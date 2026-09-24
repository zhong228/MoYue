import Foundation

/// Account-scoped durable edits survive offline launches and sign-out. A server
/// acknowledgement only clears the exact edit it uploaded, never a newer name.
struct AccountDisplayNameEdits {
    struct Edit: Codable, Equatable {
        let name: String
        let revision: UUID
        var needsUpload: Bool
    }

    var defaults: UserDefaults = .standard

    func edit(for uid: String) -> Edit? {
        guard !uid.isEmpty, let data = defaults.data(forKey: key(uid)) else { return nil }
        return try? JSONDecoder().decode(Edit.self, from: data)
    }

    func save(_ name: String, for uid: String) {
        guard !uid.isEmpty else { return }
        write(Edit(name: name, revision: UUID(), needsUpload: true), for: uid)
    }

    func acknowledge(_ uploaded: Edit?, for uid: String) {
        guard var uploaded, edit(for: uid) == uploaded else { return }
        uploaded.needsUpload = false
        write(uploaded, for: uid)
    }

    func pendingName(for uid: String) -> String? {
        guard let edit = edit(for: uid), edit.needsUpload else { return nil }
        return edit.name
    }

    private func write(_ edit: Edit, for uid: String) {
        // This fixed String/UUID/Bool payload has no fallible custom encoder.
        guard let data = try? JSONEncoder().encode(edit) else { return }
        defaults.set(data, forKey: key(uid))
    }

    private func key(_ uid: String) -> String { "yd_account_display_name_edit.\(uid)" }
}
