import 'dart:ui';

/// Pure layout math for the Hero Abacus — frame/rod/bead placement and
/// touch hit-testing. No Flutter widget/animation dependency, so this is
/// trivially unit-testable on its own and reusable identically by both the
/// painter and the controller's hit-testing.
class HeroAbacusGeometry {
  static const int rowCount = 6;
  static const int beadsPerRow = 6;

  static const double aspectRatio = 0.50;
  static const double marginFraction = 0.025;
  static const double rodInsetXFraction = 0.045;
  static const double rodInsetYFraction = 0.06;

  /// Larger than v1's 0.30 — "beads must be larger than the current
  /// version."
  static const double beadRadiusFactor = 0.34;

  /// Each bead's touch area is padded well beyond its visual radius, per
  /// the "do not require the user to touch the exact visible circle"
  /// requirement.
  static const double touchRadiusMultiplier = 1.6;

  final double width;
  final double height;
  final Rect frameRect;
  final double rodInnerLeft;
  final double rodInnerRight;
  final double innerTop;
  final double rowSpacing;
  final double beadRadius;
  final double usableLength;
  final double minSeparationFraction;

  const HeroAbacusGeometry._({
    required this.width,
    required this.height,
    required this.frameRect,
    required this.rodInnerLeft,
    required this.rodInnerRight,
    required this.innerTop,
    required this.rowSpacing,
    required this.beadRadius,
    required this.usableLength,
    required this.minSeparationFraction,
  });

  factory HeroAbacusGeometry.forWidth(double width) {
    final height = width * aspectRatio;
    final margin = width * marginFraction;
    final frameRect = Rect.fromLTWH(
      margin,
      margin,
      width - 2 * margin,
      height - 2 * margin,
    );

    final rodInsetX = width * rodInsetXFraction;
    final rodInsetY = height * rodInsetYFraction;
    final innerLeft = frameRect.left + rodInsetX;
    final innerRight = frameRect.right - rodInsetX;
    final innerTop = frameRect.top + rodInsetY;
    final innerBottom = frameRect.bottom - rodInsetY;
    final rowSpacing = (innerBottom - innerTop) / rowCount;
    final beadRadius = rowSpacing * beadRadiusFactor;
    final endMargin = beadRadius * 0.4;
    final rodInnerLeft = innerLeft + beadRadius + endMargin;
    final rodInnerRight = innerRight - beadRadius - endMargin;
    final usableLength = (rodInnerRight - rodInnerLeft) < 1.0
        ? 1.0
        : rodInnerRight - rodInnerLeft;
    final gapPx = beadRadius * 0.5;
    final minSeparationFraction = (2 * beadRadius + gapPx) / usableLength;

    return HeroAbacusGeometry._(
      width: width,
      height: height,
      frameRect: frameRect,
      rodInnerLeft: rodInnerLeft,
      rodInnerRight: rodInnerRight,
      innerTop: innerTop,
      rowSpacing: rowSpacing,
      beadRadius: beadRadius,
      usableLength: usableLength,
      minSeparationFraction: minSeparationFraction,
    );
  }

  double rowCenterY(int row) => innerTop + rowSpacing * (row + 0.5);

  double beadCenterX(double fraction) => rodInnerLeft + fraction * usableLength;

  Offset beadCenter(int row, double fraction) =>
      Offset(beadCenterX(fraction), rowCenterY(row));

  /// Converts an absolute local X pixel coordinate into a rod-local
  /// fraction, clamped to `[0, 1]`.
  double fractionForLocalX(double localX) {
    final fraction = (localX - rodInnerLeft) / usableLength;
    if (fraction.isNaN) return 0.0;
    return fraction.clamp(0.0, 1.0);
  }

  /// Nearest bead to [local] within the padded touch radius, resolving
  /// overlapping touch areas to whichever bead center is closest. Returns
  /// `(row, col)` or `null` if nothing is within range.
  (int, int)? hitTestBead(Offset local, List<List<double>> fractions) {
    final touchRadius = beadRadius * touchRadiusMultiplier;
    final touchRadiusSq = touchRadius * touchRadius;
    double bestDistanceSq = double.infinity;
    (int, int)? best;

    for (var row = 0; row < rowCount; row++) {
      final y = rowCenterY(row);
      final dy = local.dy - y;
      if (dy.abs() > touchRadius) continue;
      for (var col = 0; col < beadsPerRow; col++) {
        final x = beadCenterX(fractions[row][col]);
        final dx = local.dx - x;
        final distanceSq = dx * dx + dy * dy;
        if (distanceSq <= touchRadiusSq && distanceSq < bestDistanceSq) {
          bestDistanceSq = distanceSq;
          best = (row, col);
        }
      }
    }
    return best;
  }
}
