import SwiftUI
import UserNotifications
import ComposeApp

struct NotificationRecord: Codable, Identifiable {
    let id: String
    let title: String
    let body: String
    let date: Date
    let path: String?
    let session: String?
    var read: Bool
}

@Observable
final class NotificationArchive {
    static let shared = NotificationArchive()
    private(set) var records: [NotificationRecord] = []
    private let key = "codebridge.notificationHistory.v2"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([NotificationRecord].self, from: data) { records = saved }
    }

    func record(_ notification: UNNotification, read: Bool = false) {
        let content = notification.request.content
        if let index = records.firstIndex(where: { $0.id == notification.request.identifier }) {
            records[index].read = records[index].read || read
        } else {
            records.insert(NotificationRecord(id: notification.request.identifier, title: content.title, body: content.body, date: notification.date, path: content.userInfo["wd"] as? String, session: content.userInfo["sid"] as? String, read: read), at: 0)
            records = Array(records.prefix(200))
        }
        save()
    }

    func markRead(_ id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].read = true
        save()
    }

    func markAllRead() {
        for index in records.indices { records[index].read = true }
        save()
    }

    func refresh() {
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            DispatchQueue.main.async { notifications.sorted { $0.date < $1.date }.forEach { self.record($0) } }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: key) }
    }
}

struct NotificationHome: View {
    let store: BridgeStore
    @State private var archive = NotificationArchive.shared

    var body: some View {
        NavigationStack {
            List {
                if let count = store.snapshot?.approvalCount, count > 0 {
                    Section("待处理") {
                        Button { store.sheet = .approvals } label: {
                            Label("\(count) 项等待审批或回答", systemImage: "hand.raised").foregroundStyle(.orange)
                        }
                    }
                }
                Section("通知") {
                    ForEach(archive.records) { record in
                        Button {
                            archive.markRead(record.id)
                            if let path = record.path, let session = record.session {
                                MainViewControllerKt.handlePushOpen(workdir: path, sessionId: session)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(record.read ? .clear : Color.accentColor).frame(width: 5, height: 5).padding(.top, 6)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(record.title).font(.system(size: 14, weight: .medium)); Spacer(); Text(record.date, style: .relative).font(.caption2).foregroundStyle(.tertiary) }
                                    Text(record.body).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }
                            }.padding(.vertical, 4)
                        }.buttonStyle(.plain)
                    }
                    if archive.records.isEmpty {
                        ContentUnavailableView("暂无通知", systemImage: "bell", description: Text("任务完成、异常和审批提醒会出现在这里。"))
                    }
                }
            }
            .navigationTitle("通知").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("全部已读") { archive.markAllRead() }.font(.caption) }
                ToolbarItem(placement: .topBarTrailing) { Button("通知设置", systemImage: "slider.horizontal.3") { store.sheet = .notifications } }
            }
            .task { archive.refresh(); store.runtime.refresh() }
        }
    }
}

struct NotificationSettings: View {
    let store: BridgeStore
    var body: some View {
        Form {
            Section {
                Toggle("消息通知", isOn: Binding(get: { store.snapshot?.notificationsOn ?? false }, set: { store.runtime.setNotifications(enabled: $0) }))
                    .accessibilityIdentifier("notifications.enabled")
                Text(pushStatus).font(.caption).foregroundStyle(.secondary)
                if ["FAILED", "PARTIAL", "UNCONFIRMED_LEGACY"].contains(store.snapshot?.pushStatus ?? "") {
                    Button("重试注册") { store.runtime.retryPush() }
                }
                Button("系统通知设置", systemImage: "arrow.up.forward.app") { store.runtime.openNotificationSettings() }
            }
            Section {
                Label("任务完成", systemImage: "checkmark.circle")
                Label("异常与停止", systemImage: "exclamationmark.circle")
                Label("额度限制", systemImage: "gauge.with.dots.needle.100percent")
                Label("权限审批", systemImage: "hand.raised")
            } header: { Text("通知内容") } footer: { Text("正在查看对应会话时抑制重复提醒。推送开关不改变会话中的审批要求。") }
        }.navigationTitle("通知设置").navigationBarTitleDisplayMode(.inline)
    }

    private var pushStatus: String {
        switch store.snapshot?.pushStatus {
        case "ENABLED": "推送已注册"
        case "PREPARING": "正在注册推送…"
        case "DENIED", "NEEDS_PERMISSION": "系统通知未允许，请前往系统设置开启。"
        case "FAILED": "注册失败，请重试。"
        case "PARTIAL": "部分电脑已注册，其他连接仍待确认。"
        case "OFF": "消息推送已关闭"
        default: "推送状态尚未确认"
        }
    }
}
