import Foundation
import JavaScriptCore
import Testing

@Test(arguments: ["batch", "perItem"])
func missingTargetPreflightRejectsEntireMutationBeforeApplyOrSave(saveMode: String) throws {
    let results = try evaluateMutationExecutor(
        body: """
        const target = { value: 0 };
        let applyCount = 0;
        let saveCount = 0;
        globalThis.save = () => { saveCount += 1; };
        const output = executeTargetMutation(
          ["task-1", "missing"],
          { "task-1": target },
          mutation,
          {
            saveMode: "\(saveMode)",
            apply: item => {
              applyCount += 1;
              item.value = 1;
              return {};
            },
            verify: item => item.value === 1 ? null : "value mismatch",
            returnedFields: item => ({ value: item.value }),
            mutatedMessage: () => "Updated."
          }
        );
        output.forEach(result => {
          result.applyCount = applyCount;
          result.saveCount = saveCount;
          result.targetValue = target.value;
        });
        return output;
        """
    )

    #expect(results.count == 2)
    #expect(results.allSatisfy { $0["status"] as? String == "failed" })
    #expect(results.allSatisfy { $0["applyCount"] as? Int == 0 })
    #expect(results.allSatisfy { $0["saveCount"] as? Int == 0 })
    #expect(results.allSatisfy { $0["targetValue"] as? Int == 0 })
    #expect((results[0]["message"] as? String)?.contains("No targets were changed") == true)
    #expect((results[1]["message"] as? String)?.contains("missing") == true)
}

@Test
func perItemSaveFailureIsReportedAsFailure() throws {
    let results = try evaluateMutationExecutor(
        body: """
        const target = { value: 0 };
        globalThis.save = () => { throw new Error("simulated save failure"); };
        return executeTargetMutation(["task-1"], { "task-1": target }, mutation, {
          saveMode: "perItem",
          apply: item => { item.value = 1; return {}; },
          verify: item => item.value === 1 ? null : "value mismatch",
          returnedFields: item => ({ value: item.value }),
          mutatedMessage: () => "Updated."
        });
        """
    )

    #expect(results.count == 1)
    #expect(results[0]["status"] as? String == "failed")
    #expect((results[0]["message"] as? String)?.contains("save") == true)
}

@Test
func batchSaveFailureFailsEveryAppliedTarget() throws {
    let results = try evaluateMutationExecutor(
        body: """
        const targets = { "task-1": { value: 0 }, "task-2": { value: 0 } };
        globalThis.save = () => { throw new Error("simulated batch save failure"); };
        return executeTargetMutation(["task-1", "task-2"], targets, mutation, {
          saveMode: "batch",
          apply: item => { item.value = 1; return {}; },
          verify: item => item.value === 1 ? null : "value mismatch",
          returnedFields: item => ({ value: item.value }),
          mutatedMessage: () => "Updated."
        });
        """
    )

    #expect(results.count == 2)
    #expect(results.allSatisfy { $0["status"] as? String == "failed" })
    #expect(results.allSatisfy { ($0["message"] as? String)?.contains("save") == true })
}

@Test
func applyFailureDoesNotEraseEarlierPerItemSuccess() throws {
    let results = try evaluateMutationExecutor(
        body: """
        const targets = { "task-1": { value: 0 }, "task-2": { value: 0 } };
        globalThis.save = () => {};
        return executeTargetMutation(["task-1", "task-2"], targets, mutation, {
          saveMode: "perItem",
          apply: (item, id) => {
            if (id === "task-2") { throw new Error("simulated apply failure"); }
            item.value = 1;
            return {};
          },
          verify: item => item.value === 1 ? null : "value mismatch",
          returnedFields: item => ({ value: item.value }),
          mutatedMessage: () => "Updated."
        });
        """
    )

    #expect(results.count == 2)
    #expect(results[0]["status"] as? String == "mutated")
    #expect(results[1]["status"] as? String == "failed")
    #expect((results[1]["message"] as? String)?.contains("apply") == true)
}

