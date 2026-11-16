package dev.ccpocket.app.data

import dev.ccpocket.app.pairing.PairedDaemon
import dev.ccpocket.protocol.Frame
import dev.ccpocket.protocol.ListSessions
import dev.ccpocket.protocol.SessionSummary
import dev.ccpocket.protocol.Sessions
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class WorkspaceSessionsTest {
    @Test
    fun nativeCatalogRefreshFindsNewChatsWithoutRemountingWorkspaceCards() = runTest {
        val sent = mutableListOf<Frame>()
        val repo = PocketRepository(backgroundScope).apply {
            sessionActive.value = true
            onSendForTest = { sent += it }
        }
        val old = SessionSummary("old", "Old", "", 1, "/one", 0)
        repo.refreshWorkspaceSessions("/one")
        runCurrent()
        repo.receiveForTest(Sessions("/one", listOf(old)))
        sent.clear()

        repo.refreshLoadedWorkspaceSessions("/new-project")
        repo.refreshLoadedWorkspaceSessions("/new-project")
        runCurrent()
        assertEquals(setOf("/one", "/new-project"), sent.filterIsInstance<ListSessions>().map { it.workdir }.toSet())
        assertEquals(2, sent.filterIsInstance<ListSessions>().size)
        val added = old.copy(sessionId = "new", title = "New")
        repo.receiveForTest(Sessions("/one", listOf(added, old)))
        assertEquals(listOf(added, old), repo.workspaceSessions["/one"])
        assertNull(repo.sessionsDir.value)
    }

    @Test
    fun backgroundListsPopulateMultipleWorkspacesWithoutChangingBrowseRoute() = runTest {
        val sent = mutableListOf<Frame>()
        val repo = PocketRepository(backgroundScope).apply {
            sessionActive.value = true
            onSendForTest = { sent += it }
        }
        repo.refreshWorkspaceSessions("/one")
        repo.refreshWorkspaceSessions("/two")
        repo.refreshWorkspaceSessions("/one")
        runCurrent()
        assertEquals(listOf("/one", "/two"), sent.filterIsInstance<ListSessions>().map { it.workdir })

        val one = SessionSummary("s1", "One", "", 1, "/one", 0)
        val two = SessionSummary("s2", "Two", "", 1, "/two", 0)
        repo.receiveForTest(Sessions("/two", listOf(two)))
        repo.receiveForTest(Sessions("/one", listOf(one, one)))

        assertEquals(listOf(one), repo.workspaceSessions["/one"])
        assertEquals(listOf(two), repo.workspaceSessions["/two"])
        assertNull(repo.sessionsDir.value)
        assertTrue(repo.sessions.isEmpty())
    }

    @Test
    fun disconnectDropsWorkspaceDataAndPendingRequests() = runTest {
        val sent = mutableListOf<Frame>()
        val repo = PocketRepository(backgroundScope).apply {
            sessionActive.value = true
            paired.value = PairedDaemon("wss://test", "workspace-test", "pk", "dev", "cred")
            onSendForTest = { sent += it }
        }
        repo.refreshWorkspaceSessions("/one")
        repo.disconnect()
        runCurrent()
        assertTrue(sent.filterIsInstance<ListSessions>().isEmpty())
        repo.receiveForTest(Sessions("/one", listOf(SessionSummary("s1", "One", "", 1, "/one", 0))))
        assertTrue(repo.workspaceSessions.isEmpty())
        assertNull(repo.sessionsDir.value)
    }
}
