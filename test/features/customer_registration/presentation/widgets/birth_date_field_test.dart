import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/customer_registration/presentation/widgets/birth_date_field.dart';
import 'package:abakus_one_v2/shared/widgets/calendar/signature_calendar.dart';

/// CR.1.1 — the "Doğum Tarihi" picker: reuses [SignatureCalendar]
/// unmodified, wrapped in a year-jump step (a plain prev/next-month
/// calendar alone would need hundreds of taps to reach an old birth
/// year).
void main() {
  Future<DateTime?> pumpAndOpen(
    WidgetTester tester, {
    DateTime? value,
    String? errorText,
  }) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirthDateField(
            value: value,
            errorText: errorText,
            onChanged: (date) => picked = date,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('completeProfileBirthDateField')));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('shows a placeholder when nothing has been picked yet',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirthDateField(value: null, onChanged: (_) {}),
        ),
      ),
    );

    expect(find.text('Seç'), findsOneWidget);
  });

  testWidgets(
      'the selected value remains clearly visible on the field before submission',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirthDateField(
            value: DateTime(1990, 8, 20),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('completeProfileBirthDateDisplay')),
        findsOneWidget);
    expect(find.text('20.08.1990'), findsOneWidget);
  });

  testWidgets('shows the given errorText when present', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirthDateField(
            value: null,
            errorText: 'Doğum tarihi gerekli.',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Doğum tarihi gerekli.'), findsOneWidget);
  });

  testWidgets(
      'tapping the field opens a year grid, then picking a year and a day reports the chosen date and closes the sheet',
      (tester) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirthDateField(
            value: null,
            onChanged: (date) => picked = date,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('completeProfileBirthDateField')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('birthDateYearGrid')), findsOneWidget);

    await tester.tap(find.byKey(const Key('birthDateYearOption_2020')));
    await tester.pumpAndSettle();

    expect(find.byType(SignatureCalendar), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(SignatureCalendar),
        matching: find.text('15'),
      ),
    );
    await tester.pumpAndSettle();

    expect(picked, DateTime(2020, 1, 15));
    // The sheet closed — the year grid is no longer in the tree.
    expect(find.byKey(const Key('birthDateYearGrid')), findsNothing);
  });

  testWidgets('the back arrow returns from the calendar step to the year grid',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirthDateField(value: null, onChanged: (_) {}),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('completeProfileBirthDateField')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('birthDateYearOption_2020')));
    await tester.pumpAndSettle();
    expect(find.byType(SignatureCalendar), findsOneWidget);

    await tester.tap(find.byKey(const Key('birthDateYearBackButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('birthDateYearGrid')), findsOneWidget);
    expect(find.byType(SignatureCalendar), findsNothing);
  });

  testWidgets('a past year is bounded to exactly Jan 1 – Dec 31 of that year',
      (tester) async {
    await pumpAndOpen(tester);
    await tester.tap(find.byKey(const Key('birthDateYearOption_2020')));
    await tester.pumpAndSettle();

    final calendar = tester.widget<SignatureCalendar>(
      find.byType(SignatureCalendar),
    );
    expect(calendar.firstSelectableDate, DateTime(2020, 1, 1));
    expect(calendar.lastSelectableDate, DateTime(2020, 12, 31));
  });

  testWidgets(
      'the current year is bounded at today — a future date can never be selectable',
      (tester) async {
    await pumpAndOpen(tester);
    final currentYear = DateTime.now().year;
    await tester.tap(find.byKey(Key('birthDateYearOption_$currentYear')));
    await tester.pumpAndSettle();

    final calendar = tester.widget<SignatureCalendar>(
      find.byType(SignatureCalendar),
    );
    final today = DateTime.now();
    expect(
      calendar.lastSelectableDate,
      DateTime(today.year, today.month, today.day),
    );
  });
}
