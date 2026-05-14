//! UniFFI bindings for vodozemac.
//!
//! Public surface intentionally mirrors `dtelecom-vodozemac-wasm` (the
//! sibling wasm-bindgen crate). The Olm-shaped JS contract is identical:
//! - JSON strings for structured fields (identityKeys, oneTimeKeys, encrypt
//!   result, fallbackKey) so the @dtelecom/secure-chat-client SDK can stay
//!   target-agnostic — same parsing path on web/node/RN.
//! - Pickles are JSON strings — at-rest encryption is the SDK's job.
//! - All base64 is URL-safe, no padding (vodozemac default).
//!
//! Differences from the wasm-bindgen crate:
//! - Methods that mutate `VAccount` / `VSession` take `&self` (UniFFI Object
//!   semantics, methods on `Arc<Self>`), with a `Mutex` inside for interior
//!   mutability.
//! - Errors are a `thiserror` enum exposed across the FFI boundary as
//!   `VodozemacError` rather than raw `JsValue` strings — gives Swift /
//!   Kotlin callers structured error types and lets the TurboModule layer
//!   surface specific error codes.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use serde::Serialize;
use vodozemac::{
    olm::{
        Account as VAccount, AccountPickle, OlmMessage, PreKeyMessage, Session as VSession,
        SessionConfig, SessionPickle,
    },
    Curve25519PublicKey, KeyId,
};

uniffi::setup_scaffolding!("vodozemac");

// ── error type ──────────────────────────────────────────────────────────────

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum VodozemacError {
    #[error("invalid base64: {reason}")]
    InvalidBase64 { reason: String },
    #[error("decryption failed: {reason}")]
    DecryptError { reason: String },
    #[error("session establishment failed: {reason}")]
    SessionError { reason: String },
    #[error("invalid pickle: {reason}")]
    InvalidPickle { reason: String },
    #[error("invalid utf-8 in plaintext: {reason}")]
    InvalidUtf8 { reason: String },
    #[error("invalid message type: {value} (expected 0 or 1)")]
    InvalidMessageType { value: u8 },
    #[error("session already taken")]
    SessionAlreadyTaken,
    #[error("internal: {reason}")]
    Internal { reason: String },
}

type Result<T> = std::result::Result<T, VodozemacError>;

fn parse_curve(b64: &str) -> Result<Curve25519PublicKey> {
    Curve25519PublicKey::from_base64(b64)
        .map_err(|e| VodozemacError::InvalidBase64 { reason: e.to_string() })
}

fn key_id_to_string(k: KeyId) -> String {
    k.to_base64()
}

// ── public-view types serialized to JSON strings ────────────────────────────
//
// These match the wasm-bindgen crate exactly. We intentionally don't expose
// them as UniFFI Records — keeping the JSON-string shape means the JS-side
// parsing logic in @dtelecom/secure-chat-client (olm-adapter.ts) doesn't
// change between web/node and RN.

#[derive(Serialize)]
struct IdentityKeysJs {
    curve25519: String,
    ed25519: String,
}

#[derive(Serialize)]
struct OneTimeKeysJs {
    /// Map of base64 key id → base64 public key.
    curve25519: BTreeMap<String, String>,
}

#[derive(Serialize)]
struct EncryptResultJs {
    /// 0 = PreKey (first message of a fresh outbound session before peer
    /// has replied), 1 = Normal (post-handshake).
    #[serde(rename = "type")]
    msg_type: u8,
    /// base64-encoded Olm message body
    body: String,
}

// ── Account ─────────────────────────────────────────────────────────────────

#[derive(uniffi::Object)]
pub struct Account {
    inner: Mutex<VAccount>,
}

