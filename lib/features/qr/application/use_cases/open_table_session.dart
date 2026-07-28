import '../../../../core/utils/clock.dart';
import '../../data/table_session_repository.dart';
import '../../domain/models/table_session.dart';
import '../identity/table_session_id_generator.dart';

/// Opens a new [TableSession] for a table — either from a guest's QR scan
/// resolving (`OrderChannel.dineInQr`) or from staff seating a walk-in
/// (`OrderChannel.dineInStaff`); this use case itself is channel-agnostic,
/// matching `docs/table_qr_architecture.md` §7's description of the
/// trigger being external to the session shape itself.
///
/// Never reopens or reuses a prior session for the same table — always
/// constructs a brand-new [TableSession], preserving the isolation rule
/// `docs/table_qr_architecture.md` §7 requires (a closed/cancelled session
/// is immutable history; a new visit always starts fresh state). Callers
/// are responsible for first checking
/// `TableSessionRepository.findActiveByTableId` themselves if they need to
/// prevent opening a second concurrent session at an already-occupied
/// table — this use case does not enforce that itself, since a genuinely
/// valid multi-party-at-one-table scenario is out of scope to arbitrate
/// here.
class OpenTableSession {
  const OpenTableSession({
    required Clock clock,
    required TableSessionIdGenerator idGenerator,
    required TableSessionRepository repository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _repository = repository;

  final Clock _clock;
  final TableSessionIdGenerator _idGenerator;
  final TableSessionRepository _repository;

  Future<TableSession> call({
    required String restaurantId,
    required String branchId,
    required String tableId,
  }) async {
    final session = TableSession(
      id: _idGenerator.nextTableSessionId(),
      restaurantId: restaurantId,
      branchId: branchId,
      tableId: tableId,
      status: TableSessionStatus.active,
      openedAt: _clock.now(),
      guestSessionIds: const [],
      activeOrderIds: const [],
    );
    await _repository.save(session);
    return session;
  }
}
