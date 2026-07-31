import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/crm/presentation/screens/customer_visit_passport_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

void main() {
  testWidgets('shows a zeroed passport for a customer with no visits yet',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 1, 1))),
        ],
        child: const MaterialApp(
          home: CustomerVisitPassportScreen(
            customerId: 'customer-1',
            branchId: 'branch-1',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Ziyaret Pasosu'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Henüz tamamlanan ödül yok.'), findsOneWidget);
    expect(find.text('Henüz kazanılan ödül yok.'), findsOneWidget);
  });
}
