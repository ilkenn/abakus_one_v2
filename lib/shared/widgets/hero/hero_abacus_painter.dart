import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'hero_abacus_controller.dart';
import 'hero_abacus_geometry.dart';

/// Signature-object palette — one specific piece of brand artwork (the
/// "official ABAKÜS signature object"), not general reusable UI-surface
/// colors, per CLAUDE.md §6's existing exception for a screen-local
/// decorative/one-off hero graphic. The six bead color families are
/// locked by the product spec; only the shading *technique* around them
/// changes between v1 and this rebuild.
abstract final class HeroAbacusPalette {
  HeroAbacusPalette._();

  static const Color frameHighlight = Color(0xFFEDE1C8);
  static const Color frameMid = Color(0xFFD9C39C);
  static const Color frameShadow = Color(0xFFB89A6C);
  static const Color grainStroke = Color(0xFF7A5C36);

  static const Color rodHighlight = Color(0xFFF2ECDE);
  static const Color rodBase = Color(0xFFBCB1A0);
  static const Color rodShadow = Color(0xFF867B6B);

  static const List<Color> beadColors = [
    Color(0xFFF1E6D2), // Row 1 — Warm Cream
    Color(0xFFA9C2A0), // Row 2 — Soft Sage
    Color(0xFFD9A9AD), // Row 3 — Dusty Rose
    Color(0xFFA7C4D9), // Row 4 — Soft Sky Blue
    Color(0xFFB9AAD1), // Row 5 — Soft Lavender
    Color(0xFFD9B76B), // Row 6 — Warm Mustard
  ];
}

/// One `CustomPainter`, constructed with `repaint: controller` so
/// `CustomPaint` repaints directly from the controller's
/// `notifyListeners()` calls — no `setState`, no widget rebuild, no
/// per-bead widget diffing. A single [keyLight] direction drives the
/// frame's bevel highlight, each rod's top-highlight/bottom-shade, and
/// every bead's radial gradient, so the whole object reads as lit from one
/// consistent, soft, upper-left source — "photographed in a premium
/// product studio," not assembled from unrelated per-element gradients.
class HeroAbacusPainter extends CustomPainter {
  final HeroAbacusGeometry geometry;
  final HeroAbacusController controller;

  HeroAbacusPainter({required this.geometry, required this.controller})
      : super(repaint: controller);

  static const Alignment keyLight = Alignment(-0.35, -0.6);

  @override
  void paint(Canvas canvas, Size size) {
    _paintFrame(canvas);
    _paintRods(canvas);
    _paintBeads(canvas);
  }

  // ---- Frame: light oak / pale ash, matte, with real depth cues -------

