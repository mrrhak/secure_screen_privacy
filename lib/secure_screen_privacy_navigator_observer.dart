import 'package:flutter/widgets.dart';

import 'secure_screen_privacy.dart';

/// A [NavigatorObserver] that applies capture protection and/or app switcher
/// protection per route.
///
/// Each route resolves a full [SecureRouteConfig]: fields not set for that
/// route are explicitly turned off, so protection never leaks over from a
/// previously active route.
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [
///     SecureScreenPrivacyNavigatorObserver(
///       policies: {
///         // Block screenshots only.
///         '/payment': const SecureRouteConfig(captureProtection: true),
///         // Hide in the app switcher only.
///         '/profile': const SecureRouteConfig(
///           appSwitcherMode: AppSwitcherProtectionMode.blur,
///         ),
///         // Both at once.
///         '/wallet': const SecureRouteConfig(
///           captureProtection: true,
///           appSwitcherMode: AppSwitcherProtectionMode.color,
///         ),
///         // Neither (explicitly unprotected).
///         '/home': const SecureRouteConfig(),
///         // A dialog or bottom sheet, matched by its route name.
///         '/pin-dialog': const SecureRouteConfig(captureProtection: true),
///       },
///     ),
///   ],
/// )
/// ```
///
/// Dialogs, bottom sheets and menus are left alone unless their route name
/// has an entry in [policies]. Give one a name with `routeSettings`, for
/// example `showDialog(..., routeSettings: const RouteSettings(name:
/// '/pin-dialog'))`, and add that name to [policies]. When it closes, the
/// policy of whatever is showing under it applies again. `showDialog` and
/// `showModalBottomSheet` push onto the root Navigator by default, so this
/// observer must be on that Navigator to see them.
class SecureScreenPrivacyNavigatorObserver extends NavigatorObserver {
  SecureScreenPrivacyNavigatorObserver({
    this.policies = const {},
    this.defaultConfig = const SecureRouteConfig(),
  }) : _plugin = SecureScreenPrivacy();

  final Map<String, SecureRouteConfig> policies;
  final SecureRouteConfig defaultConfig;
  final SecureScreenPrivacy _plugin;

  // Chains each _applyConfig call after the previous one completes, so
  // navigation events are applied in the order they occurred even if their
  // underlying method-channel round trips would otherwise resolve out of
  // order (e.g. a push immediately followed by a pop, where the push's
  // enable call happens to take longer than the pop's disable call).
  Future<void> _pending = Future<void>.value();

  // The routes this observer applies a policy for (pages, plus popups that
  // have a policy - see _isTracked) currently on the Navigator, bottom first,
  // as seen through this observer's own callbacks. Only used to find what is
  // really showing when the route revealed by a pop/remove is an ignored
  // popup: e.g. page A -> dialog -> page B pushed from the dialog, then B is
  // popped. didPop reports the dialog as previousRoute, but the protection
  // that should apply is A's - without this the dialog's (unnamed) route
  // resolved to defaultConfig and turned A's protection off.
  final List<Route<dynamic>> _trackedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isTracked(route)) return;
    _trackedRoutes.add(route);
    _applyPolicyForRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isTracked(route)) return;
    _trackedRoutes.remove(route);
    _applyPolicyForRoute(_visibleRoute(previousRoute));
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _trackedRoutes.indexOf(oldRoute);
    final newIsTracked = newRoute != null && _isTracked(newRoute);
    if (index >= 0) {
      if (newIsTracked) {
        _trackedRoutes[index] = newRoute;
      } else {
        _trackedRoutes.removeAt(index);
      }
    } else if (newIsTracked) {
      _trackedRoutes.add(newRoute);
    }
    if (!newIsTracked) return;
    _applyPolicyForRoute(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isTracked(route)) return;
    _trackedRoutes.remove(route);
    _applyPolicyForRoute(_visibleRoute(previousRoute));
  }

  // The route whose policy should apply once [revealed] is on top: itself if
  // this observer tracks it, otherwise (an ignored popup) the top-most
  // tracked route this observer knows is still open underneath it.
  Route<dynamic>? _visibleRoute(Route<dynamic>? revealed) {
    if (revealed == null || _isTracked(revealed)) return revealed;
    return _trackedRoutes.isEmpty ? null : _trackedRoutes.last;
  }

  // Pages always get a policy (their own or defaultConfig). Popups only when
  // the app opted in by giving the popup's route name an entry in policies.
  bool _isTracked(Route<dynamic> route) =>
      !_isPopup(route) || policies.containsKey(route.settings.name);

  // Widgets like DropdownButton, PopupMenuButton, and showDialog push their
  // own route on the same Navigator this observer is attached to, in order
  // to show an overlay - not to navigate to a new page. Treating those like
  // real page transitions would reapply the *underlying* route's policy
  // every time such a popup opens or closes, racing against whatever the
  // app itself is doing at that moment (e.g. re-enabling protection with a
  // newly-picked mode from a dropdown) and often clobbering it, since the
  // popup's own didPush/didPop tends to resolve after the app's own
  // platform call.
  //
  // Checked via `is! PageRoute` rather than a null `settings.name` check:
  // PageRoute ("a modal route that replaces the entire screen") and
  // PopupRoute are siblings under ModalRoute, and every built-in overlay
  // route (DialogRoute/RawDialogRoute, ModalBottomSheetRoute,
  // PopupMenuButton's route, DropdownButton's route) extends PopupRoute,
  // never PageRoute - regardless of whether it's given an explicit name.
  // A name-based check alone would miss a deliberately-named dialog route
  // (e.g. one named for analytics) and reintroduce this exact bug - which is
  // why a popup is only tracked when its name is in policies (_isTracked),
  // never just because it has a name.
  bool _isPopup(Route<dynamic>? route) => route is! PageRoute;

  void _applyPolicyForRoute(Route<dynamic>? route) {
    final name = route?.settings.name;
    final config = (name != null ? policies[name] : null) ?? defaultConfig;
    // catchError so a single failed platform call (e.g. a PlatformException)
    // doesn't permanently wedge the chain - without it, _pending stays
    // errored forever and every future navigation event's _applyConfig call
    // would silently stop running.
    _pending = _pending.then((_) => _applyConfig(config)).catchError((_) {});
  }

  Future<void> _applyConfig(SecureRouteConfig config) async {
    await (config.captureProtection
        ? _plugin.enableCaptureProtection()
        : _plugin.disableCaptureProtection());

    final mode = config.appSwitcherMode;
    await (mode != null
        ? _plugin.enableAppSwitcherProtection(
            mode,
            blurIntensity: config.blurIntensity,
            color: config.color,
            imageBackgroundColor: config.imageBackgroundColor,
          )
        : _plugin.disableAppSwitcherProtection());
  }
}
