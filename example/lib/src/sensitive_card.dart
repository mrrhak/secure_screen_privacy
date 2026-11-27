import 'package:material_ui/material_ui.dart';

/// Made-up "sensitive" content (a payment card and a balance), so it's
/// obvious what a screenshot, a recording or the App Switcher would reveal.
class SensitiveCard extends StatelessWidget {
  const SensitiveCard({super.key});

  static const _width = 340.0;
  static const _aspectRatio = 1.586; // a real card's shape

  @override
  Widget build(BuildContext context) {
    final titleLarge = Theme.of(context).textTheme.titleLarge;
    // Laid out at one fixed size and scaled to fit, so it looks the same at
    // any width (including the small App Switcher preview).
    return AspectRatio(
      aspectRatio: _aspectRatio,
      child: FittedBox(
        child: Container(
          width: _width,
          height: _width / _aspectRatio,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF101828), Color(0xFF3A2A7A), Color(0xFF0F766E)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield_moon, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text('Veil Bank'),
                    Spacer(),
                    Icon(Icons.contactless, color: Colors.white, size: 22),
                  ],
                ),
                const Spacer(),
                Text(
                  '4929 1803 5521 7764',
                  style: titleLarge?.copyWith(
                    color: Colors.white,
                    letterSpacing: 2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Expanded(child: Text('SOPHEA CHAN')),
                    SizedBox(width: 12),
                    Text('09/29   CVV 482'),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Balance  \$12,480.55',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
