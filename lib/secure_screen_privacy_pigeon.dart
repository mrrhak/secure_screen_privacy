import 'package:flutter/foundation.dart';

import 'app_switcher_protection_mode.dart';
import 'blur_intensity.dart';
import 'screen_recording_event.dart';
import 'screenshot_event.dart';
import 'secure_screen_privacy_platform_interface.dart';
import 'src/messages.g.dart' as messages;
import 'src/messages.g.dart'
    show
        AppSwitcherModeMessage,
        AppSwitcherOptionsMessage,
        BlurIntensityMessage,
        SecureScreenPrivacyPluginApi;

/// An implementation of [SecureScreenPrivacyPlatform] that uses Pigeon, for
/// Android and iOS.
class PigeonSecureScreenPrivacy extends SecureScreenPrivacyPlatform {
  /// Creates a new plugin implementation instance.
  PigeonSecureScreenPrivacy({
    @visibleForTesting SecureScreenPrivacyPluginApi? api,
  }) : _hostApi = api ?? SecureScreenPrivacyPluginApi();

  final SecureScreenPrivacyPluginApi _hostApi;

  // Built once and cached: each call to the generated screenshotEvents()
  // creates a new EventChannel and registers a new native message handler,
  // and only one handler can be registered per channel name at a time - an
  // uncached getter would let a second listener silently steal the platform
  // channel out from under the first, which would then stop receiving
  // events without any error.
  late final Stream<ScreenshotEvent> _screenshotEvents = messages
      .screenshotEvents()
      .map(
        (event) => ScreenshotEvent(
          DateTime.fromMillisecondsSinceEpoch(event.timestampMillis),
        ),
      );

  @override
  Stream<ScreenshotEvent> get screenshotEvents => _screenshotEvents;

  // Cached for the same reason as _screenshotEvents above.
  late final Stream<ScreenRecordingEvent> _screenRecordingEvents = messages
      .screenRecordingEvents()
      .map(
        (event) => ScreenRecordingEvent(switch (event.isRecording) {
          true => ScreenRecordingState.recording,
          false => ScreenRecordingState.notRecording,
          // Native sends null when it can't tell (Android 14 and below).
          null => ScreenRecordingState.unknown,
        }, DateTime.fromMillisecondsSinceEpoch(event.timestampMillis)),
      );

  @override
  Stream<ScreenRecordingEvent> get screenRecordingEvents =>
      _screenRecordingEvents;

  @override
  Future<String?> getPlatformVersion() => _hostApi.getPlatformVersion();

  @override
  Future<bool> enableCaptureProtection() => _hostApi.enableCaptureProtection();

  @override
  Future<bool> disableCaptureProtection() =>
      _hostApi.disableCaptureProtection();

  @override
  Future<bool> isCaptureProtectionEnabled() =>
      _hostApi.isCaptureProtectionEnabled();

  @override
  Future<bool> enableAppSwitcherProtection(
    AppSwitcherProtectionMode mode, {
    BlurIntensity blurIntensity = BlurIntensity.ultraLight,
    int color = 0xFF000000,
    int imageBackgroundColor = 0xFF000000,
  }) {
    return _hostApi.enableAppSwitcherProtection(
      AppSwitcherOptionsMessage(
        mode: switch (mode) {
          AppSwitcherProtectionMode.blur => AppSwitcherModeMessage.blur,
          AppSwitcherProtectionMode.image => AppSwitcherModeMessage.image,
          AppSwitcherProtectionMode.color => AppSwitcherModeMessage.color,
          AppSwitcherProtectionMode.imageBlur =>
            AppSwitcherModeMessage.imageBlur,
        },
        blurIntensity: switch (blurIntensity) {
          BlurIntensity.ultraLight => BlurIntensityMessage.ultraLight,
          BlurIntensity.light => BlurIntensityMessage.light,
          BlurIntensity.medium => BlurIntensityMessage.medium,
          BlurIntensity.heavy => BlurIntensityMessage.heavy,
        },
        color: color,
        imageBackgroundColor: imageBackgroundColor,
      ),
    );
  }

  @override
  Future<bool> disableAppSwitcherProtection() =>
      _hostApi.disableAppSwitcherProtection();

  @override
  Future<bool> isAppSwitcherProtectionEnabled() =>
      _hostApi.isAppSwitcherProtectionEnabled();
}
