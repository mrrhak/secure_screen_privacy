import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:secure_screen_privacy/secure_screen_privacy.dart';
import 'package:secure_screen_privacy/secure_screen_privacy_platform_interface.dart';

class _RecordingPlatform extends SecureScreenPrivacyPlatform
    with MockPlatformInterfaceMixin {
  final List<String> calls = [];

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<bool> enableCaptureProtection() async {
    calls.add('enableCaptureProtection');
    return true;
  }

  @override
  Future<bool> disableCaptureProtection() async {
    calls.add('disableCaptureProtection');
    return true;
  }

  @override
  Future<bool> isCaptureProtectionEnabled() => Future.value(false);

  @override
  Future<bool> enableAppSwitcherProtection(
    AppSwitcherProtectionMode mode, {
    BlurIntensity blurIntensity = BlurIntensity.ultraLight,
    int color = 0xFF000000,
    int imageBackgroundColor = 0xFF000000,
  }) async {
    calls.add(
      'enableAppSwitcherProtection($mode, $blurIntensity, $color, $imageBackgroundColor)',
    );
    return true;
  }

  @override
  Future<bool> disableAppSwitcherProtection() async {
    calls.add('disableAppSwitcherProtection');
    return true;
  }

  @override
  Future<bool> isAppSwitcherProtectionEnabled() => Future.value(false);
}

/// Like [_RecordingPlatform], but lets a test delay individual method calls
/// to simulate their underlying method-channel round trips completing out of
/// the order they were started in.
class _DelayedRecordingPlatform extends SecureScreenPrivacyPlatform
    with MockPlatformInterfaceMixin {
  _DelayedRecordingPlatform(this.delayFor);

  final Duration Function(String call) delayFor;
  final List<String> calls = [];

  Future<bool> _record(String call) async {
    await Future<void>.delayed(delayFor(call));
    calls.add(call);
    return true;
  }

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<bool> enableCaptureProtection() => _record('enableCaptureProtection');

  @override
  Future<bool> disableCaptureProtection() => _record('disableCaptureProtection');

  @override
  Future<bool> isCaptureProtectionEnabled() => Future.value(false);

  @override
  Future<bool> enableAppSwitcherProtection(
    AppSwitcherProtectionMode mode, {
    BlurIntensity blurIntensity = BlurIntensity.ultraLight,
    int color = 0xFF000000,
    int imageBackgroundColor = 0xFF000000,
  }) =>
      _record('enableAppSwitcherProtection');

  @override
  Future<bool> disableAppSwitcherProtection() => _record('disableAppSwitcherProtection');

  @override
  Future<bool> isAppSwitcherProtectionEnabled() => Future.value(false);
}

/// Like [_RecordingPlatform], but throws on the first `enableCaptureProtection`
/// call to simulate a failed platform-channel round trip (e.g. a
/// PlatformException), then behaves normally afterwards.
class _ThrowsOncePlatform extends SecureScreenPrivacyPlatform
    with MockPlatformInterfaceMixin {
  final List<String> calls = [];
  bool _threw = false;

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<bool> enableCaptureProtection() async {
    if (!_threw) {
      _threw = true;
      throw PlatformException(code: 'boom');
    }
    calls.add('enableCaptureProtection');
    return true;
  }

  @override
  Future<bool> disableCaptureProtection() async {
    calls.add('disableCaptureProtection');
    return true;
  }

  @override
  Future<bool> isCaptureProtectionEnabled() => Future.value(false);

  @override
  Future<bool> enableAppSwitcherProtection(
    AppSwitcherProtectionMode mode, {
    BlurIntensity blurIntensity = BlurIntensity.ultraLight,
    int color = 0xFF000000,
    int imageBackgroundColor = 0xFF000000,
  }) async {
    calls.add('enableAppSwitcherProtection');
    return true;
  }

  @override
  Future<bool> disableAppSwitcherProtection() async {
    calls.add('disableAppSwitcherProtection');
    return true;
  }

  @override
  Future<bool> isAppSwitcherProtectionEnabled() => Future.value(false);
}

Route<dynamic> _fakeRoute(String? name) {
  return PageRouteBuilder<void>(
    settings: RouteSettings(name: name),
    pageBuilder: (_, _, _) => const SizedBox(),
  );
}

