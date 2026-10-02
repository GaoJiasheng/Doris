import Foundation

public enum IPCRequestKind: String, Codable, Sendable {
    case notify
    case noteAdd
    case eventsList
    case eventsDismiss
    case eventsDone
    case sync
    case ping
    /// A tool call from an agent through `doris mcp`; answered with an
    /// `IPCResponse` in `IPCDirectory.responsesDir()`.
    case agentCall
}

public struct IPCRequest: Codable, Sendable {
    public let v: Int
    public let id: UUID
    public let kind: IPCRequestKind
    public let payload: IPCPayload
    public var hmac: String?

    public init(id: UUID = UUID(), kind: IPCRequestKind, payload: IPCPayload) {
        self.v = 1
        self.id = id
        self.kind = kind
        self.payload = payload
        self.hmac = nil
    }
}

public enum IPCPayload: Codable, Sendable {
    case notify(IPCNotifyPayload)
    case noteAdd(IPCNoteAddPayload)
    case eventsList(IPCEventsListPayload)
    case eventsDismiss(messageID: UUID)
    case eventsDone(messageID: UUID)
    case sync
    case ping
    case agentCall(IPCAgentCallPayload)

    private enum CodingKeys: String, CodingKey { case kind, body }
    private enum K: String, Codable {
        case notify, noteAdd, eventsList, eventsDismiss, eventsDone, sync, ping, agentCall
    }
    private struct IDBox: Codable { let id: UUID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(K.self, forKey: .kind)
        switch kind {
        case .notify:
            self = .notify(try c.decode(IPCNotifyPayload.self, forKey: .body))
        case .noteAdd:
            self = .noteAdd(try c.decode(IPCNoteAddPayload.self, forKey: .body))
        case .eventsList:
            self = .eventsList(try c.decode(IPCEventsListPayload.self, forKey: .body))
        case .eventsDismiss:
            self = .eventsDismiss(messageID: try c.decode(IDBox.self, forKey: .body).id)
        case .eventsDone:
            self = .eventsDone(messageID: try c.decode(IDBox.self, forKey: .body).id)
        case .sync:
            self = .sync
        case .ping:
            self = .ping
        case .agentCall:
            self = .agentCall(try c.decode(IPCAgentCallPayload.self, forKey: .body))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notify(let p):
            try c.encode(K.notify, forKey: .kind)
            try c.encode(p, forKey: .body)
        case .noteAdd(let p):
            try c.encode(K.noteAdd, forKey: .kind)
            try c.encode(p, forKey: .body)
        case .eventsList(let p):
            try c.encode(K.eventsList, forKey: .kind)
            try c.encode(p, forKey: .body)
        case .eventsDismiss(let id):
            try c.encode(K.eventsDismiss, forKey: .kind)
            try c.encode(IDBox(id: id), forKey: .body)
        case .eventsDone(let id):
            try c.encode(K.eventsDone, forKey: .kind)
            try c.encode(IDBox(id: id), forKey: .body)
        case .sync:
            try c.encode(K.sync, forKey: .kind)
        case .ping:
            try c.encode(K.ping, forKey: .kind)
        case .agentCall(let p):
            try c.encode(K.agentCall, forKey: .kind)
            try c.encode(p, forKey: .body)
        }
    }
}

/// One MCP tool call, relayed by `doris mcp` to the app, which owns the
/// store. The arguments travel as the JSON text the agent sent, so the
/// wire format doesn't change when a tool gains a parameter.
public struct IPCAgentCallPayload: Codable, Sendable {
    /// The MCP client's `clientInfo.name` ("claude-code", "codex-mcp-client", …).
    public var client: String
    public var tool: String
    /// A JSON object.
    public var arguments: String

    public init(client: String, tool: String, arguments: String) {
        self.client = client
        self.tool = tool
        self.arguments = arguments
    }
}

/// What a tool call produced: text for the agent to read, and whether it's
/// an error the agent should correct (bad id, bad date, writes turned off).
/// Carried in `IPCResponse.data`.
public struct IPCAgentResult: Codable, Sendable {
    public var text: String
    public var isError: Bool

    public init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

public struct IPCNotifyPayload: Codable, Sendable {
    public var title: String
    public var body: String?
    public var iconName: String?
    public var displayMode: DisplayMode
    public var source: SourceKind
    public var sourceAppId: String?
    public var level: EventLevel
    public var clickAction: ClickAction?
    public var broadcast: BroadcastScope

