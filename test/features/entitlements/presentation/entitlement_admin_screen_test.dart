import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/entitlements/presentation/screens/entitlement_admin_screen.dart';

import '../test_support/entitlement_test_fixtures.dart';

void main() {
  testWidgets('lists every module with the seeded active status',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: EntitlementAdminScreen(
            branchId: 'branch-1',
            authorizationPolicy: AllowAllEntitlementPolicy(),
            performedByStaffId: 'admin-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stok Yönetimi'), findsOneWidget);
    expect(find.text('active'), findsWidgets);
  });

  testWidgets('cancelling a module sets it to revoked', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: EntitlementAdminScreen(
            branchId: 'branch-1',
            authorizationPolicy: AllowAllEntitlementPolicy(),
            performedByStaffId: 'admin-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('İptal Et').first);
    await tester.pumpAndSettle();

    expect(find.text('revoked'), findsOneWidget);
  });
}
