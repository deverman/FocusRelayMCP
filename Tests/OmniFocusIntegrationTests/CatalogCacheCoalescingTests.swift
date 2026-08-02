import Foundation
import OmniFocusCore
import Testing
@testable import OmniFocusAutomation

/// Concurrent callers arriving on a cold cache must share one fill. Without
/// coalescing each drives its own catalog fetch through the Bridge lane —
/// slowest exactly when the cache would help most.
@Suite("Catalog cache fill coalescing")
struct CatalogCacheCoalescingTests {
    private func key(_ search: String? = nil) -> CacheKey {
        CacheKey.projects(
            page: PageRequest(limit: 1000),
            fields: ["id", "name"],
            statusFilter: "active",
            includeTaskCounts: false,
            search: search,
            rootOnly: false
        )
    }

    private func page(_ id: String) -> Page<ProjectItem> {
        Page(items: [ProjectItem(id: id, name: "Project \(id)", status: "active", flagged: false)], returnedCount: 1)
    }

    @Test func concurrentCallersShareASingleFill() async throws {
        let cache = CatalogCache()
        let counter = FillCounter()
        let key = key()

        let results = try await withThrowingTaskGroup(of: Page<ProjectItem>.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await cache.projects(key: key, ttl: 300) {
                        await counter.increment()
                        // Long enough that all eight callers are waiting.
                        try await Task.sleep(nanoseconds: 120_000_000)
                        return self.page("only")
                    }
                }
            }
            var collected: [Page<ProjectItem>] = []
            for try await value in group { collected.append(value) }
            return collected
        }

        #expect(results.count == 8)
        #expect(results.allSatisfy { $0.items.first?.id == "only" })
        let fills = await counter.value
        #expect(fills == 1, "eight concurrent callers must trigger exactly one fill, saw \(fills)")
    }

    @Test func differentKeysStillFillIndependently() async throws {
        let cache = CatalogCache()
        let counter = FillCounter()

        _ = try await cache.projects(key: key("alpha"), ttl: 300) {
            await counter.increment(); return self.page("a")
        }
        _ = try await cache.projects(key: key("beta"), ttl: 300) {
            await counter.increment(); return self.page("b")
        }
        let fills = await counter.value
        #expect(fills == 2, "distinct queries must not share a fill")
    }

    @Test func warmEntryIsReusedWithoutRefilling() async throws {
        let cache = CatalogCache()
        let counter = FillCounter()
        let key = key()

        _ = try await cache.projects(key: key, ttl: 300) { await counter.increment(); return self.page("warm") }
        let second = try await cache.projects(key: key, ttl: 300) { await counter.increment(); return self.page("cold") }

        #expect(second.items.first?.id == "warm")
        let fills = await counter.value
        #expect(fills == 1)
    }

    @Test func failedFillDoesNotPoisonTheKey() async throws {
        let cache = CatalogCache()
        let key = key()

        await #expect(throws: (any Error).self) {
            _ = try await cache.projects(key: key, ttl: 300) {
                throw CacheFillTestError.failed
            }
        }

        // A later caller must be able to fill successfully.
        let recovered = try await cache.projects(key: key, ttl: 300) { self.page("recovered") }
        #expect(recovered.items.first?.id == "recovered")
    }

    @Test func invalidationDropsCachedProjects() async throws {
        let cache = CatalogCache()
        let key = key()
        _ = try await cache.projects(key: key, ttl: 300) { self.page("before") }
        await cache.invalidateProjects()
        let after = try await cache.projects(key: key, ttl: 300) { self.page("after") }
        #expect(after.items.first?.id == "after", "post-mutation invalidation must force a refill")
    }
}

private enum CacheFillTestError: Error { case failed }

private actor FillCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
