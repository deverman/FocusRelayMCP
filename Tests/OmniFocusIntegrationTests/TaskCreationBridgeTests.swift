import Foundation
import JavaScriptCore
import Testing
import OmniFocusCore

@Suite("Task creation native boundary contracts")
struct TaskCreationBridgeTests {
    @Test(arguments: ["__proto__", "__destination__", "constructor", "toString", "hasOwnProperty", "normal"], ["root", "child"])
    func allValidClientIDsSurviveReceiptRoundTripAndOrderVerification(identifier: String, position: String) throws {
        let result = try runCreationFixture("""
        request.creation.tasks[0].clientID='\(position)' === 'root' ? '\(identifier)' : 'parent';
        request.creation.tasks[0].children[0].clientID='\(position)' === 'child' ? '\(identifier)' : 'child_\(identifier)';
        request.creation.tasks[0].due={on:'2026-12-31',time:{policy:'omnifocus_default'}};
        const preview=performTaskCreation(request,io);
        const before=creations;
        request.creation.previewOnly=false;request.creation.approvedPreviewID=preview.previewID;
        const applied=performTaskCreation(request,io);
        const replay=performTaskCreation(request,io);
        JSON.stringify({before,applied,replay,creations,saves,ledger});
        """)
        #expect(result["before"] as? Int == 0)
        #expect(result["creations"] as? Int == 3)
        #expect(result["saves"] as? Int == 1)
        let applied = try JSONDecoder().decode(TaskCreationResponse.self, from: JSONSerialization.data(withJSONObject: try #require(result["applied"])))
        let replay = try JSONDecoder().decode(TaskCreationResponse.self, from: JSONSerialization.data(withJSONObject: try #require(result["replay"])))
        #expect(applied.status == .completed)
        #expect(replay.status == .completed)
        #expect(applied.results.map(\.id) == replay.results.map(\.id))
        #expect(applied.results.map(\.parentID) == [nil, "new-1", nil])
        #expect(applied.results.map(\.finalOrder) == [1, 0, 2])
        #expect(applied.results.first?.due?.iso8601 == "2026-12-31T17:45:00.000Z")
    }

    @Test func previewApplyAndReplayVerifyHierarchyWithoutDuplicates() throws {
        let result = try runCreationFixture("""
        const preview = performTaskCreation(request, io);
        const before = creations;
        request.creation.previewOnly = false;
        request.creation.approvedPreviewID = preview.previewID;
        const applied = performTaskCreation(request, io);
        const replay = performTaskCreation(request, io);
        JSON.stringify({preview, before, applied, replay, creations, saves, ledger});
        """)
        #expect(result["before"] as? Int == 0)
        #expect(result["creations"] as? Int == 3)
        #expect(result["saves"] as? Int == 1)
        let applied = try #require(result["applied"] as? [String: Any])
        let encoded = try JSONSerialization.data(withJSONObject: applied)
        let response = try JSONDecoder().decode(TaskCreationResponse.self, from: encoded)
        #expect(response.status == .completed)
        #expect(response.results.map(\.finalOrder) == [1, 0, 2])
        #expect(response.results.map(\.parentID) == [nil, "new-1", nil])
        #expect(response.results.allSatisfy { $0.status == .verified })
        #expect((result["replay"] as? [String: Any])?["status"] as? String == "completed")
        let ledger = try #require(result["ledger"] as? [String: Any])
        let stored = String(data: try JSONSerialization.data(withJSONObject: ledger), encoding: .utf8)!
        #expect(!stored.contains("Synthetic parent"))
        #expect(!stored.contains("Private synthetic note"))
    }

    @Test(arguments: ["constructor", "fields", "save", "verification", "journal"])
    func partialFailureNeverAdmitsAnotherConstructor(stage: String) throws {
        let result = try runCreationFixture("""
        const preview = performTaskCreation(request, io);
        request.creation.previewOnly = false;
        request.creation.approvedPreviewID = preview.previewID;
        failure = '\(stage)';
        const first = performTaskCreation(request, io);
        const count = creations;
        failure = null;
        const replay = performTaskCreation(request, io);
        JSON.stringify({first, replay, count, creations, saves});
        """)
        #expect(result["count"] as? Int == result["creations"] as? Int)
        #expect((result["first"] as? [String: Any])?["status"] as? String != "completed")
        if stage == "save" {
            #expect((result["replay"] as? [String: Any])?["status"] as? String != "completed")
        }
    }

    @Test(arguments: ["missingParent", "missingTag", "completedParent", "missingProject"])
    func invalidNativeReferencesFailBeforeWrites(kind: String) throws {
        let result = try runCreationFixture("""
        if ('\(kind)' === 'missingParent') request.creation.destination = {kind:'parent_task', id:'absent'};
        if ('\(kind)' === 'missingTag') request.creation.tasks[1].tagIDs = ['absent'];
        if ('\(kind)' === 'completedParent') {request.creation.destination = {kind:'parent_task', id:'existing'}; map.existing.completed = true;}
        if ('\(kind)' === 'missingProject') request.creation.destination = {kind:'project', id:'absent'};
        let error = null; try {performTaskCreation(request, io);} catch(e) {error=String(e);}
        JSON.stringify({error, creations, writes});
        """)
        #expect(result["error"] as? String != nil)
        #expect(result["creations"] as? Int == 0)
        #expect(result["writes"] as? Int == 0)
    }

    @Test func dateOnlyReadsCurrentSettingAndFreezesPreview() throws {
        let result = try runCreationFixture("""
        request.creation.tasks[0].due = {on:'2026-12-31', time:{policy:'omnifocus_default'}};
        request.creation.tasks[0].defer = {on:'2026-12-30', time:{policy:'omnifocus_default'}};
        const preview = performTaskCreation(request, io);
        configured.DefaultDueTime = '22:00'; configured.DefaultStartTime = '11:00';
        request.creation.previewOnly = false; request.creation.approvedPreviewID = preview.previewID;
        const applied = performTaskCreation(request, io);
        JSON.stringify({preview, applied, settingReads, creations});
        """)
        let preview = try #require(result["preview"] as? [String: Any])
        let applied = try #require(result["applied"] as? [String: Any])
        let item = try #require((preview["results"] as? [[String: Any]])?.first)
        #expect((item["due"] as? [String: Any])?["iso8601"] as? String == "2026-12-31T17:45:00.000Z")
        #expect((item["defer"] as? [String: Any])?["iso8601"] as? String == "2026-12-30T08:15:00.000Z")
        #expect(applied["status"] as? String == "completed")
        #expect(result["settingReads"] as? Int == 2)
    }

    @Test(arguments: [
        ("2026-03-07", "2026-03-07T22:45:00.000Z"),
        ("2026-03-08", "2026-03-08T21:45:00.000Z"),
        ("2026-10-31", "2026-10-31T21:45:00.000Z"),
        ("2026-11-01", "2026-11-01T22:45:00.000Z"),
        ("2026-12-31", "2026-12-31T22:45:00.000Z"),
        ("2027-01-01", "2027-01-01T22:45:00.000Z")
    ])
    func calendarResolutionCoversDSTAndYearBoundary(day: String, expected: String) throws {
        let result = try runCreationFixture("""
        request.creation.tasks[0].due = {on:'\(day)',time:{policy:'omnifocus_default'}};
        const preview = performTaskCreation(request,io);
        JSON.stringify({due:preview.results[0].due,creations,writes});
        """, calendarTimeZone: "America/New_York")
        let due = try #require(result["due"] as? [String: Any])
        #expect(due["iso8601"] as? String == expected)
        #expect(due["timeZoneID"] as? String == "America/New_York")
        #expect(result["creations"] as? Int == 0)
    }

    @Test func nonexistentDSTWallTimeFailsBeforeJournalOrConstructor() throws {
        let result = try runCreationFixture("""
        configured.DefaultDueTime='02:30';
        request.creation.tasks[0].due={on:'2026-03-08',time:{policy:'omnifocus_default'}};
        let error=null;try {performTaskCreation(request,io);}catch(e){error=String(e);}
        JSON.stringify({error,creations,writes});
        """, calendarTimeZone: "America/New_York")
        #expect(result["error"] as? String != nil)
        #expect(result["creations"] as? Int == 0)
        #expect(result["writes"] as? Int == 0)
    }

    @Test(arguments: ["invalidSetting", "invalidDate", "timezone"])
    func dateResolutionFailsClosed(kind: String) throws {
        let result = try runCreationFixture("""
        request.creation.tasks[0].due = {on:'2026-02-28', time:{policy:'omnifocus_default'}};
        if ('\(kind)' === 'invalidSetting') configured.DefaultDueTime = '25:00';
        if ('\(kind)' === 'invalidDate') request.creation.tasks[0].due.on = '2026-02-30';
        if ('\(kind)' === 'timezone') request.userTimeZone = 'Asia/Makassar';
        let error = null; try {performTaskCreation(request, io);} catch(e) {error=String(e);}
        JSON.stringify({error, creations, writes});
        """)
        #expect(result["error"] as? String != nil)
        #expect(result["creations"] as? Int == 0)
        #expect(result["writes"] as? Int == 0)
    }

    @Test func missingReceiptAndChangedIntentDoNotCreate() throws {
        let result = try runCreationFixture("""
        const preview = performTaskCreation(request, io);
        request.creation.previewOnly=false; request.creation.approvedPreviewID=preview.previewID;
        request.creationFingerprint='b'.repeat(64);
        let changed=null; try {performTaskCreation(request,io);} catch(e){changed=String(e);}
        ledger={}; request.creationFingerprint='a'.repeat(64);
        let missing=null; try {performTaskCreation(request,io);} catch(e){missing=String(e);}
        JSON.stringify({changed,missing,creations});
        """)
        #expect(result["changed"] as? String != nil)
        #expect(result["missing"] as? String != nil)
        #expect(result["creations"] as? Int == 0)
    }

    @Test(arguments: ["missing", "parent", "order", "field"])
    func completedReplayReconcilesNativeDriftWithoutWriting(kind: String) throws {
        let result = try runCreationFixture("""
        const preview = performTaskCreation(request, io);
        request.creation.previewOnly = false; request.creation.approvedPreviewID = preview.previewID;
        performTaskCreation(request, io);
        const before = {creations, saves, writes};
        if ('\(kind)' === 'missing') delete map['new-1'];
        if ('\(kind)' === 'parent') map['new-2'].parent = existing;
        if ('\(kind)' === 'order') inboxItems.reverse();
        if ('\(kind)' === 'field') map['new-1'].name = 'Changed externally';
        const replay = performTaskCreation(request, io);
        JSON.stringify({before, creations, saves, writes, replay});
        """)
        let before = try #require(result["before"] as? [String: Int])
        #expect(result["creations"] as? Int == before["creations"])
        #expect(result["saves"] as? Int == before["saves"])
        #expect(result["writes"] as? Int == before["writes"])
        #expect((result["replay"] as? [String: Any])?["status"] as? String == "partial")
    }

    @Test(arguments: ["project", "parent_task"])
    func stableDestinationIDsPreserveExistingChildren(kind: String) throws {
        let result = try runCreationFixture("""
        existing.children = [{id:{primaryKey:'prior'},parent:existing}];
        io.projects = () => ({project:{id:{primaryKey:'project'},task:existing}});
        request.creation.destination = {kind:'\(kind)', id:'\(kind)' === 'project' ? 'project' : 'existing'};
        const preview = performTaskCreation(request, io);
        request.creation.previewOnly = false; request.creation.approvedPreviewID = preview.previewID;
        const applied = performTaskCreation(request, io);
        JSON.stringify({applied, prior:existing.children[0].id.primaryKey});
        """)
        let data = try JSONSerialization.data(withJSONObject: try #require(result["applied"]))
        let response = try JSONDecoder().decode(TaskCreationResponse.self, from: data)
        #expect(response.status == .completed)
        #expect(response.results.map(\.parentID) == ["existing", "new-1", "existing"])
        #expect(response.results.map(\.finalOrder) == [1, 0, 2])
        #expect(result["prior"] as? String == "prior")
    }
}

private func runCreationFixture(_ body: String, calendarTimeZone: String? = nil) throws -> [String: Any] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js"), encoding: .utf8)
    let module = try #require(source.components(separatedBy: "// TASK CREATION MODULE BEGIN").last?.components(separatedBy: "// TASK CREATION MODULE END").first)
    let context = try #require(JSContext())
    var exception: String?
    context.exceptionHandler = { _, value in exception = value?.toString() }
    let setup = """
    var ledger={}, creations=0, saves=0, writes=0, failure=null, settingReads=0;
    var configured={DefaultDueTime:'17:45',DefaultStartTime:'08:15'};
    var settings={objectForKey:key=>{settingReads++;return configured[key];},defaultObjectForKey:()=>{throw Error('factory setting forbidden');}};
    function DateComponents() {}
    var Calendar={current:{identifier:'gregorian',timeZone:{toString:()=> '[object TimeZone: UTC (current)]'},
      dateComponentsFromDate:d=>({year:d.getUTCFullYear(),month:d.getUTCMonth()+1,day:d.getUTCDate(),hour:d.getUTCHours(),minute:d.getUTCMinutes(),second:d.getUTCSeconds()}),
      dateFromDateComponents:c=>new Date(Date.UTC(c.year,c.month-1,c.day,c.hour,c.minute,c.second))}};
    var existing={id:{primaryKey:'existing'},name:'Existing',parent:null,children:[],tags:[]};
    var map={existing}, inboxItems=[existing];
    var io={directory:'/state',exists:p=>Object.prototype.hasOwnProperty.call(ledger,p),read:p=>JSON.parse(JSON.stringify(ledger[p])),
      write:(p,value)=>{writes++;if(failure==='journal' && creations===1)throw Error('injected journal failure');ledger[p]=JSON.parse(JSON.stringify(value));},
      tasks:()=>map,projects:()=>({}),tags:()=>({tag:{id:{primaryKey:'tag'}}}),inbox:()=>inboxItems,
      remaining:t=>!t.completed,projectRemaining:()=>true,
      create:(name,parent)=>{creations++;if(failure==='constructor' && creations===2)throw Error('injected constructor failure');
        parent = parent && parent.task ? parent.task : parent;
        const t={id:{primaryKey:'new-'+creations},name,parent,children:[],tags:[],note:'',flagged:false,estimatedMinutes:null,
          addTag:tag=>{t.tags.push(tag);if(failure==='fields')throw Error('injected field failure');}};
        if(failure==='verification')t.name='Mismatch';
        map[t.id.primaryKey]=t;(parent?parent.children:inboxItems).push(t);return t;},
      save:()=>{saves++;if(failure==='save')throw Error('injected save failure');}};
    var request={creationFingerprint:'a'.repeat(64),creationPreviewID:'00000000-0000-0000-0000-000000000002',userTimeZone:'UTC',
      creation:{creationKey:'00000000-0000-0000-0000-000000000001',previewOnly:true,destination:{kind:'inbox'},
        tasks:[{clientID:'parent',name:'Synthetic parent',note:'Private synthetic note',tagIDs:['tag'],children:[{clientID:'child',name:'Synthetic child'}]},
          {clientID:'sibling',name:'Synthetic sibling'}]}};
    """
    var calendarSetup = ""
    if let calendarTimeZone {
        // Foundation supplies the calendar oracle; the production JS still performs
        // all date intent, settings, and round-trip validation through its API seam.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: calendarTimeZone))
        let components: @convention(block) (Double) -> String = { milliseconds in
            let c = calendar.dateComponents([.year,.month,.day,.hour,.minute,.second], from: Date(timeIntervalSince1970: milliseconds / 1000))
            return "{\"year\":\(c.year!),\"month\":\(c.month!),\"day\":\(c.day!),\"hour\":\(c.hour!),\"minute\":\(c.minute!),\"second\":\(c.second!)}"
        }
        let date: @convention(block) (Int, Int, Int, Int, Int, Int) -> Double = { year, month, day, hour, minute, second in
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!.timeIntervalSince1970 * 1000
        }
        context.setObject(components, forKeyedSubscript: "calendarComponents" as NSString)
        context.setObject(date, forKeyedSubscript: "calendarDate" as NSString)
        calendarSetup = """
        request.userTimeZone='\(calendarTimeZone)';
        Calendar.current.timeZone.toString=()=> '[object TimeZone: \(calendarTimeZone) (current)]';
        Calendar.current.dateComponentsFromDate=d=>JSON.parse(calendarComponents(d.getTime()));
        Calendar.current.dateFromDateComponents=c=>new Date(calendarDate(c.year,c.month,c.day,c.hour,c.minute,c.second));
        """
    }
    let json = try #require(context.evaluateScript(setup + calendarSetup + module + body)?.toString())
    #expect(exception == nil, "JavaScript exception: \(exception ?? "none")")
    guard exception == nil else { throw MutationValidationError(exception!) }
    return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
}
