import '../../data/cash_drawer_repository.dart';
import '../../domain/cash/cash_drawer.dart';
import '../identity/cash_drawer_id_generator.dart';

/// Registers a new [CashDrawer] at a branch — a branch may have multiple
/// drawers (`docs/business_rules.md` BR-CASH-001).
class CreateCashDrawer {
  const CreateCashDrawer({
    required CashDrawerIdGenerator idGenerator,
    required CashDrawerRepository repository,
  })  : _idGenerator = idGenerator,
        _repository = repository;

  final CashDrawerIdGenerator _idGenerator;
  final CashDrawerRepository _repository;

  Future<CashDrawer> call({
    required String branchId,
    required String name,
  }) async {
    final drawer = CashDrawer(
      id: _idGenerator.nextDrawerId(),
      branchId: branchId,
      name: name,
    );
    await _repository.save(drawer);
    return drawer;
  }
}
