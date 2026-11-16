package dev.ccpocket.app

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.Modifier
import androidx.compose.ui.uikit.OnFocusBehavior
import androidx.compose.ui.window.ComposeUIViewController
import dev.ccpocket.app.data.FleetCoordinator
import dev.ccpocket.app.data.FleetRuntime
import dev.ccpocket.app.data.PocketRepository
import dev.ccpocket.app.data.ChatItem
import dev.ccpocket.app.data.ConnPhase
import dev.ccpocket.app.data.ClaudeQuotaRefreshPolicy
import dev.ccpocket.app.data.QuotaRefreshTrigger
import dev.ccpocket.app.data.nativeChatMessages
import dev.ccpocket.app.data.nativeSessionActivity
import dev.ccpocket.app.data.nativeObservedState
import dev.ccpocket.app.data.runningSessions
import dev.ccpocket.app.data.VoiceState
import dev.ccpocket.app.media.PickedFile
import dev.ccpocket.app.push.ForegroundSession
import dev.ccpocket.app.push.foregroundSessionOf
import dev.ccpocket.app.pairing.displayName
import dev.ccpocket.app.theme.PocketTheme
import dev.ccpocket.app.ui.ChatScreen
import dev.ccpocket.app.ui.RepoSecureApprovalSheet
import dev.ccpocket.app.ui.SettingsScreen
import dev.ccpocket.app.ui.entry.agentModeChoices
import dev.ccpocket.app.ui.approval.ProvideApprovalArrivalGuard
import dev.ccpocket.app.ui.fleet.AttentionInboxScreen
import dev.ccpocket.protocol.AgentKind
import dev.ccpocket.protocol.PermissionMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import androidx.compose.runtime.mutableStateOf
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import platform.Foundation.NSData
import platform.posix.memcpy
import kotlin.io.encoding.Base64
import platform.UIKit.UIViewController

