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

/// Screen privacy for Android and iOS: blocks screenshots and screen
/// recording, hides the app in the App Switcher, and reports screenshots and
/// screen recording.
///
/// Only Android and iOS are supported. On web, Windows, macOS and Linux every
/// method throws a `PlatformException` with code `channel-error`, and the
/// streams send no events (Flutter reports the failed subscription as a
/// `MissingPluginException` through `FlutterError`), so check the platform
/// first if your app also runs there.
///
/// If you also use [SecureScreenPrivacyNavigatorObserver], it sets capture
/// and App Switcher protection on every route change, which replaces what
/// these methods turned on. Use one or the other for a given setting, or put
/// the protection you always want in the observer's `defaultConfig`.
class SecureScreenPrivacy {
  /// The OS name and version, for example `Android 14` or `iOS 18.0`.
  ///
  /// Mostly useful to check that the plugin is wired up.
  Future<String?> getPlatformVersion() {
    return SecureScreenPrivacyPlatform.instance.getPlatformVersion();
  }

  /// Blocks screenshots and screen recording of the app until
  /// [disableCaptureProtection] is called.
  ///
  /// Android sets `FLAG_SECURE` on the app's window, so screenshots and
  /// recordings come out black. iOS shows the window as secure content, so it
  /// is left out of screenshots and recordings. A call made before the screen
  /// is ready (at app start) is kept and applied as soon as it is. Returns
  /// `true` once the request is recorded.
  Future<bool> enableCaptureProtection() {
    return SecureScreenPrivacyPlatform.instance.enableCaptureProtection();
  }

  /// Allows screenshots and screen recording again.
  ///
  /// On Android the window stays secure while App Switcher protection is
  /// still on, since both use `FLAG_SECURE`. Returns `true` once the request
  /// is recorded.
  Future<bool> disableCaptureProtection() {
    return SecureScreenPrivacyPlatform.instance.disableCaptureProtection();
  }

  /// Whether capture protection was last turned on with
  /// [enableCaptureProtection].
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
  /// **Android note:** Android can't draw a blur or an image there. It uses
  /// `FLAG_SECURE` for the whole time protection is on, which shows a plain
  /// card in the app switcher. On Android 13+ the plugin sets that card's
  /// colour: [color] for [AppSwitcherProtectionMode.color],
  /// [imageBackgroundColor] for [AppSwitcherProtectionMode.image], and the
  /// app theme's current background colour (following dark/light mode) for
  /// the blur modes. Older Android versions show the theme's background
  /// colour read at app start. [blurIntensity] is ignored on Android. No
  /// app-level technique hides the live "swipe up and hold" recents peek on
  /// Android, so `FLAG_SECURE` is the most protection available there.
  ///
  /// **iPad note:** the cover goes up whenever the app's window stops being
  /// the active one, so in Split View or Slide Over the app is covered while
  /// the user works in the other app, even though it is still on screen.
  ///
  /// Returns `true` once the request is recorded.
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

  /// Shows the live app in the App Switcher again.
  ///
  /// On Android the window stays secure while capture protection is still
  /// on. Returns `true` once the request is recorded.
  Future<bool> disableAppSwitcherProtection() {
    return SecureScreenPrivacyPlatform.instance.disableAppSwitcherProtection();
  }

  /// Whether App Switcher protection was last turned on with
  /// [enableAppSwitcherProtection].
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
  /// documented caveats (all platforms: only screenshots taken while this
  /// app is on screen; Android 13 and below: a
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
  /// `WindowManager.addScreenRecordingCallback` on API 35+; iOS:
  /// `UIScreen.capturedDidChangeNotification`); cancelling the last
  /// subscription stops it. There is no separate start/stop method - the
  /// subscription *is* the toggle. The current state is emitted immediately
  /// on subscribe, so a late subscriber doesn't miss an already-in-progress
  /// recording.
  ///
  /// See the README for platform caveats - most notably, Android 14 (API 34)
  /// and below have no screen-recording signal, so they send a single
  /// [ScreenRecordingState.unknown] event on subscribe and nothing after.
  Stream<ScreenRecordingEvent> get screenRecordingEvents =>
      SecureScreenPrivacyPlatform.instance.screenRecordingEvents;
}
