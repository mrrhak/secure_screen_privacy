import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:secure_screen_privacy/secure_screen_privacy.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MyApp());
}

/// Route names demoed by [SecureScreenPrivacyNavigatorObserver] below. Each
/// one gets a different, automatically-applied protection policy purely from
/// being navigated to - no manual enable/disable calls needed on these pages.
const _paymentRoute = '/payment';
const _profileRoute = '/profile';
const _walletRoute = '/wallet';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [
        SecureScreenPrivacyNavigatorObserver(
          policies: {
            // Block screenshots/recording only.
            _paymentRoute: const SecureRouteConfig(captureProtection: true),
            // Hide in the app switcher only.
            _profileRoute: const SecureRouteConfig(
              appSwitcherMode: AppSwitcherProtectionMode.blur,
            ),
            // Both at once.
            _walletRoute: const SecureRouteConfig(
              captureProtection: true,
              appSwitcherMode: AppSwitcherProtectionMode.imageBlur,
            ),
          },
          // Every other route (including this demo's home screen) is left
          // fully unprotected so the manual toggles below aren't fought.
        ),
      ],
      initialRoute: '/',
      routes: {
        '/': (context) => const _HomeScreen(),
        _paymentRoute: (context) => const _RouteDemoScreen(
          title: 'Payment',
          description:
              'captureProtection: true\n\n'
              'Screenshots and screen recording are blocked for as long as '
              "you're on this route - applied automatically by "
              'SecureScreenPrivacyNavigatorObserver, no manual toggle needed.',
        ),
        _profileRoute: (context) => const _RouteDemoScreen(
          title: 'Profile',
          description:
              'appSwitcherMode: AppSwitcherProtectionMode.blur\n\n'
              'In-app screenshots are still allowed, but this route shows a '
              'blurred overlay in the OS app switcher/recents preview.',
        ),
        _walletRoute: (context) => const _RouteDemoScreen(
          title: 'Wallet',
          description:
              'captureProtection: true + '
              'appSwitcherMode: AppSwitcherProtectionMode.color\n\n'
              'Both protections are applied together on this route.',
        ),
      },
    );
  }
}

class _HomeScreen extends StatefulWidget {
  const _HomeScreen();

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  String _platformVersion = 'Unknown';
  bool _isCaptureProtectionEnabled = false;
  bool _isAppSwitcherProtectionEnabled = false;
  AppSwitcherProtectionMode _appSwitcherMode = AppSwitcherProtectionMode.blur;
  BlurIntensity _blurIntensity = BlurIntensity.ultraLight;
  Color _overlayColor = Colors.black;
  Color _imageBackgroundColor = Colors.black;
  final _secureScreenPrivacyPlugin = SecureScreenPrivacy();

  bool get _isListeningForScreenshots => _screenshotSubscription != null;
  StreamSubscription<ScreenshotEvent>? _screenshotSubscription;
  final List<DateTime> _screenshotTimestamps = [];

  bool get _isListeningForScreenRecording =>
      _screenRecordingSubscription != null;
  StreamSubscription<ScreenRecordingEvent>? _screenRecordingSubscription;
  bool _isRecordingActive = false;
  final List<ScreenRecordingEvent> _screenRecordingEventLog = [];

  static const _colorSwatches = [
    Colors.black,
    Colors.indigo,
    Colors.teal,
    Colors.deepOrange,
  ];

