import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:secure_screen_privacy_example/main.dart';

void main() {
  // A tall phone, so every row of the lazily built lists is on screen.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 6000);
    view.devicePixelRatio = 3;
  });
  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('shows the three tabs and switches between them', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('Block screenshots & recording'), findsOneWidget);
    expect(find.text('Hide in App Switcher'), findsOneWidget);

    await tester.tap(find.text('Detect').last);
    await tester.pumpAndSettle();
    expect(find.text('Listen for screenshots'), findsOneWidget);
    expect(find.text('Listen for screen recording'), findsOneWidget);

    await tester.tap(find.text('Routes').last);
    await tester.pumpAndSettle();
    expect(find.text('PIN dialog'), findsOneWidget);
    expect(find.text('Statement bottom sheet'), findsOneWidget);
  });

  testWidgets('blur intensity only shows for blur modes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(find.text('Blur intensity'), findsOneWidget);

    await tester.tap(find.text('Color'));
    await tester.pumpAndSettle();
    expect(find.text('Blur intensity'), findsNothing);
    expect(find.text('Cover color'), findsOneWidget);
  });
}