/// Mimics the shape of the route a `DropdownButton`/`PopupMenuButton`/
/// `showDialog` pushes on the same Navigator - a [PopupRoute], not a
/// [PageRoute] - optionally with an explicit name, to prove the observer
/// ignores these by route type rather than by name.
Route<dynamic> _fakePopupRoute({String? name}) {
  return _FakePopupRoute(settings: RouteSettings(name: name));
}

class _FakePopupRoute extends PopupRoute<void> {
  _FakePopupRoute({super.settings});

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const SizedBox();
}


/// A root Navigator showing [rootPage], whose page holds a nested Navigator
/// that starts on [nestedPage]; each Navigator has its own observer.
Future<(NavigatorState, NavigatorState)> _pumpNested(
  WidgetTester tester, {
  required SecureScreenPrivacyNavigatorObserver rootObserver,
  required SecureScreenPrivacyNavigatorObserver nestedObserver,
  String rootPage = '/shell',
  String nestedPage = '/payment',
}) async {
  final rootKey = GlobalKey<NavigatorState>();
  final nestedKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Navigator(
        key: rootKey,
        observers: [rootObserver],
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          settings: RouteSettings(name: rootPage),
          pageBuilder: (_, _, _) => Navigator(
            key: nestedKey,
            observers: [nestedObserver],
            onGenerateRoute: (_) => _fakeRoute(nestedPage),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (rootKey.currentState!, nestedKey.currentState!);
}

void main() {
  late _RecordingPlatform fakePlatform;
  late SecureScreenPrivacyPlatform originalPlatform;

  setUp(() {
    originalPlatform = SecureScreenPrivacyPlatform.instance;
    fakePlatform = _RecordingPlatform();
    SecureScreenPrivacyPlatform.instance = fakePlatform;
  });

  tearDown(() {
    SecureScreenPrivacyPlatform.instance = originalPlatform;
  });

  group('SecureRouteConfig', () {
    test('default values', () {
      const config = SecureRouteConfig();
      expect(config.captureProtection, false);
      expect(config.appSwitcherMode, isNull);
      expect(config.blurIntensity, BlurIntensity.ultraLight);
      expect(config.color, 0xFF000000);
      expect(config.imageBackgroundColor, 0xFF000000);
    });

    test('equality', () {
      const a = SecureRouteConfig(
        captureProtection: true,
        appSwitcherMode: AppSwitcherProtectionMode.blur,
      );
      const b = SecureRouteConfig(
        captureProtection: true,
        appSwitcherMode: AppSwitcherProtectionMode.blur,
      );
      const c = SecureRouteConfig(captureProtection: true);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode', () {
      const a = SecureRouteConfig(
        captureProtection: true,
        appSwitcherMode: AppSwitcherProtectionMode.color,
        color: 0xFF2196F3,
      );
      const b = SecureRouteConfig(
        captureProtection: true,
        appSwitcherMode: AppSwitcherProtectionMode.color,
        color: 0xFF2196F3,
      );

      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('SecureScreenPrivacyNavigatorObserver', () {
    testWidgets(
      'real Navigator: popping a page opened from a dialog keeps the page under it protected',
      (tester) async {
        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(captureProtection: true),
          },
        );
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Navigator(
              key: navigatorKey,
              observers: [observer],
              onGenerateRoute: (settings) => _fakeRoute('/payment'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final nav = navigatorKey.currentState!;
        nav.push(_fakePopupRoute());
        await tester.pumpAndSettle();
        nav.push(_fakeRoute('/details'));
        await tester.pumpAndSettle();
        fakePlatform.calls.clear();

        nav.pop();
        await tester.pumpAndSettle();

        expect(fakePlatform.calls, [
          'enableCaptureProtection',
          'disableAppSwitcherProtection',
        ]);
      },
    );

    test(
      'popping a page opened from a dialog keeps the page under the dialog protected',
      () async {
        // page A (protected) -> dialog -> page B pushed from the dialog ->
        // pop B. didPop reports the dialog as previousRoute; the policy that
        // must apply is A's, not defaultConfig.
        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(captureProtection: true),
          },
        );
        final pageA = _fakeRoute('/payment');
        final dialog = _fakePopupRoute();
        final pageB = _fakeRoute('/details');

        observer.didPush(pageA, null);
        observer.didPush(dialog, pageA);
        observer.didPush(pageB, dialog);
        await Future<void>.delayed(Duration.zero);
        fakePlatform.calls.clear();

        observer.didPop(pageB, dialog);
        await Future<void>.delayed(Duration.zero);

        expect(fakePlatform.calls, [
          'enableCaptureProtection',
          'disableAppSwitcherProtection',
        ]);
      },
    );

    test(
      'removing a page opened from a dialog keeps the page under the dialog protected',
      () async {
        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(captureProtection: true),
          },
        );
        final pageA = _fakeRoute('/payment');
        final dialog = _fakePopupRoute();
        final pageB = _fakeRoute('/details');

        observer.didPush(pageA, null);
        observer.didPush(dialog, pageA);
        observer.didPush(pageB, dialog);
        await Future<void>.delayed(Duration.zero);
        fakePlatform.calls.clear();

        observer.didRemove(pageB, dialog);
        await Future<void>.delayed(Duration.zero);

        expect(fakePlatform.calls, contains('enableCaptureProtection'));
        expect(fakePlatform.calls, isNot(contains('disableCaptureProtection')));
      },
    );

    test(
      'a replaced page is no longer used as the page under a dialog',
      () async {
        // A -> replaced by C (unprotected) -> dialog -> page B -> pop B:
        // C's policy applies, not A's.
        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(captureProtection: true),
            '/home': const SecureRouteConfig(),
          },
        );
        final pageA = _fakeRoute('/payment');
        final pageC = _fakeRoute('/home');
        final dialog = _fakePopupRoute();
        final pageB = _fakeRoute('/details');

        observer.didPush(pageA, null);
        observer.didReplace(newRoute: pageC, oldRoute: pageA);
        observer.didPush(dialog, pageC);
        observer.didPush(pageB, dialog);
        await Future<void>.delayed(Duration.zero);
        fakePlatform.calls.clear();

        observer.didPop(pageB, dialog);
        await Future<void>.delayed(Duration.zero);

        expect(fakePlatform.calls, [
          'disableCaptureProtection',
          'disableAppSwitcherProtection',
        ]);
      },
    );

    test(
      'popping back to a dialog with no known page underneath uses defaultConfig',
      () async {
        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(captureProtection: true),
          },
        );

        observer.didPop(_fakeRoute('/payment'), _fakePopupRoute());
        await Future<void>.delayed(Duration.zero);

        expect(fakePlatform.calls, [
          'disableCaptureProtection',
          'disableAppSwitcherProtection',
        ]);
      },
    );

    test('didPush applies policy for pushed route', () async {
      final observer = SecureScreenPrivacyNavigatorObserver(
        policies: {
          '/payment': const SecureRouteConfig(captureProtection: true),
        },
      );

      observer.didPush(_fakeRoute('/payment'), null);
      await Future<void>.delayed(Duration.zero);

      expect(fakePlatform.calls, contains('enableCaptureProtection'));
      expect(fakePlatform.calls, contains('disableAppSwitcherProtection'));
    });

    test('didPop applies policy for previous route', () async {
      final observer = SecureScreenPrivacyNavigatorObserver(
        policies: {'/home': const SecureRouteConfig()},
      );

      observer.didPop(_fakeRoute('/payment'), _fakeRoute('/home'));
      await Future<void>.delayed(Duration.zero);

      expect(fakePlatform.calls, contains('disableCaptureProtection'));
      expect(fakePlatform.calls, contains('disableAppSwitcherProtection'));
    });

    test(
      'didPop of a popup route does not reapply the underlying route\'s policy',
      () async {
        // Dismissing a dropdown/dialog/menu pops its PopupRoute and fires
        // didPop with previousRoute set back to the real page - but that
        // page's policy was already applied when it was pushed and hasn't
        // changed, so reapplying it here would race against (and could
        // clobber) any manual protection change made while the popup was
        // open.
        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {'/home': const SecureRouteConfig()},
        );

        observer.didPop(_fakePopupRoute(), _fakeRoute('/home'));
        await Future<void>.delayed(Duration.zero);

        expect(fakePlatform.calls, isEmpty);
      },
    );

    test('didReplace applies policy for new route', () async {
      final observer = SecureScreenPrivacyNavigatorObserver(
        policies: {
          '/profile': const SecureRouteConfig(
            appSwitcherMode: AppSwitcherProtectionMode.blur,
            blurIntensity: BlurIntensity.heavy,
          ),
        },
      );

      observer.didReplace(
        newRoute: _fakeRoute('/profile'),
        oldRoute: _fakeRoute('/home'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        fakePlatform.calls,
        contains(
          'enableAppSwitcherProtection(AppSwitcherProtectionMode.blur, BlurIntensity.heavy, 4278190080, 4278190080)',
        ),
      );
      expect(fakePlatform.calls, contains('disableCaptureProtection'));
    });

    test('didRemove applies policy for previous route', () async {
      final observer = SecureScreenPrivacyNavigatorObserver(
        policies: {'/home': const SecureRouteConfig()},
      );

      observer.didRemove(_fakeRoute('/payment'), _fakeRoute('/home'));
      await Future<void>.delayed(Duration.zero);

      expect(fakePlatform.calls, contains('disableCaptureProtection'));
      expect(fakePlatform.calls, contains('disableAppSwitcherProtection'));
    });

    test('unmapped routes use defaultConfig', () async {
      final observer = SecureScreenPrivacyNavigatorObserver(
        policies: {
          '/payment': const SecureRouteConfig(captureProtection: true),
        },
        defaultConfig: const SecureRouteConfig(),
      );

      observer.didPush(_fakeRoute('/unknown'), null);
      await Future<void>.delayed(Duration.zero);

      expect(fakePlatform.calls, contains('disableCaptureProtection'));
      expect(fakePlatform.calls, contains('disableAppSwitcherProtection'));
    });

    test(
      'an unnamed but real PageRoute still gets defaultConfig applied',
      () async {
        // Distinguishes this from a popup route by type (PageRoute), not by
        // name: an anonymous PageRoute (e.g. pushed via Navigator.push
        // without a name) is still a genuine page transition and should
        // resolve to defaultConfig like any other unmapped route, not be
        // silently ignored the way a popup route is.
        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(captureProtection: true),
          },
        );

        observer.didPush(_fakeRoute(null), _fakeRoute('/payment'));
        await Future<void>.delayed(Duration.zero);

        expect(fakePlatform.calls, contains('disableCaptureProtection'));
        expect(fakePlatform.calls, contains('disableAppSwitcherProtection'));
      },
    );

    test(
      'a dropdown/dialog/menu popup route is ignored, even unnamed',
      () async {
        // Widgets like DropdownButton, PopupMenuButton, and showDialog push
        // their own PopupRoute on the same Navigator this observer is
        // attached to. It must not be treated as a real page transition -
        // otherwise opening a dropdown on an unprotected route (e.g. the
        // home screen) would momentarily disable whatever protection the
        // app had manually enabled there, racing against and often
        // clobbering it.
        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(captureProtection: true),
          },
        );

        observer.didPush(_fakePopupRoute(), _fakeRoute('/payment'));
        await Future<void>.delayed(Duration.zero);

        expect(fakePlatform.calls, isEmpty);
      },
    );

    test(
      'a popup route is ignored even if deliberately given a route name not in policies',
      () async {
        // A name-based check alone would be fooled by a dialog/menu route
        // that's explicitly named (e.g. for analytics) - it must still be
        // ignored based on being a PopupRoute, not a PageRoute, regardless
        // of settings.name.
        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(captureProtection: true),
          },
        );

        observer.didPush(
          _fakePopupRoute(name: '/confirm-dialog'),
          _fakeRoute('/payment'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(fakePlatform.calls, isEmpty);
      },
    );

    testWidgets(
      'real Navigator: a named dialog with a policy is protected, and closing it restores the page policy',
      (tester) async {
        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/home': const SecureRouteConfig(),
            '/pin-dialog': const SecureRouteConfig(captureProtection: true),
          },
        );
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Navigator(
              key: navigatorKey,
              observers: [observer],
              onGenerateRoute: (settings) => _fakeRoute('/home'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        fakePlatform.calls.clear();

        final nav = navigatorKey.currentState!;
        nav.push(_fakePopupRoute(name: '/pin-dialog'));
        await tester.pumpAndSettle();
        expect(fakePlatform.calls, [
          'enableCaptureProtection',
          'disableAppSwitcherProtection',
        ]);
        fakePlatform.calls.clear();

        nav.pop();
        await tester.pumpAndSettle();
        expect(fakePlatform.calls, [
          'disableCaptureProtection',
          'disableAppSwitcherProtection',
        ]);
      },
    );

    test(
      'a named bottom sheet with an app switcher policy enables it',
      () async {
        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/card-sheet': const SecureRouteConfig(
              appSwitcherMode: AppSwitcherProtectionMode.color,
            ),
          },
        );

        observer.didPush(
          _fakePopupRoute(name: '/card-sheet'),
          _fakeRoute('/home'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(fakePlatform.calls, [
          'disableCaptureProtection',
          'enableAppSwitcherProtection(AppSwitcherProtectionMode.color, BlurIntensity.ultraLight, 4278190080, 4278190080)',
        ]);
      },
    );

    test(
      'closing an unnamed popup opened on top of a protected dialog changes nothing',
      () async {
        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/pin-dialog': const SecureRouteConfig(captureProtection: true),
          },
        );
        final page = _fakeRoute('/home');
        final dialog = _fakePopupRoute(name: '/pin-dialog');
        final menu = _fakePopupRoute();

        observer.didPush(page, null);
        observer.didPush(dialog, page);
        observer.didPush(menu, dialog);
        await Future<void>.delayed(Duration.zero);
        fakePlatform.calls.clear();

        observer.didPop(menu, dialog);
        await Future<void>.delayed(Duration.zero);

        expect(fakePlatform.calls, isEmpty);
      },
    );

    test(
      'popping a page opened from a protected dialog applies the dialog policy',
      () async {
        // page A (unprotected) -> protected dialog -> page B -> pop B: the
        // dialog is showing again, so its policy applies, not A's.
        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/home': const SecureRouteConfig(),
            '/pin-dialog': const SecureRouteConfig(captureProtection: true),
          },
        );
        final pageA = _fakeRoute('/home');
        final dialog = _fakePopupRoute(name: '/pin-dialog');
        final pageB = _fakeRoute('/details');

        observer.didPush(pageA, null);
        observer.didPush(dialog, pageA);
        observer.didPush(pageB, dialog);
        await Future<void>.delayed(Duration.zero);
        fakePlatform.calls.clear();

        observer.didPop(pageB, dialog);
        await Future<void>.delayed(Duration.zero);

        expect(fakePlatform.calls, [
          'enableCaptureProtection',
          'disableAppSwitcherProtection',
        ]);
      },
    );

    testWidgets(
      'nested navigators: a protected nested route turns protection on even though the outer page does not',
      (tester) async {
        final rootObserver = SecureScreenPrivacyNavigatorObserver();
        final nestedObserver = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(captureProtection: true),
          },
        );
        await _pumpNested(
          tester,
          rootObserver: rootObserver,
          nestedObserver: nestedObserver,
        );

        expect(fakePlatform.calls.sublist(fakePlatform.calls.length - 2), [
          'enableCaptureProtection',
          'disableAppSwitcherProtection',
        ]);
      },
    );

    testWidgets(
      'nested navigators: coming back to the outer page keeps the nested route protected',
      (tester) async {
        final rootObserver = SecureScreenPrivacyNavigatorObserver();
        final nestedObserver = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(captureProtection: true),
          },
        );
        final (root, _) = await _pumpNested(
          tester,
          rootObserver: rootObserver,
          nestedObserver: nestedObserver,
        );

        // A full page on the root covers the nested navigator: off.
        root.push(_fakeRoute('/settings'));
        await tester.pumpAndSettle();
        expect(fakePlatform.calls.sublist(fakePlatform.calls.length - 2), [
          'disableCaptureProtection',
          'disableAppSwitcherProtection',
        ]);
        fakePlatform.calls.clear();

        // Popping it shows the nested /payment again: on. Before, the root
        // observer applied its own page's policy alone and turned it off.
        root.pop();
        await tester.pumpAndSettle();
        expect(fakePlatform.calls, [
          'enableCaptureProtection',
          'disableAppSwitcherProtection',
        ]);
      },
    );

    testWidgets(
      'nested navigators: popping the outer page that holds them drops their policy',
      (tester) async {
        final rootKey = GlobalKey<NavigatorState>();
        final nestedObserver = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(captureProtection: true),
          },
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Navigator(
              key: rootKey,
              observers: [SecureScreenPrivacyNavigatorObserver()],
              onGenerateRoute: (_) => _fakeRoute('/home'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        rootKey.currentState!.push(
          PageRouteBuilder<void>(
            settings: const RouteSettings(name: '/shell'),
            pageBuilder: (_, _, _) => Navigator(
              observers: [nestedObserver],
              onGenerateRoute: (_) => _fakeRoute('/payment'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(fakePlatform.calls, contains('enableCaptureProtection'));
        fakePlatform.calls.clear();

        rootKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(fakePlatform.calls, [
          'disableCaptureProtection',
          'disableAppSwitcherProtection',
        ]);
      },
    );

    testWidgets(
      'nested navigators: the innermost app switcher mode wins, capture protection from any',
      (tester) async {
        final rootObserver = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/shell': const SecureRouteConfig(
              captureProtection: true,
              appSwitcherMode: AppSwitcherProtectionMode.color,
            ),
          },
        );
        final nestedObserver = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(
              appSwitcherMode: AppSwitcherProtectionMode.blur,
              blurIntensity: BlurIntensity.heavy,
            ),
          },
        );
        await _pumpNested(
          tester,
          rootObserver: rootObserver,
          nestedObserver: nestedObserver,
        );

        expect(fakePlatform.calls.sublist(fakePlatform.calls.length - 2), [
          'enableCaptureProtection',
          'enableAppSwitcherProtection(AppSwitcherProtectionMode.blur, BlurIntensity.heavy, 4278190080, 4278190080)',
        ]);
      },
    );

    test('route with both capture and app switcher protection calls both enable methods', () async {
      final observer = SecureScreenPrivacyNavigatorObserver(
        policies: {
          '/wallet': const SecureRouteConfig(
            captureProtection: true,
            appSwitcherMode: AppSwitcherProtectionMode.color,
            color: 0xFF123456,
          ),
        },
      );

      observer.didPush(_fakeRoute('/wallet'), null);
      await Future<void>.delayed(Duration.zero);

      expect(fakePlatform.calls, contains('enableCaptureProtection'));
      expect(
        fakePlatform.calls,
        contains(
          'enableAppSwitcherProtection(AppSwitcherProtectionMode.color, BlurIntensity.ultraLight, ${0xFF123456}, 4278190080)',
        ),
      );
    });

    test('route with neither set calls both disable methods', () async {
      final observer = SecureScreenPrivacyNavigatorObserver(
        policies: {'/home': const SecureRouteConfig()},
      );

      observer.didPush(_fakeRoute('/home'), null);
      await Future<void>.delayed(Duration.zero);

      expect(fakePlatform.calls, contains('disableCaptureProtection'));
      expect(fakePlatform.calls, contains('disableAppSwitcherProtection'));
    });

    test(
      'rapid navigation applies policies in call order despite differing platform-call latencies',
      () async {
        // The earlier-started call (push's enable) is slower than the
        // later-started call (pop's disable). Without serializing, the
        // faster call finishes first and the slower one clobbers it after -
        // leaving stale state applied even though pop happened last.
        final delayedPlatform = _DelayedRecordingPlatform(
          (call) => call == 'enableCaptureProtection'
              ? const Duration(milliseconds: 50)
              : Duration.zero,
        );
        SecureScreenPrivacyPlatform.instance = delayedPlatform;

        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(captureProtection: true),
            '/home': const SecureRouteConfig(),
          },
        );

        observer.didPush(_fakeRoute('/payment'), _fakeRoute('/home'));
        observer.didPop(_fakeRoute('/payment'), _fakeRoute('/home'));

        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Push's config (both calls) must fully complete before pop's config
        // starts, even though push's enable call is the slow one - proving
        // navigation order is preserved rather than whichever call happens
        // to finish first.
        expect(delayedPlatform.calls, [
          'enableCaptureProtection',
          'disableAppSwitcherProtection',
          'disableCaptureProtection',
          'disableAppSwitcherProtection',
        ]);
      },
    );

    test(
      'a failed platform call does not permanently stop later policies from applying',
      () async {
        final throwsOncePlatform = _ThrowsOncePlatform();
        SecureScreenPrivacyPlatform.instance = throwsOncePlatform;

        final observer = SecureScreenPrivacyNavigatorObserver(
          policies: {
            '/payment': const SecureRouteConfig(captureProtection: true),
            '/profile': const SecureRouteConfig(
              appSwitcherMode: AppSwitcherProtectionMode.blur,
            ),
          },
        );

        // First navigation's enableCaptureProtection throws.
        observer.didPush(_fakeRoute('/payment'), null);
        await Future<void>.delayed(Duration.zero);

        // A later navigation must still apply, proving the _pending chain
        // recovered instead of staying permanently errored.
        observer.didPush(_fakeRoute('/profile'), _fakeRoute('/payment'));
        await Future<void>.delayed(Duration.zero);

        expect(throwsOncePlatform.calls, contains('disableCaptureProtection'));
        expect(throwsOncePlatform.calls, contains('enableAppSwitcherProtection'));
      },
    );
  });
}
