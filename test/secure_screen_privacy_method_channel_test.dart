import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_screen_privacy/secure_screen_privacy.dart';
import 'package:secure_screen_privacy/secure_screen_privacy_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelSecureScreenPrivacy platform = MethodChannelSecureScreenPrivacy();
  const MethodChannel channel = MethodChannel('secure_screen_privacy');
  const EventChannel screenshotEventChannel = EventChannel(
    'secure_screen_privacy/screenshot_events',
  );
  const EventChannel screenRecordingEventChannel = EventChannel(
    'secure_screen_privacy/screen_recording_events',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'getPlatformVersion':
              return '42';
            case 'enableCaptureProtection':
            case 'disableCaptureProtection':
            case 'isCaptureProtectionEnabled':
            case 'enableAppSwitcherProtection':
            case 'disableAppSwitcherProtection':
            case 'isAppSwitcherProtectionEnabled':
              return true;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(screenshotEventChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(screenRecordingEventChannel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('enableCaptureProtection', () async {
    expect(await platform.enableCaptureProtection(), true);
  });

  test('disableCaptureProtection', () async {
    expect(await platform.disableCaptureProtection(), true);
  });

  test('isCaptureProtectionEnabled', () async {
    expect(await platform.isCaptureProtectionEnabled(), true);
  });

  test('enableAppSwitcherProtection', () async {
    expect(
      await platform.enableAppSwitcherProtection(AppSwitcherProtectionMode.blur),
      true,
    );
  });

  test('enableAppSwitcherProtection sends imageBlur mode', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          capturedCall = methodCall;
          return true;
        });

    final result = await platform.enableAppSwitcherProtection(
      AppSwitcherProtectionMode.imageBlur,
      blurIntensity: BlurIntensity.heavy,
    );

    expect(result, true);
    expect(capturedCall?.method, 'enableAppSwitcherProtection');
    expect((capturedCall?.arguments as Map)['mode'], 'imageBlur');
    expect((capturedCall?.arguments as Map)['blurIntensity'], 'heavy');
  });

  test('disableAppSwitcherProtection', () async {
    expect(await platform.disableAppSwitcherProtection(), true);
  });

  test('isAppSwitcherProtectionEnabled', () async {
    expect(await platform.isAppSwitcherProtectionEnabled(), true);
  });

  test('screenshotEvents maps the native payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      screenshotEventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, events) => events.success({'timestamp': 1752150000000}),
      ),
    );

    final event = await platform.screenshotEvents.first;

    expect(event.timestamp, DateTime.fromMillisecondsSinceEpoch(1752150000000));
  });

  test('screenRecordingEvents maps the native payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      screenRecordingEventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, events) =>
            events.success({'isRecording': true, 'timestamp': 1752150000000}),
      ),
    );

    final event = await platform.screenRecordingEvents.first;

    expect(event.isRecording, true);
    expect(event.timestamp, DateTime.fromMillisecondsSinceEpoch(1752150000000));
  });
}
