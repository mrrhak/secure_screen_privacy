import 'app_switcher_protection_mode.dart';
import 'blur_intensity.dart';
import 'screen_recording_event.dart';
import 'screenshot_event.dart';
import 'secure_screen_privacy_platform_interface.dart';

export 'app_switcher_protection_mode.dart';
export 'blur_intensity.dart';
export 'screen_recording_event.dart';
export 'screenshot_event.dart';
export 'secure_route_config.dart';
export 'secure_screen_privacy_navigator_observer.dart';

class SecureScreenPrivacy {
  Future<String?> getPlatformVersion() {
    return SecureScreenPrivacyPlatform.instance.getPlatformVersion();
  }

  Future<bool> enableCaptureProtection() {
    return SecureScreenPrivacyPlatform.instance.enableCaptureProtection();
  }

  Future<bool> disableCaptureProtection() {
    return SecureScreenPrivacyPlatform.instance.disableCaptureProtection();
  }

  Future<bool> isCaptureProtectionEnabled() {
    return SecureScreenPrivacyPlatform.instance.isCaptureProtectionEnabled();
  }

  /// Shows [mode] (blur/image/color/imageBlur) in the OS app switcher /
  /// recents preview instead of the live UI whenever the app is backgrounded.
  ///
  /// [blurIntensity] applies to [AppSwitcherProtectionMode.blur] and
  /// [AppSwitcherProtectionMode.imageBlur].
  /// [color] (as an ARGB int, e.g. `0xFF000000`) only applies to
  /// [AppSwitcherProtectionMode.color].
  /// [imageBackgroundColor] (as an ARGB int) only applies to
  /// [AppSwitcherProtectionMode.image] - it fills the letterbox/pillarbox
  /// bars left when the image's aspect ratio doesn't match the screen's,
  /// shows through any transparent areas of the image itself, and is the
  /// whole cover if the image asset is missing.
  /// [AppSwitcherProtectionMode.imageBlur] shows the blur in those places
  /// instead.
  ///
  /// **Android note:** [mode] and the styling parameters above are iOS-only.
  /// Android instead relies solely on `FLAG_SECURE` for the entire time
  /// protection is enabled, showing a plain black/secure card in the app
  /// switcher regardless of [mode] - no custom overlay is rendered. This is
  /// deliberate: none of a custom overlay view, `RenderEffect` blur, or
  /// `PixelCopy`-based capture protects the live gesture-nav "swipe up and
  /// hold" recents peek on Android, so a custom overlay would only add
  /// implementation cost with no additional coverage over `FLAG_SECURE`
  /// alone.
  Future<bool> enableAppSwitcherProtection(
    AppSwitcherProtectionMode mode, {
    BlurIntensity blurIntensity = BlurIntensity.ultraLight,
    int color = 0xFF000000,
    int imageBackgroundColor = 0xFF000000,
  }) {
    return SecureScreenPrivacyPlatform.instance.enableAppSwitcherProtection(
      mode,
      blurIntensity: blurIntensity,
      color: color,
      imageBackgroundColor: imageBackgroundColor,
    );
  }

  Future<bool> disableAppSwitcherProtection() {
    return SecureScreenPrivacyPlatform.instance.disableAppSwitcherProtection();
  }

  Future<bool> isAppSwitcherProtectionEnabled() {
    return SecureScreenPrivacyPlatform.instance
        .isAppSwitcherProtectionEnabled();
  }

  /// A broadcast stream of screenshot detections.
  ///
  /// Subscribing starts native screenshot detection (Android 14+:
  /// `Activity.ScreenCaptureCallback`; older Android: a `ContentObserver` on
  /// the images `MediaStore`; iOS:
  /// `UIApplication.userDidTakeScreenshotNotification`); cancelling the last
  /// subscription stops it. There is no separate start/stop method - the
  /// subscription *is* the toggle.
  ///
  /// Detection is best-effort on both platforms - see the README for the
  /// documented caveats (Android 14+: only screenshots of this app's visible
  /// screen; Android 13 and below: a
  /// de-duplicated heuristic MediaStore filter that can still false-positive
  /// on other new images and false-negative on some OEMs/locales; iOS: no
  /// image data or file path is ever available). On Android, a screenshot
  /// taken while capture protection is on is still reported, even though the
  /// saved image is black.
  Stream<ScreenshotEvent> get screenshotEvents =>
      SecureScreenPrivacyPlatform.instance.screenshotEvents;

  /// A broadcast stream of screen recording state transitions.
  ///
  /// Subscribing starts native screen recording detection (Android:
  /// `WindowManager.addScreenRecordingCallback` on API 35+, no-op below;
  /// iOS:
  /// `UIScreen.capturedDidChangeNotification`); cancelling the last
  /// subscription stops it. There is no separate start/stop method - the
  /// subscription *is* the toggle. The current state is emitted immediately
  /// on subscribe, so a late subscriber doesn't miss an already-in-progress
  /// recording.
  ///
  /// See the README for platform caveats - most notably, Android 14 (API 34)
  /// and below emit nothing: Android 14 has no screen-recording signal.
  Stream<ScreenRecordingEvent> get screenRecordingEvents =>
      SecureScreenPrivacyPlatform.instance.screenRecordingEvents;
}
