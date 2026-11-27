import 'package:flutter_test/flutter_test.dart';
import 'package:secure_screen_privacy/secure_screen_privacy.dart';
import 'package:secure_screen_privacy/secure_screen_privacy_platform_interface.dart';
import 'package:secure_screen_privacy/secure_screen_privacy_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSecureScreenPrivacyPlatform
    with MockPlatformInterfaceMixin
    implements SecureScreenPrivacyPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<bool> enableCaptureProtection() => Future.value(true);

  @override
  Future<bool> disableCaptureProtection() => Future.value(true);

  @override
  Future<bool> isCaptureProtectionEnabled() => Future.value(true);

  @override
  Future<bool> enableAppSwitcherProtection(
    AppSwitcherProtectionMode mode, {
    BlurIntensity blurIntensity = BlurIntensity.ultraLight,
    int color = 0xFF000000,
    int imageBackgroundColor = 0xFF000000,
  }) => Future.value(true);

  @override
  Future<bool> disableAppSwitcherProtection() => Future.value(true);

  @override
  Future<bool> isAppSwitcherProtectionEnabled() => Future.value(true);

  @override
  Stream<ScreenshotEvent> get screenshotEvents =>
      Stream.value(ScreenshotEvent(DateTime.fromMillisecondsSinceEpoch(0)));

  @override
  Stream<ScreenRecordingEvent> get screenRecordingEvents => Stream.value(
    ScreenRecordingEvent(
      ScreenRecordingState.recording,
      DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );
}

void main() {
  final SecureScreenPrivacyPlatform initialPlatform = SecureScreenPrivacyPlatform.instance;

  test('$MethodChannelSecureScreenPrivacy is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSecureScreenPrivacy>());
  });

  test('getPlatformVersion', () async {
    SecureScreenPrivacy secureScreenPrivacyPlugin = SecureScreenPrivacy();
    MockSecureScreenPrivacyPlatform fakePlatform = MockSecureScreenPrivacyPlatform();
    SecureScreenPrivacyPlatform.instance = fakePlatform;

    expect(await secureScreenPrivacyPlugin.getPlatformVersion(), '42');
  });

  test('enableCaptureProtection', () async {
    SecureScreenPrivacy secureScreenPrivacyPlugin = SecureScreenPrivacy();
    SecureScreenPrivacyPlatform.instance = MockSecureScreenPrivacyPlatform();

    expect(await secureScreenPrivacyPlugin.enableCaptureProtection(), true);
  });

  test('disableCaptureProtection', () async {
    SecureScreenPrivacy secureScreenPrivacyPlugin = SecureScreenPrivacy();
    SecureScreenPrivacyPlatform.instance = MockSecureScreenPrivacyPlatform();

    expect(await secureScreenPrivacyPlugin.disableCaptureProtection(), true);
  });

  test('isCaptureProtectionEnabled', () async {
    SecureScreenPrivacy secureScreenPrivacyPlugin = SecureScreenPrivacy();
    SecureScreenPrivacyPlatform.instance = MockSecureScreenPrivacyPlatform();

    expect(await secureScreenPrivacyPlugin.isCaptureProtectionEnabled(), true);
  });

  test('enableAppSwitcherProtection', () async {
    SecureScreenPrivacy secureScreenPrivacyPlugin = SecureScreenPrivacy();
    SecureScreenPrivacyPlatform.instance = MockSecureScreenPrivacyPlatform();

    expect(
      await secureScreenPrivacyPlugin.enableAppSwitcherProtection(
        AppSwitcherProtectionMode.blur,
      ),
      true,
    );
  });

  test('enableAppSwitcherProtection with a non-default blurIntensity', () async {
    SecureScreenPrivacy secureScreenPrivacyPlugin = SecureScreenPrivacy();
    SecureScreenPrivacyPlatform.instance = MockSecureScreenPrivacyPlatform();

    expect(
      await secureScreenPrivacyPlugin.enableAppSwitcherProtection(
        AppSwitcherProtectionMode.blur,
        blurIntensity: BlurIntensity.heavy,
      ),
      true,
    );
  });

  test('disableAppSwitcherProtection', () async {
    SecureScreenPrivacy secureScreenPrivacyPlugin = SecureScreenPrivacy();
    SecureScreenPrivacyPlatform.instance = MockSecureScreenPrivacyPlatform();

    expect(await secureScreenPrivacyPlugin.disableAppSwitcherProtection(), true);
  });

  test('isAppSwitcherProtectionEnabled', () async {
    SecureScreenPrivacy secureScreenPrivacyPlugin = SecureScreenPrivacy();
    SecureScreenPrivacyPlatform.instance = MockSecureScreenPrivacyPlatform();

    expect(await secureScreenPrivacyPlugin.isAppSwitcherProtectionEnabled(), true);
  });

  test('screenshotEvents', () async {
    SecureScreenPrivacy secureScreenPrivacyPlugin = SecureScreenPrivacy();
    SecureScreenPrivacyPlatform.instance = MockSecureScreenPrivacyPlatform();

    expect(
      await secureScreenPrivacyPlugin.screenshotEvents.first,
      isA<ScreenshotEvent>(),
    );
  });

  test('screenRecordingEvents', () async {
    SecureScreenPrivacy secureScreenPrivacyPlugin = SecureScreenPrivacy();
    SecureScreenPrivacyPlatform.instance = MockSecureScreenPrivacyPlatform();

    expect(
      await secureScreenPrivacyPlugin.screenRecordingEvents.first,
      isA<ScreenRecordingEvent>(),
    );
  });
}
