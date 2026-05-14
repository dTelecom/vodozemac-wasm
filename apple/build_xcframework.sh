#!/usr/bin/env bash
#
# Build the VodozemacFFI XCFramework for iOS device + iOS Simulator.
#
# Inputs: crates/vodozemac-ffi (Rust UniFFI crate)
# Outputs:
#   apple/VodozemacFFI.xcframework               — binary framework for SwiftPM consumers
#   apple/Sources/VodozemacFFI/VodozemacFFI.swift — UniFFI-generated Swift bindings
#
# Run from anywhere; the script cd's to its own directory first.
#
# Pattern adapted from matrix-rust-sdk/bindings/apple/build_crypto_xcframework.sh,
# trimmed to iOS only (no macOS / Catalyst — add later if needed).

set -eEuo pipefail

cd "$(dirname "$0")"
APPLE_DIR="$(pwd)"
ROOT_DIR="${APPLE_DIR}/.."
TARGET_DIR="${ROOT_DIR}/target"
TARGET_CRATE="vodozemac-ffi"
LIB_NAME="libvodozemac_ffi.a"
FRAMEWORK_NAME="VodozemacFFI"

# Scratch directory for lipo'd sim binary + intermediate headers.
GENERATED_DIR="${APPLE_DIR}/build"
rm -rf "${GENERATED_DIR}"
mkdir -p "${GENERATED_DIR}/simulator" "${GENERATED_DIR}/headers"

# ── 1. Compile Rust for each iOS target ───────────────────────────────────
# iOS SDK path is exported because some C-dep build scripts (e.g. vodozemac's
# transitive openssl bits, none here, but kept for forward-compat) read it.
export IOS_SDK_PATH="$(xcrun --show-sdk-path --sdk iphoneos)"

echo "→ build aarch64-apple-ios       (device)"
cargo build -p "${TARGET_CRATE}" --release --target aarch64-apple-ios

echo "→ build aarch64-apple-ios-sim   (sim arm64)"
cargo build -p "${TARGET_CRATE}" --release --target aarch64-apple-ios-sim

echo "→ build x86_64-apple-ios        (sim x86_64)"
cargo build -p "${TARGET_CRATE}" --release --target x86_64-apple-ios

# ── 2. Lipo the two sim slices into one fat sim staticlib ─────────────────
echo "→ lipo sim slices"
lipo -create \
  "${TARGET_DIR}/aarch64-apple-ios-sim/release/${LIB_NAME}" \
  "${TARGET_DIR}/x86_64-apple-ios/release/${LIB_NAME}" \
  -output "${GENERATED_DIR}/simulator/${LIB_NAME}"

# ── 3. Generate the Swift / C bindings ────────────────────────────────────
# UniFFI introspects the static lib's symbols to derive the interface, so
# we can point it at any built slice (use the device one).
echo "→ generate Swift bindings"
cargo run -p "${TARGET_CRATE}" --bin uniffi-bindgen --release -- generate \
  --library "${TARGET_DIR}/aarch64-apple-ios/release/${LIB_NAME}" \
  --language swift \
  --out-dir "${GENERATED_DIR}"

# Place the Swift source where the SwiftPM target expects it.
SOURCES_DIR="${APPLE_DIR}/Sources/${FRAMEWORK_NAME}"
mkdir -p "${SOURCES_DIR}"
mv "${GENERATED_DIR}/${FRAMEWORK_NAME}.swift" "${SOURCES_DIR}/${FRAMEWORK_NAME}.swift"

# Move headers + module map into a single `headers/` dir for xcodebuild.
mv "${GENERATED_DIR}/${FRAMEWORK_NAME}FFI.h" "${GENERATED_DIR}/headers/"
# xcodebuild wants the module map named exactly `module.modulemap`.
mv "${GENERATED_DIR}/${FRAMEWORK_NAME}FFI.modulemap" \
   "${GENERATED_DIR}/headers/module.modulemap"

# ── 4. Assemble the XCFramework ───────────────────────────────────────────
XCFRAMEWORK="${APPLE_DIR}/${FRAMEWORK_NAME}.xcframework"
rm -rf "${XCFRAMEWORK}"

echo "→ create-xcframework"
xcodebuild -create-xcframework \
  -library "${TARGET_DIR}/aarch64-apple-ios/release/${LIB_NAME}" \
  -headers "${GENERATED_DIR}/headers" \
  -library "${GENERATED_DIR}/simulator/${LIB_NAME}" \
  -headers "${GENERATED_DIR}/headers" \
  -output "${XCFRAMEWORK}"

# Scratch artifacts no longer needed; the XCFramework + generated Swift are
# the deliverables.
rm -rf "${GENERATED_DIR}"

echo ""
echo "✓ ${FRAMEWORK_NAME}.xcframework + Sources/${FRAMEWORK_NAME}/${FRAMEWORK_NAME}.swift ready"
