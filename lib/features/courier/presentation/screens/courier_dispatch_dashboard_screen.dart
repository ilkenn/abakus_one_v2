import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/build_courier_daily_operations_report.dart';
import '../../application/use_cases/build_courier_performance_snapshot.dart';
import '../../application/use_cases/record_courier_event.dart';
import '../../application/use_cases/reorder_courier_delivery_sequence.dart';
import '../../domain/analytics/courier_daily_operations_report.dart';
import '../../domain/audit/courier_operation_timeline_entry.dart';
import '../../domain/delivery/delivery.dart';
import '../../domain/dispatch/courier_dispatch_queue_snapshot.dart';
import '../../domain/health/courier_operation_health.dart';
import '../../domain/health/courier_operation_health_level.dart';
import '../../domain/identity/courier.dart';
import '../../domain/warnings/courier_live_warning.dart';
import '../providers/courier_dependencies_provider.dart';
import 'courier_communication_center_screen.dart';
import 'courier_dispatch_board_screen.dart';
import 'courier_live_map_screen.dart';

/// The consolidated manager-facing dispatch/operations center — Sprint 5C
/// Part 1, built last so it could sit on top of every other Part 2-13
/// read-model (health/warnings/queue/report/timeline) without duplicating
/// any of their logic. **Additive, not a replacement**: the existing
/// `CourierDispatchBoardScreen` (roster/shift-approval/manual-assignment,
/// Phase 5O) and `CourierLiveMapScreen`/`CourierCommunicationCenterScreen`
/// (Sprint 5C) remain the canonical screens for their own actions — this
/// screen is a situational-awareness overview with links out to them, not
/// a reimplementation.
///
/// **Documented gap, not an oversight**: same-destination "assign
/// together/separately" detection needs a delivery's destination text,
/// which lives on `Order` (`Order.deliveryAddressText`), not `Delivery`.
/// No courier-feature screen has ever read from the orders feature (an
/// architecture-affecting new cross-feature dependency), so live
/// detection is intentionally not surfaced here — only already-confirmed
/// `SameDestinationGroup` records would be safe to show, and no screen
/// yet creates them, so there is nothing to display today.
class CourierDispatchDashboardScreen extends ConsumerStatefulWidget {
  const CourierDispatchDashboardScreen({
    super.key,
    required this.branchId,
    this.authorizationPolicy,
    this.performedByStaffId = 'manager-1',
  });

  final String branchId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<CourierDispatchDashboardScreen> createState() =>
      _CourierDispatchDashboardScreenState();
}

