// Public surface for @dtelecom/vodozemac-rn.
//
// Mirrors @dtelecom/vodozemac-wasm's pkg-web shape exactly: same class
// names, same method names, same JSON-string return shapes for the
// structured outputs (identityKeys, oneTimeKeys, encrypt result, etc.).
// This is the gate that makes secure-chat-client target-agnostic — the
// SDK's `olm-adapter.ts` doesn't know whether it's hitting WASM or a
// native bridge.

import Native from "./NativeVodozemac";

// FinalizationRegistry isn't part of Hermes's older builds, but every RN
// Hermes V1 ships it. Guard with a runtime check anyway so the package
// degrades to "you must call close()" on an engine that lacks it.
type Finalizer = (handle: number) => void;
const makeRegistry = (finalize: Finalizer) => {
  if (typeof FinalizationRegistry === "undefined") {
    return null;
  }
  return new FinalizationRegistry<number>((handle: number) => {
    try {
      finalize(handle);
    } catch {
      // GC-time errors can't propagate anywhere useful. Swallow.
    }
  });
};

const accountFinalizer = makeRegistry(Native.accountClose);
const sessionFinalizer = makeRegistry(Native.sessionClose);

/**
 * Olm account — long-lived identity + one-time-key store. Persist via
 * {@link pickle} between app launches; restore with {@link fromPickle}.
 *
 * Lifetime: a finalizer releases the underlying Rust handle when the JS
 * wrapper is garbage-collected. For deterministic cleanup (the typical
 * case before signing out / wiping local state), call {@link close}.
 */
export class Account {
  private handle: number | null;

  /**
   * Mirrors `@dtelecom/vodozemac-wasm`'s pkg-web shape: `new Account()`
   * allocates a fresh native account (wasm-bindgen exposes Rust's
   * `pub fn new() -> Account` as the JS constructor, so consumers like
   * `@dtelecom/secure-chat-client` use this form directly). When a
   * `handle` is passed explicitly the wrapper is built around an
   * existing native handle — internal call sites in `createOutbound-
   * Session` / `Session.takeSession` / `Account.fromPickle` use that path.
   */
  constructor(handle?: number) {
    const resolved =
      typeof handle === "number" ? handle : Native.accountNew();
    this.handle = resolved;
    accountFinalizer?.register(this, resolved, this);
  }

  /** Create a fresh account with a new identity key. Sugar for
   *  `new Account()` — kept for symmetry with `Session.fromPickle()` etc. */
  static new(): Account {
    return new Account();
  }

  /** Restore from a JSON pickle produced by {@link pickle}. */
  static fromPickle(pickle: string): Account {
    return new Account(Native.accountFromPickle(pickle));
  }

  private h(): number {
    if (this.handle === null) {
      throw new Error("Account has been closed");
    }
    return this.handle;
  }

  /** JSON string `{ "curve25519": "<base64>", "ed25519": "<base64>" }`. */
  identityKeys(): string {
    return Native.accountIdentityKeys(this.h());
  }

  generateOneTimeKeys(count: number): void {
    Native.accountGenerateOneTimeKeys(this.h(), count);
  }

  /**
   * Returns unpublished one-time keys as a JSON string:
   * `{ "curve25519": { "<keyId>": "<publicKey>" } }`.
   * After {@link markKeysAsPublished}, the inner map is empty.
   */
  oneTimeKeys(): string {
    return Native.accountOneTimeKeys(this.h());
  }

  markKeysAsPublished(): void {
    Native.accountMarkKeysAsPublished(this.h());
  }

  maxNumberOfOneTimeKeys(): number {
    return Native.accountMaxNumberOfOneTimeKeys(this.h());
  }

  generateFallbackKey(): void {
    Native.accountGenerateFallbackKey(this.h());
  }

  /**
   * Returns the unpublished fallback key as a JSON string in the same shape
   * as {@link oneTimeKeys} — `{ "curve25519": { "<id>": "<pub>" } }`.
   */
  fallbackKey(): string {
    return Native.accountFallbackKey(this.h());
  }

  /** Sign the given message with this account's Ed25519 identity key. */
  sign(message: string): string {
    return Native.accountSign(this.h(), message);
  }

