package dev.ccpocket.app.data

import dev.ccpocket.protocol.ActiveSession
import dev.ccpocket.protocol.DirectoryEntry
import dev.ccpocket.protocol.SessionSummary
import dev.ccpocket.protocol.ObservedProgress
import dev.ccpocket.protocol.ObservedEvidence
import dev.ccpocket.protocol.ObservedFreshness
import dev.ccpocket.protocol.ObservedStates
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

class NativeSessionActivityTest {
    private fun directory(vararg sessions: ActiveSession) = DirectoryEntry(
        path = "/project", name = "project", isDir = true,
        open = sessions.isNotEmpty(), activeSessions = sessions.toList(),
    )

    @Test
    fun aFreshIdleSnapshotOverridesTheStillLiveCachedSession() {
        val cached = SessionSummary("s", "Task", "", 1, "/project", 0, live = true)
        val running = nativeSessionActivity(listOf(directory(ActiveSession("s", executing = true))))
        val settled = nativeSessionActivity(listOf(directory(ActiveSession("s"))))

        assertEquals(true, running?.get(cached.sessionId))
        assertEquals(false, settled?.get(cached.sessionId))
        assertEquals(true, cached.live)
    }

    @Test
    fun aFinishedOpenTurnOverridesAStaleDirectoryButBackgroundWorkRemainsActive() {
        val stale = listOf(directory(ActiveSession("s", executing = true)))
        assertEquals(false, nativeSessionActivity(stale, "s", currentStreaming = false)?.get("s"))
        val background = listOf(directory(ActiveSession("s", busy = true)))
        assertEquals(true, nativeSessionActivity(background, "s", currentStreaming = false)?.get("s"))
    }

    @Test
    fun anObservedChatCannotOverrideTheComputersActualTurnState() {
        val running = listOf(directory(ActiveSession("s", executing = true)))
        assertEquals(true, nativeSessionActivity(running, "s", currentStreaming = false, observing = true)?.get("s"))
        val settled = listOf(directory(ActiveSession("s")))
        assertEquals(false, nativeSessionActivity(settled, "s", currentStreaming = true, observing = true)?.get("s"))
    }

    @Test
    fun aNewOpenTurnAppearsBeforeTheNextDirectoryPoll() {
        val directory = listOf(directory())
        assertEquals(true, nativeSessionActivity(directory, "new", currentStreaming = true)?.get("new"))
        assertEquals(false, nativeSessionActivity(directory, "new", currentStreaming = false)?.get("new"))
    }

    @Test
    fun aDisappearedSessionDoesNotStayRunningAndDoesNotInventAnExplicitCompletion() {
        val next = nativeSessionActivity(listOf(directory()))
        assertFalse(next!!.containsKey("s"))
    }

    @Test
    fun unknownAndLegacySnapshotsPreserveTheFallbackInsteadOfClaimingEverythingIsIdle() {
        assertNull(nativeSessionActivity(emptyList()))
        val legacy = directory().copy(open = true, activeSessionId = "s", executing = true)
        assertNull(nativeSessionActivity(listOf(legacy)))
    }

    @Test
    fun eachWorkspaceContributesItsOwnActiveSessions() {
        val first = directory(ActiveSession("one", executing = true))
        val second = directory(ActiveSession("two")).copy(path = "/other")
        assertEquals(mapOf("one" to true, "two" to false), nativeSessionActivity(listOf(first, second)))
    }

    @Test
    fun anObservedNativeEndEventWinsBeforeTheNextDirectoryPoll() {
        val staleDirectory = listOf(directory(ActiveSession("s", executing = true)))
        val ended = ObservedProgress(state = ObservedStates.IDLE, evidence = ObservedEvidence.NATIVE_EVENT, freshness = ObservedFreshness.CURRENT)
        assertEquals(false, nativeSessionActivity(staleDirectory, "s", observing = true, observedProgress = ended)?.get("s"))
        assertEquals(ObservedStates.IDLE, nativeObservedState(ended.copy(freshness = ObservedFreshness.STALE)))
    }

    @Test
    fun staleRunningAndTranscriptRecencyCannotMasqueradeAsLiveTaskEvidence() {
        val running = ObservedProgress(state = ObservedStates.RUNNING, evidence = ObservedEvidence.NATIVE_EVENT, freshness = ObservedFreshness.CURRENT)
        assertEquals(ObservedStates.RUNNING, nativeObservedState(running))
        assertNull(nativeObservedState(running.copy(freshness = ObservedFreshness.STALE)))
        assertNull(nativeObservedState(running.copy(evidence = ObservedEvidence.TRANSCRIPT_ACTIVITY)))
        assertNull(nativeObservedState(running.copy(freshness = ObservedFreshness.UNAVAILABLE)))
    }
}
