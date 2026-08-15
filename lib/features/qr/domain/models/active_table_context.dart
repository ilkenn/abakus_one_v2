import 'guest_session.dart';
import 'table_session.dart';

/// The customer app's "which table am I ordering at" state — created once
/// a QR scan resolves and an [OpenTableSession] call succeeds, then held in
/// [activeTableContextProvider] for the rest of the visit.
///
/// Deliberately a client-side-only aggregate, not a new domain entity of
/// its own: every field it carries already exists as a real, tested domain
/// model (see `docs/table_qr_architecture.md`) — this type just bundles
/// "what the customer-facing UI needs to display and pass along" (branch/
/// table display names for the compact context indicator, the live
/// [session]/[guestSession] for order submission) so screens don't have to
/// separately watch four different providers to answer "am I at a table,
/// and which one."
class ActiveTableContext {
  /// The canonical restaurant this table belongs to — sourced from
  /// `OpenedTableGuestSession.restaurantId` (the real `openTableGuestSession`
  /// Cloud Function's server-resolved response), never client-guessed
  /// (Faz B.1, Gel Al architecture analysis). Mirrors [branchId]'s own
  /// "duplicated here for convenience, [session] already has the
  /// authoritative copy" shape — kept in sync with [session]'s own
  /// `restaurantId` by construction (`OpenTableGuestSessionFromQrScan`),
  /// never set independently of it.
  final String restaurantId;
  final String branchId;
  final String branchName;
  final String tableId;
  final String tableName;
  final TableSession session;
  final GuestSession guestSession;

  /// Server-generated, immutable snapshot (Faz R.1C.2 §11/§13) —
  /// `OpenedTableGuestSession.reservationContextId`, carried straight
  /// through, unchanged, for as long as this context lives. `null` for the
  /// ordinary walk-in case. Never re-fetched or re-derived after the
  /// session was opened — an old session's snapshot stays whatever it was
  /// at open time even if the table's reservation context later changes.
  final String? reservationContextId;

  const ActiveTableContext({
    required this.restaurantId,
    required this.branchId,
    required this.branchName,
    required this.tableId,
    required this.tableName,
    required this.session,
    required this.guestSession,
    this.reservationContextId,
  });

  ActiveTableContext copyWith({
    String? restaurantId,
    String? branchId,
    String? branchName,
    String? tableId,
    String? tableName,
    TableSession? session,
    GuestSession? guestSession,
    String? reservationContextId,
  }) {
    return ActiveTableContext(
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      tableId: tableId ?? this.tableId,
      tableName: tableName ?? this.tableName,
      session: session ?? this.session,
      guestSession: guestSession ?? this.guestSession,
      reservationContextId: reservationContextId ?? this.reservationContextId,
    );
  }
}