@Test
func verificationExceptionIsReportedAfterSave() throws {
    let results = try evaluateMutationExecutor(
        body: """
        const target = { value: 0 };
        globalThis.save = () => {};
        return executeTargetMutation(["task-1"], { "task-1": target }, mutation, {
          saveMode: "perItem",
          apply: item => { item.value = 1; return {}; },
          verify: () => { throw new Error("simulated verify failure"); },
          returnedFields: item => ({ value: item.value }),
          mutatedMessage: () => "Updated."
        });
        """
    )

    #expect(results.count == 1)
    #expect(results[0]["status"] as? String == "failed")
    #expect((results[0]["message"] as? String)?.contains("verification") == true)
}

@Test
func returnedFieldsFailurePreservesSavedMutationStatus() throws {
    let results = try evaluateMutationExecutor(
        body: """
        const target = { value: 0 };
        globalThis.save = () => {};
        return executeTargetMutation(["task-1"], { "task-1": target }, mutation, {
          saveMode: "perItem",
          apply: item => { item.value = 1; return {}; },
          verify: item => item.value === 1 ? null : "value mismatch",
          returnedFields: () => { throw new Error("simulated return-field failure"); },
          mutatedMessage: () => "Updated."
        });
        """
    )

    #expect(results.count == 1)
    #expect(results[0]["status"] as? String == "mutated")
    #expect((results[0]["message"] as? String)?.contains("return requested fields") == true)
    #expect(results[0]["returnedFields"] == nil)
}

@Test
func successMessageFailurePreservesSavedMutationStatus() throws {
    let results = try evaluateMutationExecutor(
        body: """
        const target = { value: 0 };
        globalThis.save = () => {};
        return executeTargetMutation(["task-1"], { "task-1": target }, mutation, {
          saveMode: "batch",
          apply: item => { item.value = 1; return {}; },
          verify: item => item.value === 1 ? null : "value mismatch",
          returnedFields: item => ({ value: item.value }),
          mutatedMessage: () => { throw new Error("simulated message failure"); }
        });
        """
    )

    #expect(results.count == 1)
    #expect(results[0]["status"] as? String == "mutated")
    #expect((results[0]["message"] as? String)?.contains("format success message") == true)
    #expect((results[0]["returnedFields"] as? [String: Any])?["value"] as? Int == 1)
}

@Test
func alreadySatisfiedMutationSkipsApplyAndSave() throws {
    let results = try evaluateMutationExecutor(
        body: """
        const target = { value: "dropped" };
        let saveCount = 0;
        globalThis.save = () => { saveCount += 1; };
        const output = executeTargetMutation(["task-1"], { "task-1": target }, mutation, {
          saveMode: "batch",
          isNoOp: item => item.value === "dropped",
          unchangedMessage: () => "Already dropped.",
          apply: item => { item.value = "dropped"; return {}; },
          verify: () => null,
          returnedFields: item => ({ value: item.value }),
          mutatedMessage: () => "Dropped."
        });
        output[0].saveCount = saveCount;
        return output;
        """
    )

    #expect(results[0]["status"] as? String == "unchanged")
    #expect(results[0]["saveCount"] as? Int == 0)
    #expect((results[0]["returnedFields"] as? [String: Any])?["value"] as? String == "dropped")
}

@Test
func taskStatusPreflightRejectsEntireMixedBatch() throws {
    let source = try String(contentsOf: bridgeLibraryURL, encoding: .utf8)
    let preflight = try extractJavaScriptFunction(named: "preflightTaskStatusMutation", from: source)
    let context = try #require(JSContext())
    let script = """
    const safe = fn => { try { return fn(); } catch (_) { return null; } };
    const isCompletedStatus = task => task.status === "completed";
    \(preflight)
    preflightTaskStatusMutation(
      ["eligible", "completed", "missing"],
      {
        eligible: { status: "active", repetitionRule: null },
        completed: { status: "completed", repetitionRule: null }
      },
      { status: "dropped" }
    );
    """

    let message = context.evaluateScript(script)?.toString()
    #expect(message?.contains("completed: completed tasks must first be reopened") == true)
    #expect(message?.contains("missing: target ID not found") == true)
    #expect(message?.contains("No tasks were changed") == true)
}

