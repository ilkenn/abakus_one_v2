import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';
import 'package:abakus_one_v2/features/smart_import/presentation/screens/import_jobs_screen.dart';
import 'package:abakus_one_v2/features/smart_import/presentation/screens/import_review_screen.dart';

const _managerSession = ActorSession(
  actorId: 'manager-1',
  roles: {StaffRole.manager},
  activeRole: StaffRole.manager,
  branchAccess: {'branch-1'},
);

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        actorSessionProvider.overrideWith((ref) => _managerSession),
      ],
      child: const MaterialApp(
        home: ImportJobsScreen(
          organizationId: 'org-1',
          restaurantId: 'restaurant-1',
          branchId: 'branch-1',
          performedByStaffId: 'manager-1',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an empty state when there are no import jobs',
      (tester) async {
    await _pumpScreen(tester);

    expect(find.text('Henüz bir içe aktarma işi yok.'), findsOneWidget);
  });

  testWidgets(
      'creating a CSV import job parses it and lists it, then opens the '
      'review screen', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'category,name,price\nBowl,Tavuklu Bowl,150',
    );
    await tester.tap(find.text('Oluştur ve Ayrıştır'));
    await tester.pumpAndSettle();

    expect(find.text('CSV'), findsOneWidget);

    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();

    expect(find.byType(ImportReviewScreen), findsOneWidget);
    expect(find.text('Tavuklu Bowl'), findsOneWidget);
  });
}
