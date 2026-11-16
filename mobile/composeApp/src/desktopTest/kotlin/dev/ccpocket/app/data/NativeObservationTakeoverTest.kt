package dev.ccpocket.app.data

import dev.ccpocket.protocol.AgentKind
import dev.ccpocket.protocol.CloseSession
import dev.ccpocket.protocol.Frame
import dev.ccpocket.protocol.ObservedEvidence
import dev.ccpocket.protocol.ObservedFreshness
import dev.ccpocket.protocol.ObservedProgress
import dev.ccpocket.protocol.ObservedStates
import dev.ccpocket.protocol.OpenSession
import dev.ccpocket.protocol.SendPrompt
import dev.ccpocket.protocol.SessionObservation
import dev.ccpocket.protocol.SessionLive
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NativeObservationTakeoverTest {
    @Test
    fun aConfirmedTakeoverContinuesTheOriginalThreadAndKeepsItsLiveProgress() {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val frames = mutableListOf<Frame>()
        val repo = PocketRepository(scope).apply {
            sessionActive.value = true
            connected.value = true
            onSendForTest = { frames += it }
        }
        try {
            repo.receiveForTest(SessionLive(
                "native-observer", "/native-takeover-test", "native-parent",
                observing = true, agent = AgentKind.CODEX,
            ))
            frames.clear()
            repo.takeOver()
            assertEquals("native-observer", frames.filterIsInstance<CloseSession>().single().convoId)
            val request = frames.filterIsInstance<OpenSession>().single()
            assertTrue(request.takeOver)
            assertEquals("native-parent", request.resumeId)

            repo.receiveForTest(SessionLive(
                "native-control", "/native-takeover-test", "native-parent",
                executing = false, agent = AgentKind.CODEX,
            ))
            val running = SessionObservation(
                progress = ObservedProgress(
                    state = ObservedStates.RUNNING,
                    evidence = ObservedEvidence.NATIVE_EVENT,
                    freshness = ObservedFreshness.CURRENT,
                    turnId = "turn-phone",
                ),
            )
            repo.receiveForTest(SessionLive(
                "native-control", "/native-takeover-test", "native-parent",
                executing = true, agent = AgentKind.CODEX, observation = running,
            ))
            assertFalse(repo.observing.value)
            assertEquals("native-parent", repo.sessionKey.value)
            assertEquals(running, repo.sessionObservation.value)
            assertTrue(repo.streaming.value)
            assertTrue(repo.sendPrompt("Continue the isolated test"))
            assertEquals("native-control", frames.filterIsInstance<SendPrompt>().single().convoId)
        } finally {
            scope.cancel()
        }
    }
}
