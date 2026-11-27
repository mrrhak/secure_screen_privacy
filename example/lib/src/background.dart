import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// A bright, detailed background drawn in code (no asset or network needed).
///
/// It sits behind every screen so the App Switcher blur has something to
/// blur: soft colour blobs for the overall look, plus sharp dots, rings and
/// stripes that turn visibly soft when blurred.
class ColorfulBackground extends StatelessWidget {
  const ColorfulBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(
          child: CustomPaint(painter: _BackgroundPainter()),
        ),
        child,
      ],
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1450), Color(0xFF4B1E78), Color(0xFF0E5E6F)],
        ).createShader(rect),
    );

    // Soft colour blobs.
    final blobs = <(Alignment, double, Color)>[
      (const Alignment(-0.9, -0.8), 0.55, const Color(0xFFFF4F9A)),
      (const Alignment(0.95, -0.35), 0.5, const Color(0xFF29D3FF)),
      (const Alignment(-0.6, 0.55), 0.6, const Color(0xFFFFC94A)),
      (const Alignment(0.8, 0.9), 0.55, const Color(0xFF7C4DFF)),
    ];
    final shortest = size.shortestSide;
    for (final (alignment, radiusFactor, color) in blobs) {
      final center = alignment.alongSize(size);
      final radius = shortest * radiusFactor;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // Sharp diagonal stripes in one corner.
    final stripes = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 6;
    for (var i = 0; i < 14; i++) {
      final x = size.width * 0.55 + i * 22.0;
      canvas.drawLine(Offset(x, 0), Offset(x + 160, 160), stripes);
    }

    // Sharp rings.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.35);
    for (final (alignment, radius) in [
      (const Alignment(-0.55, -0.1), 46.0),
      (const Alignment(0.6, 0.35), 70.0),
      (const Alignment(-0.2, 0.85), 34.0),
    ]) {
      final center = alignment.alongSize(size);
      canvas.drawCircle(center, radius, ring);
      canvas.drawCircle(center, radius * 0.6, ring);
    }

    // A grid of small dots, the clearest thing to watch turn soft.
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.28);
    const spacing = 28.0;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        final wave = math.sin((x + y) / 90);
        canvas.drawCircle(Offset(x, y), 1.6 + wave.abs() * 1.4, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A slightly see-through card used for every section, so the background
/// stays visible around and behind it.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surface.withValues(alpha: 0.86),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

/// A section title with an icon, used at the top of each card.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A short platform note in a tinted box.
class NoteBox extends StatelessWidget {
  const NoteBox(this.text, {super.key, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
