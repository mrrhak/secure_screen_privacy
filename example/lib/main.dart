import 'package:material_ui/material_ui.dart';
import 'package:secure_screen_privacy/secure_screen_privacy.dart';

import 'src/background.dart';
import 'src/detect_tab.dart';
import 'src/protect_tab.dart';
import 'src/routes_tab.dart';

void main() {
  runApp(const MyApp());
}

/// Lets the home screen notice when a demo route closes, so the Protect tab
/// can read back the state the route policy left behind.
final _routeObserver = RouteObserver<ModalRoute<void>>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Screen Privacy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF5B4BDB),
        useMaterial3: true,
      ),
      navigatorObservers: [
        SecureScreenPrivacyNavigatorObserver(policies: routePolicies),
        _routeObserver,
      ],
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        DemoRoutes.payment: (context) => const RouteDemoPage(
          title: 'Payment',
          route: DemoRoutes.payment,
          explanation:
              'Screenshots and screen recording are blocked while this page '
              'is open. Go back and they work again.',
        ),
        DemoRoutes.profile: (context) => const RouteDemoPage(
          title: 'Profile',
          route: DemoRoutes.profile,
          explanation:
              'Screenshots still work here, but the App Switcher shows a '
              'heavy blur instead of this page (iOS) or a blank card '
              '(Android).',
        ),
        DemoRoutes.wallet: (context) => const RouteDemoPage(
          title: 'Wallet',
          route: DemoRoutes.wallet,
          explanation:
              'Both at once: screenshots are blocked and the App Switcher '
              'shows the image over a blur (iOS).',
        ),
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  final _plugin = SecureScreenPrivacy();
  final _protectKey = GlobalKey<ProtectTabState>();
  int _tab = 0;
  String _platform = '';

  @override
  void initState() {
    super.initState();
    _plugin
        .getPlatformVersion()
        .then((version) {
          if (mounted) setState(() => _platform = version ?? '');
        })
        .catchError((_) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) _routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    _routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // The route policy for this screen is applied just after the pop.
    Future<void>.delayed(
      const Duration(milliseconds: 400),
      () => _protectKey.currentState?.syncFromNative(),
    );
  }

  static const _titles = ['Protect', 'Detect', 'Routes'];

  @override
  Widget build(BuildContext context) {
    return ColorfulBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: Text(_titles[_tab]),
          actions: [
            if (_platform.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Chip(
                  avatar: const Icon(Icons.phone_iphone, size: 16),
                  label: Text(_platform),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            ProtectTab(key: _protectKey, plugin: _plugin),
            DetectTab(plugin: _plugin),
            const RoutesTab(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield),
              label: 'Protect',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_none),
              selectedIcon: Icon(Icons.notifications_active),
              label: 'Detect',
            ),
            NavigationDestination(
              icon: Icon(Icons.alt_route_outlined),
              selectedIcon: Icon(Icons.alt_route),
              label: 'Routes',
            ),
          ],
        ),
      ),
    );
  }
}
