package dev.ccpocket.app.data

import kotlinx.serialization.Serializable

@Serializable
data class NativeChatMessage(
    val id: Int,
    val index: Int,
    val kind: String,
    val text: String,
    val tool: String? = null,
    val outcome: Boolean? = null,
    val pending: Boolean = false,
    val delivered: Boolean = false,
    val imageCount: Int = 0,
    val imagesTruncated: Boolean = false,
    val files: List<String> = emptyList(),
    val seconds: Int? = null,
)

fun nativeChatMessages(messages: List<ChatItem>, offset: Int = 0): List<NativeChatMessage> =
    messages.mapIndexed { index, item ->
        val id = index + offset
        when (item) {
            is ChatItem.User -> NativeChatMessage(id, index, "user", item.text, pending = item.pending,
                delivered = item.delivered, imageCount = item.images.size, imagesTruncated = item.imagesTruncated,
                files = item.files.map { it.name })
            is ChatItem.Assistant -> NativeChatMessage(id, index, "assistant", item.text)
            is ChatItem.Thinking -> NativeChatMessage(id, index, "thinking", item.text, seconds = item.seconds)
            is ChatItem.Tool -> NativeChatMessage(id, index, "tool", listOfNotNull(item.preview, item.output).joinToString("\n\n"),
                tool = item.tool, outcome = item.ok, imageCount = item.images.size, imagesTruncated = item.imagesTruncated)
            is ChatItem.Sys -> NativeChatMessage(id, index, if (item.isError) "error" else "system", item.text)
            is ChatItem.RuleChip -> NativeChatMessage(id, index, "activity", item.rule)
            is ChatItem.AutoRun -> NativeChatMessage(id, index, "activity", item.summary, tool = item.tool)
            is ChatItem.QuestionsAnswered -> NativeChatMessage(id, index, "answer", item.items.joinToString("\n") { "${it.first}\n${it.second}" })
            is ChatItem.QuestionsWithdrawn -> NativeChatMessage(id, index, "activity", "问题已撤回")
            is ChatItem.QuestionsUnanswered -> NativeChatMessage(id, index, "question", item.text)
            is ChatItem.OpenCodeQuestion -> NativeChatMessage(id, index, "question", item.questions.joinToString("\n") { it.question })
            is ChatItem.TurnEnded -> NativeChatMessage(id, index, "done", "回合完成", seconds = item.seconds)
        }
    }
