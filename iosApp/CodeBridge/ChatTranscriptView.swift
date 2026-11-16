import SwiftUI

struct NativeTranscriptView: View {
    let chat: BridgeChat?
    let store: BridgeStore
    @Binding var followLatest: Bool
    let openApprovals: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                messageList
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(DragGesture().onChanged { _ in followLatest = false })
            .onChange(of: chat?.messages.last?.text) { _, _ in
                if followLatest { proxy.scrollTo("latest", anchor: .bottom) }
            }
            .onChange(of: chat?.messages.count) { _, _ in
                if followLatest { proxy.scrollTo("latest", anchor: .bottom) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !followLatest {
                    Button {
                        followLatest = true
                        withAnimation { proxy.scrollTo("latest", anchor: .bottom) }
                    } label: {
                        Image(systemName: "arrow.down").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("回到底部")
                    .background(.regularMaterial, in: Circle())
                    .padding(16)
                }
            }
        }
    }

    private var messageList: some View {
        let rows = transcriptRows(chat?.messages ?? [])
        return LazyVStack(alignment: .leading, spacing: 10) {
            if let chat {
                if chat.hasMore {
                    Button(chat.loadingOlder ? "正在读取…" : "载入更早的消息") {
                        followLatest = false
                        store.runtime.loadOlder()
                    }
                    .font(.caption)
                    .disabled(chat.loadingOlder)
                    .frame(maxWidth: .infinity)
                }
                if chat.observing {
                    Label("当前为只读观察", systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if chat.opening {
                    ProgressView("正在打开会话…").frame(maxWidth: .infinity)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    switch row {
                    case .message(let message):
                        MessageContent(
                            message: message,
                            store: store,
                            streaming: chat.streaming &&
                                message.id == chat.messages.last?.id &&
                                message.kind == "assistant"
                        )
                    case .activity(let activity):
                        ProcessActivityGroup(
                            activity: activity,
                            isLive: chat.streaming && index == rows.count - 1,
                            store: store
                        )
                    }
                }
                if chat.hasAsk {
                    Button(action: openApprovals) {
                        Label("Agent 正在等待你处理", systemImage: "hand.raised")
                            .font(.subheadline)
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityIdentifier("chat.approval")
                }
            }
            Color.clear.frame(height: 1).id("latest")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private enum TranscriptRow: Identifiable {
    case message(BridgeMessage)
    case activity(ProcessActivity)

    var id: String {
        switch self {
        case .message(let message): "message-\(message.id)"
        case .activity(let activity): "activity-\(activity.id)"
        }
    }
}

private struct ProcessActivity: Identifiable {
    let id: Int
    let steps: [BridgeMessage]
    let durationSeconds: Int?

    var failedCount: Int {
        steps.count { $0.kind == "tool" && $0.outcome == false }
    }

    var derivedDurationSeconds: Int? {
        if let durationSeconds, durationSeconds > 0 { return durationSeconds }
        let total = steps.compactMap(\.seconds).reduce(0, +)
        return total > 0 ? total : nil
    }
}

private func transcriptRows(_ messages: [BridgeMessage]) -> [TranscriptRow] {
    var rows: [TranscriptRow] = []
    var steps: [BridgeMessage] = []
    var durationSeconds: Int?

    func flushActivity() {
        guard let first = steps.first else {
            durationSeconds = nil
            return
        }
        rows.append(.activity(ProcessActivity(
            id: first.id,
            steps: steps,
            durationSeconds: durationSeconds
        )))
        steps.removeAll(keepingCapacity: true)
        durationSeconds = nil
    }

    for message in messages {
        switch message.kind {
        case "thinking", "tool", "activity":
            steps.append(message)
        case "done":
            durationSeconds = message.seconds
        default:
            flushActivity()
            rows.append(.message(message))
        }
    }
    flushActivity()
    return rows
}

private struct ProcessActivityGroup: View {
    let activity: ProcessActivity
    let isLive: Bool
    let store: BridgeStore
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    statusMark
                        .frame(width: 16, height: 16)
                    Text(headline)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if activity.failedCount > 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("\(activity.failedCount) 个步骤失败")
                    }
                    Spacer(minLength: 8)
                    if let duration = activity.derivedDurationSeconds, !isLive {
                        Text(durationLabel(duration))
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .frame(minHeight: 38)
                .padding(.horizontal, 11)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.activity")
            .accessibilityLabel("\(headline)，\(expanded ? "收起" : "展开")步骤")

            if expanded {
                Divider().padding(.horizontal, 11)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(activity.steps.enumerated()), id: \.element.id) { index, step in
                        ProcessStepRow(step: step, store: store)
                        if index < activity.steps.count - 1 {
                            Divider().padding(.leading, 34)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            if #available(iOS 26, *) {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.quaternary, lineWidth: 0.5)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var statusMark: some View {
        if isLive {
            ProgressView().controlSize(.mini)
        } else if activity.failedCount > 0 {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var headline: String {
        if isLive {
            return activity.steps.count == 1 ? "正在处理 1 个步骤" : "正在处理 \(activity.steps.count) 个步骤"
        }
        if activity.steps.count == 1, let tool = activity.steps.first?.tool, !tool.isEmpty {
            return tool
        }
        return activity.steps.count == 1 ? "已完成 1 个步骤" : "已完成 \(activity.steps.count) 个步骤"
    }

    private func durationLabel(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds) 秒" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes) 分" : "\(minutes) 分 \(remainder) 秒"
    }
}

private struct ProcessStepRow: View {
    let step: BridgeMessage
    let store: BridgeStore
    @State private var images: [UIImage] = []

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 15, height: 19)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let outcome = step.outcome {
                        Image(systemName: outcome ? "checkmark" : "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(outcome ? Color.secondary : Color.orange)
                    }
                    Spacer(minLength: 0)
                }
                if !step.text.isEmpty {
                    Text(step.text)
                        .font(.system(
                            size: 11.5,
                            design: step.kind == "tool" ? .monospaced : .default
                        ))
                        .lineSpacing(0)
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                }
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if step.imagesTruncated {
                    Text("部分图片尚未载入").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .task(id: "\(step.id)|\(step.imageCount)") {
            images = (0..<step.imageCount).compactMap { image in
                guard let encoded = store.runtime.messageImage(
                    index: Int32(step.index),
                    image: Int32(image)
                ), let bytes = Data(base64Encoded: encoded) else { return nil }
                return UIImage(data: bytes)
            }
        }
    }

    private var symbol: String {
        switch step.kind {
        case "thinking": "brain"
        case "tool": "terminal"
        default: "bolt"
        }
    }

    private var label: String {
        switch step.kind {
        case "thinking": "思考"
        case "tool": step.tool ?? "工具"
        default: step.tool ?? "自动执行"
        }
    }
}

private struct MessageContent: View {
    let message: BridgeMessage
    let store: BridgeStore
    let streaming: Bool
    @State private var images: [UIImage] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch message.kind {
            case "system":
                Label(message.text, systemImage: "info.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            default:
                if !message.text.isEmpty {
                    Text(renderedText)
                        .font(.system(size: 14))
                        .lineSpacing(1)
                        .textSelection(.enabled)
                        .foregroundStyle(message.kind == "error" ? Color.orange : Color.primary)
                        .padding(message.kind == "user" ? 11 : 0)
                        .background(
                            message.kind == "user"
                                ? Color(uiColor: .secondarySystemGroupedBackground)
                                : .clear,
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                }
            }
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            ForEach(message.files, id: \.self) {
                Label($0, systemImage: "doc").font(.caption).foregroundStyle(.secondary)
            }
            if message.imagesTruncated {
                Text("部分图片尚未载入，可在完整工具中查看。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if message.pending {
                Text("待确认送达").font(.caption2).foregroundStyle(.secondary)
            } else if message.delivered {
                Text("已送达电脑").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.kind == "user" ? .trailing : .leading)
        .task(id: "\(message.id)|\(message.imageCount)") {
            images = (0..<message.imageCount).compactMap { image in
                guard let encoded = store.runtime.messageImage(
                    index: Int32(message.index),
                    image: Int32(image)
                ), let bytes = Data(base64Encoded: encoded) else { return nil }
                return UIImage(data: bytes)
            }
        }
    }

    private var renderedText: AttributedString {
        var value = message.kind == "assistant"
            ? (try? AttributedString(
                markdown: message.text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(message.text)
            : AttributedString(message.text)
        if streaming {
            value.append(AttributedString(" ▍"))
        }
        return value
    }
}
