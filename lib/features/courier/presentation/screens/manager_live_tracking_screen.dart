import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/availability/courier_availability_status.dart';
import '../../domain/location/courier_live_status.dart';
import '../../domain/location/movement_state.dart';
import '../../domain/location/signal_quality.dart';
import '../providers/courier_dependencies_provider.dart';

/// Manager-facing live-tracking dashboard — Sprint 5B Part 6/9. Shows
/// every courier eligible for [branchId] via `BuildCourierLiveStatusForBranch`
/// (branch-scoped by construction, see that builder's own doc comment).
///
/// **List-only, no map surface** — deliberately following the exact
/// precedent `CourierDispatchBoardScreen` already set for this feature
/// ("a list-based operational view is acceptable... no advanced map
/// visualization required," Phase 5O). Adding a real map means adding a
/// mapping/geolocation-rendering package (e.g. `google_maps_flutter`),
/// which is its own new-dependency architecture decision — flagged for
/// the user in the Sprint 5B report rather than added silently here.
/// Customer-facing live tracking is explicitly out of scope until a
/// future sprint (Sprint 5C).
class ManagerLiveTrackingScreen extends ConsumerStatefulWidget {
  const ManagerLiveTrackingScreen({super.key, required this.branchId});

  final String branchId;

  @override
  ConsumerState<ManagerLiveTrackingScreen> createState() =>
      _ManagerLiveTrackingScreenState();
}

class _ManagerLiveTrackingScreenState
    extends ConsumerState<ManagerLiveTrackingScreen> {
  List<CourierLiveStatus>? _statuses;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final statuses = await ref.read(buildCourierLiveStatusForBranchProvider)(
        branchId: widget.branchId);
    if (!mounted) return;
    setState(() => _statuses = statuses);
  }

  @override
  Widget build(BuildContext context) {
    final statuses = _statuses;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Canlı Kurye Takibi'),
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
        child: statuses == null
            ? const LoadingView(message: 'Kurye durumları yükleniyor...')
            : statuses.isEmpty
                ? const EmptyView(
                    icon: Icons.pin_drop_outlined,
                    message: 'Bu şubede kayıtlı kurye bulunmuyor.',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: statuses.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, index) =>
                          _CourierLiveStatusCard(status: statuses[index]),
                    ),
                  ),
      ),
    );
  }
}

class _CourierLiveStatusCard extends StatelessWidget {
  const _CourierLiveStatusCard({required this.status});

  final CourierLiveStatus status;

  static String _availabilityLabel(CourierAvailabilityStatus status) {
    switch (status) {
      case CourierAvailabilityStatus.online:
        return 'Çevrimiçi';
      case CourierAvailabilityStatus.offline:
        return 'Çevrimdışı';
      case CourierAvailabilityStatus.available:
        return 'Müsait';
      case CourierAvailabilityStatus.temporarilyUnavailable:
        return 'Geçici Olarak Müsait Değil';
      case CourierAvailabilityStatus.busy:
        return 'Teslimatta';
      case CourierAvailabilityStatus.paused:
        return 'Molada';
      case CourierAvailabilityStatus.suspended:
        return 'Askıya Alındı';
    }
  }

  static String _movementLabel(MovementState? state) {
    switch (state) {
      case null:
        return '—';
      case MovementState.stationary:
        return 'Duruyor';
      case MovementState.walking:
        return 'Yürüyor';
      case MovementState.vehicle:
        return 'Araçla Hareket Halinde';
      case MovementState.approachingTarget:
        return 'Hedefe Yaklaşıyor';
    }
  }

  static Color _signalColor(SignalQuality? quality) {
    switch (quality) {
      case null:
        return AppColors.textSecondary;
      case SignalQuality.good:
        return AppColors.success;
      case SignalQuality.fair:
        return AppColors.warning;
      case SignalQuality.poor:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status.isOnline ? Icons.circle : Icons.circle_outlined,
                size: 12,
                color: status.isOnline ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  status.courierId,
                  style: AppTypography.titleMedium,
                ),
              ),
              Text(
                _availabilityLabel(status.availabilityStatus),
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (status.hasNeverReportedLocation)
            Text(
              'Konum verisi yok',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            )
          else ...[
            Text(
              '${status.latitude!.toStringAsFixed(5)}, '
              '${status.longitude!.toStringAsFixed(5)}',
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                Text(
                  _movementLabel(status.movementState),
                  style: AppTypography.bodySmall,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.signal_cellular_alt,
                        size: 14, color: _signalColor(status.signalQuality)),
                    const SizedBox(width: 4),
                    Text(
                      status.accuracyMeters == null
                          ? '—'
                          : '${status.accuracyMeters!.round()} m doğruluk',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
                if (status.batteryLevelPercent != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.battery_std, size: 14),
                      const SizedBox(width: 4),
                      Text('%${status.batteryLevelPercent}',
                          style: AppTypography.bodySmall),
                    ],
                  ),
              ],
            ),
          ],
          if (status.activeDeliveryId != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Aktif teslimat: ${status.activeDeliveryId}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
