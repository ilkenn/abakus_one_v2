import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/takeaway_operations_dependencies_provider.dart';

/// AP-6 Sprint 1 — pure-presentational pending-scheduled-order count chip.
/// Renders nothing at all when [count] is `0` — the spec's own explicit
/// "shows count only when non-zero" requirement, never a bare "0".
class ScheduledOrdersCountBadge extends StatelessWidget {
  const ScheduledOrdersCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Semantics(
      label: '$count bekleyen ileri saatli sipariş',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: AppRadius.kPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule_rounded, size: 14, color: AppColors.onPrimary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$count',
              style: AppTypography.labelLarge.copyWith(color: AppColors.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Watches [scheduledOrdersCountProvider] and renders
/// [ScheduledOrdersCountBadge] — the widget a POS/admin screen header
/// actually mounts.
class ScheduledOrdersCountIndicator extends ConsumerWidget {
  const ScheduledOrdersCountIndicator({super.key, required this.branchId});

  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(scheduledOrdersCountProvider(branchId));
    return ScheduledOrdersCountBadge(count: countAsync.valueOrNull ?? 0);
  }
}
