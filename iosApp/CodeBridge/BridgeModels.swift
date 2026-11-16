import Foundation

struct BridgeSnapshot: Decodable {
    let consented: Bool
    let connected: Bool
    let phase: String
    let demo: Bool
    let paired: Bool
    let pairing: Bool
    let pairFailed: Bool
    let machine: String
    let machines: [BridgeMachine]
    let agents: [String]
    let defaultAgent: String
    let directories: [BridgeDirectory]
    let directoriesLoaded: Bool
    let sessions: [BridgeSession]
    let workspaceSessions: [String: [BridgeSession]]
    let sessionsDir: String?
    let sessionsLoading: Bool
    let groups: [BridgeGroup]
    let chatId: String?
    let chatTitle: String?
    let workdir: String?
    let streaming: Bool
    let unread: [String]
    let runningSessions: [String]
    let sessionActivity: [String: Bool]?
    let attentionSessions: [String]
    let notificationsOn: Bool
    let pushStatus: String
    let approvalCount: Int
    let quotas: [BridgeQuota]
    let usage: BridgeUsage?
    let usageAgent: String?
    let usageFilterable: Bool
    let defaults: [String: BridgeDefaults]
}

struct BridgeMachine: Decodable, Identifiable {
    let id: String
    let name: String
    let active: Bool
    let connected: Bool
}

struct BridgeDirectory: Decodable, Identifiable {
    let path: String
    let name: String
    let hasSessions: Bool
    let executing: Bool
    let sessionAgents: [String]
    var id: String { path }

    /// Older daemons omit sessionAgents. An empty list means provenance is unknown, so keep
    /// the workspace visible instead of treating it as belonging to no Agent.
    func belongs(to agent: String) -> Bool {
        sessionAgents.isEmpty || sessionAgents.contains(agent)
    }
}

struct BridgeSession: Decodable, Identifiable {
    let sessionId: String
    let title: String
    let firstPrompt: String
    let messageCount: Int
    let cwd: String
    let lastModified: Double
    let live: Bool
    let agent: String?
    let group: String?
    var id: String { sessionId }
}

enum BridgeSessionStatus {
    case running
    case completed
    case failed
    case waiting
    case idle

    var label: String {
        switch self {
        case .running: "运行中"
        case .completed: "完成"
        case .failed: "出错"
        case .waiting: "待确认"
        case .idle: "空闲"
        }
    }
}

struct BridgeGroup: Decodable, Identifiable {
    let id: String
    let name: String
    let order: Int
}

struct BridgeDefaults: Decodable {
    let model: String?
    let effort: String?
    let models: [String]
    let efforts: [String]
}

struct BridgeQuota: Decodable, Identifiable {
    let agent: String
    let status: String
    let planType: String?
    let fetchedAt: Double
    let limits: [BridgeLimit]
    var id: String { agent }
}

struct BridgeLimit: Decodable {
    let kind: String
    let group: String
    let percent: Int
    let resetsAt: Double?
    let modelDisplayName: String?
    var label: String {
        let window = group == "session" || kind == "session" ? "5 小时" : "7 天"
        return modelDisplayName.map { "\(window) · \($0)" } ?? window
    }
}

struct BridgeUsage: Decodable {
    let days: [UsageBucket]
    let models: [UsageModel]
    let tokensToday: Int64
    let requestsToday: Int64
    let cacheHitPct: Int?
    let hours: [UsageBucket]?
    let requestsWindow: Int64?
    let cacheHitPctWindow: Int?
    let costUsdWindow: Double?
    let cacheReadTokensWindow: Int64?
    let cacheBaseTokensWindow: Int64?
    var total: Int64 { days.reduce(0) { $0 + $1.tokens } }
}

struct UsageBucket: Decodable {
    let label: String
    let tokens: Int64
    let date: String?
}

struct UsageModel: Decodable {
    let model: String
    let tokens: Int64
    let agent: String
}

func tokenLabel(_ value: Int64) -> String {
    if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
    return String(value)
}

func agentName(_ id: String) -> String {
    ["claude": "Claude", "codex": "Codex", "opencode": "OpenCode", "kimi": "Kimi", "zcode": "ZCode", "dsh": "DeepSeek"][id] ?? id
}
