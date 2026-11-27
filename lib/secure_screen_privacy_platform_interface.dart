import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'app_switcher_protection_mode.dart';
import 'blur_intensity.dart';
import 'screen_recording_event.dart';
import 'screenshot_event.dart';
import 'secure_screen_privacy_method_channel.dart';

abstract class SecureScreenPrivacyPlatform extends PlatformInterface {
  /// Constructs a SecureScreenPrivacyPlatform.
  SecureScreenPrivacyPlatform() : super(token: _token);

  static final Object _token = Object();

  static SecureScreenPrivacyPlatform _instance = MethodChannelSecureScreenPrivacy();

  /// The default instance of [SecureScreenPrivacyPlatform] to use.
  ///
  /// Defaults to [MethodChannelSecureScreenPrivacy].
  static SecureScreenPrivacyPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SecureScreenPrivacyPlatform] when
  /// they register themselves.
  static set instance(SecureScreenPrivacyPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> enableCaptureProtection() {
    throw UnimplementedError('enableCaptureProtection() has not been implemented.');
  }

  Future<bool> disableCaptureProtection() {
    throw UnimplementedError('disableCaptureProtection() has not been implemented.');
  }

  Future<bool> isCaptureProtectionEnabled() {
    throw UnimplementedError('isCaptureProtectionEnabled() has not been implemented.');
  }

  Future<bool> enableAppSwitcherProtection(
    AppSwitcherProtectionMode mode, {
    BlurIntensity blurIntensity = BlurIntensity.ultraLight,
    int color = 0xFF000000,
    int imageBackgroundColor = 0xFF000000,
  }) {
    throw UnimplementedError('enableAppSwitcherProtection() has not been implemented.');
  }

  Future<bool> disableAppSwitcherProtection() {
    throw UnimplementedError('disableAppSwitcherProtection() has not been implemented.');
  }

  Future<bool> isAppSwitcherProtectionEnabled() {
    throw UnimplementedError('isAppSwitcherProtectionEnabled() has not been implemented.');
  }

  /// A broadcast stream of screenshot detections.
  ///
  /// Subscribing starts native screenshot detection; cancelling the last
  /// subscription stops it. There is no separate start/stop method.
  Stream<ScreenshotEvent> get screenshotEvents {
    throw UnimplementedError('screenshotEvents has not been implemented.');
  }

  /// A broadcast stream of screen recording state transitions.
  ///
  /// Subscribing starts native screen recording detection; cancelling the
  /// last subscription stops it. There is no separate start/stop method.
  Stream<ScreenRecordingEvent> get screenRecordingEvents {
    throw UnimplementedError('screenRecordingEvents has not been implemented.');
  }
}
