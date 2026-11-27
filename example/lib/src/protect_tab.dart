import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:secure_screen_privacy/secure_screen_privacy.dart';
import 'package:share_plus/share_plus.dart';

import 'background.dart';
import 'sensitive_card.dart';

/// Manual protection controls: capture protection and App Switcher
/// protection, with a preview of the App Switcher cover.
class ProtectTab extends StatefulWidget {
  const ProtectTab({super.key, required this.plugin});

  final SecureScreenPrivacy plugin;

  @override
  State<ProtectTab> createState() => ProtectTabState();
}

class ProtectTabState extends State<ProtectTab> {
  bool _captureProtection = false;
  bool _appSwitcherProtection = false;
  AppSwitcherProtectionMode _mode = AppSwitcherProtectionMode.blur;
  BlurIntensity _blurIntensity = BlurIntensity.ultraLight;
  Color _color = _swatches.first;
  Color _imageBackgroundColor = _swatches.first;

  static const _swatches = [
    Color(0xFF111827),
    Color(0xFF3F51B5),
    Color(0xFF00897B),
    Color(0xFFE65100),
    Color(0xFFFFFFFF),
  ];

  SecureScreenPrivacy get _plugin => widget.plugin;

  @override
  void initState() {
    super.initState();
    syncFromNative();
  }

  /// Reads the real state back from the native side. The route demos (and a
  /// Dart hot restart) change it without going through these switches.
  Future<void> syncFromNative() async {
    bool capture;
    bool appSwitcher;
    try {
      capture = await _plugin.isCaptureProtectionEnabled();
      appSwitcher = await _plugin.isAppSwitcherProtectionEnabled();
    } on Exception {
      return;
    }
    if (!mounted) return;
    setState(() {
      _captureProtection = capture;
      _appSwitcherProtection = appSwitcher;
    });
  }

  Future<void> _setCaptureProtection(bool enable) async {
    setState(() => _captureProtection = enable);
    try {
      final ok = enable
          ? await _plugin.enableCaptureProtection()
          : await _plugin.disableCaptureProtection();
      if (!ok) await syncFromNative();
    } on Exception {
      await syncFromNative();
    }
  }

  Future<void> _setAppSwitcherProtection(bool enable) async {
    setState(() => _appSwitcherProtection = enable);
    try {
      final ok = enable
          ? await _enableAppSwitcher()
          : await _plugin.disableAppSwitcherProtection();
      if (!ok) await syncFromNative();
    } on Exception {
      await syncFromNative();
    }
  }

  Future<bool> _enableAppSwitcher() => _plugin.enableAppSwitcherProtection(
    _mode,
    blurIntensity: _blurIntensity,
    color: _color.toARGB32(),
    imageBackgroundColor: _imageBackgroundColor.toARGB32(),
  );

  // Applies a new mode, intensity or colour straight away when protection
  // is already on.
  void _update(VoidCallback change) {
    setState(change);
    if (_appSwitcherProtection) {
      _enableAppSwitcher().catchError((_) => false);
    }
  }

  // A native screen shown over the app (UIActivityViewController on iOS),
  // to check that the App Switcher cover hides presented screens too. iPad
  // shows it as a popover, which needs the button as its anchor.
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

