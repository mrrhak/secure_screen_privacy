// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:secure_screen_privacy/secure_screen_privacy.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getPlatformVersion test', (WidgetTester tester) async {
    final SecureScreenPrivacy plugin = SecureScreenPrivacy();
    final String? version = await plugin.getPlatformVersion();
    // The version string depends on the host platform running the test, so
    // just assert that some non-empty string is returned.
    expect(version?.isNotEmpty, true);
  });

  testWidgets('enableCaptureProtection / disableCaptureProtection test', (
    WidgetTester tester,
  ) async {
    final SecureScreenPrivacy plugin = SecureScreenPrivacy();
    expect(await plugin.enableCaptureProtection(), true);
    expect(await plugin.disableCaptureProtection(), true);
  });

  testWidgets('isCaptureProtectionEnabled reflects actual native state', (
    WidgetTester tester,
  ) async {
    final SecureScreenPrivacy plugin = SecureScreenPrivacy();

    await plugin.enableCaptureProtection();
    expect(await plugin.isCaptureProtectionEnabled(), true);

    await plugin.disableCaptureProtection();
    expect(await plugin.isCaptureProtectionEnabled(), false);
  });

  testWidgets(
    'screenRecordingEvents opens and reports the current state on subscribe',
    (WidgetTester tester) async {
      // On Android 15+ this needs DETECT_SCREEN_RECORDING; without it the
      // native onListen throws and the stream errors instead of emitting.
      // Android 14 and below and iOS also emit nothing or the initial state,
      // so only assert "no error" plus the initial value when one arrives.
      final SecureScreenPrivacy plugin = SecureScreenPrivacy();
      final events = <ScreenRecordingEvent>[];
      Object? error;
      final sub = plugin.screenRecordingEvents.listen(
        events.add,
        onError: (Object e) => error = e,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      await sub.cancel();

      expect(error, isNull);
      for (final event in events) {
        expect(event.isRecording, false);
      }
    },
  );
}
