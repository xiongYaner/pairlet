import XCTest
@testable import CodeBridge

@MainActor
final class BridgeStoreReadStateTests: XCTestCase {
    private let session = BridgeSession(
        sessionId: "read-state-test", title: "Task", firstPrompt: "Test", messageCount: 1,
        cwd: "/unit-test", lastModified: 0, live: false, agent: "codex", group: nil
    )

    func testOpeningAnUnreadCompletionThenReturningClearsTheBadge() throws {
        let store = BridgeStore(observeRuntime: false)
        try applySnapshot(to: store, unread: [session.id])
        XCTAssertEqual(store.status(for: session).label, "完成")

        try applyChat(to: store, observedState: "idle")
        try applySnapshot(to: store, unread: [])
        store.chat = nil
        store.chatPresented = false

        XCTAssertEqual(store.status(for: session).label, "空闲")
    }

    func testRepeatedIdleObservationDoesNotRecreateAnUnreadResult() throws {
        let store = BridgeStore(observeRuntime: false)
        try applySnapshot(to: store, unread: [])
        try applyChat(to: store, observedState: "idle")
        try applyChat(to: store, observedState: "idle")
        store.chat = nil

        XCTAssertEqual(store.status(for: session).label, "空闲")
    }

    func testReplayingAnOldDoneMessageDoesNotCreateAnUnreadResult() throws {
        let store = BridgeStore(observeRuntime: false)
        try applySnapshot(to: store, unread: [])
        try applyChat(to: store, observing: false, messageKind: "done")
        try applyChat(to: store, observing: false, messageKind: "done")
        store.chat = nil

        XCTAssertEqual(store.status(for: session).label, "空闲")
    }

    func testTheNextRealCompletionCanBecomeUnreadAgain() throws {
        let store = BridgeStore(observeRuntime: false)
        try applySnapshot(to: store, unread: [session.id])
        try applyChat(to: store, observedState: "idle")
        try applySnapshot(to: store, unread: [])
        store.chat = nil
        XCTAssertEqual(store.status(for: session).label, "空闲")

        try applySnapshot(to: store, unread: [], running: true)
        XCTAssertEqual(store.status(for: session).label, "运行中")
        try applySnapshot(to: store, unread: [session.id])
        XCTAssertEqual(store.status(for: session).label, "完成")
    }

    func testReadingDoesNotHideRunningApprovalOrFailureStates() throws {
        let store = BridgeStore(observeRuntime: false)
        try applySnapshot(to: store, unread: [], running: true)
        XCTAssertEqual(store.status(for: session).label, "运行中")
        try applySnapshot(to: store, unread: [], running: true, attention: [session.id])
        XCTAssertEqual(store.status(for: session).label, "待确认")

        try applySnapshot(to: store, unread: [])
        try applyChat(to: store, observedState: "failed")
        XCTAssertEqual(store.status(for: session).label, "出错")
    }

    private func applySnapshot(to store: BridgeStore, unread: [String], running: Bool = false, attention: [String] = []) throws {
        let payload: [String: Any] = [
            "consented": true, "connected": true, "phase": "Ready", "demo": false, "paired": true,
            "pairing": false, "pairFailed": false, "machine": "Read state unit test", "machines": [],
            "agents": [], "defaultAgent": "codex", "directories": [], "directoriesLoaded": true,
            "sessions": [], "workspaceSessions": [:], "sessionsLoading": false, "groups": [],
            "streaming": false, "unread": unread, "runningSessions": running ? [session.id] : [],
            "sessionActivity": [session.id: running], "attentionSessions": attention,
            "notificationsOn": false, "pushStatus": "Off", "approvalCount": 0, "quotas": [],
            "usageFilterable": false, "defaults": [:],
        ]
        store.receive(try encoded(payload))
        XCTAssertNil(store.failure)
    }

    private func applyChat(to store: BridgeStore, observing: Bool = true, observedState: String? = nil, messageKind: String? = nil) throws {
        var payload: [String: Any] = [
            "convoId": "unit-convo", "sessionId": session.id, "agent": "codex", "thinkingSupported": false,
            "efforts": [], "models": [], "mode": "DEFAULT", "modes": [], "modeMutable": true,
            "streaming": false, "observing": observing, "opening": false, "connected": true,
            "hasMore": false, "loadingOlder": false, "hasAsk": false, "messages": [],
            "attachments": [], "attachmentsBusy": false, "voice": "idle", "voiceSeconds": 0,
            "voiceText": "", "micPermissionRequired": false,
        ]
        if let observedState { payload["observedState"] = observedState }
        if let messageKind {
            payload["messages"] = [[
                "id": 1, "index": 1, "kind": messageKind, "text": "Earlier result", "pending": false,
                "delivered": true, "imageCount": 0, "imagesTruncated": false, "files": [],
            ]]
        }
        store.receiveChat(try encoded(payload))
        XCTAssertNil(store.chatFailure)
    }

    private func encoded(_ payload: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
    }
}
