import CloudKit
import Combine
import Foundation
import UIKit

struct ICloudSyncPayloadFile: Equatable {
    let recordName: String
    let localURL: URL
}

enum ICloudSyncPayload {
    static func defaultFiles(
        documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
        libraryDirectory: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
    ) -> [ICloudSyncPayloadFile] {
        [
            ICloudSyncPayloadFile(
                recordName: "book_sources",
                localURL: documentsDirectory.appendingPathComponent("book_sources.json")
            ),
            ICloudSyncPayloadFile(
                recordName: "books_meta",
                localURL: documentsDirectory.appendingPathComponent("books_meta.json")
            ),
            ICloudSyncPayloadFile(
                recordName: "replace_rules",
                localURL: libraryDirectory.appendingPathComponent("replace_rules.json")
            )
        ]
    }
}

enum ICloudSyncError: LocalizedError {
    case accountUnavailable(CKAccountStatus)
    case missingRemoteBackup
    case missingAsset(String)

    var errorDescription: String? {
        switch self {
        case .accountUnavailable(let status):
            switch status {
            case .available:
                return nil
            case .noAccount:
                return localized("此裝置尚未登入 iCloud")
            case .restricted:
                return localized("此裝置的 iCloud 使用受限")
            case .couldNotDetermine:
                return localized("無法確認 iCloud 狀態，請稍後再試")
            case .temporarilyUnavailable:
                return localized("iCloud 暫時無法使用，請稍後再試")
            @unknown default:
                return localized("iCloud 無法使用")
            }
        case .missingRemoteBackup:
            return localized("iCloud 尚未找到可還原的備份")
        case .missingAsset(let name):
            return String(format: localized("iCloud 備份檔案不完整：%@"), name)
        }
    }
}

struct ICloudSyncManifest {
    let deviceId: String
    let deviceName: String
    let backupDate: Date
    let appVersion: String
}

struct ICloudSyncConflict {
    let remote: ICloudSyncManifest
    let localLastSync: Date?
}

enum ICloudSignInSyncAction: Equatable {
    case backup
    case restore
    case waitForUserChoice
}

final class ICloudSyncManager: ObservableObject {
    static let shared = ICloudSyncManager()
    static let containerIdentifier = "iCloud.com.zhangruilin.yuedureader"

    @Published private(set) var isSyncing = false
    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published var lastSyncDate: Date? {
        didSet {
            if let lastSyncDate {
                UserDefaults.standard.set(lastSyncDate, forKey: Self.lastSyncKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastSyncKey)
            }
        }
    }
    @Published var statusMessage = ""
    @Published var pendingConflict: ICloudSyncConflict?

    private static let lastSyncKey = "icloud_last_sync"
    private static let deviceIdKey = "icloud_sync_device_id"
    private static let manifestRecordName = "sync_manifest"
    private static let manifestRecordType = "YueduSyncManifest"
    private static let fileRecordType = "YueduSyncFile"

    private enum Field {
        static let asset = "asset"
        static let appVersion = "appVersion"
        static let backupDate = "backupDate"
        static let deviceId = "deviceId"
        static let deviceName = "deviceName"
        static let filename = "filename"
        static let name = "name"
        static let updatedAt = "updatedAt"
    }

    private let container: CKContainer
    private let database: CKDatabase

