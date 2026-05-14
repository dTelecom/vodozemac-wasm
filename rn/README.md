# @dtelecom/vodozemac-rn

React Native bindings for [vodozemac](https://github.com/matrix-org/vodozemac)
(Olm primitives), exposed via a UniFFI-generated Swift + Kotlin native
bridge. Drop-in replacement for `@dtelecom/vodozemac-wasm` on the React
Native target — same JS surface (`Account`, `Session`, `InboundResult`),
same JSON-string shapes, same pickle format.

Used by `@dtelecom/secure-chat-client` when running on React Native.

## Why a native bridge instead of WASM

WebAssembly is not yet shipped in any React Native release. Hermes V1
(RN 0.84+) has runtime Wasm support as of the Feb 2026 preview, but the
implementation is in Meta's internal monorepo and isn't reachable from
any public Hermes commit or RN-bundled prebuilt as of mid-2026. This
package routes around the engine entirely: Rust → UniFFI → Swift/Kotlin
→ TurboModule. No engine dependency, no polyfills.

## Install

```sh
npm install @dtelecom/vodozemac-rn react-native-get-random-values
```

Then once at the top of your app entry (`index.js`), before importing
anything else:

```ts
import "react-native-get-random-values";
```

The package ships prebuilt artifacts (iOS XCFramework + Android .so for
arm64-v8a, armeabi-v7a, x86_64) — no Rust toolchain needed on the
consumer's machine.

## Use

```ts
import init, { Account } from "@dtelecom/vodozemac-rn";

await init();                         // no-op on RN; included for parity
                                      // with @dtelecom/vodozemac-wasm

const account = Account.new();
account.generateOneTimeKeys(50);

const ids = JSON.parse(account.identityKeys());
// { curve25519: "...", ed25519: "..." }

const otks = JSON.parse(account.oneTimeKeys()).curve25519;
// { "<base64KeyId>": "<base64PublicKey>", ... }
account.markKeysAsPublished();

// Serialize for persistence — caller is responsible for at-rest encryption.
const pickle = account.pickle();
// later, restore:
const restored = Account.fromPickle(pickle);

// Release the native handle eagerly. The package also registers a
// FinalizationRegistry callback so GC will close handles eventually,
// but `close()` is the deterministic path.
account.close();
```

## API

Identical to `@dtelecom/vodozemac-wasm`. See its README for the full
method list. Method names, argument shapes, and return-value JSON
schemas are bit-for-bit compatible — code calling vodozemac through
`@dtelecom/secure-chat-client` doesn't know which target it's on.

## Platforms

- iOS 15.1+ (arm64 device + arm64/x86_64 simulator)
- Android API 24+ (arm64-v8a, armeabi-v7a, x86_64)
- React Native 0.76+ (new architecture / bridgeless)

## License

Apache-2.0
