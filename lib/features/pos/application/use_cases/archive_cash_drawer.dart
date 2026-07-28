import '../../../../core/errors/business_rule_violation.dart';
import '../../data/cash_drawer_repository.dart';
import '../../data/cash_session_repository.dart';
import '../../domain/cash/cash_drawer.dart';

/// Decommissions a [CashDrawer] (`isActive = false`) — distinct from
/// closing a session; a drawer is reused across many sessions over its
/// lifetime, archiving is a separate, rarer administrative action.
///
/// Throws [UnknownCashEntityViolation] if [drawerId] doesn't resolve, or
/// [CashSessionAlreadyActiveViolation] if the drawer currently has a
/// non-closed session — a drawer mid-session can never be archived out
/// from under a cashier.
class ArchiveCashDrawer {
  const ArchiveCashDrawer({
    required CashDrawerRepository drawerRepository,
    required CashSessionRepository sessionRepository,
  })  : _drawerRepository = drawerRepository,
        _sessionRepository = sessionRepository;

  final CashDrawerRepository _drawerRepository;
  final CashSessionRepository _sessionRepository;

  Future<CashDrawer> call(String drawerId) async {
    final drawer = await _drawerRepository.findById(drawerId);
    if (drawer == null) {
      throw UnknownCashEntityViolation(
        entityName: 'CashDrawer',
        id: drawerId,
      );
    }
    final activeSession =
        await _sessionRepository.findActiveByDrawerId(drawerId);
    if (activeSession != null) {
      throw CashSessionAlreadyActiveViolation(drawerId: drawerId);
    }

    final archived = drawer.copyWith(isActive: false);
    await _drawerRepository.save(archived);
    return archived;
  }
}
