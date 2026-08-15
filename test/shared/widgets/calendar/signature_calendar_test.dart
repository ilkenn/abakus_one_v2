import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/shared/widgets/calendar/signature_calendar.dart';

void main() {
  Future<void> pumpCalendar(
    WidgetTester tester, {
    DateTime? selectedDate,
    required DateTime firstSelectableDate,
    required DateTime lastSelectableDate,
    ValueChanged<DateTime>? onDateSelected,
  }) async {
    // Matches real usage: `DateStep` is always embedded inside
    // `ReservationStepScaffold`'s own `SingleChildScrollView` body, never
    // placed directly in a height-bounded `Scaffold.body` — mirroring that
    // here avoids an artificial overflow this harness would otherwise
    // introduce that never occurs in the real app.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SignatureCalendar(
              selectedDate: selectedDate,
              firstSelectableDate: firstSelectableDate,
              lastSelectableDate: lastSelectableDate,
              onDateSelected: onDateSelected ?? (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Faz R.2 §3 — renders as a real widget tree, never the stock Material DatePicker',
      (tester) async {
    await pumpCalendar(
      tester,
      firstSelectableDate: DateTime(2026, 8, 1),
      lastSelectableDate: DateTime(2026, 10, 1),
    );

    expect(find.byType(SignatureCalendar), findsOneWidget);
    expect(find.byType(CalendarDatePicker), findsNothing);
    expect(find.byType(DatePickerDialog), findsNothing);
  });

  testWidgets('renders the current month name and every day 1..N',
      (tester) async {
    await pumpCalendar(
      tester,
      firstSelectableDate: DateTime(2026, 8, 1),
      lastSelectableDate: DateTime(2026, 10, 1),
    );

    expect(find.textContaining('2026'), findsWidgets);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
  });

  testWidgets(
      'a date before firstSelectableDate is disabled — tapping it does not select',
      (tester) async {
    DateTime? selected;
    // firstSelectableDate is the 15th — the 1st-14th of the same month
    // must render but not be selectable.
    await pumpCalendar(
      tester,
      firstSelectableDate: DateTime(2026, 8, 15),
      lastSelectableDate: DateTime(2026, 10, 1),
      onDateSelected: (d) => selected = d,
    );

    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    expect(selected, isNull);
  });

  testWidgets(
      'a date within the selectable range can be tapped and reports the correct date',
      (tester) async {
    DateTime? selected;
    await pumpCalendar(
      tester,
      firstSelectableDate: DateTime(2026, 8, 1),
      lastSelectableDate: DateTime(2026, 10, 1),
      onDateSelected: (d) => selected = d,
    );

    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();

    expect(selected, DateTime(2026, 8, 20));
  });

  testWidgets(
      'a date beyond lastSelectableDate\'s month is unreachable — next-month nav disabled at the boundary',
      (tester) async {
    await pumpCalendar(
      tester,
      firstSelectableDate: DateTime(2026, 8, 1),
      lastSelectableDate: DateTime(2026, 8, 20),
    );

    final nextButton = find.bySemanticsLabel('Sonraki ay');
    expect(nextButton, findsOneWidget);
    // Tapping it must not throw and must not change the displayed month
    // (still August) since the horizon is entirely within August.
    await tester.tap(nextButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('Ağustos'), findsWidgets);
    expect(find.textContaining('Eylül'), findsNothing);
  });

  testWidgets('selected date renders with a distinct selected semantic state',
      (tester) async {
    await pumpCalendar(
      tester,
      selectedDate: DateTime(2026, 8, 20),
      firstSelectableDate: DateTime(2026, 8, 1),
      lastSelectableDate: DateTime(2026, 10, 1),
    );

    final semantics = tester.getSemantics(find.text('20'));
    expect(semantics.label, contains('seçili'));
  });

  testWidgets('month navigation (next/previous) updates the visible month',
      (tester) async {
    await pumpCalendar(
      tester,
      firstSelectableDate: DateTime(2026, 8, 1),
      lastSelectableDate: DateTime(2026, 12, 1),
    );

    expect(find.textContaining('Ağustos 2026'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Sonraki ay'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Eylül 2026'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Önceki ay'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ağustos 2026'), findsOneWidget);
  });
}
