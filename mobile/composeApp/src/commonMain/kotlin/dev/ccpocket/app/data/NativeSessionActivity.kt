package dev.ccpocket.app.data

import dev.ccpocket.protocol.DirectoryEntry
import dev.ccpocket.protocol.ObservedEvidence
import dev.ccpocket.protocol.ObservedFreshness
import dev.ccpocket.protocol.ObservedProgress
import dev.ccpocket.protocol.ObservedStates

fun nativeObservedState(progress: ObservedProgress?): String? {
    if (progress?.evidence != ObservedEvidence.NATIVE_EVENT || progress.freshness == ObservedFreshness.UNAVAILABLE) return null
    return when (progress.state) {
        ObservedStates.IDLE, ObservedStates.FAILED, ObservedStates.CANCELLED -> progress.state
        ObservedStates.RUNNING, ObservedStates.WAITING_INPUT -> progress.state.takeIf { progress.freshness == ObservedFreshness.CURRENT }
        else -> null
    }
}

fun nativeSessionActivity(
    directories: List<DirectoryEntry>,
    currentSessionId: String? = null,
    currentStreaming: Boolean = false,
    observing: Boolean = false,
    observedProgress: ObservedProgress? = null,
): Map<String, Boolean>? {
    if (directories.isEmpty()) return null
    val sessions = directories.flatMap { it.activeSessions }
    if (sessions.isEmpty() && directories.any { it.open || it.activeSessionId != null }) return null
    return sessions.associate { session ->
        session.sessionId to if (session.sessionId == currentSessionId && !observing) {
            currentStreaming || session.busy
        } else {
            session.executing || session.busy
        }
    }.toMutableMap().apply {
        if (currentSessionId != null && !observing && currentSessionId !in this) {
            put(currentSessionId, currentStreaming)
        }
        if (currentSessionId != null && observing) {
            nativeObservedState(observedProgress)?.let { put(currentSessionId, it == ObservedStates.RUNNING) }
        }
    }
}
