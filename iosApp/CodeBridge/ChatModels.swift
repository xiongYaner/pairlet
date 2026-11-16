import Foundation

struct BridgeChat: Decodable {
    let convoId: String?
    let sessionId: String?
    let agent: String
    let title: String?
    let workdir: String?
    let model: String?
    let effort: String?
    let thinking: Bool?
    let thinkingSupported: Bool
    let efforts: [String]
    let models: [String]
    let mode: String
    let modes: [BridgeMode]
    let modeMutable: Bool
    let contextUsed: Int64?
    let contextWindow: Int64?
    let streaming: Bool
    let observing: Bool
    let observationReadOnly: Bool?
    let observedState: String?
    let opening: Bool
    let connected: Bool
    let hasMore: Bool
    let loadingOlder: Bool
    let hasAsk: Bool
    let messages: [BridgeMessage]
    let attachments: [BridgeAttachment]
    let attachmentsBusy: Bool
    let voice: String
    let voiceSeconds: Int64
    let voiceText: String
    let voiceFailure: String?
    let voiceTranscript: String?
    let micPermissionRequired: Bool

    var contextLabel: String {
        guard let used = contextUsed, let window = contextWindow, window > 0 else { return "—" }
        return "\(Int(Double(used) / Double(window) * 100))%"
    }
}

struct BridgeMessage: Decodable, Identifiable {
    let id: Int
    let index: Int
    let kind: String
    let text: String
    let tool: String?
    let outcome: Bool?
    let pending: Bool
    let delivered: Bool
    let imageCount: Int
    let imagesTruncated: Bool
    let files: [String]
    let seconds: Int?
}

struct BridgeAttachment: Decodable, Identifiable {
    let id: Int64
    let name: String
    let state: String
    let image: Bool
}

struct BridgeMode: Decodable, Identifiable {
    let mode: String
    let id: String
    let label: String
    let detail: String?
    let danger: Bool
    let recommended: Bool
}

func effortName(_ value: String?) -> String {
    guard let value else { return "默认" }
    return ["low":"低", "medium":"中", "high":"高", "xhigh":"很高", "max":"最高", "minimal":"极低", "none":"关闭", "default":"默认"][value] ?? value
}

func permissionName(_ value: String) -> String {
    ["DEFAULT":"每步询问", "default":"每步询问", "ACCEPT_EDITS":"自动改文件", "acceptEdits":"自动改文件", "PLAN":"计划", "plan":"计划", "BYPASS_PERMISSIONS":"完全访问", "bypassPermissions":"完全访问", "auto":"自动判断"][value] ?? value
}
