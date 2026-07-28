import 'package:abakus_one_v2/features/pos/data/cash_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_audit_entry.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_audit_event_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appendEvent then findByDrawerId/findBySessionId return the event',
      () async {
    final repository = InMemoryCashAuditEntryRepository();
    await repository.appendEvent(CashAuditEntry(
      id: 'e1',
      drawerId: 'drawer-1',
      sessionId: 'session-1',
      type: CashAuditEventType.drawerOpened,
      description: 'opened',
      actorStaffId: 'staff-1',
      timestamp: DateTime(2026, 7, 29),
    ));

    expect((await repository.findByDrawerId('drawer-1')).single.id, 'e1');
    expect((await repository.findBySessionId('session-1')).single.id, 'e1');
    expect(await repository.findByDrawerId('drawer-2'), isEmpty);
  });
}