  @override
  Widget build(BuildContext context) {
    final usesBlur =
        _mode == AppSwitcherProtectionMode.blur ||
        _mode == AppSwitcherProtectionMode.imageBlur;
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SensitiveCard(),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.no_photography_outlined,
                title: 'Capture protection',
                subtitle: 'Blocks screenshots and screen recording.',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Block screenshots & recording'),
                subtitle: Text(
                  _captureProtection
                      ? 'On: screenshots and recordings come out blank'
                      : 'Off: the card above can be captured',
                ),
                value: _captureProtection,
                onChanged: _setCaptureProtection,
              ),
            ],
          ),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.layers_outlined,
                title: 'App Switcher protection',
                subtitle: 'Hides this screen in the recent apps preview.',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hide in App Switcher'),
                subtitle: const Text(
                  'Turn on, then open the App Switcher to see the cover.',
                ),
                value: _appSwitcherProtection,
                onChanged: _setAppSwitcherProtection,
              ),
              const SizedBox(height: 8),
              SegmentedButton<AppSwitcherProtectionMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AppSwitcherProtectionMode.blur,
                    label: Text('Blur'),
                  ),
                  ButtonSegment(
                    value: AppSwitcherProtectionMode.color,
                    label: Text('Color'),
                  ),
                  ButtonSegment(
                    value: AppSwitcherProtectionMode.image,
                    label: Text('Image'),
                  ),
                  ButtonSegment(
                    value: AppSwitcherProtectionMode.imageBlur,
                    label: Text('Both'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (value) =>
                    _update(() => _mode = value.single),
              ),
              if (usesBlur) ...[
                const SizedBox(height: 16),
                Text(
                  'Blur intensity',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                SegmentedButton<BlurIntensity>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: BlurIntensity.ultraLight,
                      label: Text('Ultra light'),
                    ),
                    ButtonSegment(
                      value: BlurIntensity.light,
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: BlurIntensity.medium,
                      label: Text('Medium'),
                    ),
                    ButtonSegment(
                      value: BlurIntensity.heavy,
                      label: Text('Heavy'),
                    ),
                  ],
                  selected: {_blurIntensity},
                  onSelectionChanged: (value) =>
                      _update(() => _blurIntensity = value.single),
                ),
              ],
              if (_mode == AppSwitcherProtectionMode.color) ...[
                const SizedBox(height: 16),
                _SwatchPicker(
                  label: 'Cover color',
                  colors: _swatches,
                  selected: _color,
                  onSelected: (color) => _update(() => _color = color),
                ),
              ],
              if (_mode == AppSwitcherProtectionMode.image) ...[
                const SizedBox(height: 16),
                _SwatchPicker(
                  label: 'Color around the image',
                  colors: _swatches,
                  selected: _imageBackgroundColor,
                  onSelected: (color) =>
                      _update(() => _imageBackgroundColor = color),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Preview (iOS)',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Center(
                child: _AppSwitcherPreview(
                  mode: _mode,
                  blurIntensity: _blurIntensity,
                  color: _color,
                  imageBackgroundColor: _imageBackgroundColor,
                ),
              ),
              const NoteBox(
                'iOS shows the cover you pick. The image comes from the '
                '"SecureScreenPrivacyImage" asset in the app. Android always '
                'shows a plain blank card instead, for every mode.',
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (buttonContext) => OutlinedButton.icon(
                  onPressed: () => _openShareSheet(buttonContext),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Open share sheet'),
                ),
              ),
              Text(
                'Open the App Switcher while the share sheet shows: it must '
                'be covered too.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A small phone-shaped approximation of what the iOS App Switcher card
/// shows for the chosen settings.
class _AppSwitcherPreview extends StatelessWidget {
  const _AppSwitcherPreview({
    required this.mode,
    required this.blurIntensity,
    required this.color,
    required this.imageBackgroundColor,
  });

  final AppSwitcherProtectionMode mode;
  final BlurIntensity blurIntensity;
  final Color color;
  final Color imageBackgroundColor;

  // Rough match for how iOS's ultra thin / thin / regular / thick materials
  // looked in real App Switcher snapshots of this app: always a strong blur,
  // with a whiter tint at each step up.
  double get _sigma => switch (blurIntensity) {
    BlurIntensity.ultraLight => 20,
    BlurIntensity.light => 24,
    BlurIntensity.medium => 28,
    BlurIntensity.heavy => 32,
  };

  double get _tint => switch (blurIntensity) {
    BlurIntensity.ultraLight => 0.12,
    BlurIntensity.light => 0.28,
    BlurIntensity.medium => 0.45,
    BlurIntensity.heavy => 0.58,
  };

  @override
  Widget build(BuildContext context) {
    final image = Image.asset('assets/cover_image.png', fit: BoxFit.contain);
    final blur = BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: _sigma, sigmaY: _sigma),
      child: ColoredBox(color: Colors.white.withValues(alpha: _tint)),
    );
    final cover = switch (mode) {
      AppSwitcherProtectionMode.blur => blur,
      AppSwitcherProtectionMode.color => ColoredBox(color: color),
      AppSwitcherProtectionMode.image => ColoredBox(
        color: imageBackgroundColor,
        child: image,
      ),
      AppSwitcherProtectionMode.imageBlur => Stack(
        fit: StackFit.expand,
        children: [blur, image],
      ),
    };
    // Drawn at a phone's real size and then shrunk, so the blur looks as
    // strong as it would on the whole screen.
    return SizedBox(
      width: 170,
      height: 300,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: FittedBox(
          child: SizedBox(
            width: 390,
            height: 690,
            child: ColorfulBackground(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 80, 16, 0),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SensitiveCard(),
                    ),
                  ),
                  cover,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwatchPicker extends StatelessWidget {
  const _SwatchPicker({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: [
            for (final color in colors)
              Semantics(
                button: true,
                selected: color == selected,
                label: 'Color 0x${color.toARGB32().toRadixString(16)}',
                child: GestureDetector(
                  onTap: () => onSelected(color),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color == selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.black26,
                        width: color == selected ? 3 : 1,
                      ),
                    ),
                    child: color == selected
                        ? Icon(
                            Icons.check,
                            size: 18,
                            color: color.computeLuminance() > 0.5
                                ? Colors.black
                                : Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
