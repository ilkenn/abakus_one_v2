import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/core/theme/app_colors.dart';
import 'package:abakus_one_v2/features/pos/presentation/widgets/pos_table_top_view.dart';

/// 2026-11-11 — POS bird's-eye Masalar card (product owner's rules).
void main() {
  group('PosTableTone.resolve', () {
    test('no live order is green "Boş", even with an active session', () {
      for (final status in ['available', 'occupied']) {
        final tone =
            PosTableTone.resolve(status: status, activePortionCount: 0);
        expect(tone, PosTableTone.free, reason: status);
        expect(tone.color, AppColors.success);
        expect(tone.label, 'Boş');
      }
    });

    test('a live order is red "Dolu"', () {
      final tone =
          PosTableTone.resolve(status: 'occupied', activePortionCount: 1);
      expect(tone, PosTableTone.occupied);
      expect(tone.color, AppColors.error);
      expect(tone.label, 'Dolu');
    });

    test('bill requested is orange, with or without portions', () {
      for (final portions in [0, 3]) {
        final tone = PosTableTone.resolve(
          status: 'billRequested',
          activePortionCount: portions,
        );
        expect(tone, PosTableTone.billRequested);
        expect(tone.color, AppColors.accent);
      }
    });

    test(
        'cleaning / reserved / disabled are grey — disabled is never the '
        '"has an order" red', () {
      expect(
        PosTableTone.resolve(status: 'cleaning', activePortionCount: 0).color,
        AppColors.textSecondary,
      );
      expect(
        PosTableTone.resolve(status: 'reserved', activePortionCount: 0).label,
        'Rezerve',
      );
      final disabled =
          PosTableTone.resolve(status: 'disabled', activePortionCount: 2);
      expect(disabled.color, AppColors.textSecondary);
      expect(disabled.color, isNot(AppColors.error));
      expect(disabled.label, 'Kapalı');
    });
  });

  group('posTableSeating', () {
    test('one seated chair per portion, never more than 4', () {
      for (final (portions, seated) in [(0, 0), (1, 1), (2, 2), (3, 3)]) {
        expect(
          posTableSeating(capacity: 4, activePortionCount: portions).seated,
          seated,
        );
      }
      expect(posTableSeating(capacity: 4, activePortionCount: 9).seated, 4);
    });

    test('chairs = capacity (max 4); 4 when unset or invalid', () {
      expect(posTableSeating(capacity: null, activePortionCount: 0).chairs, 4);
      expect(posTableSeating(capacity: 0, activePortionCount: 0).chairs, 4);
      expect(posTableSeating(capacity: 6, activePortionCount: 0).chairs, 4);
      final twoSeater = posTableSeating(capacity: 2, activePortionCount: 3);
      expect(twoSeater.chairs, 2);
      expect(twoSeater.seated, 2);
    });
  });

  group('PosTableTopView', () {
    Future<void> pump(WidgetTester tester, {required int seated}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.square(
              dimension: 200,
              child: PosTableTopView(
                tableName: 'Salon 1',
                tone: PosTableTone.occupied,
                chairs: 4,
                seated: seated,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('draws four chairs around the named table top', (tester) async {
      await pump(tester, seated: 0);

      expect(find.text('Salon 1'), findsOneWidget);
      for (final side in PosChairSide.values) {
        expect(find.byKey(ValueKey('chair-${side.name}')), findsOneWidget);
      }
      expect(find.byIcon(Icons.person), findsNothing);
    });

    testWidgets('two portions = two person figures, two empty chairs',
        (tester) async {
      await pump(tester, seated: 2);

      expect(find.byIcon(Icons.person), findsNWidgets(2));
      // Fill order: top, bottom, then left, right.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('chair-top')),
          matching: find.byIcon(Icons.person),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('chair-left')),
          matching: find.byIcon(Icons.person),
        ),
        findsNothing,
      );
    });

    testWidgets('a full table shows four person figures', (tester) async {
      await pump(tester, seated: 4);
      expect(find.byIcon(Icons.person), findsNWidgets(4));
    });
  });
}
