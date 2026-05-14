// Entrypoint for the UniFFI language-bindings generator. Invoked from
// the iOS/Android build scripts (apple/build_xcframework.sh,
// android/build_aar.sh) as:
//
//   cargo run -p vodozemac-ffi --bin uniffi-bindgen -- \
//     generate --library <path-to-libvodozemac_ffi.{a,dylib}> \
//     --language {swift,kotlin} --out-dir <out>
//
// The binary itself is generic; UniFFI uses --library introspection to
// derive the interface from the linked Rust artifact.

fn main() {
    uniffi::uniffi_bindgen_main()
}
