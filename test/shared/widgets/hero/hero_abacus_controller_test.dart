import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/shared/widgets/hero/hero_abacus_controller.dart';
import 'package:abakus_one_v2/shared/widgets/hero/hero_abacus_geometry.dart';

HeroAbacusController _makeController() {
  final controller = HeroAbacusController();
  controller.updateGeometry(HeroAbacusGeometry.forWidth(320));
  return controller;
}

void main() {
  final geometry = HeroAbacusGeometry.forWidth(320);

  group('HeroAbacusController — geometry/state', () {
    test('initializes exactly 6 rows of 6 beads', () {
      final controller = _makeController();
      expect(controller.positions.length, 6);
      for (final row in controller.positions) {
        expect(row.length, 6);
      }
      expect(controller.velocities.length, 6);
      for (final row in controller.velocities) {
        expect(row.length, 6);
        expect(row.every((v) => v == 0.0), isTrue);
      }
    });
  });

  group('HeroAbacusController — direct drag manipulation', () {
    test('a dragged bead never leaves its rod\'s [0,1] bounds', () {
      // The rightmost bead has nothing blocking it on the right, and the
      // leftmost bead has nothing blocking it on the left -- these are
      // the only two combinations that can reach the literal 0.0/1.0 edge
      // (any other bead is blocked by its own neighbors first, which is
      // exactly what "beads may never pass through each other" requires).
      final controller = _makeController();
      controller.beginDrag(0, 5, Duration.zero);
      controller.updateDrag(
        geometry.rodInnerRight + 100000,
        const Duration(milliseconds: 16),
      );
      expect(controller.positions[0][5], 1.0);

      final controller2 = _makeController();
      controller2.beginDrag(0, 0, Duration.zero);
      controller2.updateDrag(
        geometry.rodInnerLeft - 100000,
        const Duration(milliseconds: 16),
      );
      expect(controller2.positions[0][0], 0.0);
    });

    test(
      'a dragged bead blocked by neighbors stops at the furthest '
      'physically reachable point, not the raw pointer target',
      () {
        final controller = _makeController();
        controller.beginDrag(0, 0, Duration.zero);
        controller.updateDrag(
          geometry.rodInnerRight + 100000,
          const Duration(milliseconds: 16),
        );
        final minSep = geometry.minSeparationFraction;
        expect(controller.positions[0][0], closeTo(1.0 - 5 * minSep, 1e-9));
      },
    );

    test('a dragged bead cannot pass a neighboring bead', () {
      final controller = _makeController();
      final neighborBefore = controller.positions[0][1];

      controller.beginDrag(0, 0, Duration.zero);
      controller.updateDrag(
        geometry.rodInnerRight + 5000,
        const Duration(milliseconds: 16),
      );

      expect(controller.positions[0][0], lessThan(controller.positions[0][1]));
      expect(controller.positions[0][1], greaterThan(neighborBefore));
      expect(
        controller.positions[0][1] - controller.positions[0][0],
        closeTo(geometry.minSeparationFraction, 1e-9),
      );
    });

    test('beads never overlap past the minimum separation', () {
      final controller = _makeController();
      // Drag every bead on a row toward the same spot from both directions.
      controller.beginDrag(2, 0, Duration.zero);
      controller.updateDrag(
        geometry.rodInnerLeft + geometry.usableLength * 0.9,
        const Duration(milliseconds: 16),
      );
      controller.endDrag();
      controller.beginDrag(2, 5, Duration.zero);
      controller.updateDrag(
        geometry.rodInnerLeft + geometry.usableLength * 0.1,
        const Duration(milliseconds: 16),
      );

      final pos = controller.positions[2];
      for (var i = 1; i < pos.length; i++) {
        expect(
          pos[i] - pos[i - 1],
          greaterThanOrEqualTo(geometry.minSeparationFraction - 1e-9),
        );
      }
    });
  });

  group('HeroAbacusController — release inertia / friction', () {
    test('a released bead decays to rest within a bounded number of steps', () {
      final controller = _makeController();
      controller.beginDrag(1, 0, Duration.zero);
      var t = Duration.zero;
      var x = geometry.rodInnerLeft + geometry.usableLength * 0.05;
      controller.updateDrag(x, t);
      for (var i = 0; i < 5; i++) {
        t += const Duration(milliseconds: 8);
        x += geometry.usableLength * 0.04;
        controller.updateDrag(x, t);
      }
      controller.endDrag();

      expect(controller.velocities[1][0].abs(), greaterThan(0));

      var settledAtStep = -1;
      for (var i = 0; i < 300; i++) {
        controller.step(1 / 60);
        if (controller.isSettled) {
          settledAtStep = i;
          break;
        }
      }

      expect(settledAtStep, greaterThanOrEqualTo(0));
      expect(settledAtStep, lessThan(300));
    });

    test('repeated stepping converges to a settled state and stays there', () {
      final controller = _makeController();
      controller.debugSetState(0, 0, velocity: 3.0);

      for (var i = 0; i < 300; i++) {
        controller.step(1 / 60);
      }
      expect(controller.isSettled, isTrue);

      // Stays settled -- doesn't spontaneously re-trigger motion.
      for (var i = 0; i < 30; i++) {
        controller.step(1 / 60);
      }
      expect(controller.isSettled, isTrue);
    });
  });

  group('HeroAbacusController — collisions', () {
    test(
      'a fast push through a packed row propagates and loses energy '
      '(never explodes)',
      () {
        final controller = _makeController();
        final minSep = geometry.minSeparationFraction;
        for (var col = 0; col < 6; col++) {
          controller.debugSetState(
            3,
            col,
            position: 0.2 + col * minSep,
            velocity: 0.0,
          );
        }
        controller.debugSetState(3, 0, velocity: 4.0);

        final peak = List<double>.filled(6, 0.0);
        for (var i = 0; i < 90; i++) {
          controller.step(1 / 60);
          for (var col = 0; col < 6; col++) {
            final v = controller.velocities[3][col].abs();
            if (v > peak[col]) peak[col] = v;
          }
        }

        expect(peak[5], greaterThan(0),
            reason: 'the push should reach the far bead');
        expect(peak[5], lessThan(peak[0]));
        for (final v in peak) {
          expect(
            v,
            lessThanOrEqualTo(
                HeroAbacusController.maxVelocityFractionPerSecond),
          );
        }

        // Never overlaps at any point either.
        final pos = controller.positions[3];
        for (var i = 1; i < pos.length; i++) {
          expect(pos[i] - pos[i - 1], greaterThanOrEqualTo(minSep - 1e-6));
        }
      },
    );

    test('a low-velocity edge approach stops hard, with no rebound', () {
      final controller = _makeController();
      controller.debugSetState(
        4,
        5,
        position: 0.999,
        velocity: HeroAbacusController.highVelocityThreshold * 0.3,
      );
      controller.step(1 / 60);
      expect(controller.positions[4][5], 1.0);
      expect(controller.velocities[4][5], 0.0);
    });

    test('a high-velocity edge impact produces a small bounded rebound', () {
      final controller = _makeController();
      controller.debugSetState(
        4,
        5,
        position: 0.999,
        velocity: HeroAbacusController.highVelocityThreshold * 3,
      );
      controller.step(1 / 60);
      expect(controller.positions[4][5], 1.0);
      // Rebounds back (negative, toward the rod's interior) -- and stays
      // well below the impact speed itself (soft, not rubber).
      expect(controller.velocities[4][5], lessThan(0));
      expect(
        controller.velocities[4][5].abs(),
        lessThan(HeroAbacusController.highVelocityThreshold * 3),
      );
    });
  });

  group('HeroAbacusController — robustness', () {
    test('never reaches a NaN or Infinity state under randomized stress', () {
      final controller = _makeController();
      final random = math.Random(42);
      for (var trial = 0; trial < 50; trial++) {
        final row = random.nextInt(6);
        final col = random.nextInt(6);
        controller.debugSetState(
          row,
          col,
          position: random.nextDouble() * 3 - 1, // deliberately out of range
          velocity: (random.nextDouble() * 2 - 1) * 1e6, // deliberately huge
        );
        controller.step(1 / 60);
      }

      for (final row in controller.positions) {
        for (final v in row) {
          expect(v.isFinite, isTrue);
        }
      }
      for (final row in controller.velocities) {
        for (final v in row) {
          expect(v.isFinite, isTrue);
        }
      }
    });

    test('survives hundreds of rapid begin/update/end drag cycles', () {
      final controller = _makeController();
      final random = math.Random(7);

      expect(() {
        for (var i = 0; i < 400; i++) {
          final row = random.nextInt(6);
          final col = random.nextInt(6);
          controller.beginDrag(row, col, Duration(milliseconds: i * 4));
          controller.updateDrag(
            geometry.rodInnerLeft + random.nextDouble() * geometry.usableLength,
            Duration(milliseconds: i * 4 + 2),
          );
          controller.endDrag();
          controller.step(1 / 60);
        }
      }, returnsNormally);

      for (final row in controller.positions) {
        for (final v in row) {
          expect(v.isFinite, isTrue);
          expect(v, inInclusiveRange(0.0, 1.0));
        }
      }
    });
  });
}