class CodeBridgeRuntime {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val repo = PocketRepository(scope)
    private val fleet = FleetCoordinator(scope, repo)
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = true }
    private val writes = Snapshot.registerGlobalWriteObserver {
        scope.launch { Snapshot.sendApplyNotifications() }
    }
    private var observer: ((String) -> Unit)? = null
    private var chatObserver: ((String) -> Unit)? = null
    private var launched = false
    private val isForeground = mutableStateOf(true)
    private val quotaPolicy = ClaudeQuotaRefreshPolicy(now = { epochMillis() }, fetch = { repo.fetchAllQuotas(it) })
    private var chatOffset = 0
    private var chatPrepend = 0
    private var chatWindow = 0
    private var projectedConvo: String? = null

    init {
        FleetRuntime.coordinator = fleet
        fleet.start()
        scope.launch { snapshotFlow { snapshot() }.collect { observer?.invoke(it) } }
        scope.launch { repo.pushStatus.collect { observer?.invoke(snapshot()) } }
        scope.launch { snapshotFlow { chatSnapshot() }.collect { chatObserver?.invoke(it) } }
        scope.launch {
            snapshotFlow { foregroundSessionOf(repo.sessionKey.value, repo.convoId.value, repo.connected.value && isForeground.value) }
                .collect { ForegroundSession.update(it) }
        }
        repo.onClaudeQuotaReply = { quotaPolicy.replied() }
        scope.launch {
            snapshotFlow { repo.phase.value == ConnPhase.Ready && repo.privacyConsented.value && isForeground.value }
                .collectLatest { ready ->
                    if (!ready) { quotaPolicy.reset(); return@collectLatest }
                    quotaPolicy.event(QuotaRefreshTrigger.CONNECTED)
                    var ticks = 0
                    while (true) {
                        fleet.repos().forEach { it.refreshPendingApprovals() }
                        if (ticks % 4 == 0 && (!repo.streaming.value || repo.observing.value)) {
                            repo.refreshDirectoriesSilently()
                            repo.refreshLoadedWorkspaceSessions()
                        }
                        quotaPolicy.snapshotFetchedAt(repo.quotaByAgent.values.mapNotNull { it.fetchedAt.takeIf { time -> time > 0 } }.minOrNull())
                        quotaPolicy.tick()
                        ticks++
                        delay(3_000)
                    }
                }
        }
        scope.launch {
            snapshotFlow { repo.turnCompletions.value }.collect {
                if (it > 0) {
                    quotaPolicy.event(QuotaRefreshTrigger.TURN_DONE)
                    if (isForeground.value) {
                        repo.refreshDirectoriesSilently()
                        repo.refreshLoadedWorkspaceSessions(repo.workdir.value)
                    }
                }
            }
        }
        scope.launch {
            snapshotFlow { repo.privacyConsented.value }.collectLatest { consented ->
                if (!consented) return@collectLatest
                if (!launched) {
                    launched = true
                    if (repo.paired.value != null) repo.startRelay()
                }
                launch {
                    DeepLink.pending.filterNotNull().collect { link ->
                        repo.handleIncomingLink(link)
                        DeepLink.pending.value = null
                    }
                }
                launch {
                    PushRoute.pending.filterNotNull().collect { route ->
                        repo.requestOpenSession(route.workdir, route.sessionId, route.title, route.agent)
                        PushRoute.pending.value = null
                    }
                }
            }
        }
    }

    fun observe(callback: (String) -> Unit) {
        observer = callback
        callback(snapshot())
    }

    fun observeChat(callback: (String) -> Unit) {
        chatObserver = callback
        callback(chatSnapshot())
    }

    fun chatSnapshot(): String {
        val convo = repo.convoId.value
        val messages = repo.messages.toList()
        val prepend = repo.historyPrependGen.value
        val window = repo.historyWindowGen.value
        if (convo != projectedConvo || window != chatWindow) {
            chatOffset = 0; chatPrepend = prepend; projectedConvo = convo; chatWindow = window
        }
        if (prepend != chatPrepend) { chatOffset -= repo.lastHistoryPrependCount; chatPrepend = prepend }
        val agent = repo.sessionAgent.value ?: repo.sessionDefaultAgent
        return buildJsonObject {
            put("convoId", convo)
            put("sessionId", repo.sessionKey.value)
            put("agent", agent.name.lowercase())
            put("title", repo.chatTitle.value)
            put("workdir", repo.workdir.value)
            put("model", repo.model.value)
            put("effort", repo.effort.value)
            put("thinking", repo.thinking.value)
            put("thinkingSupported", repo.supportsThinkingToggle(agent))
            put("efforts", json.encodeToJsonElement(repo.effortOptions(agent)))
            put("models", json.encodeToJsonElement(repo.modelListFor(agent)?.models.orEmpty()))
            put("mode", repo.permissionMode.value ?: repo.mode.value.name)
            put("modes", JsonArray(modeChoices(agent).map { choice ->
                val preset = repo.modePresetsFor(agent).firstOrNull { it.mode == choice.mode }
                buildJsonObject {
                    put("id", choice.nativeMode ?: choice.mode.name)
                    put("mode", choice.nativeMode ?: choice.mode.name)
                    put("label", preset?.label ?: when {
                        choice.nativeMode != null -> "自动判断"
                        agent == AgentKind.OPENCODE -> "自动执行"
                        agent == AgentKind.CODEX -> when (choice.mode) {
                            PermissionMode.PLAN -> "谨慎"
                            PermissionMode.DEFAULT -> "均衡"
                            PermissionMode.ACCEPT_EDITS -> "自主执行"
                            PermissionMode.BYPASS_PERMISSIONS -> "完全访问"
                        }
                        else -> when (choice.mode) {
                            PermissionMode.DEFAULT -> "每步询问"
                            PermissionMode.ACCEPT_EDITS -> "自动改文件"
                            PermissionMode.PLAN -> "计划"
                            PermissionMode.BYPASS_PERMISSIONS -> "完全访问"
                        }
                    })
                    put("detail", preset?.detail)
                    put("danger", choice.danger)
                    put("recommended", preset?.recommended ?: false)
                }
            }))
            put("modeMutable", agent != AgentKind.DSH && agent != AgentKind.OPENCODE)
            put("contextUsed", repo.contextUsed.value)
            put("contextWindow", repo.contextWindow.value)
            put("streaming", repo.streaming.value)
            put("observing", repo.observing.value)
            put("observationReadOnly", repo.observationReadOnly())
            put("observedState", nativeObservedState(repo.sessionObservation.value?.progress))
            put("opening", repo.opening.value)
            put("connected", repo.connected.value)
            put("hasMore", repo.historyHasMore.value)
            put("loadingOlder", repo.historyLoadingOlder.value)
            put("hasAsk", repo.pendingAsk.value != null)
            put("messages", json.encodeToJsonElement(nativeChatMessages(messages, chatOffset)))
            put("attachments", JsonArray(
                repo.pendingFiles.map { file -> buildJsonObject {
                    put("id", file.id); put("name", file.name); put("state", file.state.name); put("image", false)
                } } + repo.pendingImages.map { photo -> buildJsonObject {
                    put("id", photo.id); put("name", "图片"); put("state", photo.state.name); put("image", true)
                } }
            ))
            put("attachmentsBusy", repo.uploadsBusy() || repo.imagesCompressing())
            val voice = repo.voice.value
            put("voice", when (voice) {
                VoiceState.Idle -> "idle"
                is VoiceState.Recording -> "recording"
                VoiceState.Transcribing -> "transcribing"
                VoiceState.StillWaiting -> "waiting"
                is VoiceState.Refining -> "refining"
                is VoiceState.Preview -> "preview"
                is VoiceState.Failed -> "failed"
            })
            put("voiceSeconds", (voice as? VoiceState.Recording)?.elapsedMs?.div(1_000) ?: 0)
            put("voiceText", repo.liveFinal.value + repo.livePartial.value)
            put("voiceFailure", (voice as? VoiceState.Failed)?.let { it.detail ?: "语音输入失败，请重试。" })
            put("voiceTranscript", repo.pendingVoiceText.value)
            put("micPermissionRequired", repo.micPermissionSheet.value)
        }.toString()
    }

    fun snapshot(): String = buildJsonObject {
        put("consented", repo.privacyConsented.value)
        put("connected", repo.connected.value)
        put("phase", repo.phase.value.name)
        put("demo", repo.demoMode.value)
        put("paired", repo.paired.value != null)
        put("pairing", repo.pairVerifying.value)
        put("pairFailed", repo.pairFailure.value != null)
        put("machine", repo.paired.value?.displayName() ?: if (repo.demoMode.value) "演示电脑" else "未连接电脑")
        put("machines", JsonArray(repo.pairedList.map { binding ->
            buildJsonObject {
                put("id", binding.accountId)
                put("name", binding.displayName())
                put("active", binding.accountId == repo.paired.value?.accountId)
                put("connected", fleet.repoFor(binding.accountId)?.connected?.value == true)
            }
        }))
        put("agents", JsonArray(repo.availableAgents.map { JsonPrimitive(it.name.lowercase()) }))
        put("defaultAgent", repo.defaultAgent.value.name.lowercase())
        put("directories", json.encodeToJsonElement(repo.directories.toList()))
        put("directoriesLoaded", repo.directoriesLoaded.value)
        put("sessions", json.encodeToJsonElement(repo.sessions.toList()))
        put("workspaceSessions", json.encodeToJsonElement(repo.workspaceSessions.toMap()))
        put("sessionsDir", repo.sessionsDir.value)
        put("sessionsLoading", repo.sessionsOpening.value != null)
        put("groups", json.encodeToJsonElement(repo.sessionGroups.toList()))
        put("chatId", repo.convoId.value)
        put("chatTitle", repo.chatTitle.value)
        put("workdir", repo.workdir.value)
        put("streaming", repo.streaming.value)
        put("sessionActivity", nativeSessionActivity(
            repo.directories.toList(), repo.sessionKey.value.takeIf { repo.convoId.value != null },
            repo.streaming.value, repo.observing.value, repo.sessionObservation.value?.progress,
        )?.let { json.encodeToJsonElement(it) } ?: JsonNull)
        put("unread", JsonArray(repo.unseenSessions.value.map(::JsonPrimitive)))
        put("runningSessions", JsonArray(
            runningSessions(repo.directories.toList())
                .filter { it.executing }
                .map { it.sessionId }
                .distinct()
                .map(::JsonPrimitive),
        ))
        put("attentionSessions", JsonArray(
            (repo.pendingApprovals.values.map { it.ask.convoId } + listOfNotNull(repo.pendingAsk.value?.convoId))
                .distinct()
                .map(::JsonPrimitive),
        ))
        put("notificationsOn", repo.notificationsOn.value)
        put("pushStatus", repo.pushStatus.value.name)
        put("approvals", json.encodeToJsonElement(repo.pendingApprovals.values.toList()))
        put("approvalCount", repo.pendingApprovals.size)
        put("quotas", json.encodeToJsonElement(repo.quotaByAgent.values.toList()))
        put("usage", repo.usage.value?.let { json.encodeToJsonElement(it) } ?: JsonNull)
        put("usageAgent", repo.usageAgent.value?.name?.lowercase())
        put("usageFilterable", repo.daemonUsageAgentFilter.value)
        put("defaults", buildJsonObject {
            repo.availableAgents.forEach { agent ->
                put(agent.name.lowercase(), buildJsonObject {
                    put("model", repo.defaultModelFor(agent))
                    put("effort", repo.defaultEffortFor(agent))
                    put("models", json.encodeToJsonElement(repo.modelListFor(agent)?.models.orEmpty()))
                    put("efforts", json.encodeToJsonElement(repo.effortOptions(agent)))
                })
            }
        })
    }.toString()

    fun acceptConsent() = repo.acceptPrivacyConsent()
    fun enterDemo() { if (repo.privacyConsented.value) repo.enterDemo() }
    fun pair(code: String) { if (repo.privacyConsented.value) repo.pairWithCode(code) }
    fun pairLink(link: String) { if (repo.privacyConsented.value) repo.handleIncomingLink(link) }
    fun selectMachine(id: String) { repo.pairedList.firstOrNull { it.accountId == id }?.let(fleet::switchTo) }
    fun listSessions(path: String) { repo.listSessions(path) }
    fun loadWorkspace(path: String) = repo.refreshWorkspaceSessions(path)
    fun refresh() {
        repo.refreshDirectories()
        repo.refreshLoadedWorkspaceSessions()
        repo.refreshPendingApprovals()
        repo.fetchAllQuotas()
    }
    fun refreshQuota() = repo.fetchAllQuotas(forceRefresh = true)
    fun fetchUsage(days: Int, agent: String) = repo.fetchUsage(days, agentKind(agent))
    fun defaultAgent(agent: String) { agentKind(agent)?.let(repo::setDefaultAgent) }
    fun defaultModel(agent: String, model: String?) { agentKind(agent)?.let { repo.setDefaultModelFor(it, model) } }
    fun defaultEffort(agent: String, effort: String?) { agentKind(agent)?.let { repo.setDefaultEffortFor(it, effort) } }
    fun fetchModels(agent: String) { agentKind(agent)?.let { repo.refreshModels(it) } }
    fun setNotifications(enabled: Boolean) = repo.setNotificationsEnabled(enabled)
    fun retryPush() = repo.retryPushRegistration()
    fun openNotificationSettings() = repo.openNotificationSettings()
    fun openSession(path: String, sessionId: String?, agent: String, title: String?) {
        repo.openSession(path, resumeId = sessionId, agent = agentKind(agent), title = title)
    }
    fun startTask(path: String, prompt: String, agent: String, model: String?): Boolean =
        agentKind(agent)?.let { repo.startTaskWithPrompt(path, prompt, it, model = model) } ?: false
    fun leaveChat() {
        val path = repo.workdir.value
        repo.backToBrowse()
        repo.refreshLoadedWorkspaceSessions(path)
    }
    fun sendPrompt(text: String): Boolean = repo.sendPrompt(text)
    fun cancelTurn() = repo.cancelTurn()
    fun takeOver(): Boolean {
        if (!repo.connected.value || !repo.observing.value || repo.opening.value || repo.observationReadOnly() || repo.daemonControlsBlocked) return false
        repo.takeOver()
        return true
    }
    fun loadOlder() = repo.loadOlderHistory()
    fun draft(): String = repo.draftFor(repo.composerKey())
    fun saveDraft(text: String) = repo.saveDraft(repo.composerKey(), text)
    fun startVoice() = repo.startVoice()
    fun finishVoice() = repo.stopVoice()
    fun cancelVoice() = repo.cancelVoice()
    fun retryVoice() = repo.retryVoice()
    fun takeVoiceText(): String? = repo.pendingVoiceText.value.also { repo.pendingVoiceText.value = null }
    fun dismissMicPermission() { repo.micPermissionSheet.value = false }
    fun switchModel(model: String) = repo.switchModel(model)
    fun switchEffort(effort: String?) {
        if (effort == null || effort in repo.effortOptions()) repo.switchEffort(effort)
    }
    fun switchThinking(thinking: Boolean?) {
        if (repo.supportsThinkingToggle()) repo.switchThinking(thinking)
    }
    fun switchMode(id: String): Boolean {
        val agent = repo.sessionAgent.value ?: repo.sessionDefaultAgent
        if (agent == AgentKind.DSH || agent == AgentKind.OPENCODE) return false
        val choice = modeChoices(agent).firstOrNull { (it.nativeMode ?: it.mode.name) == id } ?: return false
        repo.switchMode(choice.mode, choice.nativeMode)
        return true
    }
    private fun modeChoices(agent: AgentKind) = agentModeChoices(
        agent, repo.supportsPermissionMode("auto", agent), repo.modePresetsFor(agent),
    )
    fun removeAttachment(id: Long, image: Boolean) {
        if (image) repo.removePendingImage(id) else repo.removePendingFile(id)
    }
    @OptIn(ExperimentalForeignApi::class)
    fun attachImage(data: NSData): Boolean {
        if (data.length == 0uL || data.length > 20uL * 1024uL * 1024uL) return false
        val bytes = ByteArray(data.length.toInt())
        bytes.usePinned { memcpy(it.addressOf(0), data.bytes, data.length) }
        repo.attachImages(listOf(bytes))
        return true
    }
    @OptIn(ExperimentalForeignApi::class)
    fun attachFile(name: String, data: NSData, mediaType: String): Boolean {
        if (data.length > 20uL * 1024uL * 1024uL) return false
        val bytes = ByteArray(data.length.toInt())
        if (bytes.isNotEmpty()) bytes.usePinned { memcpy(it.addressOf(0), data.bytes, data.length) }
        repo.attachFiles(listOf(PickedFile(name, data.length.toLong(), bytes, mediaType)))
        return true
    }
    fun messageImage(index: Int, image: Int): String? {
        val bytes = when (val row = repo.messages.getOrNull(index)) {
            is ChatItem.User -> row.images.getOrNull(image)
            is ChatItem.Tool -> row.images.getOrNull(image)
            else -> null
        } ?: return null
        return Base64.Default.encode(bytes)
    }
    fun createGroup(name: String, path: String) = repo.createGroup(name, path)
    fun renameGroup(id: String, name: String, path: String) = repo.renameGroup(id, name, path)
    fun deleteGroup(id: String, path: String) = repo.deleteGroup(id, path)
    fun assignGroup(sessionId: String, groupId: String?, path: String) = repo.assignGroup(sessionId, groupId, path)
    fun foreground() { isForeground.value = true; if (repo.privacyConsented.value) { fleet.onAppForeground(); repo.refreshPendingApprovals() } }
    fun background() { isForeground.value = false; fleet.onAppBackground() }

    fun contentController(screen: String, onClose: () -> Unit): UIViewController = ComposeUIViewController(configure = {
        onFocusBehavior = OnFocusBehavior.DoNothing
    }) {
        PocketTheme(mode = repo.themeMode.value, accent = repo.accentTheme.value, fontScale = repo.fontScale.value) {
            ProvideApprovalArrivalGuard(repo) {
                Box(Modifier.fillMaxSize().imePadding()) {
                    when (screen) {
                        "settings" -> SettingsScreen(repo, onClose)
                        "approvals" -> AttentionInboxScreen(repo, onClose)
                        else -> ChatScreen(repo)
                    }
                    repo.pendingAsk.value?.takeIf { it.questions == null }?.let { RepoSecureApprovalSheet(repo, it) }
                }
            }
        }
    }

    fun close() {
        observer = null
        chatObserver = null
        ForegroundSession.update(null)
        writes.dispose()
        fleet.repos().forEach { it.disconnect() }
        scope.cancel()
    }

    private fun agentKind(value: String): AgentKind? = AgentKind.entries.firstOrNull { it.name.equals(value, true) }
}