#[uniffi::export]
impl Account {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self { inner: Mutex::new(VAccount::new()) })
    }

    /// Restore from a JSON pickle produced by `pickle()`.
    #[uniffi::constructor(name = "from_pickle")]
    pub fn from_pickle(pickle: String) -> Result<Arc<Self>> {
        let parsed: AccountPickle = serde_json::from_str(&pickle)
            .map_err(|e| VodozemacError::InvalidPickle { reason: e.to_string() })?;
        Ok(Arc::new(Self {
            inner: Mutex::new(VAccount::from_pickle(parsed)),
        }))
    }

    /// JSON string `{ "curve25519": "<base64>", "ed25519": "<base64>" }`.
    pub fn identity_keys(&self) -> Result<String> {
        let inner = self.lock_inner()?;
        let keys = inner.identity_keys();
        let out = IdentityKeysJs {
            curve25519: keys.curve25519.to_base64(),
            ed25519: keys.ed25519.to_base64(),
        };
        serde_json::to_string(&out)
            .map_err(|e| VodozemacError::Internal { reason: e.to_string() })
    }

    pub fn generate_one_time_keys(&self, count: u32) -> Result<()> {
        let mut inner = self.lock_inner()?;
        inner.generate_one_time_keys(count as usize);
        Ok(())
    }

    /// Returns unpublished one-time keys as a JSON string:
    /// `{ "curve25519": { "<keyId>": "<publicKey>" } }`.
    /// After `mark_keys_as_published`, the inner map is empty.
    pub fn one_time_keys(&self) -> Result<String> {
        let inner = self.lock_inner()?;
        let keys = inner.one_time_keys();
        let mut out = BTreeMap::new();
        for (id, pk) in keys.iter() {
            out.insert(key_id_to_string(*id), pk.to_base64());
        }
        let wrapper = OneTimeKeysJs { curve25519: out };
        serde_json::to_string(&wrapper)
            .map_err(|e| VodozemacError::Internal { reason: e.to_string() })
    }

    pub fn mark_keys_as_published(&self) -> Result<()> {
        let mut inner = self.lock_inner()?;
        inner.mark_keys_as_published();
        Ok(())
    }

    pub fn max_number_of_one_time_keys(&self) -> Result<u32> {
        let inner = self.lock_inner()?;
        Ok(inner.max_number_of_one_time_keys() as u32)
    }

    pub fn generate_fallback_key(&self) -> Result<()> {
        let mut inner = self.lock_inner()?;
        inner.generate_fallback_key();
        Ok(())
    }

    /// Returns the unpublished fallback key as a JSON string in the same
    /// shape as `one_time_keys()` — `{ "curve25519": { "<id>": "<pub>" } }`.
    /// Empty inner map if no unpublished fallback exists.
    pub fn fallback_key(&self) -> Result<String> {
        let inner = self.lock_inner()?;
        let keys = inner.fallback_key();
        let mut out = BTreeMap::new();
        for (id, pk) in keys.iter() {
            out.insert(key_id_to_string(*id), pk.to_base64());
        }
        let wrapper = OneTimeKeysJs { curve25519: out };
        serde_json::to_string(&wrapper)
            .map_err(|e| VodozemacError::Internal { reason: e.to_string() })
    }

    /// Sign the given message with this account's Ed25519 identity key,
    /// returning a base64 signature.
    pub fn sign(&self, message: String) -> Result<String> {
        let inner = self.lock_inner()?;
        Ok(inner.sign(message.as_bytes()).to_base64())
    }

    /// Returns the JSON pickle string.
    pub fn pickle(&self) -> Result<String> {
        let inner = self.lock_inner()?;
        let p = inner.pickle();
        serde_json::to_string(&p)
            .map_err(|e| VodozemacError::Internal { reason: e.to_string() })
    }

    /// Create an outbound Olm session targeting a peer device, using their
    /// identity key + one-time-key (or fallback prekey when pool is empty).
    /// Both keys are base64.
    pub fn create_outbound_session(
        &self,
        their_identity_key: String,
        their_one_time_key: String,
    ) -> Result<Arc<Session>> {
        let inner = self.lock_inner()?;
        let id_key = parse_curve(&their_identity_key)?;
        let otk = parse_curve(&their_one_time_key)?;
        let session = inner
            .create_outbound_session(SessionConfig::version_1(), id_key, otk)
            .map_err(|e| VodozemacError::SessionError { reason: e.to_string() })?;
        Ok(Arc::new(Session { inner: Mutex::new(session) }))
    }

    /// Create an inbound session from a received prekey message body.
    /// The peer's identity key is extracted from the message itself
    /// (libolm-compatible behaviour). Returns the new session and the
    /// decrypted plaintext of the initial message together.
    pub fn create_inbound_session(
        &self,
        prekey_message_body: String,
    ) -> Result<Arc<InboundResult>> {
        let mut inner = self.lock_inner()?;
        let pkm = PreKeyMessage::from_base64(&prekey_message_body)
            .map_err(|e| VodozemacError::InvalidBase64 { reason: e.to_string() })?;
        let id_key = pkm.identity_key();
        let result = inner
            .create_inbound_session(SessionConfig::version_1(), id_key, &pkm)
            .map_err(|e| VodozemacError::SessionError { reason: e.to_string() })?;
        let plaintext = String::from_utf8(result.plaintext)
            .map_err(|e| VodozemacError::InvalidUtf8 { reason: e.to_string() })?;
        Ok(Arc::new(InboundResult {
            session: Mutex::new(Some(Arc::new(Session {
                inner: Mutex::new(result.session),
            }))),
            plaintext,
            sender_identity_key: id_key.to_base64(),
        }))
    }
}

