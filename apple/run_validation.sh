#!/usr/bin/env bash
#
# Smoke-test the UniFFI Swift binding on the host (no iOS sim required).
# Builds `libvodozemac_ffi.dylib` for the host arch via cargo, generates
# Swift bindings + module map, compiles `Tests/smoke_validation.swift`
# against them, runs the binary. Exits non-zero on any failure.
#
# What this validates: the Rust → Swift FFI layer roundtrips correctly.
# What this does NOT validate: iOS-specific behaviour (sim only). That's
# Phase 4's job (RN TurboModule on iOS sim).

set -eEuo pipefail

cd "$(dirname "$0")"
APPLE_DIR="$(pwd)"
ROOT_DIR="${APPLE_DIR}/.."
TARGET_DIR="${ROOT_DIR}/target"

SCRATCH="${APPLE_DIR}/.validation"
rm -rf "${SCRATCH}"
mkdir -p "${SCRATCH}/headers"

# ── 1. Build the host dylib (default cargo target = native arch) ──────
echo "→ build host dylib"
cargo build -p vodozemac-ffi --release

# ── 2. Generate Swift bindings against the host dylib ────────────────
echo "→ generate Swift bindings"
cargo run -p vodozemac-ffi --bin uniffi-bindgen --release -- generate \
  --library "${TARGET_DIR}/release/libvodozemac_ffi.dylib" \
  --language swift \
  --out-dir "${SCRATCH}"

# UniFFI emits VodozemacFFIFFI.h / .modulemap separately; swiftc wants
# them under a directory whose `-I` we pass, and the modulemap needs to
# be named `module.modulemap` for clang to pick it up automatically.
mv "${SCRATCH}/VodozemacFFIFFI.h" "${SCRATCH}/headers/"
mv "${SCRATCH}/VodozemacFFIFFI.modulemap" "${SCRATCH}/headers/module.modulemap"

# ── 3. Compile + link the smoke test ─────────────────────────────────
echo "→ compile + link smoke test"
swiftc \
  -O \
  -I "${SCRATCH}/headers" \
  -L "${TARGET_DIR}/release" \
  -lvodozemac_ffi \
  -Xlinker -rpath -Xlinker "${TARGET_DIR}/release" \
  "${SCRATCH}/VodozemacFFI.swift" \
  "${APPLE_DIR}/Tests/smoke_validation.swift" \
  -o "${SCRATCH}/smoke"

# ── 4. Run ─────────────────────────────────────────────────────────────
echo "→ run"
echo ""
"${SCRATCH}/smoke"

rm -rf "${SCRATCH}"
