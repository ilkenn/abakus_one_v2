import 'courier_settlement_session_status.dart';

/// One courier's cash-settlement period, from the first collection
/// recorded against it to closure — the aggregate every
/// `CourierCashCollection`/`CourierCashDeclaration`/`CourierSettlement` is
/// scoped to. Mirrors `CashSession`'s append-only-via-`revision` shape
/// exactly.
///
/// **Append-only**: never mutated in place — every status change produces
/// a new instance with the same [id] and an incremented [revision].
///
/// Only one non-[CourierSettlementSessionStatus.closed] session may exist
/// per courier at a time — enforced by `OpenCourierSettlementSession`/
/// `CourierSettlementSessionRepository.findActiveByCourierId`, not by this
/// class itself (this class has no way to see other sessions).
class CourierSettlementSession {
  const CourierSettlementSession({
    required this.id,
    required this.courierId,
    required this.branchId,
    required this.status,
    required this.openedAt,
    this.closedAt,
    required this.revision,
  });

  /// Stable across every revision.
  final String id;

  /// A plain external identifier, like every other actor id in this
  /// codebase (`staffId`, `actorStaffId`, ...) — no `Courier` entity or
  /// repository exists yet (`docs/business_rules.md` BR-COURIER-004:
  /// courier roster is ROADMAP, no code). Referencing couriers by id only,
  /// exactly as `staffId` already does for staff (BR-ROLE-003: no role/
  /// permission system exists either), is the established pattern this
  /// sprint follows rather than inventing a `Courier` aggregate.
  final String courierId;

  final String branchId;
  final CourierSettlementSessionStatus status;
  final DateTime openedAt;

  /// `null` until [status] reaches [CourierSettlementSessionStatus.closed].
  final DateTime? closedAt;

  /// Optimistic-concurrency counter — starts at 1.
  final int revision;

  bool get isActive => status != CourierSettlementSessionStatus.closed;

  CourierSettlementSession copyWith({
    CourierSettlementSessionStatus? status,
    DateTime? closedAt,
    int? revision,
  }) {
    return CourierSettlementSession(
      id: id,
      courierId: courierId,
      branchId: branchId,
      status: status ?? this.status,
      openedAt: openedAt,
      closedAt: closedAt ?? this.closedAt,
      revision: revision ?? this.revision,
    );
  }
}