  @override
  void initState() {
    super.initState();
    initPlatformState();
    _syncCaptureProtectionState();
    _syncAppSwitcherProtectionState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  @override
  void dispose() {
    _screenshotSubscription?.cancel();
    _screenRecordingSubscription?.cancel();
    super.dispose();
  }

  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion =
          await _secureScreenPrivacyPlugin.getPlatformVersion() ??
          'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  // The native side keeps its own protection state independently of Dart's
  // (e.g. across a Dart hot restart, which resets this widget's state but not
  // the still-running native process), so resync on startup rather than
  // assuming protection starts disabled.
  Future<void> _syncCaptureProtectionState() async {
    bool isEnabled;
    try {
      isEnabled = await _secureScreenPrivacyPlugin.isCaptureProtectionEnabled();
    } on PlatformException {
      isEnabled = false;
    }

    if (!mounted) return;

    setState(() {
      _isCaptureProtectionEnabled = isEnabled;
    });
  }

  Future<void> _syncAppSwitcherProtectionState() async {
    bool isEnabled;
    try {
      isEnabled = await _secureScreenPrivacyPlugin
          .isAppSwitcherProtectionEnabled();
    } on PlatformException {
      isEnabled = false;
    }

    if (!mounted) return;

    setState(() {
      _isAppSwitcherProtectionEnabled = isEnabled;
    });
  }

  Future<void> _toggleCaptureProtection(bool enable) async {
    bool result;
    try {
      result = enable
          ? await _secureScreenPrivacyPlugin.enableCaptureProtection()
          : await _secureScreenPrivacyPlugin.disableCaptureProtection();
    } on PlatformException {
      result = false;
    }

    if (!mounted) return;

    setState(() {
      _isCaptureProtectionEnabled = enable && result;
    });
  }

  Future<void> _toggleAppSwitcherProtection(bool enable) async {
    bool result;
    try {
      result = enable
          ? await _secureScreenPrivacyPlugin.enableAppSwitcherProtection(
              _appSwitcherMode,
              blurIntensity: _blurIntensity,
              color: _overlayColor.toARGB32(),
              imageBackgroundColor: _imageBackgroundColor.toARGB32(),
            )
          : await _secureScreenPrivacyPlugin.disableAppSwitcherProtection();
    } on PlatformException {
      result = false;
    }

    if (!mounted) return;

    setState(() {
      _isAppSwitcherProtectionEnabled = enable && result;
    });
  }

  // A native screen presented over the app (UIActivityViewController on
  // iOS), for checking the App Switcher cover also hides presented screens.
  // iPad shows the sheet as a popover, which needs an anchor: the button.
  Future<void> _openShareSheet(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: 'secure_screen_privacy example',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  // Subscribing to the stream IS starting native screenshot detection;
  // cancelling IS stopping it - there's no separate start/stop method.
  void _toggleScreenshotListening(bool listen) {
    if (listen) {
      _screenshotSubscription = _secureScreenPrivacyPlugin.screenshotEvents
          .listen((event) {
            if (!mounted) return;
            setState(() {
              _screenshotTimestamps.insert(0, event.timestamp);
              if (_screenshotTimestamps.length > 5) {
                _screenshotTimestamps.removeLast();
              }
            });
          });
    } else {
      _screenshotSubscription?.cancel();
      _screenshotSubscription = null;
    }
    setState(() {});
  }

  // Subscribing to the stream IS starting native recording detection;
  // cancelling IS stopping it - there's no separate start/stop method. On
  // Android it needs Android 15 (API 35) or newer; older versions emit
  // nothing.
  void _toggleScreenRecordingListening(bool listen) {
    if (listen) {
      _screenRecordingSubscription = _secureScreenPrivacyPlugin
          .screenRecordingEvents
          .listen((event) {
            if (!mounted) return;
            setState(() {
              _isRecordingActive = event.isRecording;
              _screenRecordingEventLog.insert(0, event);
              if (_screenRecordingEventLog.length > 5) {
                _screenRecordingEventLog.removeLast();
              }
            });
          });
    } else {
      _screenRecordingSubscription?.cancel();
      _screenRecordingSubscription = null;
      _isRecordingActive = false;
    }
    setState(() {});
  }

  // Re-applies the app switcher overlay with the latest mode/intensity/color
  // whenever one of them changes while protection is already enabled.
  Future<void> _reapplyAppSwitcherProtectionIfEnabled() async {
    if (!_isAppSwitcherProtectionEnabled) return;
    try {
      await _secureScreenPrivacyPlugin.enableAppSwitcherProtection(
        _appSwitcherMode,
        blurIntensity: _blurIntensity,
        color: _overlayColor.toARGB32(),
        imageBackgroundColor: _imageBackgroundColor.toARGB32(),
      );
    } on PlatformException {
      // Ignore; the switch will reflect the last-known state on next sync.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plugin example app')),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Running on: $_platformVersion\n'),
              SwitchListTile(
                title: const Text('Block screenshots & screen recording'),
                value: _isCaptureProtectionEnabled,
                onChanged: _toggleCaptureProtection,
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Hide content in app switcher'),
                value: _isAppSwitcherProtectionEnabled,
                onChanged: _toggleAppSwitcherProtection,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<AppSwitcherProtectionMode>(
                  decoration: const InputDecoration(
                    labelText: 'App Switcher Mode',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: _appSwitcherMode,
                  items: const [
                    DropdownMenuItem(
                      value: AppSwitcherProtectionMode.blur,
                      child: Text('Blur'),
                    ),
                    DropdownMenuItem(
                      value: AppSwitcherProtectionMode.image,
                      child: Text('Image'),
                    ),
                    DropdownMenuItem(
                      value: AppSwitcherProtectionMode.color,
                      child: Text('Color'),
                    ),
                    DropdownMenuItem(
                      value: AppSwitcherProtectionMode.imageBlur,
                      child: Text('Image+Blur'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _appSwitcherMode = value;
                    });
                    _reapplyAppSwitcherProtectionIfEnabled();
                  },
                ),
              ),
              if (_appSwitcherMode == AppSwitcherProtectionMode.blur ||
                  _appSwitcherMode == AppSwitcherProtectionMode.imageBlur)
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
                  child: DropdownButtonFormField<BlurIntensity>(
                    decoration: const InputDecoration(
                      labelText: 'Blur Intensity',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: _blurIntensity,
                    items: const [
                      DropdownMenuItem(
                        value: BlurIntensity.ultraLight,
                        child: Text('Ultra light'),
                      ),
                      DropdownMenuItem(
                        value: BlurIntensity.light,
                        child: Text('Light'),
                      ),
                      DropdownMenuItem(
                        value: BlurIntensity.medium,
                        child: Text('Medium'),
                      ),
                      DropdownMenuItem(
                        value: BlurIntensity.heavy,
                        child: Text('Heavy'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _blurIntensity = value;
                      });
                      _reapplyAppSwitcherProtectionIfEnabled();
                    },
                  ),
                ),
              if (_appSwitcherMode == AppSwitcherProtectionMode.color)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _ColorSwatchPicker(
                    colors: _colorSwatches,
                    selected: _overlayColor,
                    onSelected: (color) {
                      setState(() {
                        _overlayColor = color;
                      });
                      _reapplyAppSwitcherProtectionIfEnabled();
                    },
                  ),
                ),
              if (_appSwitcherMode == AppSwitcherProtectionMode.image ||
                  _appSwitcherMode == AppSwitcherProtectionMode.imageBlur)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Image mode requires a "secure_screen_privacy_image" drawable '
                    '(Android) / "SecureScreenPrivacyImage" asset (iOS) bundled in '
                    "the host app.",
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_appSwitcherMode == AppSwitcherProtectionMode.image) ...[
                const Text('Background color'),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _ColorSwatchPicker(
                    colors: _colorSwatches,
                    selected: _imageBackgroundColor,
                    onSelected: (color) {
                      setState(() {
                        _imageBackgroundColor = color;
                      });
                      _reapplyAppSwitcherProtectionIfEnabled();
                    },
                  ),
                ),
              ],
              const Divider(),
              SwitchListTile(
                title: const Text('Listen for screenshots'),
                value: _isListeningForScreenshots,
                onChanged: _toggleScreenshotListening,
              ),
              if (_screenshotTimestamps.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final timestamp in _screenshotTimestamps)
                        Text(
                          'Screenshot detected: ${timestamp.toIso8601String()}',
                        ),
                    ],
                  ),
                ),
              const Divider(),
              SwitchListTile(
                title: const Text('Listen for screen recording'),
                subtitle: Text(
                  _isListeningForScreenRecording
                      ? (_isRecordingActive
                            ? 'Recording active'
                            : 'Not recording')
                      : 'Off',
                ),
                value: _isListeningForScreenRecording,
                onChanged: _toggleScreenRecordingListening,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'On Android this needs Android 15 (API 35) or newer.',
                  textAlign: TextAlign.center,
                ),
              ),
              if (_screenRecordingEventLog.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final event in _screenRecordingEventLog)
                        Text(
                          '${event.isRecording ? "Started" : "Stopped"}: '
                          '${event.timestamp.toIso8601String()}',
                        ),
                    ],
                  ),
                ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'SecureScreenPrivacyNavigatorObserver demo\n'
                  '(protection is applied automatically per route below)',
                  textAlign: TextAlign.center,
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, _paymentRoute),
                child: const Text('Payment (capture protection)'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, _profileRoute),
                child: const Text('Profile (app switcher blur)'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, _walletRoute),
                child: const Text('Wallet (both)'),
              ),
              const Divider(height: 32),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Opens the system share sheet on top of the app. With '
                  '"Hide content in app switcher" on, open the App Switcher '
                  'while it is showing: the share sheet must be covered too.',
                  textAlign: TextAlign.center,
                ),
              ),
              Builder(
                builder: (buttonContext) => ElevatedButton.icon(
                  onPressed: () => _openShareSheet(buttonContext),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Open share sheet'),
                ),
              ),
              SizedBox(height: 24),
              Image.network(
                'https://c4.wallpaperflare.com/wallpaper/860/881/255/amoled-dragon-phone-iphone-vertical-hd-wallpaper-preview.jpg',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A page used to demo [SecureScreenPrivacyNavigatorObserver]: its
/// protection policy comes entirely from the route name it's pushed under,
/// not from anything on this widget.
class _RouteDemoScreen extends StatelessWidget {
  const _RouteDemoScreen({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(description, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _ColorSwatchPicker extends StatelessWidget {
  const _ColorSwatchPicker({
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: colors.map((color) {
        final isSelected = color.toARGB32() == selected.toARGB32();
        return GestureDetector(
          onTap: () => onSelected(color),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2,
              ),
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        );
      }).toList(),
    );
  }
}
