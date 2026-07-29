import 'package:abakus_one_v2/features/pos/data/courier_settlement_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_audit_entry.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_audit_event_type.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/courier_settlement_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/courier_settlement_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    List<CourierSettlementAuditEntry> seedEntries = const [],
  }) async {
    final repository = InMemoryCourierSettlementAuditEntryRepository();
    for (final entry in seedEntries) {
      await repository.appendEvent(entry);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          courierSettlementAuditEntryRepositoryProvider
              .overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: CourierSettlementHistoryScreen(courierId: 'courier-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty repository shows the empty-state view', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Henüz geçmiş kayıt yok'), findsOneWidget);
  });

  testWidgets('lists audit entries for the courier', (tester) async {
    await pumpScreen(tester, seedEntries: [
      CourierSettlementAuditEntry(
        id: 'entry-1',
        courierId: 'courier-1',
        settlementSessionId: 'csession-1',
        type: CourierSettlementAuditEventType.approvalGranted,
        description: 'Courier settlement approved',
        actorStaffId: 'manager-1',
        timestamp: DateTime(2026, 7, 30, 9),
      ),
    ]);

    expect(find.text('approvalGranted'), findsOneWidget);
    expect(find.text('Courier settlement approved'), findsOneWidget);
  });
}
