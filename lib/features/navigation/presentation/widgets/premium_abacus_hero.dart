import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The Splash screen's abacus hero — Sprint 1 premium redesign, replacing
/// `splash_abacus_animation.dart` entirely (deleted, not kept alongside;
/// this had exactly one consumer).
///
/// **Concept, chosen after comparing five candidates** (see the approved
/// plan for the full ideation): this codebase has no image-generation or
/// 3D-rendering capability, so a literal photograph is out of reach —
/// this widget pushes the same CustomPainter technique the old one used to
/// its realistic ceiling instead (multi-stop wood grain, layered warm
/// contact shadow angled to imply one-sided morning light, matte —not
/// glossy— bead finish, a slight whole-frame perspective skew so the
/// object doesn't read as flat/front-on). It reads as a refined product
/// *illustration*, not a photograph — an honest ceiling, not a false
/// claim of photorealism.
///
/// **Swappable by design**: everything the real photographed/rendered
/// asset will eventually need (composition, light direction, negative
/// space) is already reflected here, so replacing the `CustomPaint` below
/// with an `Image.asset(...)` later is a one-widget swap — nothing in
/// `SplashScreen` needs to change when that happens.
class PremiumAbacusHero extends StatefulWidget {
  final double width;
  final double height;

  const PremiumAbacusHero({
    super.key,
    this.width = 340,
    this.height = 270,
  });

  @override
  State<PremiumAbacusHero> createState() => _PremiumAbacusHeroState();
}

class _PremiumAbacusHeroState extends State<PremiumAbacusHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Matte, soft-earthy bead palette — the brief's own named tones, not
  /// the old widget's brighter/varied set (mustard, coral, deep blue read
  /// as "toy," not "adult premium object").
  static const List<Color> _beadColors = [
    Color(0xFF9CAF88), // Sage green
    Color(0xFF74822F), // Olive
    Color(0xFFC2793C), // Terracotta
    Color(0xFFD9C9A8), // Warm ivory
    Color(0xFFB08B5A), // Sand
    Color(0xFF8A6A3C), // Natural oak
    Color(0xFF3F5D42), // Muted forest green
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
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
      // A very slight perspective skew — Concept B's "not perfectly
      // front-facing" requirement — so the object reads as sitting in
      // space rather than pasted flat on the screen.
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(-0.06)
          ..rotateX(0.03),
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
      ),
    );
  }
}

/// Draws the wooden frame/wires once per frame and each bead's position as
/// a function of [progress]. Refinements over the previous painter (kept
/// where the previous technique already worked — the cascade-and-settle
/// choreography — and elevated where the brief asked for more):
/// - three painted grain strokes (gentle sine-wave paths, not straight
///   lines) instead of one flat gradient, so the frame reads as fibrous
///   wood rather than a smooth gradient fill;
/// - two overlapping contact shadows, offset up-and-left, so the object
///   implies a single warm light source rather than sitting flush on the
///   page;
/// - beads get a broad, soft highlight instead of a tight specular dot —
///   the difference between "matte lacquered wood" and "glossy plastic."
class _AbacusPainter extends CustomPainter {
  final double progress;
  final List<Color> beadColors;

  _AbacusPainter({required this.progress, required this.beadColors});

  static const int _rowCount = 7;
  static const int _beadsPerRow = 5;

  static const _woodGradient = LinearGradient(
    colors: [Color(0xFFDCC69A), Color(0xFFA9764A), Color(0xFF6E4826)],
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
      const Radius.circular(24),
    );

    // Two overlapping shadows, both shifted up-and-left — a tight one for
    // grounded contact, a wide soft one for ambient falloff — read as one
    // warm light source from the upper-left rather than a flat drop shadow.
    canvas.drawRRect(
      frameRRect.shift(const Offset(6, 10)),
      Paint()
        ..color = const Color(0xFF6E4826).withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    canvas.drawRRect(
      frameRRect.shift(const Offset(3, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final framePaint = Paint()
      ..shader = _woodGradient.createShader(frameRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(frameRRect, framePaint);

    _paintGrain(canvas, frameRect.deflate(2.5));

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
      ..color = const Color(0xFFA07C4C).withValues(alpha: 0.5)
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

  /// Three gentle sine-wave strokes traced just inside the frame — cheap to
  /// draw, reads as real wood fiber rather than a flat gradient fill. Each
  /// wave uses a different frequency/phase so they don't look mechanically
  /// repeated.
  void _paintGrain(Canvas canvas, Rect bounds) {
    final grainPaint = Paint()
      ..color = const Color(0xFF4A2F16).withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;

    const waveConfigs = [
      (yFraction: 0.28, amplitude: 3.5, frequency: 2.4, phase: 0.0),
      (yFraction: 0.52, amplitude: 2.5, frequency: 3.1, phase: 1.1),
      (yFraction: 0.76, amplitude: 4.0, frequency: 1.9, phase: 2.3),
    ];

    for (final wave in waveConfigs) {
      final path = Path();
      final baseY = bounds.top + bounds.height * wave.yFraction;
      const steps = 40;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = bounds.left + bounds.width * t;
        final y = baseY +
            wave.amplitude *
                math.sin(t * math.pi * wave.frequency + wave.phase);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, grainPaint);
    }
  }

  void _drawBead(Canvas canvas, Offset center, double radius, Color color) {
    // Soft contact shadow beneath each bead, nudged toward the same
    // upper-left light direction as the frame's own shadow.
    canvas.drawCircle(
      center.translate(radius * 0.12, radius * 0.28),
      radius * 0.92,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );

    final rect = Rect.fromCircle(center: center, radius: radius);
    // A gentler gradient than a glossy sphere — the white lerp stays low
    // and the dark lerp is soft, so the bead reads as matte-lacquered
    // wood, not polished plastic.
    final gradient = RadialGradient(
      center: const Alignment(-0.3, -0.35),
      radius: 1.0,
      colors: [
        Color.lerp(color, Colors.white, 0.16)!,
        color,
        Color.lerp(color, Colors.black, 0.16)!,
      ],
      stops: const [0.0, 0.6, 1.0],
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = gradient.createShader(rect),
    );

    // A broad, soft highlight (not a tight specular dot) — matte finish
    // per the brief, distinct from the old widget's glossy point light.
    canvas.drawCircle(
      center.translate(-radius * 0.28, -radius * 0.32),
      radius * 0.42,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.black.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(covariant _AbacusPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
