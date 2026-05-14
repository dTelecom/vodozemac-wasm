// Standalone Swift smoke test for the UniFFI bindings. Compiles the
// generated `VodozemacFFI.swift` plus this file against the host dylib
// (`libvodozemac_ffi.dylib` from `cargo build --release`). Validates that
// the Rust → Swift FFI layer is wired correctly *before* we add the RN
// TurboModule layer on top in Phase 4.
//
// Run via `./run_validation.sh` (next to this file).

import Foundation

@main
struct SmokeValidation {
    static func require(_ condition: Bool, _ message: String) {
        if !condition {
            print("✗ \(message)")
            exit(1)
        }
    }

    static func main() throws {
        // ── 1. Prekey + reply roundtrip ──────────────────────────────────
        // Mirrors `tests::prekey_and_reply_roundtrip` in crates/vodozemac-ffi/src/lib.rs.

        let alice = Account()
        let bob = Account()
        try bob.generateOneTimeKeys(count: 1)

        let bobIdJSON = try bob.identityKeys()
        let bobIdData = bobIdJSON.data(using: .utf8)!
        let bobId = (try JSONSerialization.jsonObject(with: bobIdData) as! [String: String])["curve25519"]!

        let bobOtksJSON = try bob.oneTimeKeys()
        let bobOtksData = bobOtksJSON.data(using: .utf8)!
        let bobOtksOuter = try JSONSerialization.jsonObject(with: bobOtksData) as! [String: [String: String]]
        let bobOtk = bobOtksOuter["curve25519"]!.values.first!
        try bob.markKeysAsPublished()

        let aliceSess = try alice.createOutboundSession(
            theirIdentityKey: bobId,
            theirOneTimeKey: bobOtk
        )
        let encJSON = try aliceSess.encrypt(plaintext: "hello bob")
        let encData = encJSON.data(using: .utf8)!
        let enc = try JSONSerialization.jsonObject(with: encData) as! [String: Any]
        require(enc["type"] as? Int == 0, "first message should be PreKey (type=0), got \(enc["type"] ?? "nil")")
        let aliceToBobBody = enc["body"] as! String

        let inbound = try bob.createInboundSession(prekeyMessageBody: aliceToBobBody)
        require(inbound.plaintext() == "hello bob", "decrypted plaintext mismatch")
        let bobSess = try inbound.takeSession()

        let replyJSON = try bobSess.encrypt(plaintext: "hi alice")
        let replyData = replyJSON.data(using: .utf8)!
        let reply = try JSONSerialization.jsonObject(with: replyData) as! [String: Any]
        let replyType = UInt8(reply["type"] as! Int)
        let replyBody = reply["body"] as! String

        let decoded = try aliceSess.decrypt(messageType: replyType, body: replyBody)
        require(decoded == "hi alice", "reply decryption mismatch: got \(decoded)")

        print("✓ prekey + reply roundtrip")

        // ── 2. take_session is one-shot ──────────────────────────────────
        do {
            _ = try inbound.takeSession()
            print("✗ second takeSession() should have thrown SessionAlreadyTaken")
            exit(1)
        } catch VodozemacError.SessionAlreadyTaken {
            print("✓ takeSession() one-shot enforced")
        } catch {
            print("✗ unexpected error from second takeSession: \(error)")
            exit(1)
        }

        // ── 3. Pickle roundtrip ──────────────────────────────────────────
        let acc = Account()
        try acc.generateOneTimeKeys(count: 2)
        let keysBefore = try acc.identityKeys()
        let otksBefore = try acc.oneTimeKeys()
        let pickled = try acc.pickle()
        let restored = try Account.fromPickle(pickle: pickled)
        require(try restored.identityKeys() == keysBefore, "identityKeys differ after pickle restore")
        require(try restored.oneTimeKeys() == otksBefore, "oneTimeKeys differ after pickle restore")
        print("✓ pickle roundtrip")

        print("")
        print("all checks passed")
    }
}
