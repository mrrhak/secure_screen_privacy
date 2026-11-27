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
}
