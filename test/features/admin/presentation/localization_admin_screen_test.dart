import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/presentation/screens/localization_admin_screen.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  testWidgets(
      'shows the master language always enabled and disabled to '
      'toggle', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LocalizationAdminScreen(
            branchId: 'branch-1',
            authorizationPolicy: AllowAllAdminPolicy(),
            performedByStaffId: 'admin-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Türkçe'), findsOneWidget);
    expect(find.textContaining('ana dil'), findsOneWidget);

    final trCheckbox = tester.widget<CheckboxListTile>(
      find.byWidgetPredicate((w) =>
          w is CheckboxListTile &&
          w.title is Text &&
          (w.title as Text).data!.contains('Türkçe')),
    );
    expect(trCheckbox.onChanged, isNull);
  });

  testWidgets('enabling English shows it as checked', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LocalizationAdminScreen(
            branchId: 'branch-1',
            authorizationPolicy: AllowAllAdminPolicy(),
            performedByStaffId: 'admin-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final englishTile = find.byWidgetPredicate((w) =>
        w is CheckboxListTile &&
        w.title is Text &&
        (w.title as Text).data!.contains('English'));
    await tester.tap(englishTile);
    await tester.pumpAndSettle();

    final updated = tester.widget<CheckboxListTile>(englishTile);
    expect(updated.value, isTrue);
  });
}
