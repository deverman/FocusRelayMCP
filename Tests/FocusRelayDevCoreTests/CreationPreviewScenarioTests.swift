import Foundation
import Testing
@testable import FocusRelayDevCore

struct CreationPreviewScenarioTests {
    @Test(arguments: CreationPreviewScenario.allCases)
    func requestsCannotApply(scenario: CreationPreviewScenario) throws {
        let data = try JSONEncoder().encode(scenario.arguments(projectID: "project", parentID: "parent", tagID: "tag"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["previewOnly"] as? Bool == true)
        let destination = try #require(object["destination"] as? [String: String])
        #expect(destination["kind"] == scenario.rawValue)
        #expect(destination["id"] == (scenario == .inbox ? nil : scenario == .project ? "project" : "parent"))
        let roots = try #require(object["tasks"] as? [[String: Any]])
        #expect(roots.count == 1)
        #expect((roots[0]["children"] as? [[String: Any]])?.count == 2)
        #expect(roots[0]["tagIDs"] as? [String] == ["tag"])
    }
}
