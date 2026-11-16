package dev.ccpocket.daemon.codex

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.Closeable
import java.io.EOFException
import java.io.IOException
import java.io.InterruptedIOException
import java.net.StandardProtocolFamily
import java.net.UnixDomainSocketAddress
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.SelectionKey
import java.nio.channels.Selector
import java.nio.channels.SocketChannel
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.util.UUID
import java.util.concurrent.TimeUnit

class CodexDesktopIpc(
    val socketPath: Path = defaultSocketPath(),
    private val requestTimeoutMillis: Long = 120_000,
    private val ownerTimeoutMillis: Long = 1_500,
    private val snapshotTimeoutMillis: Long = 10_000,
) {
    data class Owner(val clientId: String, val supportsUntrustedAppInput: Boolean)

    sealed class Failure(message: String, cause: Throwable? = null) : IOException(message, cause) {
        class Unavailable(cause: Throwable? = null) : Failure("Codex Desktop IPC is unavailable", cause)
        class InvalidResponse(message: String = "Codex Desktop returned an invalid IPC response") : Failure(message)
        class Rejected(val reason: String) : Failure("Codex Desktop rejected the request: ${reason.take(240)}")
    }

    fun owner(sessionId: String): Owner? = exchange { connection, clientId ->
        discoverOwner(connection, clientId, sessionId)
    }

    fun snapshot(sessionId: String): JsonObject? = exchange { connection, clientId ->
        val owner = discoverOwner(connection, clientId, sessionId) ?: return@exchange null
        connection.send(following(sessionId, clientId, owner.clientId, true), snapshotTimeoutMillis)
        try {
            val deadline = deadline(snapshotTimeoutMillis)
            repeat(128) {
                val message = connection.receiveUntil(deadline)
                val params = message["params"] as? JsonObject
                val change = params?.get("change") as? JsonObject
                if (message.text("method") == "thread-stream-state-changed" &&
                    params.text("conversationId") == sessionId && change.text("type") == "snapshot"
                ) {
                    val state = change?.get("conversationState") as? JsonObject ?: throw Failure.InvalidResponse()
                    if (state.text("id") != sessionId) throw Failure.InvalidResponse("Desktop snapshot belongs to a different session")
                    return@exchange state
                }
            }
            throw Failure.InvalidResponse()
        } finally {
            runCatching { connection.send(following(sessionId, clientId, owner.clientId, false), 500) }
        }
    }

    fun followerRequest(sessionId: String, method: String, version: Int, params: JsonObject): JsonObject? =
        exchange { connection, clientId ->
            if (params.text("conversationId") != sessionId) throw Failure.InvalidResponse("Follower target does not match the session")
            val owner = discoverOwner(connection, clientId, sessionId) ?: return@exchange null
            if (!owner.supportsUntrustedAppInput) throw Failure.Rejected("The desktop owner does not accept app input")
            val response = connection.request(method, params, clientId, version, requestTimeoutMillis, owner.clientId)
            if (response.text("resultType") != "success") throw Failure.Rejected(response.text("error") ?: "unknown error")
            if (response.text("handledByClientId") != owner.clientId) throw Failure.InvalidResponse("A different desktop owner handled the request")
            val result = response["result"] as? JsonObject ?: throw Failure.InvalidResponse()
            (result["result"] as? JsonObject) ?: result
        }

    fun startTurn(sessionId: String, request: JsonObject, clientUserMessageId: String): JsonObject? {
        if (request.text("threadId") != sessionId) throw Failure.InvalidResponse("Turn target does not match the session")
        val normalizedInput = (request["input"] as? JsonArray)?.map { entry ->
            val item = entry as? JsonObject ?: return@map entry
            if (item.text("type") == "text" && item["text_elements"] == null) {
                JsonObject(item + ("text_elements" to JsonArray(emptyList())))
            } else item
        }
        val normalized = JsonObject(request + buildMap {
            put("clientUserMessageId", JsonPrimitive(clientUserMessageId))
            if (normalizedInput != null) put("input", JsonArray(normalizedInput))
        })
        return followerRequest(sessionId, "thread-follower-start-turn", 2, buildJsonObject {
            put("conversationId", sessionId)
            put("turnStart", buildJsonObject {
                put("request", normalized)
                put("context", buildJsonObject {})
            })
        })
    }

    fun steer(sessionId: String, text: String, clientUserMessageId: String): JsonObject? =
        followerRequest(sessionId, "thread-follower-steer-turn", 1, buildJsonObject {
            put("conversationId", sessionId)
            put("clientUserMessageId", clientUserMessageId)
            put("input", JsonArray(listOf(buildJsonObject {
                put("type", "text"); put("text", text); put("text_elements", JsonArray(emptyList()))
            })))
            put("attachments", JsonArray(emptyList()))
            put("restoreMessage", buildJsonObject {
                put("id", clientUserMessageId); put("text", text)
                put("attachments", JsonArray(emptyList()))
                put("context", buildJsonObject { put("commentAttachments", JsonArray(emptyList())) })
            })
        })

    fun interrupt(sessionId: String, turnId: String): JsonObject? =
        followerRequest(sessionId, "thread-follower-interrupt-turn", 4, buildJsonObject {
            put("conversationId", sessionId); put("mode", "user-stop"); put("expectedTurnId", turnId)
        })

    fun respondToApproval(sessionId: String, method: String, requestId: JsonElement, result: JsonObject): JsonObject? {
        val forwardedMethod = when (method) {
            "item/commandExecution/requestApproval" -> "thread-follower-command-approval-decision"
            "item/fileChange/requestApproval" -> "thread-follower-file-approval-decision"
            "item/permissions/requestApproval" -> "thread-follower-permissions-request-approval-response"
            else -> throw Failure.InvalidResponse("Unsupported desktop approval method")
        }
        return followerRequest(sessionId, forwardedMethod, 1, buildJsonObject {
            put("conversationId", sessionId); put("requestId", requestId)
            if (method == "item/permissions/requestApproval") put("response", result)
            else put("decision", result["decision"] ?: throw Failure.InvalidResponse("Approval decision is missing"))
        })
    }

    private fun discoverOwner(connection: Connection, clientId: String, sessionId: String): Owner? {
        val response = connection.request("thread-owner-discovery", buildJsonObject {
            put("hostId", "local"); put("conversationId", sessionId)
        }, clientId, 1, ownerTimeoutMillis)
        if (response.text("resultType") == "error" && response.text("error") == "no-client-found") return null
        if (response.text("resultType") != "success") throw Failure.Rejected(response.text("error") ?: "owner discovery failed")
        val ownerId = response.text("handledByClientId")?.takeIf { it.isNotBlank() } ?: throw Failure.InvalidResponse()
        val result = response["result"] as? JsonObject
        return Owner(ownerId, (result?.get("supportsUntrustedAppInput") as? JsonPrimitive)?.booleanOrNull == true)
    }

    private fun <Result> exchange(action: (Connection, String) -> Result): Result {
        try {
            validateSocket()
            return Connection(socketPath).use { connection ->
                val initialized = connection.request("initialize", buildJsonObject {
                    put("clientType", "codebridge-gateway")
                }, "initializing-client", 0, 5_000)
                if (initialized.text("resultType") != "success") throw Failure.InvalidResponse()
                val clientId = (initialized["result"] as? JsonObject).text("clientId")?.takeIf { it.isNotBlank() } ?: throw Failure.InvalidResponse()
                action(connection, clientId)
            }
        } catch (failure: Failure) {
            throw failure
        } catch (error: Exception) {
            throw Failure.Unavailable(error)
        }
    }

    private fun validateSocket() {
        if (Files.isSymbolicLink(socketPath) || Files.isSymbolicLink(socketPath.parent)) throw Failure.Unavailable()
        val ownUid = Files.getAttribute(Path.of(System.getProperty("user.home")), "unix:uid", NOFOLLOW_LINKS)
        val uid = Files.getAttribute(socketPath, "unix:uid", NOFOLLOW_LINKS)
        val parentUid = Files.getAttribute(socketPath.parent, "unix:uid", NOFOLLOW_LINKS)
        val mode = Files.getAttribute(socketPath, "unix:mode", NOFOLLOW_LINKS) as Int
        val parentMode = Files.getAttribute(socketPath.parent, "unix:mode", NOFOLLOW_LINKS) as Int
        if (uid != ownUid || parentUid != ownUid || (mode and 0xF000) != 0xC000 || (parentMode and 0x12) != 0) throw Failure.Unavailable()
    }

    private fun following(sessionId: String, clientId: String, ownerId: String, enabled: Boolean) = buildJsonObject {
        put("type", "broadcast"); put("method", "thread-stream-following-changed")
        put("sourceClientId", clientId); put("version", 1)
        put("params", buildJsonObject {
            put("conversationId", sessionId); put("hostId", "local"); put("following", enabled)
        })
        put("targetClientIds", JsonArray(listOf(JsonPrimitive(ownerId))))
    }

    private class Connection(path: Path) : Closeable {
        private val selector = Selector.open()
        private val channel = SocketChannel.open(StandardProtocolFamily.UNIX)

        init {
            try {
                channel.configureBlocking(false)
                channel.register(selector, SelectionKey.OP_CONNECT)
                if (!channel.connect(UnixDomainSocketAddress.of(path))) {
                    val end = deadline(5_000)
                    while (!channel.finishConnect()) await(SelectionKey.OP_CONNECT, end)
                }
            } catch (error: Exception) {
                close()
                throw error
            }
        }

        fun request(method: String, params: JsonObject, clientId: String, version: Int, timeoutMillis: Long, ownerId: String? = null): JsonObject {
            val requestId = UUID.randomUUID().toString()
            val end = deadline(timeoutMillis)
            sendUntil(buildJsonObject {
                put("type", "request"); put("requestId", requestId); put("sourceClientId", clientId)
                put("version", version); put("method", method); put("params", params); put("timeoutMs", timeoutMillis)
                ownerId?.let { put("targetClientId", it) }
            }, end)
            repeat(128) {
                val reply = receiveUntil(end)
                if (reply.text("type") == "response" && reply.text("requestId") == requestId) return reply
            }
            throw Failure.InvalidResponse()
        }

        fun send(message: JsonObject, timeoutMillis: Long) = sendUntil(message, deadline(timeoutMillis))

        private fun sendUntil(message: JsonObject, end: Long) {
            val payload = message.toString().toByteArray(Charsets.UTF_8)
            if (payload.size !in 1..MAX_FRAME_BYTES) throw Failure.InvalidResponse("Desktop IPC frame exceeds the size limit")
            val buffer = ByteBuffer.allocate(4 + payload.size).order(ByteOrder.LITTLE_ENDIAN)
            buffer.putInt(payload.size).put(payload).flip()
            while (buffer.hasRemaining()) {
                checkDeadline(end)
                if (channel.write(buffer) == 0) await(SelectionKey.OP_WRITE, end)
            }
        }

        fun receiveUntil(end: Long): JsonObject {
            val header = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
            readFully(header, end)
            header.flip()
            val size = header.int
            if (size !in 1..MAX_FRAME_BYTES) throw Failure.InvalidResponse("Desktop IPC frame exceeds the size limit")
            val body = ByteBuffer.allocate(size)
            readFully(body, end)
            return try { Json.parseToJsonElement(String(body.array(), Charsets.UTF_8)).jsonObject }
            catch (_: Exception) { throw Failure.InvalidResponse() }
        }

        private fun readFully(buffer: ByteBuffer, end: Long) {
            while (buffer.hasRemaining()) {
                checkDeadline(end)
                val count = channel.read(buffer)
                if (count < 0) throw EOFException("Desktop IPC closed")
                if (count == 0) await(SelectionKey.OP_READ, end)
            }
        }

        private fun await(operation: Int, end: Long) {
            checkDeadline(end)
            val remaining = end - System.nanoTime()
            channel.keyFor(selector).interestOps(operation)
            selector.select(TimeUnit.NANOSECONDS.toMillis(remaining).coerceAtLeast(1))
            selector.selectedKeys().clear()
        }

        private fun checkDeadline(end: Long) {
            if (Thread.currentThread().isInterrupted) throw Failure.Unavailable(InterruptedIOException("Desktop IPC request cancelled"))
            if (System.nanoTime() >= end) throw Failure.Unavailable(IOException("Desktop IPC request timed out"))
        }

        override fun close() {
            runCatching { channel.close() }
            runCatching { selector.close() }
        }
    }

    companion object {
        private const val MAX_FRAME_BYTES = 64 * 1024 * 1024
        fun defaultSocketPath(): Path = Path.of(System.getenv("CODEX_HOME") ?: "${System.getProperty("user.home")}/.codex").resolve("ipc/ipc.sock")
        private fun deadline(timeoutMillis: Long): Long = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis.coerceIn(1, 120_000))
        private fun JsonObject?.text(key: String): String? = (this?.get(key) as? JsonPrimitive)?.contentOrNull
    }
}
