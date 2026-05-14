#!/usr/bin/env bash
#
# Build the Android AAR for VodozemacFFI.
#
# Inputs: crates/vodozemac-ffi (Rust UniFFI crate)
# Outputs:
#   android/build/outputs/aar/vodozemac-release.aar
#   android/src/main/kotlin/com/dtelecom/vodozemac/vodozemac.kt
#   android/src/main/jniLibs/{abi}/libvodozemac_ffi.so
#
# Pattern adapted from matrix-rust-sdk's android build flow + UniFFI's
# Kotlin guide. Cross-compilation runs via cargo-ndk; Gradle (via the
# wrapper) packages the resulting .so + generated Kotlin into an AAR.

set -eEuo pipefail

cd "$(dirname "$0")"
ANDROID_DIR="$(pwd)"
ROOT_DIR="${ANDROID_DIR}/.."
TARGET_DIR="${ROOT_DIR}/target"
TARGET_CRATE="vodozemac-ffi"
LIB_NAME="libvodozemac_ffi.so"

# ── 0. Locate Android SDK / NDK ──────────────────────────────────────────
# Honor existing ANDROID_HOME / ANDROID_NDK_HOME if set; otherwise fall
# back to the standard Android Studio install location on macOS.
export ANDROID_HOME="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
if [ ! -d "${ANDROID_HOME}" ]; then
  echo "error: Android SDK not found at ANDROID_HOME=${ANDROID_HOME}" >&2
  echo "  install via Android Studio, or export ANDROID_HOME explicitly." >&2
  exit 1
fi

# Pick the newest installed NDK. Required by cargo-ndk to find clang.
NDK_BASE="${ANDROID_HOME}/ndk"
if [ ! -d "${NDK_BASE}" ]; then
  echo "error: no NDKs under ${NDK_BASE}." >&2
  echo "  install one via Android Studio → SDK Manager → SDK Tools → NDK." >&2
  exit 1
fi
NDK_VERSION="$(ls -1 "${NDK_BASE}" | sort -V | tail -1)"
export ANDROID_NDK_HOME="${NDK_BASE}/${NDK_VERSION}"
echo "using NDK: ${ANDROID_NDK_HOME}"

# Refresh local.properties so Gradle finds the SDK on this machine.
cat > "${ANDROID_DIR}/local.properties" <<EOF
sdk.dir=${ANDROID_HOME}
EOF

# ── 1. Build the Rust .so for each ABI ───────────────────────────────────
# cargo-ndk handles the NDK toolchain wiring (CC, AR, target sysroot per
# triple). It writes to target/<triple>/release/${LIB_NAME} and copies
# the result into the AAR's jniLibs directory via -o.
#
# -P 24 — set Android API level 24 to match the AAR's minSdk. Older
#         API targets are unstable with modern NDK clang. (Capital P;
#         lowercase -p is consumed by cargo as --package.)
echo "→ build native libs (arm64-v8a, armeabi-v7a, x86_64)"
cargo ndk \
  -P 24 \
  -t arm64-v8a \
  -t armeabi-v7a \
  -t x86_64 \
  -o "${ANDROID_DIR}/src/main/jniLibs" \
  build -p "${TARGET_CRATE}" --release

# ── 2. Generate Kotlin bindings ──────────────────────────────────────────
# UniFFI introspects the .so to derive the API. Use any built slice;
# arm64-v8a is fastest to read on Apple Silicon hosts.
echo "→ generate Kotlin bindings"
KOTLIN_DIR="${ANDROID_DIR}/src/main/kotlin"
rm -rf "${KOTLIN_DIR}/com"
mkdir -p "${KOTLIN_DIR}"

cargo run -p "${TARGET_CRATE}" --bin uniffi-bindgen --release -- generate \
  --library "${TARGET_DIR}/aarch64-linux-android/release/${LIB_NAME}" \
  --language kotlin \
  --out-dir "${KOTLIN_DIR}"

# ── 3. Package as AAR via Gradle ─────────────────────────────────────────
echo "→ gradle assembleRelease"
"${ANDROID_DIR}/gradlew" --no-daemon assembleRelease

AAR_OUT="${ANDROID_DIR}/build/outputs/aar/vodozemac-release.aar"
if [ ! -f "${AAR_OUT}" ]; then
  echo "error: expected AAR not found at ${AAR_OUT}" >&2
  exit 1
fi

echo ""
echo "✓ ${AAR_OUT}"
echo "  ($(stat -f%z "${AAR_OUT}") bytes)"
