package dev.ccpocket.daemon.session

import dev.ccpocket.daemon.codex.CodexDesktopBridge
import dev.ccpocket.daemon.codex.CodexDesktopIpc
import dev.ccpocket.daemon.conversation.ObserveSession
import dev.ccpocket.daemon.conversation.OutboundSink
import dev.ccpocket.daemon.disk.LiveProcesses
import dev.ccpocket.protocol.AgentKind
import dev.ccpocket.protocol.CancelTurn
import dev.ccpocket.protocol.Frame
import dev.ccpocket.protocol.ImageData
import dev.ccpocket.protocol.OpenSession
import dev.ccpocket.protocol.PocketError
import dev.ccpocket.protocol.PromptAck
import dev.ccpocket.protocol.SendPrompt
import dev.ccpocket.protocol.SessionLive
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.FileTime
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.io.path.appendText
import kotlin.io.path.writeText
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class SessionRegistryDesktopControlTest {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val tmp: Path = Files.createTempDirectory("ccp-desktop-control")
    private val workdir = tmp.resolve("project").also { Files.createDirectories(it) }.toString()
    private val sid = "01a1-${UUID.randomUUID()}"
    private val rollout = tmp.resolve("rollout-2026-11-16-$sid.jsonl")

    private class Capture : OutboundSink {
        val frames = CopyOnWriteArrayList<Frame>()
        override suspend fun emit(frame: Frame) { frames += frame }
    }

    private class FakeDesktop(
        private val supported: Boolean = true,
    ) : CodexDesktopBridge {
        val prompts = CopyOnWriteArrayList<Pair<String, String>>()
        val interrupts = CopyOnWriteArrayList<String>()
        var steered: String? = null

        override suspend fun owner(sessionId: String): CodexDesktopIpc.Owner? =
            CodexDesktopIpc.Owner("desktop-owner", supportsUntrustedAppInput = supported)

        override suspend fun startTurn(
            sessionId: String,
            text: String,
            images: List<ImageData>,
            clientUserMessageId: String,
        ): String {
            prompts += sessionId to text
            return "turn-phone"
        }

        override suspend fun steer(sessionId: String, text: String, clientUserMessageId: String) {
            steered = text
        }

        override suspend fun interrupt(sessionId: String, turnId: String) {
            interrupts += turnId
        }
    }

    private fun writeRollout() {
        rollout.writeText(
            """
            {"timestamp":"2026-11-16T01:00:00.000Z","type":"session_meta","payload":{"id":"$sid","cwd":"$workdir"}}
            {"timestamp":"2026-11-16T01:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-desktop"}}
            {"timestamp":"2026-11-16T01:00:02.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"desktop prompt"}]}}
            {"timestamp":"2026-11-16T01:00:03.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"desktop reply"}]}}
            {"timestamp":"2026-11-16T01:00:04.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-desktop"}}
            """.trimIndent() + "\n",
        )
        Files.setLastModifiedTime(rollout, FileTime.fromMillis(System.currentTimeMillis()))
    }

    private fun registry(desktop: CodexDesktopBridge) = SessionRegistry(
        scope,
        backends = emptyMap(),
        codexProcessProbe = { _, _ -> LiveProcesses.ExternalClaude.PRESENT },
        transcriptResolver = { agent, _, id -> if (agent == AgentKind.CODEX && id == sid) rollout else null },
        codexDesktop = desktop,
    )

    @AfterTest
    fun tearDown() {
        scope.cancel()
        tmp.toFile().deleteRecursively()
    }

    @Test
    fun explicit_takeover_uses_the_original_desktop_thread_without_creating_a_branch() = runBlocking {
        writeRollout()
        val desktop = FakeDesktop()
        val sink = Capture()
        val registry = registry(desktop)

        val convoId = registry.open(
            OpenSession(workdir, sid, agent = AgentKind.CODEX, takeOver = true, lastEventSeq = 0),
            sink,
            peerSupportsObservation = true,
        )

        assertTrue(convoId.isNotEmpty(), "${sink.frames}")
        assertFalse(registry.isLiveSession(sid), "the daemon must not start a second Codex writer")
        var live: SessionLive? = null
        withTimeout(3_000) {
            while (live?.observing != false) {
                live = sink.frames.filterIsInstance<SessionLive>().lastOrNull()
                if (live?.observing != false) delay(20)
            }
        }
        val announced = assertNotNull(live)
        assertEquals(sid, announced.sessionId)
        assertEquals(ObserveSession.SAME_THREAD_NOTICE, announced.notice)

        assertTrue(registry.sendPrompt(SendPrompt(convoId, "phone prompt", promptId = "prompt-1")))
        withTimeout(3_000) {
            while (sink.frames.none { it is PromptAck }) delay(20)
        }
        assertEquals(listOf(sid to "phone prompt"), desktop.prompts)

        registry.cancelTurn(CancelTurn(convoId))
        assertEquals(listOf("turn-phone"), desktop.interrupts)

        assertTrue(sink.frames.none { it is PocketError }, "${sink.frames}")
    }

    @Test
    fun a_desktop_owner_that_refuses_input_returns_an_error_instead_of_forking() = runBlocking {
        writeRollout()
        val desktop = FakeDesktop(supported = false)
        val sink = Capture()
        val registry = registry(desktop)

        val convoId = registry.open(
            OpenSession(workdir, sid, agent = AgentKind.CODEX, takeOver = true),
            sink,
        )

        assertEquals("", convoId)
        assertEquals(
            "desktop_control_unavailable",
            sink.frames.filterIsInstance<PocketError>().single().code,
        )
        assertTrue(desktop.prompts.isEmpty())
        assertFalse(registry.isLiveSession(sid))
    }

    @Test
    fun transcript_completion_clears_the_same_thread_running_state() = runBlocking {
        writeRollout()
        val desktop = FakeDesktop()
        val sink = Capture()
        val registry = registry(desktop)
        val convoId = registry.open(
            OpenSession(workdir, sid, agent = AgentKind.CODEX, takeOver = true, lastEventSeq = 0),
            sink,
            peerSupportsObservation = true,
        )
        withTimeout(3_000) {
            while (sink.frames.filterIsInstance<SessionLive>().none { it.observing == false }) delay(20)
        }

        assertTrue(registry.sendPrompt(SendPrompt(convoId, "start phone turn", promptId = "prompt-2")))
        withTimeout(3_000) {
            while (sink.frames.filterIsInstance<SessionLive>().lastOrNull()?.executing != true) delay(20)
        }
        rollout.appendText(
            """{"timestamp":"2026-11-16T01:10:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-phone"}}""" + "\n" +
                """{"timestamp":"2026-11-16T01:10:01.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"phone reply"}]}}""" + "\n",
        )
        Files.setLastModifiedTime(rollout, FileTime.fromMillis(System.currentTimeMillis()))
        withTimeout(5_000) {
            while (sink.frames.filterIsInstance<SessionLive>().lastOrNull()?.executing != true) delay(20)
        }
        rollout.appendText(
            """{"timestamp":"2026-11-16T01:10:02.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-phone"}}""" + "\n",
        )
        Files.setLastModifiedTime(rollout, FileTime.fromMillis(System.currentTimeMillis()))

        withTimeout(5_000) {
            while (sink.frames.filterIsInstance<SessionLive>().lastOrNull()?.executing != false) delay(20)
        }
    }
}
