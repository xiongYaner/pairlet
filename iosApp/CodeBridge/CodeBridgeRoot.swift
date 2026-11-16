import SwiftUI

struct CodeBridgeRoot: View {
    @Bindable var store: BridgeStore
    @State private var tab = 0

    var body: some View {
        Group {
            if let state = store.snapshot {
                if !state.consented {
                    consent
                } else if !state.paired && !state.demo {
                    PairingView(store: store)
                } else {
                    TabView(selection: $tab) {
                        WorkspaceHome(store: store)
                            .tabItem { Label("首页", systemImage: "folder") }.tag(0)
                        WorkspaceHome(store: store, recent: true)
                            .tabItem { Label("会话", systemImage: "bubble.left.and.bubble.right") }.tag(1)
                        NotificationHome(store: store)
                            .tabItem { Label("通知", systemImage: "bell") }.tag(2)
                        NativeSettings(store: store)
                            .tabItem { Label("设置", systemImage: "slider.horizontal.3") }.tag(3)
                    }
                }
            } else if let failure = store.failure {
                ContentUnavailableView("无法打开连接", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else {
                ProgressView("正在读取设备…")
            }
        }
        .sheet(item: $store.sheet, onDismiss: store.presentPendingChat) { sheet in
            NavigationStack {
                switch sheet {
                case .pairing: PairingView(store: store)
                case .machines: MachinesView(store: store)
                case .agents: AgentsView(store: store)
                case .newSession: NewSessionView(store: store, path: store.newSessionPath)
                case .quota: QuotaView(store: store)
                case .usage: UsageView(store: store)
                case .notifications: NotificationSettings(store: store)
                case .settings, .approvals:
                    SharedContent(store: store, screen: sheet.rawValue) { store.sheet = nil }
                }
            }
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $store.chatPresented, onDismiss: { store.runtime.leaveChat() }) {
            NativeChatView(store: store)
        }
    }

    private var consent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "lock.shield").font(.system(size: 48)).foregroundStyle(.tint)
                Text("让电脑上的 Agent\n与你随行").font(.largeTitle.bold())
                Text("你的电脑处理任务") .font(.headline)
                Text("消息、附件和工作目录通过端到端加密发送至你配对的电脑，再由电脑上配置的 Agent 与模型服务处理。模型提供方由你的电脑配置决定。")
                Text("通知与语音") .font(.headline)
                Text("启用通知后，任务提醒通过 Apple 推送送达，可能包含项目名称和结果摘要。语音输入使用 Apple 听写或你选择的电脑转写服务。")
                Text("旧 CodeBridge 用户") .font(.headline)
                Text("此版本升级为 Pairlet 连接协议。旧版会话与配对不会删除；请在电脑安装新版 daemon 后重新配对。")
                Button("同意并继续") { store.runtime.acceptConsent() }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("consent.accept")
            }.font(.subheadline).lineSpacing(2).padding(28)
        }
    }
}

struct WorkspaceHome: View {
    @Bindable var store: BridgeStore
    var recent = false
    @State private var search = ""
    @State private var collapsed = Set<String>()
    @State private var expanded = Set<String>()
    @State private var viewMode = "workspace"

