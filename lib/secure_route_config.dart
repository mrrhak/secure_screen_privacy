import 'app_switcher_protection_mode.dart';
import 'blur_intensity.dart';

/// Configuration for a single route's protection policy, used by
/// `SecureScreenPrivacyNavigatorObserver`.
///
/// Capture protection and app switcher protection are independent: set
/// either, both, or neither.
class SecureRouteConfig {
  const SecureRouteConfig({
    this.captureProtection = false,
    this.appSwitcherMode,
    this.blurIntensity = BlurIntensity.ultraLight,
    this.color = 0xFF000000,
    this.imageBackgroundColor = 0xFF000000,
  });

  /// Whether screenshots and screen recording should be blocked on this route.
  final bool captureProtection;

  /// The overlay shown in the OS app switcher/recent preview for this
  /// route, or `null` to leave app switcher protection off.
  final AppSwitcherProtectionMode? appSwitcherMode;

  /// Applies to [AppSwitcherProtectionMode.blur] and
  /// [AppSwitcherProtectionMode.imageBlur].
  final BlurIntensity blurIntensity;

  /// Applies to [AppSwitcherProtectionMode.color].
  final int color;

  /// Applies to [AppSwitcherProtectionMode.image] and
  /// [AppSwitcherProtectionMode.imageBlur].
  final int imageBackgroundColor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecureRouteConfig &&
          runtimeType == other.runtimeType &&
          captureProtection == other.captureProtection &&
          appSwitcherMode == other.appSwitcherMode &&
          blurIntensity == other.blurIntensity &&
          color == other.color &&
          imageBackgroundColor == other.imageBackgroundColor;

  @override
  int get hashCode => Object.hash(
    captureProtection,
    appSwitcherMode,
    blurIntensity,
    color,
    imageBackgroundColor,
  );
}
