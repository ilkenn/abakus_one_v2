import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/record_courier_event.dart';
import '../../application/use_cases/request_courier_shift.dart';
import '../../application/use_cases/set_courier_availability.dart';
import '../../application/use_cases/transition_courier_shift.dart';
import '../../domain/availability/courier_availability.dart';
import '../../domain/availability/courier_availability_status.dart';
import '../../domain/delivery/delivery.dart';
import '../../domain/shift/courier_shift.dart';
import '../../domain/shift/courier_shift_status.dart';
import '../providers/courier_dependencies_provider.dart';
import 'active_delivery_screen.dart';
import 'courier_delivery_history_screen.dart';
import 'courier_earnings_screen.dart';

/// The courier app's home dashboard — shift status/request, online/offline
/// control, and the entry point into an active delivery. Folds several of
/// the Phase 5N brief's separate screens (login/identity foundation,
/// shift-start request, connection/sync status, location permission
/// state) into one dashboard, since each is a small piece of state shown
/// together rather than a screen of its own — mirrors
/// `KitchenDisplayBoardScreen`'s own consolidation precedent (Phase 4).
///
/// Default courier delivery capacity (3 concurrent deliveries) is a
/// screen-level default, not a hardcoded business rule — configurable in
/// principle via `CourierOperationalProfile`, unused by any screen yet.
const _defaultCapacity = 3;

class CourierHomeScreen extends ConsumerStatefulWidget {
  const CourierHomeScreen({
    super.key,
    required this.courierId,
    required this.branchId,
    this.deviceId,
  });

  final String courierId;
  final String branchId;
  final String? deviceId;

  @override
  ConsumerState<CourierHomeScreen> createState() => _CourierHomeScreenState();
}

