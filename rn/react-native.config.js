// React Native auto-link config. Tells RN's CLI where the native pieces
// live so `pod install` (iOS) and `gradle sync` (Android) pick them up
// without the consumer editing anything.
//
// Note:
//   - iOS: RN core's stricter UserDependencyConfig schema (0.83+) does
//     NOT accept `podspecPath`. The CLI auto-discovers `.podspec` files
//     at the package root, so `Vodozemac.podspec` is picked up
//     automatically — we just leave `ios: {}`.
//   - Android: `sourceDir` MUST be relative to the package root — the RN
//     CLI does `path.join(packageRoot, sourceDir)` and an absolute path
//     gets corrupted into `.../node_modules/.../Users/vf/...`.

module.exports = {
  dependency: {
    platforms: {
      ios: {},
      android: {
        sourceDir: "android",
      },
    },
  },
};
