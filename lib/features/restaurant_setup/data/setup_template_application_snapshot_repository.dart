import '../domain/setup_template_application_snapshot.dart';

/// Append-only — no update or delete method exists, matching every
/// other "frozen record" repository in this codebase.
abstract interface class SetupTemplateApplicationSnapshotRepository {
  Future<void> save(SetupTemplateApplicationSnapshot snapshot);
  Future<List<SetupTemplateApplicationSnapshot>> findByBranchId(
      String branchId);
}

class InMemorySetupTemplateApplicationSnapshotRepository
    implements SetupTemplateApplicationSnapshotRepository {
  final List<SetupTemplateApplicationSnapshot> _snapshots = [];

  @override
  Future<void> save(SetupTemplateApplicationSnapshot snapshot) async {
    _snapshots.add(snapshot);
  }

  @override
  Future<List<SetupTemplateApplicationSnapshot>> findByBranchId(
      String branchId) async {
    return List.unmodifiable(
      _snapshots.where((s) => s.branchId == branchId),
    );
  }
}
