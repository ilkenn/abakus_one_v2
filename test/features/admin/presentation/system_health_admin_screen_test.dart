import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/presentation/screens/system_health_admin_screen.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  testWidgets(
      'shows environment info, feature flags, and maintenance mode '
      'off by default', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SystemHealthAdminScreen(
            authorizationPolicy: AllowAllAdminPolicy(),
            performedByStaffId: 'admin-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Ortam:'), findsOneWidget);
    expect(find.text('OTP ile Giriş'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('Bakım Modu'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    expect(find.text('Bakım modu KAPALI'), findsOneWidget);
    expect(find.text('Bakım Modunu Aç'), findsOneWidget);
  });

  testWidgets('activating maintenance mode with a reason updates the state',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SystemHealthAdminScreen(
            authorizationPolicy: AllowAllAdminPolicy(),
            performedByStaffId: 'admin-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Bakım Modunu Aç'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.tap(find.text('Bakım Modunu Aç'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Planned upgrade');
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();

    expect(find.text('Bakım modu AÇIK'), findsOneWidget);
    expect(find.text('Neden: Planned upgrade'), findsOneWidget);
  });
}
