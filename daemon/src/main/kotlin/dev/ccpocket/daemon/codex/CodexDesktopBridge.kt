package dev.ccpocket.daemon.codex

import dev.ccpocket.protocol.ImageData
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

/**
 * The part of the installed Codex app's local IPC needed to turn a read-only
 * observation into same-thread control.
 *
 * The Desktop remains the owner and writer. These calls are forwarded to it;
 * the daemon never starts a second app-server or asks the desktop thread to
 * fork.
 */
interface CodexDesktopBridge {
    suspend fun owner(sessionId: String): CodexDesktopIpc.Owner?

    /** Returns the Desktop's accepted turn id when the response includes one. */
    suspend fun startTurn(
        sessionId: String,
        text: String,
        images: List<ImageData>,
        clientUserMessageId: String,
    ): String?

    suspend fun steer(sessionId: String, text: String, clientUserMessageId: String)

    suspend fun interrupt(sessionId: String, turnId: String)
}

class IpcCodexDesktopBridge(
    private val ipc: CodexDesktopIpc = CodexDesktopIpc(),
) : CodexDesktopBridge {
    override suspend fun owner(sessionId: String): CodexDesktopIpc.Owner? =
        withContext(Dispatchers.IO) { ipc.owner(sessionId) }

    override suspend fun startTurn(
        sessionId: String,
        text: String,
        images: List<ImageData>,
        clientUserMessageId: String,
    ): String? = withContext(Dispatchers.IO) {
        val result = ipc.startTurn(
            sessionId = sessionId,
            request = buildJsonObject {
                put("threadId", sessionId)
                putJsonArray("input") {
                    addJsonObject {
                        put("type", "text")
                        put("text", text)
                        put("text_elements", kotlinx.serialization.json.JsonArray(emptyList()))
                    }
                    images.forEach { image ->
                        addJsonObject {
                            put("type", "image")
                            put("url", "data:${image.mediaType};base64,${image.base64}")
                        }
                    }
                }
            },
            clientUserMessageId = clientUserMessageId,
        )
        (result?.get("turn") as? JsonObject)
            ?.get("id")
            ?.let { it as? JsonPrimitive }
            ?.contentOrNull
    }

    override suspend fun steer(sessionId: String, text: String, clientUserMessageId: String) {
        withContext(Dispatchers.IO) { ipc.steer(sessionId, text, clientUserMessageId) }
    }

    override suspend fun interrupt(sessionId: String, turnId: String) {
        withContext(Dispatchers.IO) { ipc.interrupt(sessionId, turnId) }
    }
}
