import XCTest
import UIKit

final class CodeBridgeUITests: XCTestCase {
    func testFirstRunDemoNavigation() throws {
        let app = XCUIApplication()
        enterDemo(app)
        keepScreenshot(app, name: "workspace-home")
        XCTAssertTrue(app.staticTexts["pairlet"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["设为默认"].exists)
        let runningSession = app.buttons["session.row.demo-live-0001"]
        XCTAssertTrue(runningSession.waitForExistence(timeout: 10))
        XCTAssertEqual(runningSession.value as? String, "运行中")

        let codex = app.buttons["agent.filter.codex"]
        XCTAssertTrue(codex.waitForExistence(timeout: 5))
        codex.tap()
        XCTAssertTrue(app.staticTexts["Codex 暂无工作区"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["pairlet"].exists)

        app.buttons["agent.filter.claude"].tap()
        XCTAssertTrue(app.staticTexts["pairlet"].firstMatch.waitForExistence(timeout: 5))

        app.tabBars.buttons["设置"].tap()
        app.buttons["Token 用量"].tap()
        XCTAssertTrue(app.navigationBars["Token 用量"].waitForExistence(timeout: 5))
    }

    func testAgentEnableToggle() throws {
        let app = XCUIApplication()
        enterDemo(app)
        let codexFilter = app.buttons["agent.filter.codex"]
        XCTAssertTrue(codexFilter.waitForExistence(timeout: 5))

        app.buttons["管理 Agent"].tap()
        XCTAssertTrue(app.navigationBars["Agent 管理"].waitForExistence(timeout: 5))
        keepScreenshot(app, name: "agent-management")
        app.buttons["排序"].tap()
        XCTAssertTrue(app.buttons["结束排序"].waitForExistence(timeout: 5))
        app.buttons["结束排序"].tap()
        let codexToggle = app.switches["agent.toggle.codex"]
        XCTAssertTrue(codexToggle.waitForExistence(timeout: 5))
        codexToggle.tap()
        app.buttons["完成"].tap()
        XCTAssertFalse(codexFilter.waitForExistence(timeout: 2))

        app.buttons["管理 Agent"].tap()
        let restoredToggle = app.switches["agent.toggle.codex"]
        XCTAssertTrue(restoredToggle.waitForExistence(timeout: 5))
        restoredToggle.tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(codexFilter.waitForExistence(timeout: 5))
    }

    func testCreateNativeChatSendAndOpenParameters() throws {
        let app = XCUIApplication()
        enterDemo(app)
        let newSession = app.buttons.matching(identifier: "workspace.newSession").firstMatch
        XCTAssertTrue(newSession.waitForExistence(timeout: 10))
        newSession.tap()
        let prompt = app.textFields["newSession.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("SwiftUI initial task")
        app.buttons["newSession.create"].tap()

        let input = app.textFields["chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15), "新建会话弹窗关闭后应打开原生对话")
        keepScreenshot(app, name: "native-chat")
        XCTAssertTrue(app.staticTexts["SwiftUI initial task"].waitForExistence(timeout: 10))
        let activity = app.buttons["chat.activity"].firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 10), "思考与工具步骤应归并为可折叠活动")
        activity.tap()
        XCTAssertTrue(app.staticTexts["思考"].firstMatch.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Native follow-up")
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.staticTexts["Native follow-up"].waitForExistence(timeout: 10))

        for (parameter, title) in [("model", "模型"), ("reasoning", "思考设置"), ("permission", "权限模式")] {
            app.buttons["chat.parameter.\(parameter)"].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            app.buttons["chat.panel.done"].tap()
        }
        XCTAssertTrue(app.buttons["chat.voice"].exists)
        app.buttons["chat.back"].tap()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 5))
    }

