#!/usr/bin/env bash
#
# Smoke-test the UniFFI Kotlin binding on the host (no Android emulator
# required). Builds `libvodozemac_ffi.dylib` for host via cargo, generates
# Kotlin bindings, downloads JNA + org.json jars from Maven, compiles
# `Tests/SmokeValidation.kt` against them, runs the resulting jar.
#
# What this validates: the Rust → Kotlin FFI layer roundtrips correctly.
# What this does NOT validate: Android-specific runtime behaviour (real
# device / emulator). That's Phase 6's job (RN TurboModule on emu).

set -eEuo pipefail

cd "$(dirname "$0")"
ANDROID_DIR="$(pwd)"
ROOT_DIR="${ANDROID_DIR}/.."
TARGET_DIR="${ROOT_DIR}/target"

# Use Android Studio's bundled kotlinc (the system doesn't ship one).
KOTLINC="/Applications/Android Studio.app/Contents/plugins/Kotlin/kotlinc/bin/kotlinc"
if [ ! -x "${KOTLINC}" ]; then
  echo "error: kotlinc not found at ${KOTLINC}" >&2
  echo "  install Android Studio (which bundles a Kotlin compiler) or" >&2
  echo "  install standalone kotlinc + set KOTLINC env var." >&2
  exit 1
fi

SCRATCH="${ANDROID_DIR}/.validation"
rm -rf "${SCRATCH}"
mkdir -p "${SCRATCH}/classes"

# ── 1. Build the host dylib ──────────────────────────────────────────────
echo "→ build host dylib"
cargo build -p vodozemac-ffi --release

# ── 2. Generate Kotlin bindings (reuse the AAR's generated file if
# present; otherwise regenerate against the host dylib) ──────────────────
KOTLIN_SRC="${ANDROID_DIR}/src/main/kotlin/com/dtelecom/vodozemac/vodozemac.kt"
if [ ! -f "${KOTLIN_SRC}" ]; then
  echo "→ generate Kotlin bindings"
  cargo run -p vodozemac-ffi --bin uniffi-bindgen --release -- generate \
    --library "${TARGET_DIR}/release/libvodozemac_ffi.dylib" \
    --language kotlin \
    --out-dir "${ANDROID_DIR}/src/main/kotlin"
fi

# ── 3. Download JNA + org.json from Maven ────────────────────────────────
# JNA is the UniFFI Kotlin runtime; org.json gives the test a JSON parser
# without pulling in jackson/kotlinx-serialization.
JNA_VER="5.14.0"
JSON_VER="20240303"
JNA_JAR="${SCRATCH}/jna-${JNA_VER}.jar"
JSON_JAR="${SCRATCH}/json-${JSON_VER}.jar"

echo "→ fetch JNA + org.json"
curl -sL -o "${JNA_JAR}" \
  "https://repo1.maven.org/maven2/net/java/dev/jna/jna/${JNA_VER}/jna-${JNA_VER}.jar"
curl -sL -o "${JSON_JAR}" \
  "https://repo1.maven.org/maven2/org/json/json/${JSON_VER}/json-${JSON_VER}.jar"

# ── 4. Compile bindings + smoke test together ────────────────────────────
echo "→ compile bindings + smoke test"
"${KOTLINC}" -classpath "${JNA_JAR}:${JSON_JAR}" \
  -d "${SCRATCH}/smoke.jar" \
  "${KOTLIN_SRC}" \
  "${ANDROID_DIR}/Tests/SmokeValidation.kt"

# ── 5. Run ─────────────────────────────────────────────────────────────
# Point UniFFI's library lookup at the freshly built host dylib via the
# uniffi.component.<namespace>.libraryOverride system property — saves us
# from juggling java.library.path / DYLD_FALLBACK_LIBRARY_PATH.
# Kotlin stdlib must be on the runtime classpath (kotlinc bundles it but
# `java` doesn't auto-include it — it comes from kotlinc/lib/).
KOTLIN_STDLIB="$(dirname "${KOTLINC}")/../lib/kotlin-stdlib.jar"
echo "→ run"
echo ""
java \
  -Duniffi.component.vodozemac.libraryOverride="${TARGET_DIR}/release/libvodozemac_ffi.dylib" \
  -cp "${SCRATCH}/smoke.jar:${JNA_JAR}:${JSON_JAR}:${KOTLIN_STDLIB}" \
  SmokeValidationKt

rm -rf "${SCRATCH}"
