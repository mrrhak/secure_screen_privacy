import 'package:pigeon/pigeon.dart';

// The interface between Dart and the Android (Kotlin) and iOS (Swift) code.
// After editing this file, regenerate and format the outputs:
//   dart run pigeon --input pigeon/messages.dart
//   dart format lib/src/messages.g.dart
// CI fails when the generated files don't match this file.

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'secure_screen_privacy',
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut:
        'android/src/main/kotlin/com/mrrhak/secure_screen_privacy/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.mrrhak.secure_screen_privacy'),
    swiftOut:
        'ios/secure_screen_privacy/Sources/secure_screen_privacy/Messages.g.swift',
  ),
)
/// How the App Switcher hides the app (see `AppSwitcherProtectionMode`).
enum AppSwitcherModeMessage { blur, image, color, imageBlur }

/// Blur strength for the blur modes (see `BlurIntensity`).
enum BlurIntensityMessage { ultraLight, light, medium, heavy }

/// The settings passed to `enableAppSwitcherProtection`.
class AppSwitcherOptionsMessage {
  AppSwitcherOptionsMessage({
    required this.mode,
    required this.blurIntensity,
    required this.color,
    required this.imageBackgroundColor,
  });

  AppSwitcherModeMessage mode;
  BlurIntensityMessage blurIntensity;

  /// ARGB colour for `color` mode.
  int color;

  /// ARGB colour behind the image for `image` mode.
  int imageBackgroundColor;
}

/// One screenshot, reported when it happens.
class ScreenshotEventMessage {
  ScreenshotEventMessage({required this.timestampMillis});

  /// When it was detected, in milliseconds since the epoch.
  int timestampMillis;
}

/// A screen recording state change.
class ScreenRecordingEventMessage {
  ScreenRecordingEventMessage({
    this.isRecording,
    required this.timestampMillis,
  });

  /// Null when the platform can't tell (Android 14 and below).
  bool? isRecording;

  /// When it was detected, in milliseconds since the epoch.
  int timestampMillis;
}

/// Calls from Dart to the native plugin.
@HostApi()
abstract class SecureScreenPrivacyPluginApi {
  /// Returns the system version of the host platform.
  String getPlatformVersion();

  bool enableCaptureProtection();

  bool disableCaptureProtection();

  bool isCaptureProtectionEnabled();

  bool enableAppSwitcherProtection(AppSwitcherOptionsMessage options);

  bool disableAppSwitcherProtection();

  bool isAppSwitcherProtectionEnabled();
}

/// Event streams from the native plugin. Each gets its own event channel and
/// its own stream handler on Android and iOS.
@EventChannelApi()
abstract class SecureScreenPrivacyEventApi {
  /// Starts screenshot detection while listened to.
  ScreenshotEventMessage screenshotEvents();

  /// Starts screen recording detection while listened to.
  ScreenRecordingEventMessage screenRecordingEvents();
}
