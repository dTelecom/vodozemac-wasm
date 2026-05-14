// TurboModule implementation for the Vodozemac bridge on Android.
//
// Holds a handle table mapping JS-facing numeric handles to UniFFI
// `Account` / `Session` instances. Method signatures conform to
// `NativeVodozemacSpec`, the Java abstract class RN's codegen generates
// from `src/NativeVodozemac.ts`.
//
// All methods are synchronous: vodozemac is pure computation, RN calls
// TurboModules on the JS thread, and Promise wrapping would just add
// scheduler latency.

package com.dtelecom.vodozemac.rn

import com.dtelecom.vodozemac.Account
import com.dtelecom.vodozemac.NativeVodozemacSpec
import com.dtelecom.vodozemac.Session
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.module.annotations.ReactModule
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

@ReactModule(name = VodozemacModule.NAME)
class VodozemacModule(reactContext: ReactApplicationContext) : NativeVodozemacSpec(reactContext) {

    companion object {
        const val NAME = "Vodozemac"
    }

    // Handles are Long (JS Number's safe-integer range). Side-table is
    // shared across the module's lifetime; ReentrantLock guards it.
    private val lock = ReentrantLock()
    private var nextHandle: Long = 1
    private val accounts: MutableMap<Long, Account> = mutableMapOf()
    private val sessions: MutableMap<Long, Session> = mutableMapOf()

    private fun allocHandle(): Long = lock.withLock {
        val h = nextHandle
        nextHandle += 1
        h
    }

    private fun registerAccount(a: Account): Long {
        val h = allocHandle()
        lock.withLock { accounts[h] = a }
        return h
    }

    private fun registerSession(s: Session): Long {
        val h = allocHandle()
        lock.withLock { sessions[h] = s }
        return h
    }

    private fun getAccount(h: Long): Account = lock.withLock {
        accounts[h] ?: throw IllegalStateException("no account for handle $h")
    }

    private fun getSession(h: Long): Session = lock.withLock {
        sessions[h] ?: throw IllegalStateException("no session for handle $h")
    }

    override fun getName(): String = NAME

    // ── Account ────────────────────────────────────────────────────────

    override fun accountNew(): Double = registerAccount(Account()).toDouble()

    override fun accountFromPickle(pickle: String): Double =
        registerAccount(Account.fromPickle(pickle)).toDouble()

    override fun accountIdentityKeys(handle: Double): String =
        getAccount(handle.toLong()).identityKeys()

    override fun accountGenerateOneTimeKeys(handle: Double, count: Double): Boolean {
        getAccount(handle.toLong()).generateOneTimeKeys(count.toInt().toUInt())
        return true
    }

    override fun accountOneTimeKeys(handle: Double): String =
        getAccount(handle.toLong()).oneTimeKeys()

    override fun accountMarkKeysAsPublished(handle: Double): Boolean {
        getAccount(handle.toLong()).markKeysAsPublished()
        return true
    }

    override fun accountMaxNumberOfOneTimeKeys(handle: Double): Double =
        getAccount(handle.toLong()).maxNumberOfOneTimeKeys().toDouble()

    override fun accountGenerateFallbackKey(handle: Double): Boolean {
        getAccount(handle.toLong()).generateFallbackKey()
        return true
    }

    override fun accountFallbackKey(handle: Double): String =
        getAccount(handle.toLong()).fallbackKey()

    override fun accountSign(handle: Double, message: String): String =
        getAccount(handle.toLong()).sign(message)

    override fun accountPickle(handle: Double): String =
        getAccount(handle.toLong()).pickle()

    override fun accountCreateOutboundSession(
        handle: Double,
        theirIdentityKey: String,
        theirOneTimeKey: String,
    ): Double {
        val session = getAccount(handle.toLong())
            .createOutboundSession(theirIdentityKey, theirOneTimeKey)
        return registerSession(session).toDouble()
    }

    override fun accountCreateInboundSession(
        handle: Double,
        prekeyMessageBody: String,
    ): WritableMap {
        val inbound = getAccount(handle.toLong()).createInboundSession(prekeyMessageBody)
        val sessionHandle = registerSession(inbound.takeSession())
        val map = Arguments.createMap()
        map.putDouble("sessionHandle", sessionHandle.toDouble())
        map.putString("plaintext", inbound.plaintext())
        map.putString("senderIdentityKey", inbound.senderIdentityKey())
        return map
    }

    override fun accountClose(handle: Double): Boolean {
        lock.withLock { accounts.remove(handle.toLong()) }
        return true
    }

    // ── Session ────────────────────────────────────────────────────────

    override fun sessionFromPickle(pickle: String): Double =
        registerSession(Session.fromPickle(pickle)).toDouble()

    override fun sessionEncrypt(handle: Double, plaintext: String): String =
        getSession(handle.toLong()).encrypt(plaintext)

    override fun sessionDecrypt(handle: Double, messageType: Double, body: String): String =
        getSession(handle.toLong()).decrypt(messageType.toInt().toUByte(), body)

    override fun sessionSessionId(handle: Double): String =
        getSession(handle.toLong()).sessionId()

    override fun sessionHasReceivedMessage(handle: Double): Boolean =
        getSession(handle.toLong()).hasReceivedMessage()

    override fun sessionPickle(handle: Double): String =
        getSession(handle.toLong()).pickle()

    override fun sessionClose(handle: Double): Boolean {
        lock.withLock { sessions.remove(handle.toLong()) }
        return true
    }
}
