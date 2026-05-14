// React Native auto-link config. Tells RN's CLI where the native pieces
// live so `pod install` (iOS) and `gradle sync` (Android) pick them up
// without the consumer editing anything.
//
// Note: paths here are interpreted differently per platform.
//   - iOS `podspecPath` MUST be absolute (CocoaPods includes it verbatim).
//   - Android `sourceDir` MUST be relative to the package root — the RN
//     CLI does `path.join(packageRoot, sourceDir)` and an absolute path
//     gets corrupted into `.../node_modules/.../Users/vf/...`.

module.exports = {
  dependency: {
    platforms: {
      ios: {
        podspecPath: __dirname + "/Vodozemac.podspec",
      },
      android: {
        sourceDir: "android",
      },
    },
  },
};
