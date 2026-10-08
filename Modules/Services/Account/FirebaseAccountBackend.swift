import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

/// Existing direct-to-Firebase implementation. This is the pre-Gateway code
/// path, moved behind `AccountBackend` unchanged so overseas behaviour is
/// preserved.
@MainActor
final class FirebaseAccountBackend: AccountBackend {
    private let functionsRegion = "asia-east1"

    /// Firestore / Storage / Functions have no default app on placeholder-plist
    /// CI builds, so constructing them eagerly would crash the app at
    /// `AccountBackendRouter.shared` first touch (which happens during
    /// `SubscriptionStore` launch work). Every access is guarded; without a
    /// configured Firebase app these become no-ops / "not authenticated"
    /// instead of throwing inside the SDK.
    private let db: Firestore? = FirebaseAvailability.isConfigured ? Firestore.firestore() : nil
    private let storage: Storage? = FirebaseAvailability.isConfigured ? Storage.storage() : nil

    /// Collections whose local shadow must be cleared when the account changes.
    static let shadowCollections = [
        "books", "bookSources", "replaceRules", "rssSources", "rssFolders", "rssArticleStatuses"
    ]

    func fetchProfile(uid: String) async throws -> UserProfile? {
        guard let userRef = userDocument(uid) else { return nil }
        let snapshot = try await userRef.getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: UserProfile.self)
    }

    func upsertProfile(_ profile: UserProfile) async throws {
        guard let userRef = userDocument(profile.uid) else { return }
        let data = try Firestore.Encoder().encode(profile)
        // Await the server acknowledgement; enqueueing a local Firestore write
        // is not confirmation that a pending nickname has reached the server.
        try await userRef.setData(data, merge: true)
    }

    func uploadAvatar(data: Data) async throws -> URL {
        guard let uid = FirebaseAuthManager.shared.uid else {
            throw AccountBackendError.notAuthenticated
        }
        guard let storage else { throw AccountBackendError.notAuthenticated }
        let ref = storage.reference(withPath: "avatars/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        if let userRef = userDocument(uid) {
            try await userRef.setData([
                "photoURL": url.absoluteString,
                "updatedAt": Timestamp(date: Date())
            ], merge: true)
        }
        return url
    }

    func refreshEntitlement(uid: String) async throws -> CachedSubscriptionEntitlement? {
        // Without a resolved environment there is no correct field to read:
        // defaulting to `isProActive` would hand the App Store entitlement to a
        // TestFlight build. Nothing to say beats saying the wrong thing.
        guard SubscriptionRuntimeEnvironment.isResolved else { return nil }
        guard let db else { return nil }
        // `.server`, not the default source: the default attempts the server
        // and silently falls back to Firestore's own offline cache, so an
        // unreachable backend answered with a stale pre-purchase document whose
        // `false` would overwrite the verified keychain value.
        let snapshot = try await db.collection("entitlements").document(uid)
            .getDocument(source: .server)
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        let fields = SubscriptionRuntimeEnvironment.entitlementFieldNames
        return CachedSubscriptionEntitlement(
            isProActive: data[fields.isActive] as? Bool == true,
            expiresAt: (data[fields.expiresAt] as? Timestamp)?.dateValue(),
            productIDs: data[fields.productIDs] as? [String]
        )
    }

    func accountToken() async throws -> UUID {
        try requireFirebaseFunctions()
        let result = try await Functions.functions(region: functionsRegion)
            .httpsCallable("getSubscriptionAccountToken")
            .call()
        guard let payload = result.data as? [String: Any],
              let rawToken = payload["token"] as? String,
              let token = UUID(uuidString: rawToken) else {
            throw SubscriptionAccountError.invalidServerResponse
        }
        return token
    }

    func bind(signedTransaction: String) async throws -> CachedSubscriptionEntitlement {
        try requireFirebaseFunctions()
        let result = try await Functions.functions(region: functionsRegion)
            .httpsCallable("bindSubscriptionPurchase")
            .call(["signedTransaction": signedTransaction])
        return try Self.entitlement(from: result.data)
    }

    func deleteSubscriptionAccountData() async throws {
        try requireFirebaseFunctions()
        _ = try await Functions.functions(region: functionsRegion)
            .httpsCallable("deleteSubscriptionAccountData")
            .call()
    }

    func verifyTestFlightAccess() async throws -> Bool {
        try requireFirebaseFunctions()
        let result = try await Functions.functions(region: functionsRegion)
            .httpsCallable("verifyTestFlightAccess").call()
        guard let data = result.data as? [String: Any], let allowed = data["allowed"] as? Bool else {
            throw AccountBackendError.invalidResponse
        }
        return allowed
    }

    func requestTestFlightAccess(email: String) async throws -> TestFlightAccessResult {
        try requireFirebaseFunctions()
        let result = try await Functions.functions(region: functionsRegion)
            .httpsCallable("requestTestFlightAccess")
            .call(["email": email])
        guard let payload = result.data as? [String: Any],
              let alreadySubmitted = payload["alreadySubmitted"] as? Bool,
              let status = payload["status"] as? String else {
            throw TestFlightAccessServiceError.invalidResponse
        }
        return TestFlightAccessResult(alreadySubmitted: alreadySubmitted, status: status)
    }

    func deleteRemoteData(uid: String) async throws {
        guard let userRef = userDocument(uid) else { return }
        for collection in Self.shadowCollections + ["readingPositions"] {
            try await deleteCollection(userRef.collection(collection))
        }
        try? await storage?.reference(withPath: "avatars/\(uid).jpg").delete()
        try await userRef.delete()
    }

    static func entitlement(from value: Any) throws -> CachedSubscriptionEntitlement {
        guard let payload = value as? [String: Any],
              let isProActive = payload["isProActive"] as? Bool else {
            throw SubscriptionAccountError.invalidServerResponse
        }
        let expiresAt: Date?
        if let milliseconds = payload["expiresAtMilliseconds"] as? NSNumber {
            expiresAt = Date(timeIntervalSince1970: milliseconds.doubleValue / 1_000)
        } else {
            expiresAt = nil
        }
        return CachedSubscriptionEntitlement(
            isProActive: isProActive,
            expiresAt: expiresAt,
            productIDs: payload["productIds"] as? [String]
        )
    }

    private func deleteCollection(_ collection: CollectionReference) async throws {
        guard let db else { return }
        let snapshot = try await collection.getDocuments()
        guard !snapshot.documents.isEmpty else { return }
        let batch = db.batch()
        snapshot.documents.forEach { batch.deleteDocument($0.reference) }
        try await batch.commit()
    }

    private func userDocument(_ uid: String) -> DocumentReference? {
        db?.collection("users").document(uid)
    }

    /// Cloud Functions has the same "no default app" crash as Firestore /
    /// Storage on placeholder-plist builds. Account calls only happen while
    /// something is acting as signed in; without Firebase there is no account
    /// backend at all, so the caller-facing Contract is "not authenticated".
    private func requireFirebaseFunctions() throws {
        guard FirebaseAvailability.isConfigured else {
            throw AccountBackendError.notAuthenticated
        }
    }
}
