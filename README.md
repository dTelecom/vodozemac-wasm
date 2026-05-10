# @dtelecom/vodozemac-wasm

Browser + Node WASM bindings for [vodozemac](https://github.com/matrix-org/vodozemac), exposing only the Olm primitives needed for non-Matrix 1:1 chat protocols. No Matrix-specific types, no protocol assumptions about user/device id shape.

Built from a small Rust crate that wraps `vodozemac` via `wasm-bindgen`. Same wire format as libolm (Olm v1), so existing libolm-pickled state is migration-friendly via the standalone `vodozemac::olm::libolm_compat` path (not exposed in v0.1.0 — add when needed).

## Why

`@matrix-org/olm` (libolm) has been EOL since Oct 2023 with known CVEs. The Matrix-recommended successor (`@matrix-org/matrix-sdk-crypto-wasm`) only exposes the high-level Matrix-protocol `OlmMachine`, not raw Olm primitives. This package fills the gap.

## API surface

```ts
import init, { Account, Session, InboundResult } from "@dtelecom/vodozemac-wasm";
// In Node (test runner) the `init` is a no-op; in the browser it loads the WASM.
await init();

const a = new Account();
a.identityKeys();                               // { curve25519, ed25519 }
a.generateOneTimeKeys(100);
a.oneTimeKeys();                                // { curve25519: { <id>: <publicKey>, ... } }
a.markKeysAsPublished();
a.generateFallbackKey();
a.fallbackKey();
a.sign("message");                              // base64 Ed25519 sig
const pickle: string = a.pickle();
const restored = Account.fromPickle(pickle);

// Outbound:
const session: Session = a.createOutboundSession(theirIdKey, theirOTK);
const { type, body } = session.encrypt("hi");   // type=0 prekey, type=1 normal

// Inbound:
const result: InboundResult = a.createInboundSession(theirIdKey, prekeyBody);
const session2 = result.takeSession();
const plaintext = result.plaintext;

// Persistence:
const sp: string = session.pickle();
const restored2 = Session.fromPickle(sp);
```

## Build

Requires Rust 1.85+ (edition 2024) and `wasm-pack`.

```sh
npm run build       # both web + node targets
npm run build:web   # browser bundlers (vite, webpack)
npm run build:node  # Node test runners
```

Output:
- `pkg-web/` — ESM, browser-targeted; calls `init(url)` to load `.wasm` via fetch
- `pkg-node/` — CommonJS-like, Node-targeted; loads `.wasm` synchronously via `fs`

Bundle size: ~400 KB unoptimized, ~150 KB gzipped (vs libolm's ~750 KB unoptimized).

## Status

v0.1.0 — supports the Olm primitives needed by `@dtelecom/secure-chat-client`. Megolm (group sessions), libolm-pickle migration, SAS verification not yet bound. Add when a consumer needs them.

React Native (iOS/Android) bindings via UniFFI — planned for the same Rust crate. Not in v0.1.0.