  /** Serialize to JSON pickle. */
  pickle(): string {
    return Native.accountPickle(this.h());
  }

  /**
   * Create an outbound Olm session targeting a peer device. Both keys
   * are URL-safe base64 (no padding).
   */
  createOutboundSession(
    theirIdentityKey: string,
    theirOneTimeKey: string,
  ): Session {
    const sessHandle = Native.accountCreateOutboundSession(
      this.h(),
      theirIdentityKey,
      theirOneTimeKey,
    );
    return new Session(sessHandle);
  }

  /**
   * Create an inbound session from a received prekey message body.
   * The peer's identity key is extracted from the message itself.
   */
  createInboundSession(prekeyMessageBody: string): InboundResult {
    const r = Native.accountCreateInboundSession(this.h(), prekeyMessageBody);
    return new InboundResult(
      r.sessionHandle,
      r.plaintext,
      r.senderIdentityKey,
    );
  }

  /** Release the native handle eagerly. Safe to call multiple times. */
  close(): void {
    if (this.handle !== null) {
      Native.accountClose(this.handle);
      accountFinalizer?.unregister(this);
      this.handle = null;
    }
  }
}

/**
 * An established Olm session (one peer device). Sessions are owned;
 * always pickle them before persisting and restore with {@link fromPickle}.
 */
export class Session {
  private handle: number | null;

  /** Internal — use {@link Account.createOutboundSession}, {@link Account.createInboundSession}, or {@link Session.fromPickle}. */
  constructor(handle: number) {
    this.handle = handle;
    sessionFinalizer?.register(this, handle, this);
  }

  static fromPickle(pickle: string): Session {
    return new Session(Native.sessionFromPickle(pickle));
  }

  private h(): number {
    if (this.handle === null) {
      throw new Error("Session has been closed");
    }
    return this.handle;
  }

  /** Encrypt. Returns JSON `{ "type": 0|1, "body": "<base64>" }`. */
  encrypt(plaintext: string): string {
    return Native.sessionEncrypt(this.h(), plaintext);
  }

  /** Decrypt. `messageType` is 0 for PreKey, 1 for Normal. */
  decrypt(messageType: number, body: string): string {
    return Native.sessionDecrypt(this.h(), messageType, body);
  }

  sessionId(): string {
    return Native.sessionSessionId(this.h());
  }

  hasReceivedMessage(): boolean {
    return Native.sessionHasReceivedMessage(this.h());
  }

  pickle(): string {
    return Native.sessionPickle(this.h());
  }

  /** Release the native handle eagerly. Safe to call multiple times. */
  close(): void {
    if (this.handle !== null) {
      Native.sessionClose(this.handle);
      sessionFinalizer?.unregister(this);
      this.handle = null;
    }
  }
}

/**
 * Result of {@link Account.createInboundSession}. Carries the new session
 * (owned, take exactly once via {@link takeSession}), the decrypted
 * plaintext of the prekey message, and the peer's identity key.
 */
export class InboundResult {
  private sessionHandle: number | null;
  readonly plaintext: string;
  readonly senderIdentityKey: string;

  constructor(
    sessionHandle: number,
    plaintext: string,
    senderIdentityKey: string,
  ) {
    this.sessionHandle = sessionHandle;
    this.plaintext = plaintext;
    this.senderIdentityKey = senderIdentityKey;
  }

  /** Take ownership of the new Session. Throws if called twice. */
  takeSession(): Session {
    if (this.sessionHandle === null) {
      throw new Error("session already taken");
    }
    const handle = this.sessionHandle;
    this.sessionHandle = null;
    return new Session(handle);
  }
}

/**
 * No-op on RN — the native libs are loaded at TurboModule registration
 * time, before any JS code runs. Exists only so the package's API
 * matches `@dtelecom/vodozemac-wasm`'s `await init()` shape, letting
 * `secure-chat-client` use the same bootstrap path on web/node/RN.
 */
export default async function init(): Promise<void> {
  // Touching Native here triggers the TurboModule registration check
  // (`getEnforcing` throws if the module wasn't linked). Calling a
  // cheap method like accountMaxNumberOfOneTimeKeys would require an
  // already-allocated handle, so just resolve.
  return Promise.resolve();
}