    var body: some View {
        NavigationStack {
            ScrollView {
                // Workspace previews request session history from the computer. A regular VStack materializes
                // every workspace at once, so a large machine opens dozens of encrypted list requests on the
                // first frame. LazyVStack starts those tasks only as cards approach the viewport.
                LazyVStack(alignment: .leading, spacing: 8) {
                    workspaceBar.padding(.horizontal, 16)
                    if store.snapshot?.demo == true {
                        Label("演示模式 · 不会向电脑发送任务", systemImage: "play.circle")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
                    }
                    if recent || viewMode == "recent" || viewMode == "unread" {
                        ForEach(visibleSessions) { session in sessionRow(session) }
                    } else {
                        ForEach(visibleDirectories) { directory in
                            workspace(directory)
                        }
                    }
                    if store.snapshot?.directoriesLoaded == false { ProgressView().frame(maxWidth: .infinity).padding() }
                    if store.snapshot?.directoriesLoaded == true && visibleDirectories.isEmpty &&
                        !recent && viewMode == "workspace" {
                        ContentUnavailableView(
                            store.filter == "all" ? "还没有工作区" : "\(agentName(store.filter)) 暂无工作区",
                            systemImage: "folder.badge.plus",
                            description: Text(store.filter == "all"
                                ? "在电脑上打开一个 Agent 会话，刷新后会出现在这里。"
                                : "可切换到其他 Agent，或在这个 Agent 中新建一次对话。")
                        )
                    }
                }.padding(.bottom, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(recent ? "会话" : "对话")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "搜索会话或工作区")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("管理 Agent", systemImage: "person.2") { store.sheet = .agents }
                    Menu("查看方式", systemImage: "line.3.horizontal.decrease") {
                        Picker("查看方式", selection: $viewMode) {
                            Text("按工作区").tag("workspace")
                            Text("最近更新").tag("recent")
                            Text("未读会话").tag("unread")
                        }
                    }
                    Button("新建会话", systemImage: "square.and.pencil") {
                        store.newSessionPath = visibleDirectories.first?.path ?? ""
                        store.sheet = .newSession
                    }.accessibilityIdentifier("home.newSession")
                }
            }
            .refreshable { store.runtime.refresh() }
            .safeAreaInset(edge: .bottom, spacing: 0) { compactQuota }
        }
    }

    private var workspaceBar: some View {
        HStack(spacing: 8) {
            Button { store.sheet = .machines } label: {
                HStack(spacing: 5) {
                    Image(systemName: "laptopcomputer")
                    Text(store.snapshot?.machine ?? "电脑").lineLimit(1)
                    Circle().fill(store.snapshot?.connected == true ? Color.green : .orange).frame(width: 5, height: 5)
                }.font(.caption).frame(maxWidth: 110).frame(minHeight: 44)
            }.foregroundStyle(.primary)
            Divider().frame(height: 22)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    Button { store.filter = "all" } label: {
                        Image(systemName: "person.2").frame(width: 42, height: 44)
                    }
                    .accessibilityIdentifier("agent.filter.all")
                    .background(store.filter == "all" ? Color.accentColor.opacity(0.15) : .clear, in: Capsule())
                    ForEach(store.enabledAgentsInOrder, id: \.self) { agent in
                        Button { store.filter = agent } label: {
                            AgentMark(agent: agent).frame(width: 42, height: 44)
                        }
                        .accessibilityIdentifier("agent.filter.\(agent)")
                        .background(store.filter == agent ? Color.accentColor.opacity(0.15) : .clear, in: Capsule())
                        .contextMenu {
                            if agent != store.snapshot?.defaultAgent {
                                Button("设为默认 Agent", systemImage: "checkmark.circle") {
                                    store.setDefaultAgent(agent)
                                }
                            }
                        }
                    }
                }
            }
        }.padding(5).modifier(GlassSurface())
    }

    private func workspace(_ directory: BridgeDirectory) -> some View {
        let rows = (store.workspaceSessions[directory.path] ?? []).filter(matches)
        let isCollapsed = collapsed.contains(directory.path)
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    if isCollapsed { collapsed.remove(directory.path) } else { collapsed.insert(directory.path) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(directory.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        Text("\(rows.count)").font(.caption2).foregroundStyle(.tertiary)
                        Image(systemName: "chevron.down").font(.system(size: 9)).rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        Spacer(minLength: 0)
                    }.frame(minHeight: 44)
                }.foregroundStyle(.primary)
                Button("在工作区新建会话", systemImage: "square.and.pencil") {
                    store.newSessionPath = directory.path
                    store.sheet = .newSession
                }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                    .accessibilityIdentifier("workspace.newSession")
            }.padding(.horizontal, 20)
            if !isCollapsed {
                ForEach(expanded.contains(directory.path) ? rows : Array(rows.prefix(3))) { session in sessionRow(session) }
                if rows.count > 3 {
                    Button(expanded.contains(directory.path) ? "收起更多" : "显示更多 · \(rows.count - 3)") {
                        if expanded.contains(directory.path) { expanded.remove(directory.path) } else { expanded.insert(directory.path) }
                    }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 48).frame(minHeight: 36)
                }
            }
        }
        .task(id: "\(store.snapshot?.machine ?? "")|\(directory.path)|\(isCollapsed)") {
            guard !isCollapsed else { return }
            store.runtime.loadWorkspace(path: directory.path)
        }
    }

    private var visibleSessions: [BridgeSession] {
        store.sessions.filter(matches).filter { viewMode != "unread" || store.snapshot?.unread.contains($0.id) == true }
    }

    private var visibleDirectories: [BridgeDirectory] {
        (store.snapshot?.directories ?? []).filter { directory in
            guard directory.hasSessions else { return false }
            let matchesAgent = store.filter == "all" || directory.belongs(to: store.filter)
            guard matchesAgent else { return false }
            guard !search.isEmpty else { return true }
            if "\(directory.name) \(directory.path)".localizedCaseInsensitiveContains(search) {
                return true
            }
            return (store.workspaceSessions[directory.path] ?? []).contains(where: matches)
        }
    }

    private func matches(_ session: BridgeSession) -> Bool {
        (store.filter == "all" || (session.agent ?? "claude") == store.filter) &&
        (search.isEmpty || "\(session.title) \(session.cwd)".localizedCaseInsensitiveContains(search))
    }

    private func sessionRow(_ session: BridgeSession) -> some View {
        Button { store.open(session) } label: {
            HStack(spacing: 8) {
                AgentMark(agent: session.agent ?? "claude", size: 16)
                Text(session.title.isEmpty ? session.firstPrompt : session.title)
                    .font(.system(size: 14)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Text(compactRelativeTime(session.lastModified))
                        .font(.system(size: 10, design: .rounded).monospacedDigit())
                        .foregroundStyle(.tertiary).lineLimit(1).frame(width: 30, alignment: .trailing)
                    SessionStatusBadge(status: store.status(for: session))
                        .accessibilityIdentifier("session.status.\(session.id)")
                }
            }.frame(minHeight: 40).contentShape(Rectangle()).padding(.leading, 34).padding(.trailing, 18)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session.row.\(session.id)")
        .accessibilityValue(store.status(for: session).label)
    }

    @ViewBuilder private var compactQuota: some View {
        if let quota = store.snapshot?.quotas.first(where: { $0.agent == "codex" && $0.status == "ok" }), !quota.limits.isEmpty {
            Button { store.sheet = .quota } label: {
                HStack(spacing: 12) {
                    AgentMark(agent: "codex", size: 14)
                    Text("Codex").font(.caption)
                    ForEach(Array(quota.limits.prefix(2).enumerated()), id: \.offset) { _, limit in
                        Text("\(limit.label) \(limit.percent)%").font(.caption2.monospacedDigit())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2)
                }.padding(.horizontal, 18).frame(height: 42)
            }.foregroundStyle(.secondary).background(.bar)
        }
    }
}

private func compactRelativeTime(_ epochMillis: Double) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince1970 - epochMillis / 1000))
    if seconds < 60 { return "\(max(seconds, 1))秒" }
    if seconds < 3_600 { return "\(seconds / 60)分" }
    if seconds < 86_400 { return "\(seconds / 3_600)时" }
    if seconds < 604_800 { return "\(seconds / 86_400)天" }
    if seconds < 31_536_000 { return "\(seconds / 604_800)周" }
    return "\(seconds / 31_536_000)年"
}

private struct SessionStatusBadge: View {
    let status: BridgeSessionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(status.label).font(.system(size: 10, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(color.opacity(0.11), in: Capsule())
        .accessibilityLabel("状态：\(status.label)")
    }

    private var color: Color {
        switch status {
        case .running: .blue
        case .completed: .green
        case .failed: .red
        case .waiting: .orange
        case .idle: .gray
        }
    }
}
