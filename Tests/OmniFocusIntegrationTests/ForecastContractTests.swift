import Foundation
import JavaScriptCore
import Testing
@testable import OmniFocusAutomation
import OmniFocusCore

@Suite("Partial Forecast contract")
struct ForecastContractTests {
    @Test(.enabled(if: LiveTestEnvironment.bridgeEnabled,
                   "Set FOCUS_RELAY_BRIDGE_TESTS=1 to run against the installed bridge."))
    func forecastListCountAndWarningsLive() throws {
        let client = BridgeClient()
        for inboxOnly in [false, true] {
            let filter = TaskFilter(inboxOnly: inboxOnly, includeTotalCount: true, forecast: .pastAndToday)
            let counts = try client.getTaskCounts(filter: filter)
            let page = try client.listTasks(filter: filter, page: PageRequest(limit: 15), fields: ["id"])
            #expect(page.totalCount == counts.total)
            #expect(Set(page.items.map(\.id)).count == page.items.count)
            #expect(counts.completed == 0)
            #expect(counts.warnings?.contains(where: { $0.contains("not the native Forecast total") }) == true)
            #expect(page.warnings?.contains(where: { $0.contains("calendar events") }) == true)
        }
    }

    @Test func localCalendarDaysIncludeDSTAndNonUTCOffsets() throws {
        let formatter = ISO8601DateFormatter()
        let now = try #require(formatter.date(from: "2026-10-03T16:30:00Z"))
        let utc = ForecastWindow(now: now, timeZone: try #require(TimeZone(identifier: "UTC")))
        let local = ForecastWindow(now: now, timeZone: try #require(TimeZone(identifier: "Asia/Makassar")))
        #expect(utc.startMilliseconds != local.startMilliseconds)
        let expectedStart = try #require(formatter.date(from: "2026-10-03T16:00:00Z"))
        #expect(local.startMilliseconds == expectedStart.timeIntervalSince1970 * 1000)
        for (date, hours) in [("2026-03-08T12:00:00Z", 23.0), ("2026-11-01T12:00:00Z", 25.0)] {
            let day = ForecastWindow(now: try #require(formatter.date(from: date)),
                                     timeZone: try #require(TimeZone(identifier: "America/New_York")))
            #expect(day.endMilliseconds - day.startMilliseconds == hours * 3_600_000)
        }
    }

    @Test func cursorCannotCrossForecastScope() throws {
        let ordinary = try QueryBoundCursor.taskIdentity(for: TaskFilter())
        let forecast = try QueryBoundCursor.taskIdentity(for: TaskFilter(forecast: .pastAndToday))
        #expect(ordinary.fingerprint != forecast.fingerprint)
    }

    @Test func actualBridgeListAndCountRespectUnionScopeAndIntersections() throws {
        let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let context = try #require(JSContext())
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        let setup = """
        const files = {};
        const URL = {fromString: x => x};
        const Data = {fromString: x => x};
        const FileWrapper = {
          Type: {Directory: 'dir'}, WritingOptions: {Atomic: 'atomic'},
          fromURL: path => {
            if (!(path in files)) throw Error('absent');
            return {type: 'dir', contents: {toString: () => files[path]}, remove: () => {delete files[path];}};
          },
          withContents: (_, data) => ({write: path => { files[path] = data; }}),
          withChildren: () => ({write: path => {files[path] = '';}})
        };
        const PlugIn = {Library: function() {}};
        const Version = function() {};
        const Task = {Status: {Available:'Available',Next:'Next',DueSoon:'DueSoon',Overdue:'Overdue',Blocked:'Blocked',Completed:'Completed',Dropped:'Dropped'}};
        const Project = {Status: {Active:'Active',OnHold:'OnHold',Done:'Done',Dropped:'Dropped'}};
        const chosen = {id:{primaryKey:'chosen'}, name:'Today'};
        const Tag = {forecastTag: chosen};
        const flattenedProjects = [];
        function task(id, extra) {
          return Object.assign({id:{primaryKey:id},name:id,taskStatus:'Available',tags:[],parent:null,containingProject:null}, extra || {});
        }
        const start = Date.parse('2026-10-03T16:00:00Z');
        const end = Date.parse('2026-10-04T16:00:00Z');
        const due = task('due-blocked', {taskStatus:'Blocked',dueDate:new Date(start-1)});
        const planned = task('planned', {plannedDate:new Date(end-1)});
        const deferred = task('deferred', {taskStatus:'Blocked',deferDate:new Date(start)});
        const flagged = task('flagged', {effectiveFlagged:true});
        const tagged = task('tagged', {tags:[chosen]});
        const multi = task('multi', {dueDate:new Date(start),effectiveFlagged:true,tags:[chosen]});
        const no = task('no');
        const tomorrow = task('tomorrow', {taskStatus:'DueSoon',dueDate:new Date(end)});
        const oldDefer = task('old-defer', {deferDate:new Date(start-1)});
        const done = task('done', {taskStatus:'Completed',effectiveFlagged:true});
        const child = task('hidden-child', {parent:done,effectiveFlagged:true});
        const dropped = task('dropped', {taskStatus:'Dropped',effectiveFlagged:true});
        const droppedChild = task('dropped-child', {parent:dropped,effectiveFlagged:true});
        const project = {id:{primaryKey:'project'},name:'Project',status:'Active'};
        const root = task('project', {containingProject:project,tags:[chosen],effectiveFlagged:true});
        project.task = root; project.flattenedTasks = [root,tagged,multi]; flattenedProjects.push(project);
        tagged.containingProject = project; multi.containingProject = project;
        const flattenedTasks = [due,planned,deferred,flagged,tagged,multi,multi,no,tomorrow,oldDefer,done,child,dropped,droppedChild,root];
        const inbox = [due,no]; inbox.apply = fn => inbox.forEach(fn);
        Task.byIdentifier = id => flattenedTasks.find(t=>t.id.primaryKey===id);
        """
        context.evaluateScript(setup)
        let library = try #require(context.evaluateScript(source))
        context.setObject(library, forKeyedSubscript: "library" as NSString)
        let result = context.evaluateScript("""
        let requestIndex = 0;
        function run(op, extra, page, window = {startMilliseconds:start,endMilliseconds:end}) {
          const requestID = 'probe-' + (++requestIndex);
          files['file:///fixture/requests/' + requestID + '.json'] = JSON.stringify({op:op,
            filter:Object.assign({forecast:'past-and-today',includeTotalCount:true}, extra || {}),
            forecastWindow:window,
            fields:['id'],page:page || {limit:50}});
          library.handleRequest(requestID,'/fixture');
          return JSON.parse(files['file:///fixture/responses/' + requestID + '.json']);
        }
        const responses = {list:run('list_tasks'),count:run('get_task_counts'),
          inbox:run('list_tasks',{inboxOnly:true}),inboxCount:run('get_task_counts',{inboxOnly:true}),
          available:run('list_tasks',{availableOnly:true}),availableCount:run('get_task_counts',{availableOnly:true}),
          first:run('list_tasks',{}, {limit:2}),second:run('list_tasks',{}, {limit:2,cursor:'2'}),
          project:run('list_tasks',{project:'project'}),projectCount:run('get_task_counts',{project:'project'}),
          tags:run('list_tasks',{tags:['chosen']}),tagsCount:run('get_task_counts',{tags:['chosen']}),
          selected:run('list_tasks',{ids:['multi','no']}),
          missingWindow:run('list_tasks',{},null,null),
          reversedWindow:run('get_task_counts',{},null,{startMilliseconds:end,endMilliseconds:start}),
          ordinary:run('list_tasks',{forecast:null}),completed:run('list_tasks',{completed:true})};
        Tag.forecastTag = null;
        responses.noTag = run('get_task_counts');
        JSON.stringify(responses);
        """)?.toString()
        #expect(exception == nil, "\(exception ?? "")")
        let json = try #require(result)
        let data = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [String: Any]])
        func payload(_ key: String) throws -> [String: Any] {
            let response = try #require(data[key])
            #expect(response["ok"] as? Bool == true, "\(response)")
            return try #require(response["data"] as? [String: Any])
        }
        func ids(_ key: String) throws -> [String] {
            try #require(try payload(key)["items"] as? [[String: Any]]).compactMap { $0["id"] as? String }
        }
        #expect(try ids("list") == ["due-blocked","planned","deferred","flagged","tagged","multi"])
        #expect(try payload("count")["total"] as? Int == 6)
        #expect(try payload("list")["totalCount"] as? Int == 6)
        #expect(try ids("inbox") == ["due-blocked"])
        #expect(try payload("inboxCount")["total"] as? Int == 1)
        #expect(try ids("available") == ["planned","flagged","tagged","multi"])
        #expect(try payload("availableCount")["total"] as? Int == 4)
        #expect(try ids("first") + ids("second") == ["due-blocked","planned","deferred","flagged"])
        #expect(try ids("completed").isEmpty)
        #expect(try ids("ordinary").contains("no"))
        #expect(try ids("project") == ["tagged", "multi"])
        #expect(try payload("projectCount")["total"] as? Int == 2)
        #expect(try ids("tags") == ["tagged", "multi"])
        #expect(try payload("tagsCount")["total"] as? Int == 2)
        #expect(try ids("selected") == ["multi"])
        #expect(try payload("noTag")["total"] as? Int == 5)
        #expect(data["missingWindow"]?["ok"] as? Bool == false)
        #expect(data["reversedWindow"]?["ok"] as? Bool == false)
        for key in ["list","count","inbox","inboxCount"] {
            let warnings = try #require(data[key]?["warnings"] as? [String])
            #expect(warnings.first?.contains("not the native Forecast total") == true)
        }
    }
}
