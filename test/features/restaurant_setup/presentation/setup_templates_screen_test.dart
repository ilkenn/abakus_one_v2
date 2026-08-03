import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/restaurant_setup/presentation/screens/setup_templates_screen.dart';

import '../test_support/restaurant_setup_test_fixtures.dart';

void main() {
  testWidgets('lists the seeded public template and applies it',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SetupTemplatesScreen(
            organizationId: 'org-1',
            restaurantId: 'restaurant-1',
            branchId: 'branch-1',
            authorizationPolicy: AllowAllSetupPolicy(),
            performedByStaffId: 'manager-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bowl & Salata Başlangıç Şablonu'), findsOneWidget);

    await tester.tap(find.text('Bu Şablonu Uygula'));
    await tester.pumpAndSettle();

    expect(find.textContaining('önerileri kaydedildi'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Uygulanan Şablonlar'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    expect(find.text('Uygulanan Şablonlar'), findsOneWidget);
  });
}