class _CourierDispatchDashboardScreenState
    extends ConsumerState<CourierDispatchDashboardScreen> {
  CourierOperationHealth? _health;
  List<CourierLiveWarning>? _warnings;
  CourierDispatchQueueSnapshot? _queue;
  CourierDailyOperationsReport? _report;
  List<CourierOperationTimelineEntry>? _timeline;
  List<(Courier, List<Delivery>)>? _courierActiveDeliveries;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final branchId = widget.branchId;
    final health =
        await ref.read(buildCourierOperationHealthProvider)(branchId: branchId);
    final warnings =
        await ref.read(buildCourierLiveWarningsProvider)(branchId: branchId);
    final queue =
        await ref.read(buildCourierDispatchQueueProvider)(branchId: branchId);
    final report = await BuildCourierDailyOperationsReport(
      courierRepository: ref.read(courierRepositoryProvider),
      deliveryRepository: ref.read(deliveryRepositoryProvider),
      deliveryEarningsRepository: ref.read(deliveryEarningsRepositoryProvider),
      buildCourierPerformanceSnapshot: BuildCourierPerformanceSnapshot(
        deliveryRepository: ref.read(deliveryRepositoryProvider),
        assignmentRepository: ref.read(deliveryAssignmentRepositoryProvider),
        failureRepository: ref.read(deliveryFailureRepositoryProvider),
        geofenceOverrideRepository:
            ref.read(geofenceOverrideRepositoryProvider),
        contactActionRepository:
            ref.read(customerContactActionRepositoryProvider),
      ),
    )(branchId: branchId, date: ref.read(clockProvider).now());
    final timeline = await ref.read(buildCourierOperationTimelineProvider)(
        branchId: branchId);

    final couriers =
        await ref.read(courierRepositoryProvider).findByBranchId(branchId);
    final courierActiveDeliveries = <(Courier, List<Delivery>)>[];
    for (final courier in couriers) {
      final deliveries = await ref
          .read(deliveryRepositoryProvider)
          .findActiveByCourierId(courier.id);
      if (deliveries.length >= 2) {
        courierActiveDeliveries.add((courier, deliveries));
      }
    }

    if (!mounted) return;
    setState(() {
      _health = health;
      _warnings = warnings;
      _queue = queue;
      _report = report;
      _timeline = timeline.take(10).toList();
      _courierActiveDeliveries = courierActiveDeliveries;
    });
  }

  Future<void> _editSequence(Courier courier, List<Delivery> deliveries) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    final newOrder = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SequenceEditorSheet(
        courier: courier,
        deliveries: deliveries,
      ),
    );
    if (newOrder == null) return;

    try {
      await ReorderCourierDeliverySequence(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        deliveryRepository: ref.read(deliveryRepositoryProvider),
        sequenceRepository: ref.read(courierDeliverySequenceRepositoryProvider),
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
        recordCourierEvent: RecordCourierEvent(
          idGenerator: ref.read(courierEventIdGeneratorProvider),
          eventRepository: ref.read(courierEventRepositoryProvider),
          eventPublisher: ref.read(courierEventPublisherProvider),
        ),
      )(
        courierId: courier.id,
        branchId: widget.branchId,
        newOrder: newOrder,
        performedByStaffId: widget.performedByStaffId,
      );
      setState(() => _error = null);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  static String _healthEmoji(CourierOperationHealthLevel level) {
    switch (level) {
      case CourierOperationHealthLevel.healthy:
        return '🟢';
      case CourierOperationHealthLevel.degraded:
        return '🟡';
      case CourierOperationHealthLevel.critical:
        return '🔴';
    }
  }

  static String _healthLabel(CourierOperationHealthLevel level) {
    switch (level) {
      case CourierOperationHealthLevel.healthy:
        return 'Sağlıklı';
      case CourierOperationHealthLevel.degraded:
        return 'Dikkat';
      case CourierOperationHealthLevel.critical:
        return 'Kritik';
    }
  }

  static Color _healthColor(CourierOperationHealthLevel level) {
    switch (level) {
      case CourierOperationHealthLevel.healthy:
        return AppColors.success;
      case CourierOperationHealthLevel.degraded:
        return AppColors.warning;
      case CourierOperationHealthLevel.critical:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final health = _health;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Sevkiyat Kontrol Merkezi'),
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
        child: health == null
            ? const LoadingView(message: 'Kontrol merkezi yükleniyor...')
            : _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (_error != null) ...[
          Text(_error!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
          const SizedBox(height: AppSpacing.sm),
        ],
        _buildHealthCard(),
        const SizedBox(height: AppSpacing.md),
        _buildQuickActions(context),
        const SizedBox(height: AppSpacing.md),
        _buildWarningsCard(),
        const SizedBox(height: AppSpacing.md),
        _buildReportCard(),
        const SizedBox(height: AppSpacing.md),
        _buildQueueCard(),
        const SizedBox(height: AppSpacing.md),
        _buildSequenceCard(),
        const SizedBox(height: AppSpacing.md),
        _buildTimelineCard(),
      ],
    );
  }

  Widget _buildHealthCard() {
    final health = _health!;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Text(_healthEmoji(health.level),
              style: const TextStyle(fontSize: 32)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Operasyon Durumu: ${_healthLabel(health.level)}',
                  style: AppTypography.titleMedium
                      .copyWith(color: _healthColor(health.level)),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Geciken: ${health.delayedDeliveryCount} • '
                  'Çevrimdışı: ${health.offlineCourierCount} • '
                  'GPS Sorunu: ${health.gpsFailureCount} • '
                  'Bekleyen: ${health.waitingDeliveryCount} • '
                  'Alarm: ${health.operationalAlarmCount}',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.map_outlined),
          label: const Text('Canlı Harita'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CourierLiveMapScreen(branchId: widget.branchId),
          )),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('İletişim Merkezi'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CourierCommunicationCenterScreen(
              branchId: widget.branchId,
              authorizationPolicy: widget.authorizationPolicy,
              performedByStaffId: widget.performedByStaffId,
            ),
          )),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.assignment_outlined),
          label: const Text('Sevkiyat Panosu'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CourierDispatchBoardScreen(
              branchId: widget.branchId,
              authorizationPolicy: widget.authorizationPolicy,
              performedByStaffId: widget.performedByStaffId,
            ),
          )),
        ),
      ],
    );
  }

  Widget _buildWarningsCard() {
    final warnings = _warnings ?? const [];
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Canlı Uyarılar', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          if (warnings.isEmpty)
            Text('Aktif uyarı yok.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary))
          else
            for (final warning in warnings)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 16, color: AppColors.warning),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(warning.description,
                          style: AppTypography.bodySmall),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildReportCard() {
    final report = _report;
    if (report == null) return const SizedBox.shrink();
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bugün', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: [
              _Kpi('Teslimat', '${report.totalDeliveries}'),
              _Kpi('Mesafe',
                  '${report.totalDistanceTravelledKm.toStringAsFixed(1)} km'),
              _Kpi(
                'Ort. Süre',
                report.averageDeliveryDurationSeconds == null
                    ? '-'
                    : '${(report.averageDeliveryDurationSeconds! / 60).round()} dk',
              ),
              _Kpi('Yoğun Saat',
                  report.peakHour == null ? '-' : '${report.peakHour}:00'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard() {
    final queue = _queue;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('FIFO Sevkiyat Sırası', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          if (queue == null || queue.positions.isEmpty)
            Text('Sırada bekleyen kurye yok.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary))
          else
            for (final position in queue.positions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text('${position.position}.',
                        style: AppTypography.bodyMedium.copyWith(
                            fontWeight: position.position == 1
                                ? FontWeight.bold
                                : FontWeight.normal)),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(position.courierId,
                          style: AppTypography.bodyMedium),
                    ),
                    if (position.position == 1)
                      const Text('Sıradaki',
                          style: TextStyle(color: AppColors.success)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSequenceCard() {
    final entries = _courierActiveDeliveries ?? const [];
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Teslimat Sırası Kontrolü',
              style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          if (entries.isEmpty)
            Text('Birden fazla aktif teslimatı olan kurye yok.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary))
          else
            for (final (courier, deliveries) in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                          '${courier.displayName} (${deliveries.length} teslimat)',
                          style: AppTypography.bodyMedium),
                    ),
                    TextButton(
                      onPressed: () => _editSequence(courier, deliveries),
                      child: const Text('Sırayı Düzenle'),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard() {
    final timeline = _timeline ?? const [];
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Operasyon Zaman Çizelgesi',
              style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          if (timeline.isEmpty)
            const EmptyView(
              icon: Icons.history,
              message: 'Henüz kayıtlı işlem yok.',
            )
          else
            for (final entry in timeline)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${entry.timestamp.minute.toString().padLeft(2, '0')} '
                  '${entry.courierDisplayName != null ? '${entry.courierDisplayName}: ' : ''}'
                  '${entry.description}',
                  style: AppTypography.bodySmall,
                ),
              ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTypography.titleMedium),
        Text(label,
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _SequenceEditorSheet extends StatefulWidget {
  const _SequenceEditorSheet({
    required this.courier,
    required this.deliveries,
  });

  final Courier courier;
  final List<Delivery> deliveries;

  @override
  State<_SequenceEditorSheet> createState() => _SequenceEditorSheetState();
}

class _SequenceEditorSheetState extends State<_SequenceEditorSheet> {
  final List<Delivery> _ordered = [];

  @override
  void initState() {
    super.initState();
    _ordered.addAll(widget.deliveries);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.courier.displayName} - Teslimat Sırası',
                style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ReorderableListView(
                shrinkWrap: true,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final item = _ordered.removeAt(oldIndex);
                    _ordered.insert(newIndex, item);
                  });
                },
                children: [
                  for (final delivery in _ordered)
                    ListTile(
                      key: ValueKey(delivery.id),
                      leading: const Icon(Icons.drag_handle),
                      title: Text(delivery.orderId.value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context)
                    .pop(_ordered.map((d) => d.id).toList()),
                child: const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
