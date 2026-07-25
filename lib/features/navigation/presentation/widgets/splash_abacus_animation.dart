import 'package:flutter/material.dart';

/// The Splash screen's animated abacus mark — beads in a premium, varied
/// palette slide out along their wires and settle with a light physical
/// overshoot, evoking Abaküs's namesake instrument. This is the brand mark
/// itself, not a placeholder — not shared because Splash is its only
/// consumer. See `docs/master_spec_migration.md` for the design decisions
/// behind its palette, proportions, and wood treatment.
class SplashAbacusAnimation extends StatefulWidget {
  final double width;
  final double height;

  const SplashAbacusAnimation({
    super.key,
    this.width = 340,
    this.height = 270,
  });

  @override
  State<SplashAbacusAnimation> createState() => _SplashAbacusAnimationState();
}

class _SplashAbacusAnimationState extends State<SplashAbacusAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// A premium, muted-but-vivid palette distinct from the app's core UI
  /// tokens — this is a one-off decorative illustration (the brand mark
  /// itself), not reusable UI color, so it deliberately lives here rather
  /// than in `AppColors`. Chosen to read as lacquered-wood tones rather
  /// than primary-color toy brights, per the explicit "must not look like
  /// a toy" requirement.
  static const List<Color> _beadColors = [
    Color(0xFF9CAF88), // Sage Green
    Color(0xFF1F6B4A), // Emerald Green
    Color(0xFFC85A2A), // Terracotta
    Color(0xFFE0A83E), // Mustard Yellow
    Color(0xFF2E4F7C), // Deep Blue
    Color(0xFFE37A57), // Coral
    Color(0xFF74822F), // Olive
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    // Accessibility Standards §9: reduce-motion users get the settled end
    // state immediately rather than sitting through the bead cascade.
    if (WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final frameOpacity = Curves.easeOut.transform(
            (_controller.value / 0.25).clamp(0.0, 1.0),
          );
          return Opacity(
            opacity: frameOpacity,
            child: CustomPaint(
              painter: _AbacusPainter(
                progress: _controller.value,
                beadColors: _beadColors,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Draws the wooden frame/wires once per frame and each bead's position as
/// a function of [progress] — beads start bunched at the wire's left end
/// and fan out to evenly-spaced resting positions. Each row starts its
/// motion later than the one above it, and within a row each bead starts a
/// touch later than its predecessor, so the whole illustration reads as a
/// single cascading wave rather than a rigid block move. `Curves.easeOutBack`
/// gives every bead a brief overshoot past its resting position before
/// relaxing back — the "settle" effect.
class _AbacusPainter extends CustomPainter {
  final double progress;
  final List<Color> beadColors;

  _AbacusPainter({required this.progress, required this.beadColors});

  static const int _rowCount = 7;
  static const int _beadsPerRow = 5;

  /// Three stops instead of two — a flat two-color diagonal reads as a
  /// gradient effect, a third mid-tone reads as actual wood grain.
  static const _woodGradient = LinearGradient(
    colors: [Color(0xFFD9B27F), Color(0xFFB1793F), Color(0xFF7A4F26)],
    stops: [0.0, 0.55, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  void paint(Canvas canvas, Size size) {
    const framePadding = 14.0;
    const postWidth = 11.0;

    final frameRect = Rect.fromLTWH(
      framePadding / 2,
      framePadding / 2,
      size.width - framePadding,
      size.height - framePadding,
    );
    final frameRRect = RRect.fromRectAndRadius(
      frameRect,
      const Radius.circular(22),
    );

    // A soft contact shadow beneath the whole frame lifts it off the
    // background instead of letting it sit flush/flat on the page.
    canvas.drawRRect(
      frameRRect.shift(const Offset(0, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    final framePaint = Paint()
      ..shader = _woodGradient.createShader(frameRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(frameRRect, framePaint);

    // Thin darker grain lines traced just inside the frame stroke — cheap
    // to draw, reads as real wood fiber rather than a flat gradient fill.
    final grainPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        frameRect.deflate(2.5),
        const Radius.circular(20),
      ),
      grainPaint,
    );

    final postPaint = Paint()..shader = _woodGradient.createShader(frameRect);
    for (final isLeft in [true, false]) {
      final postX = isLeft
          ? framePadding + postWidth / 2
          : size.width - framePadding - postWidth / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(postX, size.height / 2),
            width: postWidth,
            height: size.height - framePadding * 2,
          ),
          const Radius.circular(postWidth / 2),
        ),
        postPaint,
      );
    }

    const innerLeft = framePadding + postWidth + 6;
    final innerRight = size.width - framePadding - postWidth - 6;
    const innerTop = framePadding + 8;
    final innerBottom = size.height - framePadding - 8;
    final wireLength = innerRight - innerLeft;
    final rowSpacing = (innerBottom - innerTop) / _rowCount;
    final beadRadius = (rowSpacing * 0.33).clamp(9.0, 18.0);

    final wirePaint = Paint()
      ..color = const Color(0xFFB08954).withValues(alpha: 0.55)
      ..strokeWidth = 1.6;

    final usableSpan = wireLength - 2 * beadRadius - 8;
    final spacing = usableSpan / (_beadsPerRow - 1);
    final startX = innerLeft + beadRadius + 4;

    for (var row = 0; row < _rowCount; row++) {
      final wireY = innerTop + rowSpacing * (row + 0.5);
      canvas.drawLine(
        Offset(innerLeft, wireY),
        Offset(innerRight, wireY),
        wirePaint,
      );

      final color = beadColors[row % beadColors.length];
      final rowStart = row * 0.09;

      for (var bead = 0; bead < _beadsPerRow; bead++) {
        final beadStart = (rowStart + bead * 0.02).clamp(0.0, 0.85);
        const localDuration = 0.5;
        final localT = ((progress - beadStart) / localDuration).clamp(
          0.0,
          1.0,
        );
        final eased = Curves.easeOutBack.transform(localT);

        final targetX = startX + spacing * bead;
        final x = startX + (targetX - startX) * eased;

        _drawBead(canvas, Offset(x, wireY), beadRadius, color);
      }
    }
  }

  void _drawBead(Canvas canvas, Offset center, double radius, Color color) {
    canvas.drawCircle(
      center.translate(0, radius * 0.2),
      radius * 0.94,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = RadialGradient(
      center: const Alignment(-0.35, -0.4),
      radius: 0.9,
      colors: [
        Color.lerp(color, Colors.white, 0.32)!,
        color,
        Color.lerp(color, Colors.black, 0.24)!,
      ],
      stops: const [0.0, 0.55, 1.0],
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = gradient.createShader(rect),
    );

    // A small, tight specular dot (distinct from the broader gradient
    // highlight above) is what reads as "lacquered" rather than "matte
    // plastic" — the difference between a premium and a toy finish.
    canvas.drawCircle(
      center.translate(-radius * 0.32, -radius * 0.38),
      radius * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.65),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.black.withValues(alpha: 0.15),
    );
  }

  @override
  bool shouldRepaint(covariant _AbacusPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
