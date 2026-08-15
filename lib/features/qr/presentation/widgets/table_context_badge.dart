import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/active_table_context_provider.dart';

/// Compact, single-line "you are ordering at this table" indicator —
/// structurally the same shape as `ActiveOrderBanner` (a small pill row,
/// conditional render, no card chrome), shown wherever the customer needs
/// a persistent reminder of the active table without it eating screen
/// space: [MenuScreen]'s title area, [CartScreen]'s top.
///
/// Renders nothing when [activeTableContextProvider] is `null` — every
/// call site can drop this in unconditionally, immediately after whatever
/// it sits below, with no extra spacing to account for either way (the
/// visible pill carries its own top margin; the invisible
/// [SizedBox.shrink] carries none).
class TableContextBadge extends ConsumerWidget {
  const TableContextBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tableContext = ref.watch(activeTableContextProvider);
    if (tableContext == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: const BoxDecoration(
          color: AppColors.primaryExtraLight,
          borderRadius: AppRadius.kPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.table_restaurant_rounded,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                '${tableContext.branchName} · ${tableContext.tableName}',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
