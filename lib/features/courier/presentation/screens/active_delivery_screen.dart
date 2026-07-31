import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../crm/application/use_cases/record_customer_visit_and_evaluate_rewards.dart';
import '../../../crm/presentation/providers/crm_dependencies_provider.dart';
import '../../../orders/data/package_preparation_repository.dart';
import '../../../orders/domain/fulfillment/package_preparation_status.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../pos/application/use_cases/advance_package_preparation.dart';
import '../../../pos/data/pos_order_repository.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/presentation/providers/package_preparation_dependencies_provider.dart';
import '../../../pos/presentation/providers/pos_dependencies_provider.dart';
import '../../application/use_cases/complete_delivery.dart';
import '../../application/use_cases/confirm_package_pickup.dart';
import '../../application/use_cases/record_courier_event.dart';
import '../../application/use_cases/record_delivery_failure.dart';
import '../../application/use_cases/respond_to_delivery_assignment.dart';
import '../../application/use_cases/transition_delivery.dart';
import '../../domain/delivery/delivery.dart';
import '../../domain/delivery/delivery_assignment.dart';
import '../../domain/delivery/delivery_failure_reason.dart';
import '../../domain/delivery/delivery_proof_type.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/feedback/courier_feedback_tag.dart';
import '../providers/courier_dependencies_provider.dart';

/// Folds the Phase 5N brief's assignment-offer, active-delivery,
/// restaurant-arrival, package-pickup, navigation-handoff, customer-
/// arrival, delivery-proof, and delivery-failure screens into one
/// state-driven flow screen — one [Delivery] at a time, the UI showing
/// only the single action valid for its current [DeliveryStatus]
/// ("one primary action per state," per the brief's own UI priority).
class ActiveDeliveryScreen extends ConsumerStatefulWidget {
  const ActiveDeliveryScreen({
    super.key,
    required this.deliveryId,
    required this.courierId,
    this.deviceId,
    this.authorizationPolicy,
  });

  final String deliveryId;
  final String courierId;
  final String? deviceId;

  /// Nullable, matching every other Phase 3/4/5 screen's precedent (e.g.
  /// `KitchenDisplayBoardScreen`) — no app-wide authorization wiring exists
  /// yet; actions check for one at call time and surface a message if
  /// absent rather than crashing.
  final PosAuthorizationPolicy? authorizationPolicy;

  @override
  ConsumerState<ActiveDeliveryScreen> createState() =>
      _ActiveDeliveryScreenState();
}

