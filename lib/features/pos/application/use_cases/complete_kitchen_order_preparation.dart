import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../data/kitchen_audit_entry_repository.dart';
import '../../data/kitchen_projection_repository.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/kds/kitchen_audit_entry.dart';
import '../../domain/kds/kitchen_event_type.dart';
import '../../domain/kds/kitchen_order_view.dart';
import 'record_kitchen_event.dart';

/// Marks an order's kitchen preparation complete — Phase 4K's "complete
/// order preparation" action, and the Phase 4H bridge into package
/// preparation.
///
/// **Kitchen-ready does not automatically mean handed to courier, and
/// packing remains a separate operational lifecycle**: this use case only
/// advances `PackagePreparation` from `preparing` to `readyForPacking`
/// (never further) for [OrderChannel.delivery]/[OrderChannel.takeaway]
/// orders — package preparation itself still requires its own subsequent
/// explicit steps (`AdvancePackagePreparation`/`CompleteQualityControl`,
/// Sprint 3D, both untouched). [OrderChannel.dineInQr]/[OrderChannel
/// .dineInStaff] orders **never** touch `PackagePreparation` at all — a
/// dine-in order has nothing to pack.
///
/// Throws [KitchenOrderNotFullyReadyViolation] unless
/// `KitchenOrderView.isFullyReady` is already `true` for the order's
/// current work items — order readiness is derived, never manually
/// forced past what its lines actually show.
class CompleteKitchenOrderPreparation {
  const CompleteKitchenOrderPreparation({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required KitchenProjectionRepository projectionRepository,
    required KitchenAuditEntryRepository auditRepository,
    required RecordKitchenEvent recordKitchenEvent,
    Future<void> Function({
      required OrderId orderId,
      required String performedByStaffId,
      required DateTime at,
    })? advanceToReadyForPacking,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _projectionRepository = projectionRepository,
        _auditRepository = auditRepository,
        _recordKitchenEvent = recordKitchenEvent,
        _advanceToReadyForPacking = advanceToReadyForPacking;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final KitchenProjectionRepository _projectionRepository;
  final KitchenAuditEntryRepository _auditRepository;
  final RecordKitchenEvent _recordKitchenEvent;

  /// Injected rather than depending on `AdvancePackagePreparation`
  /// directly, so this use case stays testable without also having to
  /// construct a full `PackagePreparationRepository` fixture for tests
  /// that only care about the kitchen side. The default production wiring
  /// passes a closure over the real `AdvancePackagePreparation`.
  final Future<void> Function({
    required OrderId orderId,
    required String performedByStaffId,
    required DateTime at,
  })? _advanceToReadyForPacking;

  Future<void> call({
    required OrderId orderId,
    required String kitchenTicketId,
    required String branchId,
    required OrderChannel channel,
    required String performedByStaffId,
    String? deviceId,
  }) async {
    final workItems = await _projectionRepository.findByOrderId(orderId);
    final view = KitchenOrderView.build(
      orderId: orderId,
      kitchenTicketId: kitchenTicketId,
      workItems: workItems,
    );
    if (!view.isFullyReady) {
      throw KitchenOrderNotFullyReadyViolation(orderId: orderId.value);
    }

    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.completeOrderPreparation,
      actorStaffId: performedByStaffId,
      context: {'orderId': orderId.value},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.completeOrderPreparation.name,
      );
    }

    final now = _clock.now();
    final event = await _recordKitchenEvent(
      branchId: branchId,
      orderId: orderId,
      kitchenTicketId: kitchenTicketId,
      type: KitchenEventType.orderPreparationCompleted,
      idempotencyKey: '$kitchenTicketId-order-preparation-completed',
      occurredAt: now,
      sourceDeviceId: deviceId,
    );

    await _auditRepository.appendEvent(KitchenAuditEntry(
      id: '${event.id}-audit',
      branchId: branchId,
      orderId: orderId.value,
      kitchenTicketId: kitchenTicketId,
      deviceId: deviceId,
      type: KitchenAuditEventType.orderPreparationCompleted,
      description: 'Order preparation completed',
      actorStaffId: performedByStaffId,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    final isPackagingChannel =
        channel == OrderChannel.delivery || channel == OrderChannel.takeaway;
    if (isPackagingChannel && _advanceToReadyForPacking != null) {
      await _advanceToReadyForPacking(
        orderId: orderId,
        performedByStaffId: performedByStaffId,
        at: now,
      );
    }
  }
}