    public init(
        title: String,
        body: String? = nil,
        iconName: String? = nil,
        displayMode: DisplayMode = .banner,
        source: SourceKind = .cliGeneric,
        sourceAppId: String? = nil,
        level: EventLevel = .info,
        clickAction: ClickAction? = nil,
        broadcast: BroadcastScope = .local
    ) {
        self.title = title
        self.body = body
        self.iconName = iconName
        self.displayMode = displayMode
        self.source = source
        self.sourceAppId = sourceAppId
        self.level = level
        self.clickAction = clickAction
        self.broadcast = broadcast
    }

    private enum CodingKeys: String, CodingKey {
        case title, body, iconName, displayMode, source, sourceAppId
        case level, clickAction, broadcast
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try c.decode(String.self, forKey: .title)
        self.body = try c.decodeIfPresent(String.self, forKey: .body)
        self.iconName = try c.decodeIfPresent(String.self, forKey: .iconName)
        self.displayMode = try c.decode(DisplayMode.self, forKey: .displayMode)
        self.source = try c.decode(SourceKind.self, forKey: .source)
        self.sourceAppId = try c.decodeIfPresent(String.self, forKey: .sourceAppId)
        // `level` was added late; rows coming from older clients won't
        // carry it. Default to `.info` so they render as low-priority.
        self.level = (try c.decodeIfPresent(EventLevel.self, forKey: .level)) ?? .info
        self.clickAction = try c.decodeIfPresent(ClickAction.self, forKey: .clickAction)
        self.broadcast = try c.decode(BroadcastScope.self, forKey: .broadcast)
    }
}

public struct IPCNoteAddPayload: Codable, Sendable {
    public var title: String
    public var body: String
    public var folderName: String?
    public var tags: [String]

    public init(title: String, body: String = "", folderName: String? = nil, tags: [String] = []) {
        self.title = title
        self.body = body
        self.folderName = folderName
        self.tags = tags
    }
}

public struct IPCEventsListPayload: Codable, Sendable {
    public var source: SourceKind?
    public var sinceSeconds: TimeInterval?
    public var unreadOnly: Bool
    public var limit: Int?
    public var follow: Bool

    public init(source: SourceKind? = nil, sinceSeconds: TimeInterval? = nil, unreadOnly: Bool = false, limit: Int? = nil, follow: Bool = false) {
        self.source = source
        self.sinceSeconds = sinceSeconds
        self.unreadOnly = unreadOnly
        self.limit = limit
        self.follow = follow
    }
}

public struct IPCResponse: Codable, Sendable {
    public var v: Int
    public var requestID: UUID
    public var ok: Bool
    public var error: String?
    public var data: Data?

    public init(requestID: UUID, ok: Bool, error: String? = nil, data: Data? = nil) {
        self.v = 1
        self.requestID = requestID
        self.ok = ok
        self.error = error
        self.data = data
    }
}

public struct IPCEventsRow: Codable, Sendable {
    public let id: UUID
    public let title: String
    public let body: String?
    public let source: SourceKind
    public let sourceAppId: String?
    public let level: EventLevel
    public let receivedAt: Date
    public let displayMode: DisplayMode
    public let state: MessageState

    public init(id: UUID, title: String, body: String?, source: SourceKind, sourceAppId: String?, level: EventLevel = .info, receivedAt: Date, displayMode: DisplayMode, state: MessageState) {
        self.id = id
        self.title = title
        self.body = body
        self.source = source
        self.sourceAppId = sourceAppId
        self.level = level
        self.receivedAt = receivedAt
        self.displayMode = displayMode
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, body, source, sourceAppId
        case level, receivedAt, displayMode, state
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.body = try c.decodeIfPresent(String.self, forKey: .body)
        self.source = try c.decode(SourceKind.self, forKey: .source)
        self.sourceAppId = try c.decodeIfPresent(String.self, forKey: .sourceAppId)
        // `level` was added late; default older rows to `.info`.
        self.level = (try c.decodeIfPresent(EventLevel.self, forKey: .level)) ?? .info
        self.receivedAt = try c.decode(Date.self, forKey: .receivedAt)
        self.displayMode = try c.decode(DisplayMode.self, forKey: .displayMode)
        self.state = try c.decode(MessageState.self, forKey: .state)
    }
}

public enum IPCEncoding {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