class _ActiveDeliveryScreenState extends ConsumerState<ActiveDeliveryScreen> {
  Delivery? _delivery;
  DeliveryAssignment? _assignment;
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final delivery =
        await ref.read(deliveryRepositoryProvider).findById(widget.deliveryId);
    DeliveryAssignment? assignment;
    final assignmentId = delivery?.currentAssignmentId;
    if (assignmentId != null) {
      assignment = await ref
          .read(deliveryAssignmentRepositoryProvider)
          .findById(assignmentId);
    }
    if (!mounted) return;
    setState(() {
      _delivery = delivery;
      _assignment = assignment;
      _loading = false;
    });
  }

  RecordCourierEvent get _recordEvent => RecordCourierEvent(
        idGenerator: ref.read(courierEventIdGeneratorProvider),
        eventRepository: ref.read(courierEventRepositoryProvider),
        eventPublisher: ref.read(courierEventPublisherProvider),
      );

  Future<void> _respond(bool accept, {String? rejectionReasonCode}) async {
    final assignment = _assignment;
    final policy = widget.authorizationPolicy;
    if (assignment == null) return;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await RespondToDeliveryAssignment(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        assignmentRepository: ref.read(deliveryAssignmentRepositoryProvider),
        deliveryRepository: ref.read(deliveryRepositoryProvider),
        availabilityRepository: ref.read(courierAvailabilityRepositoryProvider),
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
        recordCourierEvent: _recordEvent,
      )(
        assignmentId: assignment.id,
        courierId: widget.courierId,
        accept: accept,
        rejectionReasonCode: rejectionReasonCode,
        performedByStaffId: widget.courierId,
        deviceId: widget.deviceId,
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  Future<void> _transition(DeliveryStatus to) async {
    final delivery = _delivery;
    final policy = widget.authorizationPolicy;
    if (delivery == null) return;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await TransitionDelivery(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        repository: ref.read(deliveryRepositoryProvider),
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
        recordCourierEvent: _recordEvent,
      )(
        deliveryId: delivery.id,
        to: to,
        expectedRevision: delivery.revision,
        performedByStaffId: widget.courierId,
        deviceId: widget.deviceId,
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  Future<void> _confirmPickup() async {
    final delivery = _delivery;
    final policy = widget.authorizationPolicy;
    if (delivery == null) return;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    final packageRepository = ref.read(packagePreparationRepositoryProvider);
    try {
      await ConfirmPackagePickup(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        repository: ref.read(deliveryRepositoryProvider),
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
        recordCourierEvent: _recordEvent,
        isPackageReadyForPickup: ({required orderId}) async {
          final current = await packageRepository.findCurrentByOrderId(orderId);
          return current?.status == PackagePreparationStatus.waitingForCourier;
        },
        advanceToCourierCollected: (
            {required orderId,
            required performedByStaffId,
            required at}) async {
          await AdvancePackagePreparation(repository: packageRepository)(
            orderId: orderId,
            newStatus: PackagePreparationStatus.courierCollected,
            performedByStaffId: performedByStaffId,
            at: at,
          );
        },
      )(
          deliveryId: delivery.id,
          performedByStaffId: widget.courierId,
          deviceId: widget.deviceId);
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  Future<void> _completeDelivery() async {
    final delivery = _delivery;
    final policy = widget.authorizationPolicy;
    if (delivery == null) return;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    final packageRepository = ref.read(packagePreparationRepositoryProvider);
    try {
      await CompleteDelivery(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        repository: ref.read(deliveryRepositoryProvider),
        proofIdGenerator: ref.read(deliveryProofIdGeneratorProvider),
        proofRepository: ref.read(deliveryProofRepositoryProvider),
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
        recordCourierEvent: _recordEvent,
        advanceToDelivered: ({
          required OrderId orderId,
          required String performedByStaffId,
          required DateTime at,
        }) async {
          await _advancePackageToDelivered(
              packageRepository, orderId, performedByStaffId, at);
        },
        recordVisitAndEvaluateRewards: ({
          required OrderId orderId,
          required String branchId,
          required DateTime at,
        }) async {
          await _recordVisitForDeliveredOrder(
            ref.read(posOrderRepositoryProvider),
            ref.read(recordCustomerVisitAndEvaluateRewardsProvider),
            orderId,
            branchId,
            at,
          );
        },
      )(
        deliveryId: delivery.id,
        courierId: widget.courierId,
        expectedRevision: delivery.revision,
        performedByStaffId: widget.courierId,
        deviceId: widget.deviceId,
        proofType: DeliveryProofType.receptionNote,
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  static Future<void> _advancePackageToDelivered(
    PackagePreparationRepository repository,
    OrderId orderId,
    String performedByStaffId,
    DateTime at,
  ) async {
    final current = await repository.findCurrentByOrderId(orderId);
    if (current == null) return;
    var status = current.status;
    final advance = AdvancePackagePreparation(repository: repository);
    if (status == PackagePreparationStatus.courierCollected) {
      await advance(
        orderId: orderId,
        newStatus: PackagePreparationStatus.outForDelivery,
        performedByStaffId: performedByStaffId,
        at: at,
      );
      status = PackagePreparationStatus.outForDelivery;
    }
    if (status == PackagePreparationStatus.outForDelivery) {
      await advance(
        orderId: orderId,
        newStatus: PackagePreparationStatus.delivered,
        performedByStaffId: performedByStaffId,
        at: at,
      );
    }
  }

  /// **Sprint 5E** (`docs/decisions.md` ADR-022): resolves the delivered
  /// order and hands it to [RecordCustomerVisitAndEvaluateRewards
  /// .callForOrder] — `order == null` (no `Order` was ever submitted
  /// under this id — should not happen for a real delivery, but this is
  /// best-effort orchestration, not a guaranteed invariant) skips the
  /// same way `callForOrder` itself skips a missing `customerId`:
  /// delivery completion itself must never fail because loyalty
  /// bookkeeping couldn't find a customer to credit.
  static Future<void> _recordVisitForDeliveredOrder(
    PosOrderRepository orderRepository,
    RecordCustomerVisitAndEvaluateRewards recordVisit,
    OrderId orderId,
    String branchId,
    DateTime at,
  ) async {
    final order = await orderRepository.findById(orderId);
    if (order == null) return;
    await recordVisit.callForOrder(order: order, occurredAt: at);
  }

  Future<void> _recordFailure(DeliveryFailureReason reason) async {
    final delivery = _delivery;
    final policy = widget.authorizationPolicy;
    if (delivery == null) return;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await RecordDeliveryFailure(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        idGenerator: ref.read(deliveryFailureIdGeneratorProvider),
        deliveryRepository: ref.read(deliveryRepositoryProvider),
        failureRepository: ref.read(deliveryFailureRepositoryProvider),
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
        recordCourierEvent: _recordEvent,
      )(
        deliveryId: delivery.id,
        reasonCode: reason,
        performedByStaffId: widget.courierId,
        deviceId: widget.deviceId,
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    final delivery = _delivery;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Aktif Teslimat'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: _loading || delivery == null
            ? const LoadingView(message: 'Teslimat yükleniyor...')
            : Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_message != null) ...[
                      Text(_message!,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.error)),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    AppCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sipariş: ${delivery.orderId.value}',
                              style: AppTypography.titleMedium),
                          const SizedBox(height: AppSpacing.xs),
                          Text('Durum: ${delivery.status.name}',
                              style: AppTypography.bodyMedium
                                  .copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(child: _buildActionArea(delivery)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildActionArea(Delivery delivery) {
    switch (delivery.status) {
      case DeliveryStatus.assigned:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: () => _respond(true),
              child: const Text('Teslimatı Kabul Et'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () => _respond(false,
                  rejectionReasonCode: CourierFeedbackTag.trafficDelay.name),
              child: const Text('Reddet'),
            ),
          ],
        );
      case DeliveryStatus.accepted:
        return ElevatedButton(
          onPressed: () => _transition(DeliveryStatus.arrivedAtRestaurant),
          child: const Text('Restorana Vardım'),
        );
      case DeliveryStatus.arrivedAtRestaurant:
        return ElevatedButton(
          onPressed: _confirmPickup,
          child: const Text('Paketi Teslim Al'),
        );
      case DeliveryStatus.pickedUp:
        return ElevatedButton(
          onPressed: () => _transition(DeliveryStatus.enRoute),
          child: const Text('Yola Çıktım'),
        );
      case DeliveryStatus.enRoute:
        return ElevatedButton(
          onPressed: () => _transition(DeliveryStatus.arrivedAtCustomer),
          child: const Text('Müşteriye Vardım'),
        );
      case DeliveryStatus.arrivedAtCustomer:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _completeDelivery,
              child: const Text('Teslimatı Tamamla'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () =>
                  _recordFailure(DeliveryFailureReason.customerUnavailable),
              child: const Text('Teslim Edilemedi'),
            ),
          ],
        );
      case DeliveryStatus.delivered:
        return Center(
          child: Text('Teslimat tamamlandı',
              style:
                  AppTypography.titleMedium.copyWith(color: AppColors.success)),
        );
      default:
        return Center(
          child: Text(delivery.status.name,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
        );
    }
  }
}
