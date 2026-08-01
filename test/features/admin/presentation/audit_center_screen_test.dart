import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/audit/admin_audit_entry.dart';
import 'package:abakus_one_v2/features/admin/domain/audit/admin_audit_event_type.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/audit_center_screen.dart';

void main() {
  testWidgets('shows an empty state when there are no audit entries',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AuditCenterScreen(branchId: 'branch-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.text('Bu filtrelerle eşleşen denetim kaydı yok.'), findsOneWidget);
  });

  testWidgets('lists a seeded admin audit entry with its domain badge',
      (tester) async {
    final adminAuditRepository = InMemoryAdminAuditEntryRepository();
    await adminAuditRepository.appendEvent(AdminAuditEntry(
      id: 'admin-audit-1',
      branchId: 'branch-1',
      actorId: 'admin-1',
      type: AdminAuditEventType.staffRoleGranted,
      description: 'Rol atandı',
      targetEntityId: 'staff-2',
      timestamp: DateTime(2026, 1, 1),
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminAuditEntryRepositoryProvider
              .overrideWithValue(adminAuditRepository),
        ],
        child: const MaterialApp(
          home: AuditCenterScreen(branchId: 'branch-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rol atandı'), findsOneWidget);
    expect(find.text('Yönetici'), findsOneWidget);
  });
}
