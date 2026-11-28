import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_screen_privacy/secure_screen_privacy.dart';
import 'package:secure_screen_privacy/secure_screen_privacy_pigeon.dart';
import 'package:secure_screen_privacy/src/messages.g.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const screenshotEventChannel = EventChannel(
    'dev.flutter.pigeon.secure_screen_privacy.SecureScreenPrivacyEventApi.screenshotEvents',
    pigeonMethodCodec,
  );
  const screenRecordingEventChannel = EventChannel(
    'dev.flutter.pigeon.secure_screen_privacy.SecureScreenPrivacyEventApi.screenRecordingEvents',
    pigeonMethodCodec,
  );

  late FakeSecureScreenPrivacyPluginApi api;
  late PigeonSecureScreenPrivacy platform;

  setUp(() {
    api = FakeSecureScreenPrivacyPluginApi();
    platform = PigeonSecureScreenPrivacy(api: api);
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockStreamHandler(screenshotEventChannel, null);
    messenger.setMockStreamHandler(screenRecordingEventChannel, null);
  });

  void sendOnListen(EventChannel channel, Object event) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          channel,
          MockStreamHandler.inline(
            onListen: (arguments, events) => events.success(event),
          ),
        );
  }

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('capture protection calls reach the host API', () async {
    expect(await platform.enableCaptureProtection(), true);
    expect(await platform.isCaptureProtectionEnabled(), true);
    expect(await platform.disableCaptureProtection(), true);
    expect(await platform.isCaptureProtectionEnabled(), false);
  });

  test('App Switcher protection calls reach the host API', () async {
    expect(
      await platform.enableAppSwitcherProtection(
        AppSwitcherProtectionMode.blur,
      ),
      true,
    );
    expect(await platform.isAppSwitcherProtectionEnabled(), true);
    expect(await platform.disableAppSwitcherProtection(), true);
    expect(await platform.isAppSwitcherProtectionEnabled(), false);
  });

  test('enableAppSwitcherProtection sends the defaults', () async {
    await platform.enableAppSwitcherProtection(AppSwitcherProtectionMode.blur);

    final options = api.lastOptions!;
    expect(options.mode, AppSwitcherModeMessage.blur);
    expect(options.blurIntensity, BlurIntensityMessage.ultraLight);
    expect(options.color, 0xFF000000);
    expect(options.imageBackgroundColor, 0xFF000000);
  });

  test('enableAppSwitcherProtection maps every mode', () async {
    const expected = {
      AppSwitcherProtectionMode.blur: AppSwitcherModeMessage.blur,
      AppSwitcherProtectionMode.image: AppSwitcherModeMessage.image,
      AppSwitcherProtectionMode.color: AppSwitcherModeMessage.color,
      AppSwitcherProtectionMode.imageBlur: AppSwitcherModeMessage.imageBlur,
    };
    expect(expected.keys, containsAll(AppSwitcherProtectionMode.values));
    for (final entry in expected.entries) {
      await platform.enableAppSwitcherProtection(entry.key);
      expect(api.lastOptions!.mode, entry.value);
    }
  });

  test('enableAppSwitcherProtection maps every blur intensity', () async {
    const expected = {
      BlurIntensity.ultraLight: BlurIntensityMessage.ultraLight,
      BlurIntensity.light: BlurIntensityMessage.light,
      BlurIntensity.medium: BlurIntensityMessage.medium,
      BlurIntensity.heavy: BlurIntensityMessage.heavy,
    };
    expect(expected.keys, containsAll(BlurIntensity.values));
    for (final entry in expected.entries) {
      await platform.enableAppSwitcherProtection(
        AppSwitcherProtectionMode.imageBlur,
        blurIntensity: entry.key,
      );
      expect(api.lastOptions!.blurIntensity, entry.value);
    }
  });

  test('enableAppSwitcherProtection sends the colours', () async {
    await platform.enableAppSwitcherProtection(
      AppSwitcherProtectionMode.image,
      color: 0xFF112233,
      imageBackgroundColor: 0xFF445566,
    );

    expect(api.lastOptions!.color, 0xFF112233);
    expect(api.lastOptions!.imageBackgroundColor, 0xFF445566);
  });

  test('without a native plugin, calls throw a channel-error', () async {
    final unconnected = PigeonSecureScreenPrivacy();

    await expectLater(
      unconnected.enableCaptureProtection(),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'channel-error'),
      ),
    );
  });

  test('screenshotEvents maps the native event', () async {
    sendOnListen(
      screenshotEventChannel,
      ScreenshotEventMessage(timestampMillis: 1752150000000),
    );

    final event = await platform.screenshotEvents.first;

    expect(event.timestamp, DateTime.fromMillisecondsSinceEpoch(1752150000000));
  });

  test('screenshotEvents is the same stream on every read', () {
    expect(
      identical(platform.screenshotEvents, platform.screenshotEvents),
      true,
    );
    expect(
      identical(platform.screenRecordingEvents, platform.screenRecordingEvents),
      true,
    );
  });

  for (final (isRecording, state) in [
    (true, ScreenRecordingState.recording),
    (false, ScreenRecordingState.notRecording),
    (null, ScreenRecordingState.unknown),
  ]) {
    test('screenRecordingEvents maps isRecording $isRecording to '
        '${state.name}', () async {
      sendOnListen(
        screenRecordingEventChannel,
        ScreenRecordingEventMessage(
          isRecording: isRecording,
          timestampMillis: 1752150000000,
        ),
      );

      final event = await platform.screenRecordingEvents.first;

      expect(event.state, state);
      expect(event.isRecording, isRecording == true);
      expect(
        event.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1752150000000),
      );
    });
  }
}

/// Fake host API that keeps the protection state and the last options sent.
class FakeSecureScreenPrivacyPluginApi implements SecureScreenPrivacyPluginApi {
  bool captureProtection = false;
  bool appSwitcherProtection = false;
  AppSwitcherOptionsMessage? lastOptions;

  @override
  Future<String> getPlatformVersion() async => '42';

  @override
  Future<bool> enableCaptureProtection() async => captureProtection = true;

  @override
  Future<bool> disableCaptureProtection() async {
    captureProtection = false;
    return true;
  }

  @override
  Future<bool> isCaptureProtectionEnabled() async => captureProtection;

  @override
  Future<bool> enableAppSwitcherProtection(
    AppSwitcherOptionsMessage options,
  ) async {
    lastOptions = options;
    return appSwitcherProtection = true;
  }

  @override
  Future<bool> disableAppSwitcherProtection() async {
    appSwitcherProtection = false;
    return true;
  }

  @override
  Future<bool> isAppSwitcherProtectionEnabled() async => appSwitcherProtection;

  @override
  // ignore: non_constant_identifier_names
  BinaryMessenger? get pigeonVar_binaryMessenger => null;

  @override
  // ignore: non_constant_identifier_names
  String get pigeonVar_messageChannelSuffix => '';
}
