import SwiftUI

struct PairingView: View {
    let store: BridgeStore
    @State private var code = ""
    @State private var link = ""

    var body: some View {
        Form {
            Section {
                Label("连接你的电脑", systemImage: "laptopcomputer.and.iphone")
                    .font(.title2.weight(.semibold)).padding(.vertical, 12)
                Text("在电脑上运行 pairlet pair，输入显示的六位配对码，或粘贴完整的配对链接。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("配对码") {
                TextField("000 000", text: $code).keyboardType(.numberPad)
                    .font(.title2.monospacedDigit()).accessibilityIdentifier("pairing.code")
                Button(store.snapshot?.pairing == true ? "正在配对…" : "配对电脑") { store.runtime.pair(code: code.filter(\.isNumber)) }
                    .disabled(code.filter(\.isNumber).count != 6 || store.snapshot?.pairing == true)
            }
            Section("自托管配对链接") {
                TextField("pairlet://pair?…", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("使用配对链接") { store.runtime.pairLink(link: link) }.disabled(link.isEmpty)
            }
            if store.snapshot?.pairFailed == true {
                Section { Label("配对失败，请检查代码是否过期、电脑网络和中继地址。", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            Section {
                Button("先看看演示") { store.enterDemo() }.accessibilityIdentifier("pairing.demo")
            } footer: {
                Text("演示完全在本机运行。旧版 CodeBridge Gateway 使用不同协议，新版需要与 Pairlet daemon 重新配对。")
            }
        }.navigationTitle("配对").navigationBarTitleDisplayMode(.inline)
    }
}

struct MachinesView: View {
    let store: BridgeStore
    var body: some View {
        List {
            Section("已配对的电脑") {
                ForEach(store.snapshot?.machines ?? []) { machine in
                    Button {
                        store.runtime.selectMachine(id: machine.id)
                        store.sheet = nil
                    } label: {
                        HStack {
                            Image(systemName: "laptopcomputer")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(machine.name)
                                Text(machine.connected ? "在线" : "连接中").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if machine.active { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }.frame(minHeight: 44)
                    }.foregroundStyle(.primary)
                }
            }
            Button("配对另一台电脑", systemImage: "plus") { store.sheet = .pairing }
        }.navigationTitle("电脑").navigationBarTitleDisplayMode(.inline)
    }
}

struct AgentsView: View {
    let store: BridgeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode
    @State private var selected = ""

    var body: some View {
        List {
            Section {
                ForEach(store.orderedAgents, id: \.self) { agent in
                    HStack(spacing: 12) {
                        Button {
                            store.setDefaultAgent(agent)
                            selected = agent
                        } label: {
                            HStack(spacing: 10) {
                                AgentMark(agent: agent, size: 24)
                                Text(agentName(agent)).foregroundStyle(.primary)
                                if agent == store.snapshot?.defaultAgent && store.isAgentEnabled(agent) {
                                    Label("默认", systemImage: "checkmark")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.tint)
                                        .labelStyle(.titleAndIcon)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!store.isAgentEnabled(agent))
                        .accessibilityIdentifier("agent.default.\(agent)")

                        Toggle("启用 \(agentName(agent))", isOn: Binding(
                            get: { store.isAgentEnabled(agent) },
                            set: { store.setAgentEnabled(agent, enabled: $0) },
                        ))
                        .labelsHidden()
                        .disabled(store.isAgentEnabled(agent) && store.enabledAgentsInOrder.count == 1)
                        .accessibilityIdentifier("agent.toggle.\(agent)")
                    }
                    .opacity(store.isAgentEnabled(agent) ? 1 : 0.55)
                }
                .onMove(perform: store.moveAgents)
            } header: {
                Text("启用的 Agent 会显示在首页")
            } footer: {
                Text("点按名称设为默认 Agent；进入编辑模式后可拖拽调整首页顺序。")
            }
            if let defaults = store.snapshot?.defaults[effectiveAgent] {
                Section("\(agentName(effectiveAgent)) 默认值") {
                    Picker("模型", selection: Binding(get: { defaults.model ?? "" }, set: { store.runtime.defaultModel(agent: effectiveAgent, model: $0.isEmpty ? nil : $0) })) {
                        Text("跟随 CLI").tag("")
                        ForEach(defaults.models, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("思考级别", selection: Binding(get: { defaults.effort ?? "" }, set: { store.runtime.defaultEffort(agent: effectiveAgent, effort: $0.isEmpty ? nil : $0) })) {
                        Text("跟随默认").tag("")
                        ForEach(defaults.efforts, id: \.self) { Text(effortName($0)).tag($0) }
                    }
                    Button("刷新可用模型", systemImage: "arrow.clockwise") { store.runtime.fetchModels(agent: effectiveAgent) }
                }
            }
            Section { Button("完整 Agent 与会话设置", systemImage: "slider.horizontal.3") { store.sheet = .settings } }
        }
        .navigationTitle("Agent 管理").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(editMode?.wrappedValue.isEditing == true ? "结束排序" : "排序") {
                    withAnimation {
                        editMode?.wrappedValue = editMode?.wrappedValue.isEditing == true ? .inactive : .active
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
        }
        .task(id: effectiveAgent) { store.runtime.fetchModels(agent: effectiveAgent) }
    }

    private var effectiveAgent: String {
        if !selected.isEmpty && store.orderedAgents.contains(selected) {
            return selected
        }
        return store.defaultEnabledAgent ?? store.orderedAgents.first ?? "claude"
    }
}

struct NewSessionView: View {
    let store: BridgeStore
    let path: String
    @Environment(\.dismiss) private var dismiss
    @State private var directory = ""
    @State private var prompt = ""
    @State private var agent = ""
    @State private var model = ""
    @State private var failed = false

    var body: some View {
        Form {
            Section("工作区") {
                TextField("电脑上的绝对路径", text: $directory)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("newSession.path")
            }
            Section("任务") {
                TextField("让 Agent 做什么？", text: $prompt, axis: .vertical).lineLimit(4...7).accessibilityIdentifier("newSession.prompt")
            }
            Section {
                Picker("Agent", selection: $agent) {
                    ForEach(store.enabledAgentsInOrder, id: \.self) { Text(agentName($0)).tag($0) }
                }
                .accessibilityIdentifier("newSession.agent")
                Picker("模型", selection: $model) {
                    Text(store.snapshot?.defaults[agent]?.model.map { "跟随默认 · \($0)" } ?? "跟随默认").tag("")
                    ForEach(store.snapshot?.defaults[agent]?.models ?? [], id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("思考级别", value: effortName(store.snapshot?.defaults[agent]?.effort))
            } footer: { Text("模型可按本次会话选择；思考级别沿用 Agent 默认值，进入对话后可随时调整。") }
            if failed { Text("暂时无法创建，请检查电脑连接和 Agent 可用性。").foregroundStyle(.orange) }
        }
        .navigationTitle("新建会话").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") {
                    if store.runtime.startTask(path: directory, prompt: prompt, agent: agent, model: model.isEmpty ? nil : model) { dismiss() } else { failed = true }
                }.disabled(directory.isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agent.isEmpty)
                    .accessibilityIdentifier("newSession.create")
            }
        }
        .onAppear {
            directory = path
            agent = store.filter != "all" && store.isAgentEnabled(store.filter)
                ? store.filter
                : store.defaultEnabledAgent ?? ""
        }
        .onChange(of: agent) { _, _ in
            model = ""
            if !agent.isEmpty { store.runtime.fetchModels(agent: agent) }
        }
    }
}

struct NativeSettings: View {
    let store: BridgeStore
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("CodeBridge", systemImage: "point.3.connected.trianglepath.dotted").font(.title3.weight(.semibold))
                    LabeledContent("电脑", value: store.snapshot?.machine ?? "未连接")
                    LabeledContent("连接", value: store.snapshot?.connected == true ? "已加密连接" : "正在连接")
                }
                Section("连接与默认值") {
                    row("电脑", "laptopcomputer", .machines)
                    row("Agent 管理", "person.2", .agents)
                    row("完整设置", "slider.horizontal.3", .settings)
                }
                Section("通知与统计") {
                    row("消息通知", "bell", .notifications)
                    row("套餐额度", "gauge.with.dots.needle.50percent", .quota)
                    row("Token 用量", "chart.bar", .usage)
                }
                Section {
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Text("基于 Pairlet · MIT License").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ title: String, _ symbol: String, _ sheet: BridgeSheet) -> some View {
        Button { store.sheet = sheet } label: {
            HStack { Label(title, systemImage: symbol); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
        }.foregroundStyle(.primary).frame(minHeight: 38)
    }
}
