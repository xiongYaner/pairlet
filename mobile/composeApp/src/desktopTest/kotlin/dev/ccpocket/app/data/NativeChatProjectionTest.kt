package dev.ccpocket.app.data

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NativeChatProjectionTest {
    @Test
    fun preservesDeliveryAndToolOutcomeWithoutCopyingAttachmentPayloads() {
        val rows = nativeChatMessages(listOf(
            ChatItem.User("附件", images = listOf("PRIVATE_IMAGE_BYTES".encodeToByteArray()),
                pending = true, delivered = true, imagesTruncated = true,
                files = listOf(SentFile("report.txt", 20, "/private/session/report.txt"))),
            ChatItem.Tool("Read", "report.txt", ok = false, output = "读取失败",
                images = listOf(byteArrayOf(1, 2)), imagesTruncated = true),
        ))
        assertTrue(rows[0].pending)
        assertTrue(rows[0].delivered)
        assertEquals(listOf("report.txt"), rows[0].files)
        assertEquals(1, rows[0].imageCount)
        assertTrue(rows[0].imagesTruncated)
        assertEquals(false, rows[1].outcome)
        assertEquals("report.txt\n\n读取失败", rows[1].text)
        assertEquals(1, rows[1].imageCount)
        val wire = Json.encodeToString(rows)
        assertFalse(wire.contains("PRIVATE_IMAGE_BYTES"))
        assertFalse(wire.contains("/private/session/"))
    }

    @Test
    fun keepsExistingRowIdentityWhenHistoryIsPrependedAndReplyStreams() {
        val original = listOf(ChatItem.User("问题"), ChatItem.Assistant("答"))
        val before = nativeChatMessages(original)
        val after = nativeChatMessages(
            listOf(ChatItem.Sys("之前的记录", false)) +
                listOf(ChatItem.User("问题"), ChatItem.Assistant("答案持续输出"), ChatItem.TurnEnded(2)),
            offset = -1,
        )
        assertEquals(before.map { it.id }, after.drop(1).take(2).map { it.id })
        assertEquals(listOf(0, 1, 2, 3), after.map { it.index })
        assertEquals(after.size, after.map { it.id }.toSet().size)
    }

    @Test
    fun exposesThinkingErrorsQuestionsAndTurnBoundaries() {
        val rows = nativeChatMessages(listOf(
            ChatItem.Thinking("分析", 3), ChatItem.Sys("失败"), ChatItem.Sys("提示", false),
            ChatItem.RuleChip("规则"), ChatItem.AutoRun("a", "已执行", "session-rule", "Read"),
            ChatItem.QuestionsAnswered(listOf("选哪个" to "A")), ChatItem.QuestionsWithdrawn,
            ChatItem.QuestionsUnanswered("历史问题"), ChatItem.OpenCodeQuestion(emptyList()),
            ChatItem.TurnEnded(4),
        ))
        assertEquals(listOf("thinking", "error", "system", "activity", "activity", "answer", "activity", "question", "question", "done"), rows.map { it.kind })
        assertEquals("选哪个\nA", rows[5].text)
        assertEquals(3, rows.first().seconds)
        assertEquals(4, rows.last().seconds)
    }

    @Test
    fun projectsEveryStreamedAssistantSnapshotWithStableIdentity() {
        val first = nativeChatMessages(listOf(ChatItem.User("问题"), ChatItem.Assistant("第一段")))
        val second = nativeChatMessages(listOf(ChatItem.User("问题"), ChatItem.Assistant("第一段继续")))
        val third = nativeChatMessages(listOf(
            ChatItem.User("问题"),
            ChatItem.Assistant("第一段继续输出完成"),
            ChatItem.TurnEnded(3),
        ))

        assertEquals(first[1].id, second[1].id)
        assertEquals(second[1].id, third[1].id)
        assertEquals("第一段", first[1].text)
        assertEquals("第一段继续", second[1].text)
        assertEquals("第一段继续输出完成", third[1].text)
        assertEquals(3, third.last().seconds)
    }
}
