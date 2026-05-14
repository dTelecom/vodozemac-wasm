// swift-tools-version:5.9
//
// VodozemacFFI Swift Package. Wraps the prebuilt XCFramework
// (`VodozemacFFI.xcframework`, built by `./build_xcframework.sh`) so Swift
// consumers can depend on it via SwiftPM or a CocoaPods podspec that
// vendors the xcframework directly.
//
// Naming:
//   - The xcframework's modulemap declares `module VodozemacFFIFFI` (FFI
//     suffix doubled — that's UniFFI's convention for the C interop layer).
//     Exposed here as a `.binaryTarget` of the same name.
//   - The generated `Sources/VodozemacFFI/VodozemacFFI.swift` `import`s
//     `VodozemacFFIFFI` and re-exports the Swift API. Consumers `import
//     VodozemacFFI`.

import PackageDescription

let package = Package(
    name: "VodozemacFFI",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "VodozemacFFI",
            targets: ["VodozemacFFI"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "VodozemacFFIFFI",
            path: "VodozemacFFI.xcframework"
        ),
        .target(
            name: "VodozemacFFI",
            dependencies: ["VodozemacFFIFFI"],
            path: "Sources/VodozemacFFI"
        ),
    ]
)