impl Account {
    fn lock_inner(&self) -> Result<std::sync::MutexGuard<'_, VAccount>> {
        self.inner
            .lock()
            .map_err(|_| VodozemacError::Internal { reason: "account mutex poisoned".into() })
    }
}

// ── Session ─────────────────────────────────────────────────────────────────

#[derive(uniffi::Object)]
pub struct Session {
    inner: Mutex<VSession>,
}

#[uniffi::export]
impl Session {
    /// Restore from a JSON pickle produced by `pickle()`.
    #[uniffi::constructor(name = "from_pickle")]
    pub fn from_pickle(pickle: String) -> Result<Arc<Self>> {
        let parsed: SessionPickle = serde_json::from_str(&pickle)
            .map_err(|e| VodozemacError::InvalidPickle { reason: e.to_string() })?;
        Ok(Arc::new(Self {
            inner: Mutex::new(VSession::from_pickle(parsed)),
        }))
    }

    /// JSON string `{ "type": 0|1, "body": "<base64>" }`. Type 0 = PreKey,
    /// 1 = Normal.
    pub fn encrypt(&self, plaintext: String) -> Result<String> {
        let mut inner = self.lock_inner()?;
        let msg = inner
            .encrypt(plaintext.as_bytes())
            .map_err(|e| VodozemacError::Internal { reason: e.to_string() })?;
        let out = match msg {
            OlmMessage::PreKey(pkm) => EncryptResultJs {
                msg_type: 0,
                body: pkm.to_base64(),
            },
            OlmMessage::Normal(m) => EncryptResultJs {
                msg_type: 1,
                body: m.to_base64(),
            },
        };
        serde_json::to_string(&out)
            .map_err(|e| VodozemacError::Internal { reason: e.to_string() })
    }

    /// Decrypt a message of the given type (0 = PreKey, 1 = Normal).
    pub fn decrypt(&self, message_type: u8, body: String) -> Result<String> {
        let mut inner = self.lock_inner()?;
        let msg = match message_type {
            0 => OlmMessage::PreKey(
                PreKeyMessage::from_base64(&body)
                    .map_err(|e| VodozemacError::InvalidBase64 { reason: e.to_string() })?,
            ),
            1 => OlmMessage::Normal(
                vodozemac::olm::Message::from_base64(&body)
                    .map_err(|e| VodozemacError::InvalidBase64 { reason: e.to_string() })?,
            ),
            _ => return Err(VodozemacError::InvalidMessageType { value: message_type }),
        };
        let plaintext = inner
            .decrypt(&msg)
            .map_err(|e| VodozemacError::DecryptError { reason: e.to_string() })?;
        String::from_utf8(plaintext)
            .map_err(|e| VodozemacError::InvalidUtf8 { reason: e.to_string() })
    }

    pub fn session_id(&self) -> Result<String> {
        let inner = self.lock_inner()?;
        Ok(inner.session_id())
    }

    pub fn has_received_message(&self) -> Result<bool> {
        let inner = self.lock_inner()?;
        Ok(inner.has_received_message())
    }

    /// Returns the JSON pickle string.
    pub fn pickle(&self) -> Result<String> {
        let inner = self.lock_inner()?;
        let p = inner.pickle();
        serde_json::to_string(&p)
            .map_err(|e| VodozemacError::Internal { reason: e.to_string() })
    }
}

impl Session {
    fn lock_inner(&self) -> Result<std::sync::MutexGuard<'_, VSession>> {
        self.inner
            .lock()
            .map_err(|_| VodozemacError::Internal { reason: "session mutex poisoned".into() })
    }
}

// ── InboundResult ──────────────────────────────────────────────────────────

#[derive(uniffi::Object)]
pub struct InboundResult {
    // Wrapped in Mutex<Option<...>> so `take_session()` can move it out
    // exactly once across the FFI boundary.
    session: Mutex<Option<Arc<Session>>>,
    plaintext: String,
    sender_identity_key: String,
}

#[uniffi::export]
impl InboundResult {
    /// Take ownership of the new session. Errors if called twice.
    pub fn take_session(&self) -> Result<Arc<Session>> {
        let mut slot = self
            .session
            .lock()
            .map_err(|_| VodozemacError::Internal { reason: "inbound mutex poisoned".into() })?;
        slot.take().ok_or(VodozemacError::SessionAlreadyTaken)
    }

    pub fn plaintext(&self) -> String {
        self.plaintext.clone()
    }

    /// The peer's curve25519 identity key, extracted from the prekey message.
    /// Useful for on-prekey-message new-device discovery.
    pub fn sender_identity_key(&self) -> String {
        self.sender_identity_key.clone()
    }
}

