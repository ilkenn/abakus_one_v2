import '../domain/waste_record.dart';

abstract interface class WasteRecordRepository {
  Future<void> append(WasteRecord record);
  Future<List<WasteRecord>> findByBranchId(String branchId);
}

class InMemoryWasteRecordRepository implements WasteRecordRepository {
  final List<WasteRecord> _records = [];

  @override
  Future<void> append(WasteRecord record) async {
    _records.add(record);
  }

  @override
  Future<List<WasteRecord>> findByBranchId(String branchId) async {
    return List.unmodifiable(_records.where((r) => r.branchId == branchId));
  }
}
