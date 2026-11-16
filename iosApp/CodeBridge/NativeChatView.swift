import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ComposeApp

private enum ChatPanel: String, Identifiable {
    case model, reasoning, permission, information, tools, approvals
    var id: String { rawValue }
}

struct NativeChatView: View {
    @Bindable var store: BridgeStore
    @State private var draft = ""
    @State private var panel: ChatPanel?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var importingFile = false
    @State private var notice: String?
    @State private var followLatest = true
    @State private var pendingMode: BridgeMode?
    @State private var modelSearch = ""
    @State private var confirmingTakeover = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            NativeTranscriptView(chat: store.chat, store: store, followLatest: $followLatest) {
                panel = .approvals
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(store.chat?.title ?? "对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("返回", systemImage: "chevron.left") { store.runtime.saveDraft(text: draft); store.chatPresented = false }
                        .accessibilityIdentifier("chat.back")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("对话工具", systemImage: "ellipsis") {
                        Button("会话信息", systemImage: "info.circle") { panel = .information }
                        Button("文件、Diff 与更多工具", systemImage: "doc.text.magnifyingglass") { panel = .tools }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .sheet(item: $panel) { item in
                NavigationStack {
                    Group {
                        switch item {
                    case .model: modelPicker
                    case .reasoning: reasoningPicker
                    case .permission: permissionPicker
                    case .information: information
                    case .tools, .approvals:
                        SharedContent(store: store, screen: item == .tools ? "chat" : "approvals") { panel = nil }
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { panel = nil }.accessibilityIdentifier("chat.panel.done")
                        }
                    }
                }.presentationDragIndicator(.visible)
            }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.item], allowsMultipleSelection: true, onCompletion: importFiles)
            .onChange(of: selectedPhotos) { _, selection in
                Task {
                    for photo in selection {
                        do {
                            if let data = try await photo.loadTransferable(type: Data.self), !store.runtime.attachImage(data: data) { notice = "图片超过 20 MB，请选择较小的图片。" }
                        } catch { notice = "图片读取失败，请重试。" }
                    }
                    selectedPhotos = []
                }
            }
            .task(id: store.chat?.convoId) {
                draft = store.runtime.draft()
                followLatest = true
                if let agent = store.chat?.agent { store.runtime.fetchModels(agent: agent) }
            }
            .onChange(of: draft) { _, value in store.runtime.saveDraft(text: value) }
            .onChange(of: store.chat?.voiceTranscript, initial: true) { _, value in
                guard value != nil, let transcript = store.runtime.takeVoiceText() else { return }
                draft += draft.isEmpty || draft.last?.isWhitespace == true ? transcript : " " + transcript
                inputFocused = true
            }
            .alert("确认完全访问", isPresented: Binding(get: { pendingMode != nil }, set: { if !$0 { pendingMode = nil } })) {
                Button("取消", role: .cancel) { pendingMode = nil }
                Button("切换", role: .destructive) { if let mode = pendingMode { applyMode(mode) }; pendingMode = nil }
            } message: { Text(pendingMode?.detail ?? "命令与文件修改可能直接执行，请仅用于你信任的目录。") }
            .alert("需要麦克风权限", isPresented: Binding(get: { store.chat?.micPermissionRequired == true }, set: { if !$0 { store.runtime.dismissMicPermission() } })) {
                Button("取消", role: .cancel) { store.runtime.dismissMicPermission() }
                Button("打开设置") {
                    store.runtime.dismissMicPermission()
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } message: { Text("请在系统设置中允许麦克风和语音识别，然后重试。") }
            .alert("接管这个 Codex 会话？", isPresented: $confirmingTakeover) {
                Button("取消", role: .cancel) {}
                Button("确认接管") {
                    store.runtime.saveDraft(text: draft)
                    if !store.runtime.takeOver() { notice = "暂时无法接管，请确认电脑在线且会话允许操作。" }
                }.accessibilityIdentifier("chat.takeover.confirm")
            } message: {
                Text("手机将把后续消息发送到官方 Codex 当前同一个会话，原 thread ID 不变，不会创建分支。电脑端仍可继续查看和操作这个会话；若电脑上的 owner 已退出，请先重新打开该会话再接管。")
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let notice = notice ?? store.chatFailure { Text(notice).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
            if store.chat?.connected == false { Text("连接尚未就绪，消息会在连接恢复后继续处理。").font(.caption2).foregroundStyle(.secondary) }
            if store.chat?.observing == true {
                observationNotice
            } else {
                editableComposer
            }
        }.padding(.bottom, 6).padding(.top, 4).background(.bar)
    }

    @ViewBuilder
    private var editableComposer: some View {
            VStack(spacing: 0) {
                if let chat = store.chat, chat.voice != "idle" { voiceBar(chat) }
                HStack(spacing: 3) {
                    parameter(store.chat?.model ?? "模型", symbol: "cpu", panel: .model)
                    parameter(effortName(store.chat?.effort), symbol: "brain", panel: .reasoning)
                    parameter(permissionName(store.chat?.mode ?? "DEFAULT"), symbol: "shield", panel: .permission)
                    parameter(store.chat?.contextLabel ?? "—", symbol: "circle.dotted", panel: .information)
                }.padding(.horizontal, 5)
                if let attachments = store.chat?.attachments, !attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(attachments) { attachment in
                                HStack(spacing: 5) {
                                    Image(systemName: attachment.image ? "photo" : "doc")
                                    Text(attachment.name).lineLimit(1)
                                    Text(attachment.state).foregroundStyle(.secondary)
                                    Button("移除附件", systemImage: "xmark.circle.fill") { store.runtime.removeAttachment(id: attachment.id, image: attachment.image) }.labelStyle(.iconOnly)
                                }.font(.caption2).padding(8).background(.quaternary, in: Capsule())
                            }
                        }.padding(.horizontal, 10)
                    }
                }
                TextField("给 \(agentName(store.chat?.agent ?? "claude")) 发消息…", text: $draft, axis: .vertical)
                    .font(.system(size: 15)).lineLimit(1...6).padding(.horizontal, 14).padding(.vertical, 9)
                    .focused($inputFocused).accessibilityIdentifier("chat.input")
                HStack(spacing: 6) {
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 4, matching: .images) { Image(systemName: "photo").frame(width: 44, height: 44) }.accessibilityLabel("添加照片")
                    Button("添加文件", systemImage: "paperclip") { importingFile = true }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                    Button("语音输入", systemImage: "mic") { inputFocused = false; store.runtime.startVoice() }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                        .disabled(store.chat?.voice != "idle" && store.chat?.voice != "failed")
                        .accessibilityIdentifier("chat.voice")
                    Spacer(minLength: 0)
                    if store.chat?.streaming == true {
                        Button("停止", systemImage: "stop.fill") { store.runtime.cancelTurn() }.labelStyle(.iconOnly).frame(width: 44, height: 44).accessibilityIdentifier("chat.stop")
                    }
                    Button("发送", systemImage: "arrow.up") { send() }
                        .labelStyle(.iconOnly).buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                        .disabled(!canSend).accessibilityIdentifier("chat.send")
                }.padding(.horizontal, 7).padding(.bottom, 5)
            }.modifier(GlassSurface()).padding(.horizontal, 10)
            if store.chat?.streaming == true { Text("正在运行 · 新消息将排队处理").font(.system(size: 10)).foregroundStyle(.secondary) }
    }

    private var observationNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("观察模式 · 仅查看", systemImage: "eye")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("chat.observation.notice")
            Text(store.chat?.observationReadOnly == true
                ? "此会话被设置为只读，可以查看消息，不能发送或接管。"
                : "此会话由电脑上的 Codex 管理。手机正在同步消息；接管后会直接发送到原会话，不会创建分支。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.chat?.observationReadOnly != true {
                Button("接管原会话并继续", systemImage: "arrow.left.arrow.right") {
                    inputFocused = false
                    confirmingTakeover = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.chat?.connected != true || store.chat?.opening == true)
                .accessibilityIdentifier("chat.takeover")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .modifier(GlassSurface()).padding(.horizontal, 10)
    }

    private func voiceBar(_ chat: BridgeChat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: chat.voice == "recording" ? "waveform" : "mic")
                Text(chat.voice == "recording" ? "录音中 · \(chat.voiceSeconds)秒" : chat.voice == "failed" ? "语音输入失败" : "正在转写…")
                    .font(.caption).monospacedDigit()
                Spacer()
                Button("取消", systemImage: "xmark") { store.runtime.cancelVoice() }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                if chat.voice == "recording" {
                    Button("完成转写", systemImage: "checkmark") { store.runtime.finishVoice() }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                } else if chat.voice == "failed" || chat.voice == "waiting" {
                    Button("重试", systemImage: "arrow.clockwise") { store.runtime.retryVoice() }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
            }
            if !chat.voiceText.isEmpty { Text(chat.voiceText).font(.system(size: 14)).lineLimit(3) }
            if let failure = chat.voiceFailure { Text(failure).font(.caption).foregroundStyle(.orange) }
            Text("转写后放入输入框，确认后发送。").font(.caption2).foregroundStyle(.secondary)
        }.padding(.horizontal, 14).padding(.bottom, 8)
    }

    private var canSend: Bool {
        guard let chat = store.chat, chat.convoId != nil, !chat.observing, !chat.opening, !chat.attachmentsBusy,
              chat.voice == "idle" || chat.voice == "failed" else { return false }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !chat.attachments.isEmpty
    }

    private func parameter(_ title: String, symbol: String, panel target: ChatPanel) -> some View {
        Button { panel = target } label: {
            HStack(spacing: 4) { Image(systemName: symbol); Text(title).lineLimit(1) }
                .font(.system(size: 11)).frame(maxWidth: .infinity, minHeight: 44)
        }.foregroundStyle(.secondary).accessibilityIdentifier("chat.parameter.\(target.rawValue)")
    }

    private func send() {
        if store.runtime.sendPrompt(text: draft) { draft = ""; followLatest = true; notice = nil }
        else { notice = "消息未发送，请检查会话状态。" }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            for url in try result.get().prefix(4) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20 * 1024 * 1024 else { notice = "单个附件不能超过 20 MB。"; continue }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                if !store.runtime.attachFile(name: url.lastPathComponent, data: data, mediaType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream") { notice = "附件无法添加，请重试。" }
            }
        } catch { notice = "文件读取失败，请重试。" }
    }

    private var modelPicker: some View {
        List {
            ForEach(filteredModels, id: \.self) { model in
                Button { store.runtime.switchModel(model: model); panel = nil } label: {
                    HStack { Text(model); Spacer(); if model == store.chat?.model { Image(systemName: "checkmark") } }
                }
            }
            if filteredModels.isEmpty {
                Text(modelSearch.isEmpty ? "尚未取得可用模型，请刷新电脑上的模型列表。" : "没有匹配的模型。")
                    .foregroundStyle(.secondary)
            }
            Button("刷新模型") { if let agent = store.chat?.agent { store.runtime.fetchModels(agent: agent) } }
        }
        .searchable(text: $modelSearch, prompt: "搜索模型名称或 ID")
        .navigationTitle("模型").navigationBarTitleDisplayMode(.inline)
    }

    private var filteredModels: [String] {
        let models = store.chat?.models ?? []
        let query = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return models }
        return models.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var reasoningPicker: some View {
        Form {
            Section {
                Button("默认") { store.runtime.switchEffort(effort: nil) }
                ForEach(store.chat?.efforts ?? [], id: \.self) { effort in
                    Button { store.runtime.switchEffort(effort: effort) } label: {
                        HStack { Text(effortName(effort)); Spacer(); if effort == store.chat?.effort { Image(systemName: "checkmark") } }
                    }
                }
            } header: { Text("思考深度") } footer: { Text("从下一回合生效，不打断当前任务。可用级别由当前 Agent 和模型决定。") }
            if store.chat?.thinkingSupported == true {
                Section("扩展思考") {
                    Picker("扩展思考", selection: thinkingSelection) {
                        Text("默认").tag("default"); Text("开启").tag("on"); Text("关闭").tag("off")
                    }.pickerStyle(.segmented)
                }
            }
        }.navigationTitle("思考设置").navigationBarTitleDisplayMode(.inline)
    }

    private var thinkingSelection: Binding<String> {
        Binding {
            store.chat?.thinking.map { $0 ? "on" : "off" } ?? "default"
        } set: { selection in
            let enabled: KotlinBoolean? = selection == "default" ? nil : KotlinBoolean(bool: selection == "on")
            store.runtime.switchThinking(thinking: enabled)
        }
    }

    private var permissionPicker: some View {
        List {
            ForEach(store.chat?.modes ?? []) { mode in
                Button {
                    if mode.danger { pendingMode = mode } else { applyMode(mode) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.label).foregroundStyle(mode.danger ? .orange : .primary)
                        if let detail = mode.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 5)
                }.disabled(store.chat?.modeMutable != true)
            }
            if store.chat?.modeMutable == false {
                Text("此 Agent 的权限由启动配置决定，当前会话内无法切换。").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("权限模式").navigationBarTitleDisplayMode(.inline)
    }

    private func applyMode(_ mode: BridgeMode) {
        if store.runtime.switchMode(id: mode.id) { panel = nil } else { notice = "当前 Agent 不支持此权限模式。" }
    }

    private var information: some View {
        List {
            LabeledContent("Agent", value: agentName(store.chat?.agent ?? "claude"))
            LabeledContent("模型", value: store.chat?.model ?? "默认")
            LabeledContent("思考", value: effortName(store.chat?.effort))
            LabeledContent("电脑", value: store.snapshot?.machine ?? "")
            LabeledContent("目录", value: store.chat?.workdir ?? "")
            if let used = store.chat?.contextUsed, let window = store.chat?.contextWindow { LabeledContent("上下文", value: "\(tokenLabel(used)) / \(tokenLabel(window))") }
            Button("打开文件与 Diff 工具") { panel = .tools }
        }.navigationTitle("会话信息").navigationBarTitleDisplayMode(.inline)
    }
}
