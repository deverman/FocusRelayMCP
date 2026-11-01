import Foundation

/// Preview-only inputs shared by the developer command and its safety contracts.
public enum CreationPreviewScenario: String, CaseIterable, Sendable {
    case inbox, project, parentTask = "parent_task"

    public func arguments(projectID: String, parentID: String, tagID: String?) -> BurstJSONValue {
        var destination: [String: BurstJSONValue] = ["kind": .string(rawValue)]
        if self != .inbox { destination["id"] = .string(self == .project ? projectID : parentID) }
        var root: [String: BurstJSONValue] = [
            "clientID": .string("root"), "name": .string("FocusRelay benchmark preview only"),
            "children": .array([
                .object(["clientID": .string("first"), "name": .string("First preview child")]),
                .object(["clientID": .string("second"), "name": .string("Second preview child")])
            ])
        ]
        if let tagID { root["tagIDs"] = .array([.string(tagID)]) }
        return .object(["destination": .object(destination), "previewOnly": .bool(true), "tasks": .array([.object(root)])])
    }
}