@Test
func reviewedNowPreflightRejectsIneligibleAndMissingProjectsTogether() throws {
    let source = try String(contentsOf: bridgeLibraryURL, encoding: .utf8)
    let preflight = try extractJavaScriptFunction(named: "preflightReviewedNow", from: source)
    let context = try #require(JSContext())
    let script = """
    const projectStatusString = project => project.status;
    const reviewIntervalSnapshot = project => project.reviewInterval || null;
    \(preflight)
    preflightReviewedNow(
      ["active", "done", "missing", "no-interval"],
      {
        active: { status: "active", reviewInterval: { steps: 1, unit: "weeks" } },
        done: { status: "done", reviewInterval: { steps: 1, unit: "weeks" } },
        "no-interval": { status: "onHold", reviewInterval: null }
      }
    );
    """

    let message = context.evaluateScript(script)?.toString()
    #expect(message?.contains("done: project status done is not eligible") == true)
    #expect(message?.contains("missing: target ID not found") == true)
    #expect(message?.contains("no-interval: project has no usable review interval") == true)
    #expect(message?.contains("No projects were changed") == true)
}

@Test
func reviewedNowUsesOneTimestampAndPreservesIntervals() throws {
    let source = try String(contentsOf: bridgeLibraryURL, encoding: .utf8)
    let intervalSnapshot = try extractJavaScriptFunction(named: "reviewIntervalSnapshot", from: source)
    let apply = try extractJavaScriptFunction(named: "applyReviewedNow", from: source)
    let verify = try extractJavaScriptFunction(named: "verifyReviewedNow", from: source)
    let context = try #require(JSContext())
    let script = """
    const safe = fn => { try { return fn(); } catch (_) { return null; } };
    \(intervalSnapshot)
    \(apply)
    \(verify)
    const reviewedAt = new Date("2026-07-23T01:02:03.456Z");
    const first = { reviewInterval: { steps: 1, unit: "weeks" }, lastReviewDate: null, nextReviewDate: null };
    const second = { reviewInterval: { steps: 2, unit: "months" }, lastReviewDate: null, nextReviewDate: null };
    const firstContext = applyReviewedNow(first, reviewedAt);
    const secondContext = applyReviewedNow(second, reviewedAt);
    first.nextReviewDate = new Date("2026-07-30T01:02:03.456Z");
    second.nextReviewDate = new Date("2026-09-23T01:02:03.456Z");
    JSON.stringify({
      sameTimestamp: first.lastReviewDate.getTime() === second.lastReviewDate.getTime(),
      firstVerified: verifyReviewedNow(first, firstContext),
      secondVerified: verifyReviewedNow(second, secondContext),
      firstInterval: first.reviewInterval,
      secondInterval: second.reviewInterval
    });
    """

    let json = try #require(context.evaluateScript(script)?.toString())
    let result = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(result["sameTimestamp"] as? Bool == true)
    #expect(result["firstVerified"] is NSNull)
    #expect(result["secondVerified"] is NSNull)
    #expect((result["firstInterval"] as? [String: Any])?["steps"] as? Int == 1)
    #expect((result["secondInterval"] as? [String: Any])?["steps"] as? Int == 2)
}

private func evaluateMutationExecutor(body: String) throws -> [[String: Any]] {
    let source = try String(contentsOf: bridgeLibraryURL, encoding: .utf8)
    let safe = try extractJavaScriptFunction(named: "safe", from: source)
    let executor = try extractJavaScriptFunction(named: "executeTargetMutation", from: source)
    let context = try #require(JSContext())
    let script = """
    \(safe)
    \(executor)
    const mutation = { previewOnly: false, verify: true };
    JSON.stringify((() => {
      \(body)
    })());
    """

    let value = context.evaluateScript(script)
    if let exception = context.exception {
        Issue.record("JavaScript exception: \(exception)")
    }
    let json = try #require(value?.toString())
    let data = Data(json.utf8)
    return try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
}

private func extractJavaScriptFunction(named name: String, from source: String) throws -> String {
    let marker = "function \(name)"
    let start = try #require(source.range(of: marker)?.lowerBound)
    let openingBrace = try #require(source[start...].firstIndex(of: "{"))
    var depth = 0
    var cursor = openingBrace

    while cursor < source.endIndex {
        switch source[cursor] {
        case "{": depth += 1
        case "}":
            depth -= 1
            if depth == 0 {
                return String(source[start...cursor])
            }
        default: break
        }
        cursor = source.index(after: cursor)
    }

    Issue.record("Could not find the end of JavaScript function \(name)")
    return ""
}

private var bridgeLibraryURL: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")
}
