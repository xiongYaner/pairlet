package dev.ccpocket.protocol

/** Fork default and legacy upstream routing; never redirect a paired identity to a different operator. */
object RelayEndpoint {
    const val DEFAULT = "wss://relay.xiaowanai.cn"
    private const val UPSTREAM = "wss://relay.pairlet.cn"

    fun transport(stored: String): String = when (stored.removeSuffix("/")) {
        "wss://pocket.ark-nexus.cc", "wss://pocket.ark-nexus.cc:443",
        "wss://relay.pairlet.org", "wss://relay.pairlet.org:443",
        "wss://relay.pairlet.cn", "wss://relay.pairlet.cn:443" -> UPSTREAM
        "wss://relay.xiaowanai.cn", "wss://relay.xiaowanai.cn:443" -> DEFAULT
        else -> stored
    }
}
