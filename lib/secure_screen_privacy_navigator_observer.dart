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
///
/// **Nested navigators:** give each `Navigator` its own observer. They work
/// together: protection is on when any showing navigator's current route
/// wants it, and the app switcher mode comes from the innermost showing
/// navigator that sets one. A nested navigator counts as showing while the
/// page that holds it is the top page of its parent navigator (when the
/// parent has an observer too). Several nested navigators shown side by side
/// or kept alive as tabs all count, so a protected route on a hidden tab
/// keeps protection on until that tab navigates.
///
/// **Direct calls:** this observer sets both capture and App Switcher
/// protection on every route change, so it replaces anything turned on with
/// `SecureScreenPrivacy` methods. Use one or the other for a given setting,
/// or put the protection you always want in [defaultConfig].
class SecureScreenPrivacyNavigatorObserver extends NavigatorObserver {
  SecureScreenPrivacyNavigatorObserver({
    this.policies = const {},
    this.defaultConfig = const SecureRouteConfig(),
  }) : _plugin = SecureScreenPrivacy() {
    _observers.add(WeakReference(this));
  }

  final Map<String, SecureRouteConfig> policies;
  final SecureRouteConfig defaultConfig;
  final SecureScreenPrivacy _plugin;

  // Chains each _applyConfig call after the previous one completes, so
  // navigation events are applied in the order they occurred even if their
  // underlying method-channel round trips would otherwise resolve out of
  // order (e.g. a push immediately followed by a pop, where the push's
  // enable call happens to take longer than the pop's disable call).
  // Shared by every observer, since they all drive the same native state.
  // When nothing is queued a new chain starts in the caller's zone, so a
  // finished chain from another zone (e.g. a test's) is never waited on.
  static Future<void> _pending = Future<void>.value();
  static int _queued = 0;

  // Every observer created, so nested navigators' observers can combine
  // their policies instead of overwriting each other's (see _combined).
  // Weak, so an observer dropped by the app doesn't stay alive here.
  static final List<WeakReference<SecureScreenPrivacyNavigatorObserver>>
  _observers = [];

