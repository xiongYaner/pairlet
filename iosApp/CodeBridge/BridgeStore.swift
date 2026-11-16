import SwiftUI
import ComposeApp

@Observable
final class BridgeStore {
    @ObservationIgnored lazy var runtime = CodeBridgeRuntime()
    var snapshot: BridgeSnapshot?
    var chat: BridgeChat?
    var chatFailure: String?
    var failure: String?
    var workspaceSessions: [String: [BridgeSession]] = [:]
    var filter = "all"
    var sheet: BridgeSheet?
    var newSessionPath = ""
    var chatPresented = false
    var agentOrder: [String] = []
    var enabledAgents: Set<String> = []
    private var pendingChatPresentation = false
    private var machine = ""
    private var preferenceScope = ""
    private var knownAgents: Set<String> = []
    private var errorSessionIDs: Set<String> = []
    private var completedSessionIDs: Set<String> = []
    private let preferences = UserDefaults.standard

    init(observeRuntime: Bool = true) {
        guard observeRuntime else { return }
        runtime.observe { [weak self] value in
            self?.receive(value)
        }
        runtime.observeChat { [weak self] value in
            self?.receiveChat(value)
        }
    }

    func receive(_ value: String) {
        do {
            let next = try JSONDecoder().decode(BridgeSnapshot.self, from: Data(value.utf8))
            synchronizeAgentPreferences(for: next)
            if next.machine != machine {
                workspaceSessions.removeAll()
                errorSessionIDs.removeAll()
                completedSessionIDs.removeAll()
                machine = next.machine
            } else if let previousActivity = snapshot?.sessionActivity, let activity = next.sessionActivity {
                for (sessionID, wasRunning) in previousActivity where wasRunning && activity[sessionID] == false {
                    completedSessionIDs.insert(sessionID)
                }
            }
            for (sessionID, running) in next.sessionActivity ?? [:] where running {
                completedSessionIDs.remove(sessionID)
                errorSessionIDs.remove(sessionID)
            }
            if let path = next.sessionsDir { workspaceSessions[path] = next.sessions }
            workspaceSessions.merge(next.workspaceSessions) { _, incoming in incoming }
            if next.chatId != nil && snapshot?.chatId == nil {
                pendingChatPresentation = true
                if sheet == nil { presentPendingChat() } else { sheet = nil }
            }
            snapshot = next
            if filter != "all" && !enabledAgents.contains(filter) {
                filter = "all"
            }
            failure = nil
        } catch {
            failure = "无法读取连接状态，请重新打开 App。"
            #if DEBUG
            if let decoding = error as? DecodingError {
                switch decoding {
                case .keyNotFound(let key, let context): print("CodeBridge snapshot missing key: \(context.codingPath.map(\.stringValue).joined(separator: ".")).\(key.stringValue)")
                case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context): print("CodeBridge snapshot decode path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                @unknown default: print("CodeBridge snapshot decode failed")
                }
            }
            #endif
        }
    }

    func receiveChat(_ value: String) {
        do {
            let next = try JSONDecoder().decode(BridgeChat.self, from: Data(value.utf8))
            let previous = chat?.sessionId == next.sessionId ? chat : nil
            updateSessionSignals(from: next, previous: previous)
            chat = next
            chatFailure = nil
        } catch {
            chatFailure = "暂时无法读取对话状态，请重试。"
        }
    }

    private func updateSessionSignals(from next: BridgeChat, previous: BridgeChat?) {
        guard let sessionID = next.sessionId else { return }
        if next.observing {
            switch next.observedState {
            case "running":
                completedSessionIDs.remove(sessionID)
                errorSessionIDs.remove(sessionID)
            case "idle":
                completedSessionIDs.remove(sessionID)
                errorSessionIDs.remove(sessionID)
            case "failed":
                errorSessionIDs.insert(sessionID)
                completedSessionIDs.remove(sessionID)
            default: break
            }
            return
        }
        let latestError = next.messages.last { $0.kind == "error" }
        let latestSuccess = next.messages.last { $0.kind == "done" || $0.kind == "assistant" }

        if let latestError, (latestSuccess?.index ?? -1) < latestError.index {
            errorSessionIDs.insert(sessionID)
            completedSessionIDs.remove(sessionID)
            return
        }

        if next.streaming {
            completedSessionIDs.remove(sessionID)
            return
        }

        guard let latestSuccess else { return }
        errorSessionIDs.remove(sessionID)
        if previous?.streaming == true {
            completedSessionIDs.insert(sessionID)
        }
    }

    var orderedAgents: [String] {
        let available = snapshot?.agents ?? []
        return agentOrder.filter(available.contains) + available.filter { !agentOrder.contains($0) }
    }

    var enabledAgentsInOrder: [String] {
        orderedAgents.filter(enabledAgents.contains)
    }

    var defaultEnabledAgent: String? {
        if let preferred = snapshot?.defaultAgent, enabledAgents.contains(preferred) {
            return preferred
        }
        return enabledAgentsInOrder.first
    }