    func testNotificationAndStatisticsSurfaces() throws {
        let app = XCUIApplication()
        enterDemo(app)

        app.tabBars.buttons["通知"].tap()
        XCTAssertTrue(app.navigationBars["通知"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["全部已读"].exists)
        XCTAssertTrue(app.buttons["通知设置"].exists)
        app.buttons["通知设置"].tap()
        XCTAssertTrue(app.navigationBars["通知设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["notifications.enabled"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["任务完成"].exists)

        app.terminate()
        enterDemo(app)
        app.tabBars.buttons["设置"].tap()
        app.buttons["套餐额度"].tap()
        XCTAssertTrue(app.navigationBars["套餐额度"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["查看 Token 用量"].exists)

        app.terminate()
        enterDemo(app)
        app.tabBars.buttons["设置"].tap()
        app.buttons["Token 用量"].tap()
        XCTAssertTrue(app.navigationBars["Token 用量"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["今日"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["7 天"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["30 天"].exists)
    }

    func testLivePairingAndNativeTurnWhenProvisioned() throws {
        // simctl pbcopy can be cleared while XCUITest boots the runner. The simulator
        // launchd environment survives that transition and also keeps the pairing code
        // out of test source, so prefer it when the release smoke run provides it.
        let raw = ProcessInfo.processInfo.environment["CODEBRIDGE_LIVE_TEST_CONFIG"]
            ?? (UIPasteboard.general.string ?? "")
        guard let data = raw.data(using: .utf8),
              let config = try? JSONDecoder().decode(LiveTestConfig.self, from: data),
              config.pairCode.count == 6 else {
            throw XCTSkip("Set the simulator pasteboard to a live-test JSON document before running this test.")
        }

        let app = XCUIApplication()
        app.launch()
        if app.buttons["consent.accept"].waitForExistence(timeout: 10) {
            app.buttons["consent.accept"].tap()
        }

        let code = app.textFields["pairing.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        code.tap()
        code.typeText(config.pairCode)
        app.buttons["配对电脑"].tap()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 45), "真实配对未完成")
        keepScreenshot(app, name: "live-paired-home")

        let newSession = app.buttons["home.newSession"]
        XCTAssertTrue(newSession.waitForExistence(timeout: 15))
        newSession.tap()
        let path = app.textFields["newSession.path"]
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        path.tap()
        path.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) {
            app.menuItems["Select All"].tap()
        } else if app.menuItems["全选"].waitForExistence(timeout: 2) {
            app.menuItems["全选"].tap()
        }
        path.typeText(config.workdir)

        let prompt = app.textFields["newSession.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText(LiveTestConfig.prompt)

        let agent = app.descendants(matching: .any)["newSession.agent"]
        XCTAssertTrue(agent.waitForExistence(timeout: 5))
        agent.tap()
        let codex = app.collectionViews.buttons["Codex"].firstMatch
        XCTAssertTrue(codex.waitForExistence(timeout: 5), "Agent picker should expose Codex")
        codex.tap()

        app.buttons["newSession.create"].tap()

        let input = app.textFields["chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 20), "真实配对后未打开新会话")
        XCTAssertTrue(app.staticTexts["PAIRLET_SWIFTUI_SMOKE_OK"].waitForExistence(timeout: 120), "真实 Agent 未返回")
        keepScreenshot(app, name: "live-native-turn")
    }

    func testLiveObservationExplainsReadOnlyAndConfirmsTakeoverWhenProvisioned() throws {
        let raw = ProcessInfo.processInfo.environment["CODEBRIDGE_LIVE_TEST_CONFIG"] ?? ""
        guard let data = raw.data(using: .utf8),
              let config = try? JSONDecoder().decode(LiveTestConfig.self, from: data),
              let observedSessionId = config.observedSessionId else {
            throw XCTSkip("Provide an active external session for the observation smoke test.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        if app.buttons["consent.accept"].waitForExistence(timeout: 10) { app.buttons["consent.accept"].tap() }
        let code = app.textFields["pairing.code"]
        if code.waitForExistence(timeout: 5) {
            code.tap()
            code.typeText(config.pairCode)
            app.buttons["配对电脑"].tap()
        }
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 45))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let denyNotifications = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Don't Allow", "Don’t Allow", "不允许"])).firstMatch
        if denyNotifications.waitForExistence(timeout: 3) { denyNotifications.tap() }
        var route = URLComponents()
        route.scheme = "ccpocket"
        route.host = "session"
        route.queryItems = [URLQueryItem(name: "wd", value: config.workdir), URLQueryItem(name: "sid", value: observedSessionId)]
        app.open(try XCTUnwrap(route.url))
        let notice = app.descendants(matching: .any)["chat.observation.notice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 30))
        XCTAssertFalse(app.textFields["chat.input"].exists)
        keepScreenshot(app, name: "observation-read-only")
        app.buttons["chat.takeover"].tap()
        let confirmation = app.alerts["接管这个 Codex 会话？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "同一个会话")).firstMatch.exists)
        XCTAssertTrue(confirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "不会创建分支")).firstMatch.exists)
        keepScreenshot(app, name: "takeover-confirmation")
        confirmation.buttons["取消"].tap()
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        app.buttons["chat.back"].tap()
        app.terminate()
    }

    private func enterDemo(_ app: XCUIApplication) {
        continueAfterFailure = false
        app.launch()
        if app.buttons["consent.accept"].waitForExistence(timeout: 10) { app.buttons["consent.accept"].tap() }
        if app.buttons["pairing.demo"].waitForExistence(timeout: 5) { app.buttons["pairing.demo"].tap() }
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 15))
    }

    private func keepScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct LiveTestConfig: Decodable {
    let pairCode: String
    let workdir: String
    let observedSessionId: String?

    static let prompt = "Reply with exactly PAIRLET_SWIFTUI_SMOKE_OK and do not use any tools."
}
