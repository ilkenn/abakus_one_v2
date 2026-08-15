import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/shared/widgets/hero/hero_abacus.dart';
import 'package:abakus_one_v2/shared/widgets/hero/hero_abacus_controller.dart';
import 'package:abakus_one_v2/shared/widgets/hero/hero_abacus_geometry.dart';
import 'package:abakus_one_v2/shared/widgets/hero/hero_abacus_painter.dart';

const double _testWidth = 320.0;

void main() {
  group('HeroAbacus', () {
    testWidgets('renders a single CustomPaint driven by HeroAbacusPainter', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: HeroAbacus(width: _testWidth)),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is HeroAbacusPainter,
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'a raw pointer drag moves the targeted bead 1:1 while the pointer is down',
      (tester) async {
        final controller = HeroAbacusController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: HeroAbacus(width: _testWidth, controller: controller),
              ),
            ),
          ),
        );
        await tester.pump();

        final topLeft = tester.getTopLeft(find.byType(HeroAbacus));
        final geometry = HeroAbacusGeometry.forWidth(_testWidth);
        final startFraction = controller.positions[0][0];
        final beadScreenCenter =
            topLeft + geometry.beadCenter(0, startFraction);

        final gesture = await tester.startGesture(beadScreenCenter);
        const dragDx = 24.0;
        await gesture.moveBy(const Offset(dragDx, 0));
        await tester.pump();

        final expectedFraction = geometry.fractionForLocalX(
          geometry.beadCenter(0, startFraction).dx + dragDx,
        );
        // No pumpAndSettle, no waiting -- proves the position is applied
        // immediately, with no tween/interpolation behind the finger.
        expect(controller.positions[0][0], closeTo(expectedFraction, 1e-6));

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets(
      'the teaser is temporarily disabled -- onIntroAnimationComplete never fires',
      (tester) async {
        var completed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: HeroAbacus(
                  width: _testWidth,
                  onIntroAnimationComplete: () => completed = true,
                ),
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 3500));

        expect(completed, isFalse);
      },
    );

    testWidgets('survives a rapid sequence of start/move/up gestures', (
      tester,
    ) async {
      final controller = HeroAbacusController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HeroAbacus(width: _testWidth, controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      final topLeft = tester.getTopLeft(find.byType(HeroAbacus));
      final geometry = HeroAbacusGeometry.forWidth(_testWidth);

      for (var i = 0; i < 15; i++) {
        final row = i % HeroAbacusGeometry.rowCount;
        final col = (i * 2) % HeroAbacusGeometry.beadsPerRow;
        final start =
            topLeft + geometry.beadCenter(row, controller.positions[row][col]);
        final gesture = await tester.startGesture(start);
        await gesture.moveBy(Offset((i.isEven ? 1 : -1) * 15.0, 0));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 8));
      }

      await tester.pumpAndSettle();

      for (final row in controller.positions) {
        for (final v in row) {
          expect(v.isFinite, isTrue);
          expect(v, inInclusiveRange(0.0, 1.0));
        }
      }
    });
  });
}
