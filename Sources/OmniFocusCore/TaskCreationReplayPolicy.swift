import Foundation

/// A pure admission policy, not durable storage. Callers must persist `applying`
/// before invoking any constructor. Receipts are not temporary IPC responses.
public enum TaskCreationReplayPolicy {
    public enum State: String, Codable, Sendable { case prepared, applying, completed, uncertain }
    public enum Decision: Sendable, Equatable {
        case reusePreview
        case applyApprovedPreview
        case reconcileOnly
    }

    public static func decision(for request: TaskCreationRequest, storedCreationKey: String,
                                storedFingerprint: String, storedPreviewID: String, state: State) throws -> Decision {
        try request.validate()
        guard let storedKey = UUID(uuidString: storedCreationKey)?.uuidString,
              storedKey == request.normalizedCreationKey,
              storedFingerprint == (try request.intentFingerprint()),
              let previewID = UUID(uuidString: storedPreviewID)?.uuidString else {
            throw MutationValidationError("Creation receipt does not match the requested plan; do not retry with a new key until existing state is reconciled.")
        }
        if !request.previewOnly {
            guard request.approvedPreviewID.flatMap({ UUID(uuidString: $0)?.uuidString }) == previewID else {
                throw MutationValidationError("approvedPreviewID does not match the frozen creation plan.")
            }
        }
        switch state {
        case .prepared:
            return request.previewOnly ? .reusePreview : .applyApprovedPreview
        case .applying, .completed, .uncertain:
            // Even if no IDs were recorded, the constructor may already have run.
            // Missing task IDs, changed fields or a failed save are not permission to recreate.
            return .reconcileOnly
        }
    }
}
