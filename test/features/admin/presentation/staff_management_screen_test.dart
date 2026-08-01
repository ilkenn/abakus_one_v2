import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/presentation/screens/staff_detail_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/staff_management_screen.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: StaffManagementScreen(
            authorizationPolicy: AllowAllAdminPolicy(),
            performedByStaffId: 'admin-1',
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows an empty roster with no staff members yet',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Personel Yönetimi'), findsOneWidget);
  });

  testWidgets('registering a new staff member adds it to the list',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Yeni Personel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ayşe Yılmaz');
    await tester.tap(find.text('Oluştur'));
    await tester.pumpAndSettle();

    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.textContaining('Rol atanmadı'), findsOneWidget);
  });

  testWidgets('tapping a staff member opens StaffDetailScreen', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byTooltip('Yeni Personel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ayşe Yılmaz');
    await tester.tap(find.text('Oluştur'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ayşe Yılmaz'));
    await tester.pumpAndSettle();

    expect(find.byType(StaffDetailScreen), findsOneWidget);
  });
}
