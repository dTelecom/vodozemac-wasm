# @dtelecom/vodozemac-wasm

Browser + Node + React Native WASM bindings for [vodozemac](https://github.com/matrix-org/vodozemac), exposing only the Olm primitives needed for non-Matrix 1:1 chat protocols. No Matrix-specific types, no protocol assumptions about user/device id shape.

Built from a small Rust crate that wraps `vodozemac` via `wasm-bindgen`. Same wire format as libolm (Olm v1), so existing libolm-pickled state is migration-friendly via the standalone `vodozemac::olm::libolm_compat` path (not exposed in v0.1.0 — add when needed).

## Why

`@matrix-org/olm` (libolm) has been EOL since Oct 2023 with known CVEs. The Matrix-recommended successor (`@matrix-org/matrix-sdk-crypto-wasm`) only exposes the high-level Matrix-protocol `OlmMachine`, not raw Olm primitives. This package fills the gap.

## API surface

```ts
import init, { Account, Session, InboundResult } from "@dtelecom/vodozemac-wasm";
// Node loads WASM synchronously at module import — `init()` is a no-op.
// Browser fetches the .wasm asset on first init().
// React Native (Hermes V1 / RN 0.84+) decodes the embedded base64 on first init().
// Same call site in all three; the conditional package exports route to the
// right loader automatically.
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
npm run build       # all three targets
npm run build:web   # browser bundlers (vite, webpack)
npm run build:node  # Node test runners
npm run build:rn    # React Native (Hermes V1 / RN 0.84+) — derives from pkg-web; no Rust rebuild
```

Output:
- `pkg-web/` — ESM, browser-targeted; calls `init(url)` to load `.wasm` via fetch
- `pkg-node/` — CommonJS-like, Node-targeted; loads `.wasm` synchronously via `fs`
- `pkg-rn/` — ESM, React Native-targeted (Hermes V1 / RN 0.84+); WASM bytes are base64-embedded into the JS bundle so Metro doesn't need to ship them as a separate asset. The browser glue is reused with `__wbg_init` and `__wbg_load` stripped (those depend on `import.meta.url` + `fetch` which Metro can't resolve to a real `.wasm` asset). Caller calls the default async `init()` once; subsequent calls are no-ops.

Bundle size: ~400 KB raw WASM, ~150 KB gzipped (vs libolm's ~750 KB unoptimized). The RN target adds ~520 KB of base64 string for the WASM bytes — measurable but acceptable for an RN bundle.

## Status

v0.2.0 — adds the React Native target (`pkg-rn/`). Same Olm primitives as v0.1.0, no API or wire-format changes from the consumer's POV. Megolm (group sessions), libolm-pickle migration, and SAS verification still not bound — add when a consumer needs them.
