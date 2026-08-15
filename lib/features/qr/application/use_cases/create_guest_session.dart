import '../../../../core/utils/clock.dart';
import '../../domain/models/guest_session.dart';
import '../identity/guest_session_id_generator.dart';

/// Creates one [GuestSession] the moment a QR scan resolves and its
/// [TableSession] is opened — matching `GuestSession`'s own doc comment
/// ("created the moment a customer's QR scan resolves to a table").
///
/// **Deliberately has no repository/persistence step**, unlike
/// `OpenTableSession`: nothing in this codebase reads a `GuestSession` back
/// by id yet (no staff/POS flow references one) — this app's
/// `activeTableContextProvider` is, today, the only place a created
/// `GuestSession` needs to live, for the duration of the visit. Adding a
/// `GuestSessionRepository` with no real caller would be speculative
/// architecture; if a future flow needs to look one up independently
/// (e.g. multi-device same-table sync), that's the moment to add one —
/// this use case's signature doesn't need to change to gain that later.
class CreateGuestSession {
  const CreateGuestSession({
    required Clock clock,
    required GuestSessionIdGenerator idGenerator,
  })  : _clock = clock,
        _idGenerator = idGenerator;

  final Clock _clock;
  final GuestSessionIdGenerator _idGenerator;

  GuestSession call({
    required String tableSessionId,
    required String branchId,
    required String tableId,
    String? authenticatedUserId,
    String detectedLanguageCode = 'tr',
    String selectedLanguageCode = 'tr',
  }) {
    final now = _clock.now();
    return GuestSession(
      id: _idGenerator.nextGuestSessionId(),
      tableSessionId: tableSessionId,
      branchId: branchId,
      tableId: tableId,
      detectedLanguageCode: detectedLanguageCode,
      selectedLanguageCode: selectedLanguageCode,
      authenticatedUserId: authenticatedUserId,
      createdAt: now,
      lastSeenAt: now,
      status: GuestSessionStatus.active,
    );
  }
}
