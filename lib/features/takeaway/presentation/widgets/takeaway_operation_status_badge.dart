import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/branch_takeaway_settings.dart';
import '../providers/takeaway_operations_dependencies_provider.dart';
import 'takeaway_mode_change_dialog.dart';

/// AP-6 Sprint 1 — pure-presentational takeaway-mode pill: Aktif
/// ([AppColors.success]) / Yoğun +Ndk ([AppColors.warning]) / Kapalı
/// ([AppColors.error]). Design-token colors/typography/spacing only (§6).
class TakeawayOperationStatusBadge extends StatelessWidget {
  const TakeawayOperationStatusBadge({
    super.key,
    required this.status,
    this.busyDelayMinutes = 0,
    this.onTap,
  });

  final TakeawayOperationStatus status;
  final int busyDelayMinutes;
  final VoidCallback? onTap;

  Color get _color {
    switch (status) {
      case TakeawayOperationStatus.active:
        return AppColors.success;
      case TakeawayOperationStatus.busy:
        return AppColors.warning;
      case TakeawayOperationStatus.paused:
        return AppColors.error;
    }
  }

  String get _label {
    switch (status) {
      case TakeawayOperationStatus.active:
        return 'Aktif';
      case TakeawayOperationStatus.busy:
        return busyDelayMinutes > 0 ? 'Yoğun (+$busyDelayMinutes dk)' : 'Yoğun';
      case TakeawayOperationStatus.paused:
        return 'Kapalı';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.kPill,
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            _label,
            style: AppTypography.labelLarge.copyWith(color: color),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: 'Paket servis durumu: $_label. Değiştirmek için dokunun.',
      child: InkWell(
        borderRadius: AppRadius.kPill,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// The live, staff-facing takeaway-mode control: watches
/// [branchTakeawaySettingsProvider], renders [TakeawayOperationStatusBadge],
/// and opens [TakeawayModeChangeDialog] on tap. The one widget a POS/admin
/// screen header actually mounts — [TakeawayOperationStatusBadge] itself
/// stays provider-free/pure so it's independently testable.
class TakeawayOperationStatusControl extends ConsumerWidget {
  const TakeawayOperationStatusControl({
    super.key,
    required this.organizationId,
    required this.branchId,
  });

  final String organizationId;
  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(branchTakeawaySettingsProvider(branchId));
    final settings = settingsAsync.valueOrNull;
    final status = settings?.status ?? TakeawayOperationStatus.active;
    final busyDelayMinutes = settings?.busyDelayMinutes ?? 0;

    return TakeawayOperationStatusBadge(
      status: status,
      busyDelayMinutes: busyDelayMinutes,
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => TakeawayModeChangeDialog(
          organizationId: organizationId,
          branchId: branchId,
          currentStatus: status,
          currentBusyDelayMinutes: busyDelayMinutes,
        ),
      ),
    );
  }
}
