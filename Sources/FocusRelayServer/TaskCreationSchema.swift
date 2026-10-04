import MCP

func taskCreationSchema() -> Value {
    let string: Value = .object(["type": .string("string")])
    let date: Value = .object([
        "type": .string("object"),
        "description": .string("Exactly one of at (strict ISO timestamp with offset, at most milliseconds) or on (real YYYY-MM-DD calendar date with time.policy=omnifocus_default)."),
        "oneOf": .array([
            .object(["required": .array([.string("at")]), "not": .object(["anyOf": .array([
                .object(["required": .array([.string("on")])]), .object(["required": .array([.string("time")])])
            ])])]),
            .object(["required": .array([.string("on"), .string("time")]), "not": .object(["required": .array([.string("at")])])])
        ]),
        "properties": .object([
            "at": string, "on": string,
            "time": .object(["type": .string("object"), "properties": .object([
                "policy": .object(["type": .string("string"), "enum": .array([.string("omnifocus_default")])])
            ]), "required": .array([.string("policy")])])
        ])
    ])
    func node(depth: Int) -> Value {
        var properties: [String: Value] = [
            "clientID": .object(["type": .string("string"), "pattern": .string("^[A-Za-z0-9_-]{1,64}$")]),
            "name": string, "note": string,
            "flagged": .object(["type": .string("boolean")]),
            "estimatedMinutes": .object(["type": .string("integer"), "minimum": .int(0)]),
            "tagIDs": .object(["type": .string("array"), "items": string, "uniqueItems": .bool(true)]),
            "due": date, "defer": date
        ]
        if depth < 5 {
            properties["children"] = .object(["type": .string("array"), "items": node(depth: depth + 1), "maxItems": .int(20)])
        } else {
            properties["children"] = .object(["type": .string("array"), "maxItems": .int(0),
                "items": .object(["type": .string("object"), "properties": .object([:])])])
        }
        return .object(["type": .string("object"), "properties": .object(properties),
                        "required": .array([.string("clientID"), .string("name")])])
    }
    return closingObjectSchemas(.object([
        "type": .string("object"), "required": .array([.string("creationKey"), .string("tasks")]),
        "properties": .object([
            "creationKey": .object(["type": .string("string"), "format": .string("uuid")]),
            "destination": .object(["type": .string("object"), "required": .array([.string("kind")]), "properties": .object([
                "kind": .object(["type": .string("string"), "enum": .array([.string("inbox"), .string("project"), .string("parent_task")])]), "id": string
            ])]),
            "tasks": .object(["type": .string("array"), "items": node(depth: 1), "minItems": .int(1), "maxItems": .int(20)]),
            "previewOnly": .object(["type": .string("boolean"), "default": .bool(true)]),
            "approvedPreviewID": .object(["type": .string("string"), "format": .string("uuid")]),
            "returnFields": .object(["type": .string("array"), "uniqueItems": .bool(true), "items": .object([
                "type": .string("string"), "enum": .array(["name", "note", "flagged", "estimatedMinutes", "tagIDs", "dueDate", "deferDate"].map(Value.string))
            ])])
        ])
    ]))
}
