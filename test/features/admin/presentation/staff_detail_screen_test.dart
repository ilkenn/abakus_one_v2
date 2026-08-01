import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/staff_detail_screen.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required StaffMemberRepository repository,
    required String staffMemberId,
    required String performedByStaffId,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffMemberRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: StaffDetailScreen(
            staffMemberId: staffMemberId,
            authorizationPolicy: const AllowAllAdminPolicy(),
            performedByStaffId: performedByStaffId,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the member and lets a manager grant a role',
      (tester) async {
    final repository = InMemoryStaffMemberRepository();
    await repository.save(buildTestStaffMember(id: 'target-1'));

    await pumpScreen(
      tester,
      repository: repository,
      staffMemberId: 'target-1',
      performedByStaffId: 'admin-1',
    );

    expect(find.text('Test Personel'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'staff'));
    await tester.pumpAndSettle();

    final updated = await repository.findById('target-1');
    expect(updated!.roles, contains(StaffRole.staff));
  });

  testWidgets(
      'viewing your own account hides role toggles (self-promotion guard)',
      (tester) async {
    final repository = InMemoryStaffMemberRepository();
    await repository
        .save(buildTestStaffMember(id: 'admin-1', roles: {StaffRole.admin}));

    await pumpScreen(
      tester,
      repository: repository,
      staffMemberId: 'admin-1',
      performedByStaffId: 'admin-1',
    );

    expect(find.byType(FilterChip), findsNothing);
    expect(find.textContaining('self-promotion'), findsOneWidget);
  });
}
