import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/money.dart';
import '../../data/cash_audit_entry_repository.dart';
import '../../data/cash_drawer_repository.dart';
import '../../data/cash_movement_repository.dart';
import '../../data/cash_session_repository.dart';
import '../../domain/cash/cash_audit_entry.dart';
import '../../domain/cash/cash_audit_event_type.dart';
import '../../domain/cash/cash_movement.dart';
import '../../domain/cash/cash_movement_type.dart';
import '../../domain/cash/cash_opening.dart';
import '../../domain/cash/cash_session.dart';
import '../../domain/cash/cash_session_status.dart';
import '../identity/cash_movement_id_generator.dart';
import '../identity/cash_session_id_generator.dart';

/// Opens a [CashDrawer] into a new [CashSession] — the drawer-lifecycle
/// "Closed → Open Drawer → Cash Session Active" transition.
///
/// Throws [UnknownCashEntityViolation] if [drawerId] doesn't resolve, or
/// [CashSessionAlreadyActiveViolation] if the drawer already has a
/// non-closed session — only one active session per drawer is ever
/// permitted.
class OpenCashDrawer {
  const OpenCashDrawer({
    required Clock clock,
    required CashSessionIdGenerator sessionIdGenerator,
    required CashMovementIdGenerator movementIdGenerator,
    required CashDrawerRepository drawerRepository,
    required CashSessionRepository sessionRepository,
    required CashMovementRepository movementRepository,
    required CashAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _sessionIdGenerator = sessionIdGenerator,
        _movementIdGenerator = movementIdGenerator,
        _drawerRepository = drawerRepository,
        _sessionRepository = sessionRepository,
        _movementRepository = movementRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final CashSessionIdGenerator _sessionIdGenerator;
  final CashMovementIdGenerator _movementIdGenerator;
  final CashDrawerRepository _drawerRepository;
  final CashSessionRepository _sessionRepository;
  final CashMovementRepository _movementRepository;
  final CashAuditEntryRepository _auditRepository;

  Future<CashSession> call({
    required String drawerId,
    required String openedByStaffId,
    required Money openingFloatAmount,
  }) async {
    final drawer = await _drawerRepository.findById(drawerId);
    if (drawer == null) {
      throw UnknownCashEntityViolation(
        entityName: 'CashDrawer',
        id: drawerId,
      );
    }
    final existingActive =
        await _sessionRepository.findActiveByDrawerId(drawerId);
    if (existingActive != null) {
      throw CashSessionAlreadyActiveViolation(drawerId: drawerId);
    }

    final now = _clock.now();
    final session = CashSession(
      id: _sessionIdGenerator.nextSessionId(),
      drawerId: drawerId,
      branchId: drawer.branchId,
      status: CashSessionStatus.active,
      opening: CashOpening(
        openedByStaffId: openedByStaffId,
        openedAt: now,
        openingFloatAmount: openingFloatAmount,
      ),
      revision: 1,
    );
    await _sessionRepository.save(session);

    await _movementRepository.append(CashMovement(
      id: _movementIdGenerator.nextMovementId(),
      sessionId: session.id,
      drawerId: drawerId,
      type: CashMovementType.openingFloat,
      amount: openingFloatAmount,
      reason: 'Açılış kasası',
      actorStaffId: openedByStaffId,
      timestamp: now,
    ));

    await _auditRepository.appendEvent(CashAuditEntry(
      id: '${session.id}-audit-opened',
      drawerId: drawerId,
      sessionId: session.id,
      type: CashAuditEventType.drawerOpened,
      description: 'Drawer opened with float ${openingFloatAmount.minorUnits}',
      actorStaffId: openedByStaffId,
      timestamp: now,
    ));

    return session;
  }
}
