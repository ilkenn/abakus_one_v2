import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/shared/widgets/hero/hero_abacus_geometry.dart';

List<List<double>> _restingFractions() => List.generate(
      HeroAbacusGeometry.rowCount,
      (_) => List.generate(
        HeroAbacusGeometry.beadsPerRow,
        (col) => (col + 0.5) / HeroAbacusGeometry.beadsPerRow,
      ),
    );

void main() {
  final geometry = HeroAbacusGeometry.forWidth(320);

  group('HeroAbacusGeometry — hit testing', () {
    test('returns null far away from every bead', () {
      final fractions = _restingFractions();
      final result =
          geometry.hitTestBead(const Offset(-1000, -1000), fractions);
      expect(result, isNull);
    });

    test('returns the bead directly under the touch point', () {
      final fractions = _restingFractions();
      final target = geometry.beadCenter(2, fractions[2][3]);

      final result = geometry.hitTestBead(target, fractions);
      expect(result, (2, 3));
    });

    test('touch target is padded beyond the visual bead radius', () {
      final fractions = _restingFractions();
      final center = geometry.beadCenter(1, fractions[1][2]);
      // Between the visual radius and the padded touch radius.
      final justOutsideVisual = center.translate(geometry.beadRadius * 1.3, 0);

      final result = geometry.hitTestBead(justOutsideVisual, fractions);
      expect(result, (1, 2));
    });

    test('resolves overlapping touch areas to the nearer bead', () {
      final fractions = _restingFractions();
      // Force two beads on the same row unusually close together.
      fractions[0][0] = 0.50;
      fractions[0][1] = 0.502;

      final pointCloserToFirst = geometry.beadCenter(0, 0.5005);
      final result = geometry.hitTestBead(pointCloserToFirst, fractions);

      expect(result, isNotNull);
      final distanceToFirst =
          (geometry.beadCenter(0, fractions[0][0]) - pointCloserToFirst)
              .distance;
      final distanceToSecond =
          (geometry.beadCenter(0, fractions[0][1]) - pointCloserToFirst)
              .distance;
      expect(distanceToFirst, lessThan(distanceToSecond));
      expect(result, (0, 0));
    });
  });

  group('HeroAbacusGeometry — fraction conversion', () {
    test('fractionForLocalX clamps to [0, 1]', () {
      expect(geometry.fractionForLocalX(geometry.rodInnerLeft - 9999), 0.0);
      expect(geometry.fractionForLocalX(geometry.rodInnerRight + 9999), 1.0);
    });

    test('fractionForLocalX is 0.5 at the rod midpoint', () {
      final midX = geometry.rodInnerLeft + geometry.usableLength / 2;
      expect(geometry.fractionForLocalX(midX), closeTo(0.5, 1e-9));
    });
  });
}
