package dev.ccpocket.daemon.codex

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.Closeable
import java.io.EOFException
import java.net.StandardProtocolFamily
import java.net.UnixDomainSocketAddress
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.ServerSocketChannel
import java.nio.channels.SocketChannel
import java.nio.file.Files
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CodexDesktopIpcTest {
    @Test
    fun discoversOwnerAndReadsASameIdSnapshotWithoutResumingOrForking() {
        Fixture(fragmented = true).use { fixture ->
            val ipc = fixture.ipc()
            assertEquals(CodexDesktopIpc.Owner("desktop-owner", true), ipc.owner("thread-1"))
            assertEquals("thread-1", ipc.snapshot("thread-1")?.get("id")?.jsonPrimitive?.content)
            fixture.awaitMessages { messages -> messages.count { it.text("method") == "thread-stream-following-changed" } == 2 }
            val follows = fixture.messages.filter { it.text("method") == "thread-stream-following-changed" }
            assertEquals(listOf("true", "false"), follows.map { it["params"]!!.jsonObject["following"]!!.jsonPrimitive.content })
            assertFalse(fixture.messages.any { it.text("method") in setOf("thread/resume", "thread/fork", "thread-follower-start-turn") })
        }
    }

    @Test
    fun absentOwnerReturnsNullAndNeverSendsAMutation() {
        Fixture(ownerPresent = false).use { fixture ->
            val ipc = fixture.ipc()
            assertNull(ipc.owner("thread-1"))
            assertNull(ipc.snapshot("thread-1"))
            assertNull(ipc.startTurn("thread-1", turnRequest(), "message-1"))
            assertFalse(fixture.messages.any { it.text("method") == "thread-follower-start-turn" })
        }
    }

    @Test
    fun forwardsAnIdempotentTurnToTheOwnerAndNormalizesTextElements() {
        Fixture().use { fixture ->
            val response = fixture.ipc().startTurn("thread-1", turnRequest(), "message-1")
            assertEquals("turn-2", response?.get("turn")?.jsonObject?.get("id")?.jsonPrimitive?.content)
            val forwarded = fixture.messages.single { it.text("method") == "thread-follower-start-turn" }
            assertEquals("desktop-owner", forwarded.text("targetClientId"))
            assertEquals("2", forwarded["version"]!!.jsonPrimitive.content)
            val request = forwarded["params"]!!.jsonObject["turnStart"]!!.jsonObject["request"]!!.jsonObject
            assertEquals("thread-1", request.text("threadId"))
            assertEquals("message-1", request.text("clientUserMessageId"))
            assertEquals(JsonArray(emptyList()), request["input"]!!.jsonArray.single().jsonObject["text_elements"])
        }
    }

    @Test
    fun forwardsSteerInterruptAndApprovalUsingTheirCurrentProtocolVersions() {
        Fixture().use { fixture ->
            val ipc = fixture.ipc()
            ipc.steer("thread-1", "next step", "message-steer")
            ipc.interrupt("thread-1", "turn-1")
            ipc.respondToApproval("thread-1", "item/commandExecution/requestApproval", JsonPrimitive(42), buildJsonObject { put("decision", "accept") })
            val steer = fixture.messages.single { it.text("method") == "thread-follower-steer-turn" }
            assertTrue(steer["params"]!!.jsonObject["restoreMessage"]!!.jsonObject["context"] is JsonObject)
            val interrupt = fixture.messages.single { it.text("method") == "thread-follower-interrupt-turn" }
            assertEquals("4", interrupt["version"]!!.jsonPrimitive.content)
            assertEquals("turn-1", interrupt["params"]!!.jsonObject.text("expectedTurnId"))
            val approval = fixture.messages.single { it.text("method") == "thread-follower-command-approval-decision" }
            assertEquals(JsonPrimitive(42), approval["params"]!!.jsonObject["requestId"])
        }
    }

    @Test
    fun refusesAnOwnerThatDoesNotAcceptAppInput() {
        Fixture(acceptsInput = false).use { fixture ->
            assertFailsWith<CodexDesktopIpc.Failure.Rejected> { fixture.ipc().startTurn("thread-1", turnRequest(), "message-1") }
            assertFalse(fixture.messages.any { it.text("method") == "thread-follower-start-turn" })
        }
    }

    @Test
    fun rejectsResponsesHandledByAnUnexpectedOwner() {
        Fixture(wrongHandler = true).use { fixture ->
            assertFailsWith<CodexDesktopIpc.Failure.InvalidResponse> { fixture.ipc().startTurn("thread-1", turnRequest(), "message-1") }
        }
    }

    @Test
    fun rejectsASnapshotWhoseIdentityDoesNotMatchTheRequestedThread() {
        Fixture(snapshotId = "different-thread").use { fixture ->
            assertFailsWith<CodexDesktopIpc.Failure.InvalidResponse> { fixture.ipc().snapshot("thread-1") }
        }
    }

    @Test
    fun ownerDiscoveryHasItsOwnBoundedTimeout() {
        Fixture(ownerDelayMillis = 350).use { fixture ->
            val start = System.nanoTime()
            assertFailsWith<CodexDesktopIpc.Failure.Unavailable> { fixture.ipc(ownerTimeoutMillis = 60).owner("thread-1") }
            assertTrue((System.nanoTime() - start) / 1_000_000 < 1_000)
        }
    }

    @Test
    fun refusesSymlinksAndNonSocketEndpoints() {
        Fixture().use { fixture ->
            val alias = fixture.directory.resolve("alias.sock")
            Files.createSymbolicLink(alias, fixture.socket)
            assertFailsWith<CodexDesktopIpc.Failure.Unavailable> { CodexDesktopIpc(alias).owner("thread-1") }
            val regular = fixture.directory.resolve("regular.sock")
            Files.writeString(regular, "not a socket")
            assertFailsWith<CodexDesktopIpc.Failure.Unavailable> { CodexDesktopIpc(regular).owner("thread-1") }
        }
    }

    @Test
    fun rejectsOversizedFramesBeforeAllocatingTheirPayload() {
        Fixture(oversizedOwnerResponse = true).use { fixture ->
            assertFailsWith<CodexDesktopIpc.Failure.InvalidResponse> { fixture.ipc().owner("thread-1") }
        }
    }

    private fun turnRequest() = buildJsonObject {
        put("threadId", "thread-1")
        put("input", JsonArray(listOf(buildJsonObject { put("type", "text"); put("text", "isolated fixture") })))
    }

    private class Fixture(
        val ownerPresent: Boolean = true,
        val acceptsInput: Boolean = true,
        val wrongHandler: Boolean = false,
        val snapshotId: String = "thread-1",
        val ownerDelayMillis: Long = 0,
        val fragmented: Boolean = false,
        val oversizedOwnerResponse: Boolean = false,
    ) : Closeable {
        val directory = Files.createTempDirectory("desktop-ipc-")
        val socket = directory.resolve("ipc.sock")
        val messages = CopyOnWriteArrayList<JsonObject>()
        private val server = ServerSocketChannel.open(StandardProtocolFamily.UNIX).bind(UnixDomainSocketAddress.of(socket))
        private val worker = thread(isDaemon = true, name = "desktop-ipc-fixture") {
            while (server.isOpen) {
                try {
                    server.accept().use { connection ->
                        while (connection.isOpen) {
                            val incoming = read(connection)
                            messages += incoming
                            if (incoming.text("type") == "broadcast") {
                                if (incoming["params"]?.jsonObject?.get("following") == JsonPrimitive(true)) {
                                    write(connection, buildJsonObject {
                                        put("type", "broadcast"); put("method", "thread-stream-state-changed")
                                        put("params", buildJsonObject {
                                            put("conversationId", "thread-1")
                                            put("change", buildJsonObject {
                                                put("type", "snapshot"); put("revision", 1)
                                                put("conversationState", buildJsonObject { put("id", snapshotId); put("turns", JsonArray(emptyList())) })
                                            })
                                        })
                                    })
                                }
                                continue
                            }
                            val method = incoming.text("method")
                            if (method == "thread-owner-discovery" && ownerDelayMillis > 0) Thread.sleep(ownerDelayMillis)
                            if (method == "thread-owner-discovery" && oversizedOwnerResponse) {
                                val header = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(64 * 1024 * 1024 + 1)
                                header.flip(); while (header.hasRemaining()) connection.write(header)
                                continue
                            }
                            write(connection, buildJsonObject {
                                put("type", "response"); put("requestId", incoming["requestId"]!!)
                                if (method == "thread-owner-discovery" && !ownerPresent) {
                                    put("resultType", "error"); put("error", "no-client-found")
                                } else {
                                    put("resultType", "success")
                                    put("handledByClientId", if (method == "initialize") "fixture-client" else if (wrongHandler && method != "thread-owner-discovery") "wrong-owner" else "desktop-owner")
                                    put("result", when (method) {
                                        "initialize" -> buildJsonObject { put("clientId", "fixture-client") }
                                        "thread-owner-discovery" -> buildJsonObject { put("supportsUntrustedAppInput", acceptsInput) }
                                        "thread-follower-start-turn" -> buildJsonObject {
                                            put("result", buildJsonObject { put("turn", buildJsonObject { put("id", "turn-2"); put("status", "inProgress") }) })
                                        }
                                        else -> buildJsonObject { put("result", buildJsonObject { put("ok", true) }) }
                                    })
                                }
                            })
                        }
                    }
                } catch (_: Exception) { }
            }
        }

        fun ipc(ownerTimeoutMillis: Long = 1_500) = CodexDesktopIpc(socket, requestTimeoutMillis = 2_000, ownerTimeoutMillis = ownerTimeoutMillis, snapshotTimeoutMillis = 2_000)

        fun awaitMessages(predicate: (List<JsonObject>) -> Boolean) {
            val deadline = System.nanoTime() + 2_000_000_000
            while (!predicate(messages) && System.nanoTime() < deadline) Thread.sleep(5)
            assertTrue(predicate(messages))
        }

        private fun read(connection: SocketChannel): JsonObject {
            val header = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
            while (header.hasRemaining()) if (connection.read(header) < 0) throw EOFException()
            header.flip()
            val size = header.int
            require(size in 1..1_000_000)
            val payload = ByteBuffer.allocate(size)
            while (payload.hasRemaining()) if (connection.read(payload) < 0) throw EOFException()
            return Json.parseToJsonElement(String(payload.array(), Charsets.UTF_8)).jsonObject
        }

        private fun write(connection: SocketChannel, message: JsonObject) {
            val payload = message.toString().toByteArray(Charsets.UTF_8)
            val buffer = ByteBuffer.allocate(4 + payload.size).order(ByteOrder.LITTLE_ENDIAN)
            buffer.putInt(payload.size).put(payload).flip()
            if (fragmented) {
                while (buffer.hasRemaining()) {
                    val piece = ByteBuffer.wrap(byteArrayOf(buffer.get()))
                    while (piece.hasRemaining()) connection.write(piece)
                }
            } else while (buffer.hasRemaining()) connection.write(buffer)
        }

        override fun close() {
            server.close()
            worker.interrupt()
            worker.join(1_000)
            Files.walk(directory).use { entries -> entries.sorted(Comparator.reverseOrder()).forEach(Files::deleteIfExists) }
        }
    }

    companion object {
        private fun JsonObject.text(key: String) = this[key]?.jsonPrimitive?.content
    }
}
