/// Blur intensity used by [AppSwitcherProtectionMode.blur] and
/// [AppSwitcherProtectionMode.imageBlur].
///
/// Values are named generically (not after any one platform's blur API) so
/// they can be reused if Android ever implements its own blur rendering -
/// currently, only iOS renders a blur; see [AppSwitcherProtectionMode] for
/// the Android caveat.
enum BlurIntensity {
  /// Maps to iOS `UIBlurEffect.Style.systemUltraThinMaterial`.
  ultraLight,

  /// Maps to iOS `UIBlurEffect.Style.systemThinMaterial`.
  light,

  /// Maps to iOS `UIBlurEffect.Style.systemMaterial`.
  medium,

  /// Maps to iOS `UIBlurEffect.Style.systemThickMaterial`.
  heavy,
}
