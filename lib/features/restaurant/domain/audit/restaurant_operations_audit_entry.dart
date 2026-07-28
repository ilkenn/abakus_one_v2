import 'restaurant_operations_audit_event_type.dart';

/// One immutable, append-only audit record of a critical restaurant-
/// operations action — channel policy changes, check reopen/transfer/
/// merge/split, package-completion overrides, kitchen ticket reprints.
///
/// Mirrors `ClosureAuditEntry`'s shape (Phase 3 Sprint 3C) but is a
/// distinct type, branch-scoped rather than order-scoped — most of these
/// events (a channel policy change, a floor edit) have no single `OrderId`
/// to key against.
class RestaurantOperationsAuditEntry {
  const RestaurantOperationsAuditEntry({
    required this.id,
    required this.branchId,
    required this.type,
    required this.description,
    required this.actorStaffId,
    required this.timestamp,
    this.previousValue,
    this.newValue,
  });

  /// Externally supplied — no id-generation mechanism lives on this class,
  /// matching every other identifier in this codebase.
  final String id;

  final String branchId;
  final RestaurantOperationsAuditEventType type;
  final String description;
  final String actorStaffId;
  final DateTime timestamp;

  final String? previousValue;
  final String? newValue;
}