class _CourierHomeScreenState extends ConsumerState<CourierHomeScreen> {
  CourierShift? _shift;
  CourierAvailability? _availability;
  List<Delivery>? _activeDeliveries;
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final shift = await ref
        .read(courierShiftRepositoryProvider)
        .findActiveByCourierId(widget.courierId);
    final availability = await ref
        .read(courierAvailabilityRepositoryProvider)
        .findByCourierId(widget.courierId);
    final deliveries = await ref
        .read(deliveryRepositoryProvider)
        .findActiveByCourierId(widget.courierId);
    if (!mounted) return;
    setState(() {
      _shift = shift;
      _availability = availability;
      _activeDeliveries = deliveries;
      _loading = false;
    });
  }

  RecordCourierEvent get _recordEvent => RecordCourierEvent(
        idGenerator: ref.read(courierEventIdGeneratorProvider),
        eventRepository: ref.read(courierEventRepositoryProvider),
        eventPublisher: ref.read(courierEventPublisherProvider),
      );

  Future<void> _requestShift() async {
    try {
      await RequestCourierShift(
        clock: ref.read(clockProvider),
        idGenerator: ref.read(courierShiftIdGeneratorProvider),
        repository: ref.read(courierShiftRepositoryProvider),
      )(courierId: widget.courierId, branchId: widget.branchId);
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  Future<void> _transitionShift(CourierShiftStatus to) async {
    final shift = _shift;
    if (shift == null) return;
    try {
      await TransitionCourierShift(
        clock: ref.read(clockProvider),
        repository: ref.read(courierShiftRepositoryProvider),
        deliveryRepository: ref.read(deliveryRepositoryProvider),
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
        recordCourierEvent: _recordEvent,
      )(shiftId: shift.id, to: to, performedByStaffId: widget.courierId);
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  Future<void> _setAvailability(CourierAvailabilityStatus to) async {
    try {
      await SetCourierAvailability(
        clock: ref.read(clockProvider),
        shiftRepository: ref.read(courierShiftRepositoryProvider),
        availabilityRepository: ref.read(courierAvailabilityRepositoryProvider),
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
        recordCourierEvent: _recordEvent,
      )(
        courierId: widget.courierId,
        to: to,
        capacity: _availability?.capacity ?? _defaultCapacity,
        performedByStaffId: widget.courierId,
      );
      setState(() => _message = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _message = e.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kurye Ana Ekranı'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.payments_outlined),
            tooltip: 'Kazançlarım',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CourierEarningsScreen(
                  courierId: widget.courierId,
                ),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Teslimat Geçmişi',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CourierDeliveryHistoryScreen(
                  courierId: widget.courierId,
                ),
              ));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Yükleniyor...')
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (_message != null) ...[
                      Text(_message!,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.error)),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    _buildShiftCard(),
                    const SizedBox(height: AppSpacing.md),
                    if (_shift?.status == CourierShiftStatus.active)
                      _buildAvailabilityCard(),
                    const SizedBox(height: AppSpacing.md),
                    if ((_activeDeliveries ?? const []).isNotEmpty)
                      _buildActiveDeliveriesCard(),
                  ],
                ),
              ),
      ),
    );
  }

  static const _shiftLabels = {
    CourierShiftStatus.scheduled: 'Planlandı',
    CourierShiftStatus.awaitingManagerApproval: 'Onay Bekliyor',
    CourierShiftStatus.approved: 'Onaylandı',
    CourierShiftStatus.active: 'Aktif',
    CourierShiftStatus.ending: 'Sonlandırılıyor',
    CourierShiftStatus.completed: 'Tamamlandı',
    CourierShiftStatus.rejected: 'Reddedildi',
    CourierShiftStatus.cancelled: 'İptal Edildi',
    CourierShiftStatus.suspended: 'Askıya Alındı',
  };

  Widget _buildShiftCard() {
    final shift = _shift;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Vardiya Durumu', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            shift == null ? 'Aktif vardiya yok' : _shiftLabels[shift.status]!,
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          if (shift == null)
            ElevatedButton(
              onPressed: _requestShift,
              child: const Text('Vardiya Talep Et'),
            )
          else if (shift.status == CourierShiftStatus.approved)
            ElevatedButton(
              onPressed: () => _transitionShift(CourierShiftStatus.active),
              child: const Text('Vardiyayı Başlat'),
            )
          else if (shift.status == CourierShiftStatus.active)
            OutlinedButton(
              onPressed: () => _transitionShift(CourierShiftStatus.ending),
              child: const Text('Vardiyayı Sonlandır'),
            )
          else if (shift.status == CourierShiftStatus.ending)
            ElevatedButton(
              onPressed: (_activeDeliveries ?? const []).isEmpty
                  ? () => _transitionShift(CourierShiftStatus.completed)
                  : null,
              child: Text((_activeDeliveries ?? const []).isEmpty
                  ? 'Vardiyayı Tamamla'
                  : 'Aktif teslimatlar bitmeden tamamlanamaz'),
            ),
        ],
      ),
    );
  }

  static const _availabilityLabels = {
    CourierAvailabilityStatus.online: 'Çevrimiçi',
    CourierAvailabilityStatus.offline: 'Çevrimdışı',
    CourierAvailabilityStatus.available: 'Müsait',
    CourierAvailabilityStatus.temporarilyUnavailable: 'Geçici Müsait Değil',
    CourierAvailabilityStatus.busy: 'Meşgul',
    CourierAvailabilityStatus.paused: 'Duraklatıldı',
    CourierAvailabilityStatus.suspended: 'Askıya Alındı',
  };

  Widget _buildAvailabilityCard() {
    final availability = _availability;
    final isAvailable =
        availability?.status == CourierAvailabilityStatus.available;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Müsaitlik', style: AppTypography.titleMedium),
              Text(
                availability == null
                    ? 'Çevrimdışı'
                    : _availabilityLabels[availability.status]!,
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          Switch(
            value: isAvailable,
            onChanged: (value) => _setAvailability(value
                ? CourierAvailabilityStatus.available
                : CourierAvailabilityStatus.offline),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveDeliveriesCard() {
    final deliveries = _activeDeliveries ?? const <Delivery>[];
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Aktif Teslimatlar', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final delivery in deliveries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Teslimat #${delivery.id}'),
              subtitle: Text(delivery.status.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ActiveDeliveryScreen(
                    deliveryId: delivery.id,
                    courierId: widget.courierId,
                    deviceId: widget.deviceId,
                  ),
                ));
              },
            ),
        ],
      ),
    );
  }
}