  // The policy this observer last applied, or null before its first route.
  SecureRouteConfig? _currentConfig;

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
    if (route.navigator != null && !route.isCurrent) {
      // Added below the top, e.g. a page inserted under the top one in
      // Navigator.pages (go_router and other declarative routers). What
      // shows is unchanged, so only record where it sits. Before, its
      // policy was applied and replaced the protection of the page on top.
      _trackedRoutes.insert(_indexAbove(previousRoute), route);
      return;
    }
    _trackedRoutes.add(route);
    _applyPolicyForRoute(route);
  }

  // Where a route added right above [below] goes in _trackedRoutes: just
  // after it, at the bottom when nothing is below, or just under the top
  // when [below] is a route this observer doesn't know (an ignored popup).
  int _indexAbove(Route<dynamic>? below) {
    if (below == null) return 0;
    final index = _trackedRoutes.indexOf(below);
    if (index >= 0) return index + 1;
    return _trackedRoutes.isEmpty ? 0 : _trackedRoutes.length - 1;
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
    final wasTop = index >= 0 && index == _trackedRoutes.length - 1;
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
    if (wasTop) {
      // The top page or popup was swapped: apply whatever is on top now,
      // which is the page under it when the new route is an ignored popup.
      // Before, a protected popup replaced by an ignored one kept its
      // protection on.
      _applyTopTrackedRoute();
    } else if (index < 0 &&
        newIsTracked &&
        (newRoute.navigator == null || newRoute.isCurrent)) {
      _applyPolicyForRoute(newRoute);
    }
    // Otherwise a route below the top was swapped: what shows is unchanged.
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isTracked(route)) return;
    final index = _trackedRoutes.indexOf(route);
    if (index < 0) {
      // Never seen by this observer: go by the route Flutter reports.
      _applyPolicyForRoute(_visibleRoute(previousRoute));
      return;
    }
    final wasTop = index == _trackedRoutes.length - 1;
    _trackedRoutes.removeAt(index);
    // previousRoute is the route that was *under* the removed one, not the
    // one on top. Applying it turned protection off after
    // pushAndRemoveUntil to a protected page (the new page is pushed first,
    // then the old ones are removed) or after removeRoute took out a page
    // under a protected one. Only removing the top changes what shows.
    if (wasTop) _applyTopTrackedRoute();
  }

  void _applyTopTrackedRoute() =>
      _applyPolicyForRoute(_trackedRoutes.isEmpty ? null : _trackedRoutes.last);

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
    _currentConfig = config;
    // catchError so a single failed platform call (e.g. a PlatformException)
    // doesn't permanently wedge the chain - without it, _pending stays
    // errored forever and every future navigation event's _applyConfig call
    // would silently stop running.
    //
    // This observer's own config is taken now, so quick navigations still
    // apply in order; the other observers' part is read when the step runs
    // (after the Navigator has finished building, so the widget tree can be
    // walked).
    final previous = _queued == 0 ? Future<void>.value() : _pending;
    _queued++;
    _pending = previous
        .then((_) => _applyConfig(_combined(config)))
        .catchError((_) {})
        .whenComplete(() => _queued--);
  }

  // Merges this observer's [config] with the current policy of every other
  // observer whose navigator is showing: capture protection if any of them
  // wants it, and the app switcher settings of the innermost one that sets a
  // mode. With a single observer this is just [config].
  SecureRouteConfig _combined(SecureRouteConfig config) {
    _observers.removeWhere((ref) => ref.target == null);
    final parts = <(int, SecureRouteConfig)>[];
    for (final ref in _observers) {
      final observer = ref.target!;
      final isSelf = identical(observer, this);
      final observerConfig = isSelf ? config : observer._currentConfig;
      if (observerConfig == null) continue;
      if (observer.navigator == null) {
        // Not on a Navigator (yet): only its own call counts.
        if (isSelf) parts.add((0, observerConfig));
        continue;
      }
      final depth = observer._showingDepth();
      if (depth != null) parts.add((depth, observerConfig));
    }
    if (parts.isEmpty) return config;
    if (parts.length == 1) return parts.single.$2;

    parts.sort((a, b) => a.$1.compareTo(b.$1));
    final capture = parts.any((part) => part.$2.captureProtection);
    SecureRouteConfig? switcher;
    for (final part in parts) {
      if (part.$2.appSwitcherMode != null) switcher = part.$2;
    }
    return SecureRouteConfig(
      captureProtection: capture,
      appSwitcherMode: switcher?.appSwitcherMode,
      blurIntensity: switcher?.blurIntensity ?? BlurIntensity.ultraLight,
      color: switcher?.color ?? 0xFF000000,
      imageBackgroundColor: switcher?.imageBackgroundColor ?? 0xFF000000,
    );
  }

  // How many navigators deep this observer's navigator is (0 for the root)
  // if it is showing, or null if it is not: its navigator is gone, or it
  // sits inside a page that is no longer the top page of a parent navigator
  // that has an observer (e.g. that page was popped, or a new page covers
  // it). A parent navigator without an observer can't tell, so it counts as
  // showing.
  int? _showingDepth() {
    final nav = navigator;
    if (nav == null || !nav.mounted) return null;
    final parentNav = nav.context.findAncestorStateOfType<NavigatorState>();
    if (parentNav == null) return 0;

    SecureScreenPrivacyNavigatorObserver? parent;
    for (final ref in _observers) {
      final observer = ref.target;
      if (observer != null && identical(observer.navigator, parentNav)) {
        parent = observer;
        break;
      }
    }
    if (parent == null) return 1;
    final parentDepth = parent._showingDepth();
    if (parentDepth == null) return null;

    Route<dynamic>? topPage;
    for (final route in parent._trackedRoutes.reversed) {
      if (route is PageRoute) {
        topPage = route;
        break;
      }
    }
    if (topPage == null) return parentDepth + 1;
    final pageContext = (topPage as PageRoute).subtreeContext;
    if (pageContext == null) return null;
    var inside = false;
    nav.context.visitAncestorElements((element) {
      if (identical(element, pageContext)) {
        inside = true;
        return false;
      }
      return !identical(element, parentNav.context);
    });
    return inside ? parentDepth + 1 : null;
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
