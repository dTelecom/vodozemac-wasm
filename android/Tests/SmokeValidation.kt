// Standalone Kotlin smoke test for the UniFFI bindings. Compiles the
// generated `vodozemac.kt` against this file + JNA + the host dylib
// (`libvodozemac_ffi.dylib` from `cargo build --release`). Validates that
// the Rust → Kotlin FFI layer is wired correctly *before* we add the RN
// TurboModule layer on top in Phase 4.
//
// Run via `./run_validation.sh` (next to this file).

import com.dtelecom.vodozemac.*
import org.json.JSONObject

@Suppress("RemoveRedundantQualifierName")
private fun require(condition: Boolean, message: String) {
    if (!condition) {
        System.err.println("✗ $message")
        kotlin.system.exitProcess(1)
    }
}

fun main() {
    // ── 1. Prekey + reply roundtrip ──────────────────────────────────────
    // Mirrors `tests::prekey_and_reply_roundtrip` in
    // crates/vodozemac-ffi/src/lib.rs — running it on the Kotlin side
    // confirms the UniFFI binding actually dispatches into Rust correctly.

    val alice = Account()
    val bob = Account()
    bob.generateOneTimeKeys(count = 1u)

    val bobIdentity = JSONObject(bob.identityKeys())
    val bobId = bobIdentity.getString("curve25519")

    val bobOtks = JSONObject(bob.oneTimeKeys()).getJSONObject("curve25519")
    val bobOtk = bobOtks.getString(bobOtks.keys().next())
    bob.markKeysAsPublished()

    val aliceSess = alice.createOutboundSession(
        theirIdentityKey = bobId,
        theirOneTimeKey = bobOtk,
    )
    val encJson = JSONObject(aliceSess.encrypt(plaintext = "hello bob"))
    require(encJson.getInt("type") == 0, "first message should be PreKey (type=0), got ${encJson.getInt("type")}")
    val aliceToBobBody = encJson.getString("body")

    val inbound = bob.createInboundSession(prekeyMessageBody = aliceToBobBody)
    require(inbound.plaintext() == "hello bob", "decrypted plaintext mismatch: ${inbound.plaintext()}")
    val bobSess = inbound.takeSession()

    val replyJson = JSONObject(bobSess.encrypt(plaintext = "hi alice"))
    val replyType = replyJson.getInt("type").toUByte()
    val replyBody = replyJson.getString("body")

    val decoded = aliceSess.decrypt(messageType = replyType, body = replyBody)
    require(decoded == "hi alice", "reply decryption mismatch: got $decoded")
    println("✓ prekey + reply roundtrip")

    // ── 2. take_session is one-shot ──────────────────────────────────────
    try {
        inbound.takeSession()
        System.err.println("✗ second takeSession() should have thrown SessionAlreadyTakenException")
        kotlin.system.exitProcess(1)
    } catch (e: VodozemacException.SessionAlreadyTaken) {
        println("✓ takeSession() one-shot enforced")
    }

    // ── 3. Pickle roundtrip ──────────────────────────────────────────────
    val acc = Account()
    acc.generateOneTimeKeys(count = 2u)
    val keysBefore = acc.identityKeys()
    val otksBefore = acc.oneTimeKeys()
    val pickled = acc.pickle()
    val restored = Account.fromPickle(pickle = pickled)
    require(restored.identityKeys() == keysBefore, "identityKeys differ after pickle restore")
    require(restored.oneTimeKeys() == otksBefore, "oneTimeKeys differ after pickle restore")
    println("✓ pickle roundtrip")

    println()
    println("all checks passed")
}
