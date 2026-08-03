import '../domain/expiry_record.dart';

abstract interface class ExpiryRecordRepository {
  Future<void> append(ExpiryRecord record);
  Future<List<ExpiryRecord>> findByLocationId(String locationId);
}

class InMemoryExpiryRecordRepository implements ExpiryRecordRepository {
  final List<ExpiryRecord> _records = [];

  @override
  Future<void> append(ExpiryRecord record) async {
    _records.add(record);
  }

  @override
  Future<List<ExpiryRecord>> findByLocationId(String locationId) async {
    return List.unmodifiable(
      _records.where((r) => r.locationId == locationId),
    );
  }
}