  void _paintFrame(Canvas canvas) {
    final frameRect = geometry.frameRect;
    final cornerRadius = Radius.circular(frameRect.shortestSide * 0.16);
    final frameRRect = RRect.fromRectAndRadius(frameRect, cornerRadius);
    final borderWidth = frameRect.shortestSide * 0.045;

    // Two soft, warm, one-sided contact shadows so the object reads as
    // sitting on the page under real light, not pasted flat onto it.
    canvas.drawRRect(
      frameRRect.shift(const Offset(0, 14)),
      Paint()
        ..color = const Color(0xFF6E5A3A).withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.drawRRect(
      frameRRect.shift(const Offset(0, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.09)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Base stroke — light oak, gradient oriented so the light-facing
    // corner (opposite keyLight) reads brightest.
    final frameGradient = LinearGradient(
      colors: const [
        HeroAbacusPalette.frameHighlight,
        HeroAbacusPalette.frameMid,
        HeroAbacusPalette.frameShadow,
      ],
      stops: const [0.0, 0.55, 1.0],
      begin: Alignment(-keyLight.x, -keyLight.y),
      end: keyLight,
    );
    canvas.drawRRect(
      frameRRect,
      Paint()
        ..shader = frameGradient.createShader(frameRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeCap = StrokeCap.round,
    );

    _paintGrain(canvas, frameRect.deflate(borderWidth));

    // A darker inset stroke just inside the outer border -- reads as the
    // frame having real thickness/depth, not a single flat ring.
    final innerEdgeRRect = RRect.fromRectAndRadius(
      frameRect.deflate(borderWidth * 0.95),
      Radius.circular(cornerRadius.x * 0.85),
    );
    canvas.drawRRect(
      innerEdgeRRect,
      Paint()
        ..color = HeroAbacusPalette.frameShadow.withValues(alpha: 0.32)
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth * 0.32,
    );

    // A soft bevel highlight along the light-facing top/left edges only
    // (upper-left key light) -- brighter along the top, fainter on the
    // left, matching "upper-left/front" with a top-biased emphasis.
    final r = cornerRadius.x;
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = borderWidth * 0.26
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);

    final topY = frameRect.top + borderWidth * 0.55;
    canvas.drawLine(
      Offset(frameRect.left + r, topY),
      Offset(frameRect.right - r, topY),
      highlightPaint..color = Colors.white.withValues(alpha: 0.38),
    );
    final leftX = frameRect.left + borderWidth * 0.55;
    canvas.drawLine(
      Offset(leftX, frameRect.top + r),
      Offset(leftX, frameRect.bottom - r),
      highlightPaint..color = Colors.white.withValues(alpha: 0.20),
    );
  }

  /// Three gentle sine-wave strokes traced just inside the frame — reads
  /// as ultra-matte wood fiber rather than a flat gradient fill.
  void _paintGrain(Canvas canvas, Rect bounds) {
    final grainPaint = Paint()
      ..color = HeroAbacusPalette.grainStroke.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;

    const waveConfigs = [
      (yFraction: 0.22, amplitude: 2.6, frequency: 2.6, phase: 0.0),
      (yFraction: 0.5, amplitude: 1.8, frequency: 3.3, phase: 1.3),
      (yFraction: 0.8, amplitude: 3.0, frequency: 2.0, phase: 2.4),
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

  // ---- Rods: brushed champagne titanium, cylindrical -------------------

  void _paintRods(Canvas canvas) {
    final rodHeight = math.max(3.0, geometry.rowSpacing * 0.11);
    for (var row = 0; row < HeroAbacusGeometry.rowCount; row++) {
      final y = geometry.rowCenterY(row);
      final rodRect = Rect.fromLTRB(
        geometry.rodInnerLeft,
        y - rodHeight / 2,
        geometry.rodInnerRight,
        y + rodHeight / 2,
      );
      final rodRRect = RRect.fromRectAndRadius(
        rodRect,
        Radius.circular(rodHeight / 2),
      );

      canvas.drawRRect(
        rodRRect.shift(Offset(0, rodHeight * 0.6)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.05)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );

      // Vertical gradient across the rod's own height -- top edge lit,
      // base tone in the middle, darker lower edge -- gives a cylindrical
      // read instead of a flat 1px line.
      const rodGradient = LinearGradient(
        colors: [
          HeroAbacusPalette.rodHighlight,
          HeroAbacusPalette.rodBase,
          HeroAbacusPalette.rodShadow,
        ],
        stops: [0.0, 0.5, 1.0],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
      canvas.drawRRect(
        rodRRect,
        Paint()..shader = rodGradient.createShader(rodRect),
      );

      // Restrained specular strip along the top -- "extremely restrained
      // metallic reflection," not a bright highlight.
      final specRect = Rect.fromLTRB(
        rodRect.left,
        rodRect.top,
        rodRect.right,
        rodRect.top + rodHeight * 0.32,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(specRect, Radius.circular(rodHeight * 0.16)),
        Paint()..color = Colors.white.withValues(alpha: 0.18),
      );
    }
  }

  // ---- Beads: matte ceramic, three-dimensional --------------------------

  void _paintBeads(Canvas canvas) {
    for (var row = 0; row < HeroAbacusGeometry.rowCount; row++) {
      final color = HeroAbacusPalette.beadColors[row];
      for (var col = 0; col < HeroAbacusGeometry.beadsPerRow; col++) {
        final fraction = controller.positions[row][col];
        final center = geometry.beadCenter(row, fraction);
        _paintBead(canvas, center, geometry.beadRadius, color);
      }
    }
  }

  void _paintBead(Canvas canvas, Offset center, double radius, Color color) {
    // Soft ambient/contact shadow around the rod intersection -- an
    // ellipse (not a circle) so it reads as the bead resting against the
    // rod, not floating.
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, radius * 0.5),
        width: radius * 1.7,
        height: radius * 0.5,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2),
    );

    final rect = Rect.fromCircle(center: center, radius: radius);
    // Radial light falloff toward the shared key light, extended with a
    // darker bottom rim (ceramic underside) -- no hard specular hotspot,
    // no gloss, no transparency.
    final gradient = RadialGradient(
      center: keyLight,
      radius: 1.05,
      colors: [
        Color.lerp(color, Colors.white, 0.20)!,
        color,
        Color.lerp(color, Colors.black, 0.10)!,
        Color.lerp(color, Colors.black, 0.22)!,
      ],
      stops: const [0.0, 0.5, 0.82, 1.0],
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = gradient.createShader(rect),
    );

    // Soft, broad catch-light -- matte, not a crisp specular dot.
    canvas.drawCircle(
      center.translate(radius * keyLight.x * 0.55, radius * keyLight.y * 0.55),
      radius * 0.42,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.35),
    );

    // Very faint secondary layer -- a cheap, inexpensive stand-in for
    // "subtle surface variation" without a generated texture.
    canvas.drawCircle(
      center.translate(radius * 0.15, radius * 0.2),
      radius * 0.55,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.03)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.5),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = Colors.black.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(covariant HeroAbacusPainter oldDelegate) =>
      oldDelegate.geometry != geometry || oldDelegate.controller != controller;
}