    func isAgentEnabled(_ agent: String) -> Bool {
        enabledAgents.contains(agent)
    }

    func setAgentEnabled(_ agent: String, enabled: Bool) {
        guard orderedAgents.contains(agent) else { return }
        if enabled {
            enabledAgents.insert(agent)
        } else {
            guard enabledAgentsInOrder.count > 1 else { return }
            if snapshot?.defaultAgent == agent,
               let replacement = enabledAgentsInOrder.first(where: { $0 != agent }) {
                runtime.defaultAgent(agent: replacement)
            }
            enabledAgents.remove(agent)
            if filter == agent {
                filter = "all"
            }
        }
        persistAgentPreferences()
    }

    func setDefaultAgent(_ agent: String) {
        guard enabledAgents.contains(agent) else { return }
        runtime.defaultAgent(agent: agent)
    }

    func moveAgents(fromOffsets: IndexSet, toOffset: Int) {
        var rows = orderedAgents
        rows.move(fromOffsets: fromOffsets, toOffset: toOffset)
        agentOrder = rows
        persistAgentPreferences()
    }

    private func synchronizeAgentPreferences(for state: BridgeSnapshot) {
        let scope = state.machines.first(where: \.active)?.id ?? (state.demo ? "demo" : state.machine)
        if preferenceScope != scope {
            preferenceScope = scope
            agentOrder = preferences.stringArray(forKey: agentOrderKey) ?? []
            if let stored = preferences.stringArray(forKey: enabledAgentsKey) {
                enabledAgents = Set(stored)
            } else {
                enabledAgents = Set(state.agents)
            }
            knownAgents = Set(state.agents)
        }

        let available = state.agents
        guard !available.isEmpty else { return }
        let newAgents = Set(available).subtracting(knownAgents)
        if !newAgents.isEmpty {
            enabledAgents.formUnion(newAgents)
            knownAgents.formUnion(newAgents)
        }
        agentOrder = agentOrder.filter(available.contains) + available.filter { !agentOrder.contains($0) }
        if enabledAgents.intersection(available).isEmpty {
            enabledAgents.formUnion(available)
        }
        persistAgentPreferences()
    }

    private var agentOrderKey: String { "pairlet.agent-order.\(preferenceScope)" }
    private var enabledAgentsKey: String { "pairlet.enabled-agents.\(preferenceScope)" }

    private func persistAgentPreferences() {
        guard !preferenceScope.isEmpty else { return }
        preferences.set(agentOrder, forKey: agentOrderKey)
        preferences.set(Array(enabledAgents).sorted(), forKey: enabledAgentsKey)
    }

    func status(for session: BridgeSession) -> BridgeSessionStatus {
        let attention = snapshot?.attentionSessions.contains(session.id) == true
            || (chat?.sessionId == session.id && chat?.hasAsk == true)
            || (chat?.sessionId == session.id && chat?.observedState == "waiting_input")
        if attention { return .waiting }

        let activity = snapshot?.sessionActivity.map { $0[session.id] ?? false }
        let liveChatRunning = chat?.sessionId == session.id && chat?.observing == false && chat?.streaming == true
        let running = activity ?? (snapshot?.runningSessions.contains(session.id) == true || session.live)
        if running || liveChatRunning { return .running }
        if errorSessionIDs.contains(session.id) { return .failed }
        if completedSessionIDs.contains(session.id) || snapshot?.unread.contains(session.id) == true {
            return .completed
        }
        return .idle
    }

    var sessions: [BridgeSession] {
        workspaceSessions.values.flatMap { $0 }
            .filter { filter == "all" || ($0.agent ?? "claude") == filter }
            .sorted { $0.lastModified > $1.lastModified }
    }

    func presentPendingChat() {
        guard pendingChatPresentation else { return }
        pendingChatPresentation = false
        chatPresented = true
    }

    func enterDemo() {
        runtime.enterDemo()
        receive(runtime.snapshot())
    }

    func open(_ session: BridgeSession) {
        runtime.openSession(path: session.cwd, sessionId: session.id, agent: session.agent ?? "claude", title: session.title)
        chatPresented = true
    }

    func dismissChat() {
        chatPresented = false
        runtime.leaveChat()
    }
}

enum BridgeSheet: String, Identifiable {
    case pairing, machines, agents, newSession, quota, usage, notifications, settings, approvals
    var id: String { rawValue }
}

struct SharedContent: UIViewControllerRepresentable {
    let store: BridgeStore
    let screen: String
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        store.runtime.contentController(screen: screen, onClose: onClose)
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

struct GlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct AgentMark: View {
    let agent: String
    var size: CGFloat = 18

    var body: some View {
        Image("agent-\(agent)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(agentTint)
            .frame(width: size, height: size)
            .accessibilityLabel(agentName(agent))
    }

    private var agentTint: Color {
        switch agent {
        case "claude": Color(red: 0.82, green: 0.36, blue: 0.18)
        case "dsh": Color(red: 0.22, green: 0.48, blue: 0.96)
        default: .primary
        }
    }
}
