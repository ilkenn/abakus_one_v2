import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/manually_assign_delivery.dart';
import '../../application/use_cases/record_courier_event.dart';
import '../../application/use_cases/review_courier_shift.dart';
import '../../domain/delivery/delivery.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/identity/courier.dart';
import '../../domain/shift/courier_shift.dart';
import '../providers/courier_dependencies_provider.dart';
import 'courier_performance_screen.dart';

/// Folds the Phase 5O brief's Courier Roster, Courier Status Board, Shift
/// Approval Queue, Active Shifts, Delivery Dispatch Board, Manual
/// Assignment, and Active Deliveries List into one operational dashboard
/// (mirrors `KitchenDisplayBoardScreen`'s consolidation precedent) — "a
/// list-based operational view is acceptable," per the brief's own
/// explicit "no advanced map visualization required" note.
class CourierDispatchBoardScreen extends ConsumerStatefulWidget {
  const CourierDispatchBoardScreen({
    super.key,
    required this.branchId,
    this.authorizationPolicy,
    this.performedByStaffId = 'manager-1',
  });

  final String branchId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<CourierDispatchBoardScreen> createState() =>
      _CourierDispatchBoardScreenState();
}

class _CourierDispatchBoardScreenState
    extends ConsumerState<CourierDispatchBoardScreen> {
  List<CourierShift>? _pendingShifts;
  List<Courier>? _couriers;
  List<Delivery>? _activeDeliveries;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final pending = await ref
        .read(courierShiftRepositoryProvider)
        .findPendingApprovalByBranchId(widget.branchId);
    final couriers = await ref
        .read(courierRepositoryProvider)
        .findByBranchId(widget.branchId);
    final deliveries = await ref
        .read(deliveryRepositoryProvider)
        .findActiveByBranchId(widget.branchId);
    if (!mounted) return;
    setState(() {
      _pendingShifts = pending;
      _couriers = couriers;
      _activeDeliveries = deliveries;
    });
  }

  RecordCourierEvent get _recordEvent => RecordCourierEvent(
        idGenerator: ref.read(courierEventIdGeneratorProvider),
        eventRepository: ref.read(courierEventRepositoryProvider),
        eventPublisher: ref.read(courierEventPublisherProvider),
      );

  Future<void> _reviewShift(CourierShift shift, bool approve) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await ReviewCourierShift(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        repository: ref.read(courierShiftRepositoryProvider),
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
        recordCourierEvent: _recordEvent,
      )(
        shiftId: shift.id,
        approve: approve,
        reviewedByStaffId: widget.performedByStaffId,
        rejectionReason: approve ? null : 'Manager reddetti',
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  Future<void> _manuallyAssign(Delivery delivery, String courierId) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _message = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await ManuallyAssignDelivery(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        assignmentIdGenerator: ref.read(deliveryAssignmentIdGeneratorProvider),
        attemptIdGenerator:
            ref.read(deliveryAssignmentAttemptIdGeneratorProvider),
        deliveryRepository: ref.read(deliveryRepositoryProvider),
        assignmentRepository: ref.read(deliveryAssignmentRepositoryProvider),
        attemptRepository:
            ref.read(deliveryAssignmentAttemptRepositoryProvider),
        availabilityRepository: ref.read(courierAvailabilityRepositoryProvider),
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
        recordCourierEvent: _recordEvent,
      )(
        deliveryId: delivery.id,
        expectedRevision: delivery.revision,
        courierId: courierId,
        overrideReason: 'Manager tarafından manuel atama',
        overriddenByStaffId: widget.performedByStaffId,
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  Future<void> _pickCourierAndAssign(Delivery delivery) async {
    final couriers = _couriers ?? const <Courier>[];
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Kurye Seç'),
        children: [
          for (final courier in couriers)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(courier.id),
              child: Text(courier.displayName),
            ),
        ],
      ),
    );
    if (selected != null) {
      await _manuallyAssign(delivery, selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingShifts;
    final couriers = _couriers;
    final deliveries = _activeDeliveries;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kurye Sevkiyat Panosu'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: pending == null || couriers == null || deliveries == null
            ? const LoadingView(message: 'Pano yükleniyor...')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_message != null) ...[
                    Text(_message!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  _buildShiftApprovalSection(pending),
                  const SizedBox(height: AppSpacing.lg),
                  _buildRosterSection(couriers),
                  const SizedBox(height: AppSpacing.lg),
                  _buildDispatchSection(deliveries),
                ],
              ),
      ),
    );
  }

  Widget _buildShiftApprovalSection(List<CourierShift> pending) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Vardiya Onay Kuyruğu', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (pending.isEmpty)
            Text('Bekleyen vardiya talebi yok',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary))
          else
            for (final shift in pending)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Kurye: ${shift.courierId}'),
                subtitle: Text('İstek: ${shift.requestedAt}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline,
                          color: AppColors.success),
                      onPressed: () => _reviewShift(shift, true),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined,
                          color: AppColors.error),
                      onPressed: () => _reviewShift(shift, false),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildRosterSection(List<Courier> couriers) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kurye Kadrosu', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (couriers.isEmpty)
            const EmptyView(
              icon: Icons.groups_outlined,
              message: 'Bu şubede kayıtlı kurye yok',
            )
          else
            for (final courier in couriers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(courier.displayName),
                subtitle: Text(
                    '${courier.vehicleType.name} • ${courier.status.name}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CourierPerformanceScreen(
                      courierId: courier.id,
                    ),
                  ));
                },
              ),
        ],
      ),
    );
  }

  Widget _buildDispatchSection(List<Delivery> deliveries) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Aktif Teslimatlar', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (deliveries.isEmpty)
            const EmptyView(
              icon: Icons.local_shipping_outlined,
              message: 'Aktif teslimat yok',
            )
          else
            for (final delivery in deliveries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Sipariş: ${delivery.orderId.value}'),
                subtitle: Text(delivery.status.name),
                trailing: delivery.status == DeliveryStatus.readyForAssignment
                    ? TextButton(
                        onPressed: () => _pickCourierAndAssign(delivery),
                        child: const Text('Ata'),
                      )
                    : Text(delivery.courierId ?? '-'),
              ),
        ],
      ),
    );
  }
}