// ── tests ──────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    /// End-to-end roundtrip: Alice and Bob each create an Account, publish
    /// keys, Alice sends a prekey message to Bob, Bob decrypts it and
    /// replies, Alice decrypts the reply. Exercises every method needed
    /// for the first two messages of a fresh Olm session.
    #[test]
    fn prekey_and_reply_roundtrip() {
        let alice = Account::new();
        let bob = Account::new();
        bob.generate_one_time_keys(1).unwrap();

        // Pull Bob's identity + one OTK as base64 strings (the SDK gets
        // these via the key bundle wire format; here we extract from JSON).
        let bob_identity: serde_json::Value =
            serde_json::from_str(&bob.identity_keys().unwrap()).unwrap();
        let bob_id_curve = bob_identity["curve25519"].as_str().unwrap().to_string();

        let bob_otks: serde_json::Value =
            serde_json::from_str(&bob.one_time_keys().unwrap()).unwrap();
        let (_bob_otk_id, bob_otk) = bob_otks["curve25519"]
            .as_object()
            .unwrap()
            .iter()
            .next()
            .unwrap();
        let bob_otk = bob_otk.as_str().unwrap().to_string();
        bob.mark_keys_as_published().unwrap();

        // Alice → Bob: prekey message
        let alice_session = alice
            .create_outbound_session(bob_id_curve.clone(), bob_otk.clone())
            .unwrap();
        let enc_out = alice_session.encrypt("hello bob".to_string()).unwrap();
        let enc: serde_json::Value = serde_json::from_str(&enc_out).unwrap();
        assert_eq!(enc["type"], 0); // PreKey
        let alice_to_bob_body = enc["body"].as_str().unwrap().to_string();

        // Bob receives + decrypts via create_inbound_session
        let inbound = bob.create_inbound_session(alice_to_bob_body).unwrap();
        assert_eq!(inbound.plaintext(), "hello bob");
        let bob_session = inbound.take_session().unwrap();

        // Bob → Alice: reply (now Normal type)
        let reply = bob_session.encrypt("hi alice".to_string()).unwrap();
        let reply_v: serde_json::Value = serde_json::from_str(&reply).unwrap();
        // Bob hasn't been written to by Alice's session response yet, so
        // his outbound is still PreKey-shaped from libolm's perspective.
        // The important property is round-trip decoding works:
        let reply_type = reply_v["type"].as_u64().unwrap() as u8;
        let reply_body = reply_v["body"].as_str().unwrap().to_string();

        let decoded = alice_session.decrypt(reply_type, reply_body).unwrap();
        assert_eq!(decoded, "hi alice");
    }

    /// Pickle round-trip: account survives serialize → deserialize.
    #[test]
    fn account_pickle_roundtrip() {
        let acc = Account::new();
        acc.generate_one_time_keys(2).unwrap();
        let keys_before = acc.identity_keys().unwrap();
        let one_time_before = acc.one_time_keys().unwrap();

        let pickled = acc.pickle().unwrap();
        let restored = Account::from_pickle(pickled).unwrap();
        assert_eq!(restored.identity_keys().unwrap(), keys_before);
        assert_eq!(restored.one_time_keys().unwrap(), one_time_before);
    }

    /// take_session is one-shot.
    #[test]
    fn inbound_take_session_only_once() {
        // Build a minimal prekey scenario inline so we can test InboundResult.
        let alice = Account::new();
        let bob = Account::new();
        bob.generate_one_time_keys(1).unwrap();

        let bob_id_keys: serde_json::Value =
            serde_json::from_str(&bob.identity_keys().unwrap()).unwrap();
        let bob_id = bob_id_keys["curve25519"].as_str().unwrap().to_string();
        let bob_otks: serde_json::Value =
            serde_json::from_str(&bob.one_time_keys().unwrap()).unwrap();
        let bob_otk = bob_otks["curve25519"]
            .as_object()
            .unwrap()
            .values()
            .next()
            .unwrap()
            .as_str()
            .unwrap()
            .to_string();

        let alice_sess = alice.create_outbound_session(bob_id, bob_otk).unwrap();
        let enc: serde_json::Value =
            serde_json::from_str(&alice_sess.encrypt("hi".into()).unwrap()).unwrap();
        let body = enc["body"].as_str().unwrap().to_string();

        let inbound = bob.create_inbound_session(body).unwrap();
        assert!(inbound.take_session().is_ok());
        assert!(matches!(
            inbound.take_session(),
            Err(VodozemacError::SessionAlreadyTaken)
        ));
    }
}
