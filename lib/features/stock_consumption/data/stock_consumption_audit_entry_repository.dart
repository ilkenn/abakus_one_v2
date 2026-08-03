import '../domain/stock_consumption_audit_entry.dart';

abstract interface class StockConsumptionAuditEntryRepository {
  Future<void> appendEvent(StockConsumptionAuditEntry entry);
  Future<List<StockConsumptionAuditEntry>> findByTargetEntityId(
      String targetEntityId);
  Future<List<StockConsumptionAuditEntry>> findByBranchId(String branchId);
}

class InMemoryStockConsumptionAuditEntryRepository
    implements StockConsumptionAuditEntryRepository {
  final List<StockConsumptionAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(StockConsumptionAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<StockConsumptionAuditEntry>> findByTargetEntityId(
      String targetEntityId) async {
    return List.unmodifiable(
      _entries.where((e) => e.targetEntityId == targetEntityId),
    );
  }

  @override
  Future<List<StockConsumptionAuditEntry>> findByBranchId(
      String branchId) async {
    return List.unmodifiable(
      _entries.where((e) => e.branchId == branchId),
    );
  }
}
