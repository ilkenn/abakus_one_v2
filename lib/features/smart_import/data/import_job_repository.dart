import '../domain/import_job.dart';

abstract interface class ImportJobRepository {
  Future<void> save(ImportJob job);
  Future<ImportJob?> findById(String id);

  /// Branch-scoped — never an unscoped "all jobs" query, so branch data
  /// never leaks across branches.
  Future<List<ImportJob>> findByBranchId(String branchId);
}

class InMemoryImportJobRepository implements ImportJobRepository {
  final Map<String, ImportJob> _byId = {};

  @override
  Future<void> save(ImportJob job) async => _byId[job.id] = job;

  @override
  Future<ImportJob?> findById(String id) async => _byId[id];

  @override
  Future<List<ImportJob>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _byId.values.where((j) => j.branchId == branchId),
    );
  }
}