    private static var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: deviceIdKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceIdKey)
        return id
    }

    private init(container: CKContainer = CKContainer(identifier: ICloudSyncManager.containerIdentifier)) {
        self.container = container
        database = container.privateCloudDatabase
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    static func signInAction(
        remoteManifest: ICloudSyncManifest?,
        hasLocalData: Bool,
        currentDeviceId: String
    ) -> ICloudSignInSyncAction {
        guard let remoteManifest else { return .backup }
        guard remoteManifest.deviceId != currentDeviceId else { return .backup }
        return hasLocalData ? .waitForUserChoice : .restore
    }

    func refreshAccountStatus() async -> CKAccountStatus {
        let status = await fetchAccountStatus()
        await MainActor.run {
            accountStatus = status
        }
        return status
    }

    func syncAfterSignIn() {
        Task {
            do {
                try await performSignInSync()
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    func backup() async throws {
        try await ensureAccountAvailable()
        await setSync(true, message: localized("iCloud 備份中…"))
        defer { Task { @MainActor in self.isSyncing = false } }

        let files = ICloudSyncPayload.defaultFiles()
        for file in files {
            try await uploadFileIfExists(file)
        }

        let date = Date()
        let manifest = await makeManifest(date: date)
        try await saveManifest(manifest)

        await MainActor.run {
            lastSyncDate = date
            statusMessage = localized("iCloud 備份成功")
        }
    }

    func restore() async throws {
        try await performRestore(skipConflictCheck: false)
    }

    func resolveConflict(keepRemote: Bool) async throws {
        await MainActor.run { pendingConflict = nil }
        if keepRemote {
            try await performRestore(skipConflictCheck: true)
        } else {
            try await backup()
        }
    }

    func statusTitle(isAppSignedIn: Bool) -> String {
        guard isAppSignedIn else { return localized("尚未開啟同步") }
        switch accountStatus {
        case .available:
            return localized("iCloud 同步已開啟")
        case .noAccount:
            return localized("請先登入 iCloud")
        case .restricted:
            return localized("iCloud 受限")
        case .couldNotDetermine:
            return localized("iCloud 狀態待確認")
        case .temporarilyUnavailable:
            return localized("iCloud 暫時無法使用")
        @unknown default:
            return localized("iCloud 狀態待確認")
        }
    }

    private func performSignInSync() async throws {
        try await ensureAccountAvailable()
        let files = ICloudSyncPayload.defaultFiles()
        let remoteManifest = try await fetchManifestIfExists()
        switch Self.signInAction(
            remoteManifest: remoteManifest,
            hasLocalData: hasLocalSyncableData(files: files),
            currentDeviceId: Self.deviceId
        ) {
        case .restore:
            try await performRestore(skipConflictCheck: true)
        case .backup:
            try await backup()
        case .waitForUserChoice:
            guard let remoteManifest else { return }
            await MainActor.run {
                pendingConflict = ICloudSyncConflict(remote: remoteManifest, localLastSync: lastSyncDate)
                statusMessage = localized("偵測到衝突，請選擇要使用哪個版本")
            }
        }
    }

    private func performRestore(skipConflictCheck: Bool) async throws {
        try await ensureAccountAvailable()
        await setSync(true, message: localized("iCloud 還原中…"))
        defer { Task { @MainActor in self.isSyncing = false } }

        guard let remoteManifest = try await fetchManifestIfExists() else {
            throw ICloudSyncError.missingRemoteBackup
        }

        if !skipConflictCheck,
           remoteManifest.deviceId != Self.deviceId,
           hasLocalSyncableData(files: ICloudSyncPayload.defaultFiles())
        {
            let localSync = await MainActor.run { lastSyncDate }
            await MainActor.run {
                pendingConflict = ICloudSyncConflict(remote: remoteManifest, localLastSync: localSync)
                statusMessage = localized("偵測到衝突，請選擇要使用哪個版本")
            }
            return
        }

        for file in ICloudSyncPayload.defaultFiles() {
            try await downloadFileIfExists(file)
        }

        await MainActor.run {
            lastSyncDate = Date()
            statusMessage = localized("iCloud 還原成功，書庫和替換規則需重啟 App 後完全生效")
        }
    }

    private func ensureAccountAvailable() async throws {
        let status = await refreshAccountStatus()
        guard status == .available else {
            throw ICloudSyncError.accountUnavailable(status)
        }
    }

    private func fetchAccountStatus() async -> CKAccountStatus {
        await withCheckedContinuation { continuation in
            container.accountStatus { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    private func uploadFileIfExists(_ file: ICloudSyncPayloadFile) async throws {
        guard FileManager.default.fileExists(atPath: file.localURL.path) else { return }

        let data = try Data(contentsOf: file.localURL)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuedu-icloud-\(file.recordName)-\(UUID().uuidString)")
            .appendingPathExtension("json")
        try data.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let recordID = fileRecordID(file.recordName)
        let record = (try? await fetchRecord(recordID)) ?? CKRecord(
            recordType: Self.fileRecordType,
            recordID: recordID
        )
        record[Field.name] = file.recordName as NSString
        record[Field.filename] = file.localURL.lastPathComponent as NSString
        record[Field.updatedAt] = Date() as NSDate
        record[Field.asset] = CKAsset(fileURL: tempURL)
        try await saveRecord(record)
    }

    private func downloadFileIfExists(_ file: ICloudSyncPayloadFile) async throws {
        let record: CKRecord
        do {
            record = try await fetchRecord(fileRecordID(file.recordName))
        } catch {
            if isRecordNotFound(error) { return }
            throw error
        }

        guard let asset = record[Field.asset] as? CKAsset,
              let assetURL = asset.fileURL else {
            throw ICloudSyncError.missingAsset(file.recordName)
        }

        let data = try Data(contentsOf: assetURL)
        try FileManager.default.createDirectory(
            at: file.localURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: file.localURL, options: .atomic)

        if file.recordName == "book_sources",
           let decoded = try? JSONDecoder().decode([BookSource].self, from: data)
        {
            await MainActor.run {
                BookSourceStore.shared.sources = decoded
            }
        }

        if file.recordName == "books_meta" {
            UserDefaults.standard.removeObject(forKey: "yd_books_meta")
        }
    }

    private func saveManifest(_ manifest: ICloudSyncManifest) async throws {
        let recordID = CKRecord.ID(recordName: Self.manifestRecordName)
        let record = (try? await fetchRecord(recordID)) ?? CKRecord(
            recordType: Self.manifestRecordType,
            recordID: recordID
        )
        record[Field.deviceId] = manifest.deviceId as NSString
        record[Field.deviceName] = manifest.deviceName as NSString
        record[Field.backupDate] = manifest.backupDate as NSDate
        record[Field.appVersion] = manifest.appVersion as NSString
        try await saveRecord(record)
    }

    private func fetchManifestIfExists() async throws -> ICloudSyncManifest? {
        do {
            let record = try await fetchRecord(CKRecord.ID(recordName: Self.manifestRecordName))
            return manifest(from: record)
        } catch {
            if isRecordNotFound(error) { return nil }
            throw error
        }
    }

    private func manifest(from record: CKRecord) -> ICloudSyncManifest? {
        guard let deviceId = record[Field.deviceId] as? String,
              let deviceName = record[Field.deviceName] as? String,
              let backupDate = record[Field.backupDate] as? Date
        else {
            return nil
        }
        let appVersion = record[Field.appVersion] as? String ?? ""
        return ICloudSyncManifest(
            deviceId: deviceId,
            deviceName: deviceName,
            backupDate: backupDate,
            appVersion: appVersion
        )
    }

    private func fetchRecord(_ recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let record {
                    continuation.resume(returning: record)
                } else {
                    continuation.resume(throwing: CKError(.unknownItem))
                }
            }
        }
    }

    private func saveRecord(_ record: CKRecord) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.save(record) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func fileRecordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "sync_file_\(name)")
    }

    private func isRecordNotFound(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        return ckError.code == .unknownItem || ckError.code == .zoneNotFound
    }

    private func hasLocalSyncableData(files: [ICloudSyncPayloadFile]) -> Bool {
        files.contains { file in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.localURL.path),
                  let size = attributes[.size] as? NSNumber else {
                return false
            }
            return size.intValue > 2
        }
    }

    private func makeManifest(date: Date) async -> ICloudSyncManifest {
        let deviceName = await MainActor.run { UIDevice.current.name }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return ICloudSyncManifest(
            deviceId: Self.deviceId,
            deviceName: deviceName,
            backupDate: date,
            appVersion: appVersion
        )
    }

    @MainActor
    private func setSync(_ syncing: Bool, message: String) {
        isSyncing = syncing
        statusMessage = message
    }
}
