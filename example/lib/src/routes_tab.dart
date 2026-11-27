import 'package:material_ui/material_ui.dart';
import 'package:secure_screen_privacy/secure_screen_privacy.dart';

import 'background.dart';
import 'sensitive_card.dart';

/// Route names with a protection policy, see [routePolicies].
abstract final class DemoRoutes {
  static const payment = '/payment';
  static const profile = '/profile';
  static const wallet = '/wallet';
  static const pinDialog = '/pin-dialog';
  static const statementSheet = '/statement-sheet';
}

/// The policies given to [SecureScreenPrivacyNavigatorObserver] in main.dart.
/// Every other route, including the home screen, gets the default: nothing
/// protected.
const routePolicies = <String, SecureRouteConfig>{
  DemoRoutes.payment: SecureRouteConfig(captureProtection: true),
  DemoRoutes.profile: SecureRouteConfig(
    appSwitcherMode: AppSwitcherProtectionMode.blur,
    blurIntensity: BlurIntensity.heavy,
  ),
  DemoRoutes.wallet: SecureRouteConfig(
    captureProtection: true,
    appSwitcherMode: AppSwitcherProtectionMode.imageBlur,
  ),
  // Popups are only protected when their route name is listed here.
  DemoRoutes.pinDialog: SecureRouteConfig(captureProtection: true),
  DemoRoutes.statementSheet: SecureRouteConfig(
    captureProtection: true,
    appSwitcherMode: AppSwitcherProtectionMode.color,
    color: 0xFF111827,
  ),
};

String describePolicy(SecureRouteConfig? config) {
  if (config == null) return 'No policy: nothing protected';
  final parts = [
    if (config.captureProtection) 'Screenshots blocked',
    if (config.appSwitcherMode != null)
      'App Switcher: ${config.appSwitcherMode!.name}',
  ];
  return parts.isEmpty ? 'Nothing protected' : parts.join(' + ');
}

/// Pages, a dialog and a bottom sheet that get their protection from
/// [SecureScreenPrivacyNavigatorObserver] just by their route name.
class RoutesTab extends StatelessWidget {
  const RoutesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        const GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                icon: Icons.alt_route,
                title: 'Protection per route',
                subtitle:
                    'SecureScreenPrivacyNavigatorObserver turns protection on '
                    'and off as you move between screens. No switches needed.',
              ),
              NoteBox(
                'This home screen has no policy, so coming back here turns '
                'everything off, including what you set on the Protect tab.',
              ),
            ],
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              _tile(
                context,
                icon: Icons.payments_outlined,
                title: 'Payment page',
                route: DemoRoutes.payment,
                onTap: () => Navigator.pushNamed(context, DemoRoutes.payment),
              ),
              _tile(
                context,
                icon: Icons.person_outline,
                title: 'Profile page',
                route: DemoRoutes.profile,
                onTap: () => Navigator.pushNamed(context, DemoRoutes.profile),
              ),
              _tile(
                context,
                icon: Icons.account_balance_wallet_outlined,
                title: 'Wallet page',
                route: DemoRoutes.wallet,
                onTap: () => Navigator.pushNamed(context, DemoRoutes.wallet),
              ),
            ],
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              _tile(
                context,
                icon: Icons.pin_outlined,
                title: 'PIN dialog',
                route: DemoRoutes.pinDialog,
                onTap: () => showPinDialog(context),
              ),
              _tile(
                context,
                icon: Icons.receipt_long_outlined,
                title: 'Statement bottom sheet',
                route: DemoRoutes.statementSheet,
                onTap: () => showStatementSheet(context),
              ),
              _tile(
                context,
                icon: Icons.chat_bubble_outline,
                title: 'Plain dialog',
                route: null,
                subtitle: 'No name, so it changes nothing',
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Plain dialog'),
                    content: const Text(
                      'This dialog has no route name in the policies, so the '
                      'protection of the screen under it stays as it was.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String? route,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle ?? describePolicy(routePolicies[route])),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// A dialog protected by its route name ([DemoRoutes.pinDialog]).
Future<void> showPinDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    routeSettings: const RouteSettings(name: DemoRoutes.pinDialog),
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.lock_outline),
      title: const Text('Your card PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '4 8 2 9',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              letterSpacing: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Try a screenshot: it comes out blank while this is open.',
          ),
          const SizedBox(height: 12),
          const ProtectionStatus(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

/// A bottom sheet protected by its route name ([DemoRoutes.statementSheet]).
Future<void> showStatementSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    routeSettings: const RouteSettings(name: DemoRoutes.statementSheet),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Recent transactions'),
            subtitle: Text('Protected while this sheet is open'),
          ),
          for (final (name, amount) in const [
            ('Coffee Lab', '-\$4.80'),
            ('Salary', '+\$3,250.00'),
            ('Rent', '-\$1,100.00'),
            ('Grocery Mart', '-\$62.15'),
          ])
            ListTile(dense: true, title: Text(name), trailing: Text(amount)),
          const Padding(padding: EdgeInsets.all(16), child: ProtectionStatus()),
        ],
      ),
    ),
  );
}

/// A screen whose protection comes only from the route name it was pushed
/// under.
class RouteDemoPage extends StatelessWidget {
  const RouteDemoPage({
    super.key,
    required this.title,
    required this.route,
    required this.explanation,
  });

  final String title;
  final String route;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    return ColorfulBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const Padding(padding: EdgeInsets.all(16), child: SensitiveCard()),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    icon: Icons.policy_outlined,
                    title: route,
                    subtitle: describePolicy(routePolicies[route]),
                  ),
                  Text(explanation),
                  const SizedBox(height: 12),
                  const ProtectionStatus(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows what the plugin reports as switched on right now, read back from
/// the native side a moment after the screen opens.
class ProtectionStatus extends StatefulWidget {
  const ProtectionStatus({super.key});

  @override
  State<ProtectionStatus> createState() => _ProtectionStatusState();
}

class _ProtectionStatusState extends State<ProtectionStatus> {
  final _plugin = SecureScreenPrivacy();
  bool? _capture;
  bool? _appSwitcher;

  @override
  void initState() {
    super.initState();
    // The observer applies the policy right after the route is pushed.
    Future<void>.delayed(const Duration(milliseconds: 400), _read);
  }

  Future<void> _read() async {
    try {
      final capture = await _plugin.isCaptureProtectionEnabled();
      final appSwitcher = await _plugin.isAppSwitcherProtectionEnabled();
      if (!mounted) return;
      setState(() {
        _capture = capture;
        _appSwitcher = appSwitcher;
      });
    } on Exception {
      // Not available (for example in widget tests).
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip('Capture protection', _capture),
        _chip('App Switcher', _appSwitcher),
      ],
    );
  }

  Widget _chip(String label, bool? on) {
    return Chip(
      avatar: Icon(
        on == null
            ? Icons.hourglass_empty
            : on
            ? Icons.check_circle
            : Icons.remove_circle_outline,
        size: 18,
        color: on == true ? Colors.green : null,
      ),
      label: Text(
        on == null
            ? label
            : on
            ? '$label: on'
            : '$label: off',
      ),
    );
  }
}
