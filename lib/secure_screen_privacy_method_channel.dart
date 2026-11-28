import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_switcher_protection_mode.dart';
import 'blur_intensity.dart';
import 'screen_recording_event.dart';
import 'screenshot_event.dart';
import 'secure_screen_privacy_platform_interface.dart';

/// An implementation of [SecureScreenPrivacyPlatform] that uses method channels.
class MethodChannelSecureScreenPrivacy extends SecureScreenPrivacyPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('secure_screen_privacy');

  /// The event channel used to receive screenshot detections from the
  /// native platform.
  @visibleForTesting
  final screenshotEventChannel = const EventChannel(
    'secure_screen_privacy/screenshot_events',
  );

  // Built once and cached: EventChannel.receiveBroadcastStream() registers a
  // new native message handler on every call, and only one handler can be
  // registered per channel name at a time - an uncached getter would let a
  // second listener silently steal the platform channel out from under the
  // first, which would then stop receiving events without any error.
  late final Stream<ScreenshotEvent> _screenshotEvents = screenshotEventChannel
      .receiveBroadcastStream()
      .map((event) {
        final map = Map<Object?, Object?>.from(event as Map);
        final millis = map['timestamp'] as int;
        return ScreenshotEvent(DateTime.fromMillisecondsSinceEpoch(millis));
      });

  @override
  Stream<ScreenshotEvent> get screenshotEvents => _screenshotEvents;

  /// The event channel used to receive screen recording state transitions
  /// from the native platform.
  @visibleForTesting
  final screenRecordingEventChannel = const EventChannel(
    'secure_screen_privacy/screen_recording_events',
  );

  // Cached for the same reason as _screenshotEvents above.
  late final Stream<ScreenRecordingEvent> _screenRecordingEvents =
      screenRecordingEventChannel.receiveBroadcastStream().map((event) {
        final map = Map<Object?, Object?>.from(event as Map);
        // Native sends null when it can't tell (Android 14 and below).
        final isRecording = map['isRecording'] as bool?;
        final millis = map['timestamp'] as int;
        return ScreenRecordingEvent(switch (isRecording) {
          true => ScreenRecordingState.recording,
          false => ScreenRecordingState.notRecording,
          null => ScreenRecordingState.unknown,
        }, DateTime.fromMillisecondsSinceEpoch(millis));
      });

  @override
  Stream<ScreenRecordingEvent> get screenRecordingEvents =>
      _screenRecordingEvents;

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<bool> enableCaptureProtection() async {
    final result = await methodChannel.invokeMethod<bool>(
      'enableCaptureProtection',
    );
    return result ?? false;
  }

  @override
  Future<bool> disableCaptureProtection() async {
    final result = await methodChannel.invokeMethod<bool>(
      'disableCaptureProtection',
    );
    return result ?? false;
  }

  @override
  Future<bool> isCaptureProtectionEnabled() async {
    final result = await methodChannel.invokeMethod<bool>(
      'isCaptureProtectionEnabled',
    );
    return result ?? false;
  }

  @override
  Future<bool> enableAppSwitcherProtection(
    AppSwitcherProtectionMode mode, {
    BlurIntensity blurIntensity = BlurIntensity.ultraLight,
    int color = 0xFF000000,
    int imageBackgroundColor = 0xFF000000,
  }) async {
    final result = await methodChannel
        .invokeMethod<bool>('enableAppSwitcherProtection', {
          'mode': mode.name,
          'blurIntensity': blurIntensity.name,
          'color': color,
          'imageBackgroundColor': imageBackgroundColor,
        });
    return result ?? false;
  }

  @override
  Future<bool> disableAppSwitcherProtection() async {
    final result = await methodChannel.invokeMethod<bool>(
      'disableAppSwitcherProtection',
    );
    return result ?? false;
  }

  @override
  Future<bool> isAppSwitcherProtectionEnabled() async {
    final result = await methodChannel.invokeMethod<bool>(
      'isAppSwitcherProtectionEnabled',
    );
    return result ?? false;
  }
}
