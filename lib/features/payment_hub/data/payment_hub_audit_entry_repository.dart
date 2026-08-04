import '../domain/audit/payment_hub_audit_entry.dart';

abstract interface class PaymentHubAuditEntryRepository {
  Future<void> appendEvent(PaymentHubAuditEntry entry);
  Future<List<PaymentHubAuditEntry>> findByTargetEntityId(
      String targetEntityId);
}

class InMemoryPaymentHubAuditEntryRepository
    implements PaymentHubAuditEntryRepository {
  final List<PaymentHubAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(PaymentHubAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<PaymentHubAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }
}
