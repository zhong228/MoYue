import Foundation

enum ReaderProgressSyncPolicy {
    static func shouldPersistOnPageChanged(
        isCoreTextReady: Bool,
        totalPages: Int,
        isRestoringPosition: Bool
    ) -> Bool {
        isCoreTextReady && totalPages > 0 && !isRestoringPosition
    }

    static func shouldUseEnginePageDirectly(
        enginePage: Int,
        totalPages: Int,
        savedPositionSnapshot: Double,
        hasRestoreTarget: Bool
    ) -> Bool {
        // A precise restore target (from the position store) always wins during the
        // cold-restore window. Otherwise a transient non-zero engine page — set by the
        // engine's own restore on a different timeline — can race ahead and strand us
        // at the chapter start before the precise restore applies.
        if hasRestoreTarget {
            return false
        }
        if enginePage > 0 {
            return true
        }
        if totalPages <= 0 {
            return false
        }
        return savedPositionSnapshot == 0
    }
}

