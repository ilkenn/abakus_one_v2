import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/loyalty_history_entry.dart';

/// P3A (2026-08-23) — the Turkish label mapping for each closed
/// `LoyaltyLedgerEntryType`, kept as pure functions (not inlined in the
/// widget) so both the widget and a unit test can exercise every entry
/// type directly. Deliberately client-owned copy — the backend
/// (`getCustomerLoyaltyHistory.ts`) returns only the machine-stable enum
/// value, never localized text.
///
/// Only [LoyaltyLedgerEntryType.orderEarn] can appear in a real result
/// today (no writer exists yet for any other type) — every other branch is
/// forward-compatible mapping, not evidence those events currently occur.
String loyaltyHistoryEntryTitle(LoyaltyLedgerEntryType type) {
  return switch (type) {
    LoyaltyLedgerEntryType.orderEarn => 'Siparişten Boncuk kazandın',
    LoyaltyLedgerEntryType.orderEarnReversal =>
      'Sipariş iadesi nedeniyle Boncuk düzeltmesi',
    LoyaltyLedgerEntryType.boncukRedemption => 'Boncuk harcadın',
    LoyaltyLedgerEntryType.boncukRedemptionRestore =>
      'Harcanan Boncuk iade edildi',
    LoyaltyLedgerEntryType.catalogRedemption => 'Ödül için Boncuk kullandın',
    LoyaltyLedgerEntryType.catalogRedemptionRestore =>
      'Ödül Boncuk\'u iade edildi',
    LoyaltyLedgerEntryType.wheelEarn => 'Çarktan Boncuk kazandın',
    LoyaltyLedgerEntryType.wheelExpiry => 'Çark Boncuk\'unun süresi doldu',
    LoyaltyLedgerEntryType.taskEarn => 'Görevden Boncuk kazandın',
    LoyaltyLedgerEntryType.taskReversal => 'Görev Boncuk\'u geri alındı',
    LoyaltyLedgerEntryType.adminAdjustment => 'Hesabında düzenleme yapıldı',
    LoyaltyLedgerEntryType.unknown => 'Boncuk hareketi',
  };
}

/// The debt-aware second line — only non-null when [entry.debtAppliedBoncuk]
/// is meaningful (`> 0`), per the locked "do not lie about where new
/// Boncuk went" requirement. Never raw accounting jargon.
String? loyaltyHistoryEntrySubtitle(LoyaltyHistoryEntry entry) {
  if (entry.debtAppliedBoncuk <= 0) return null;
  return '${entry.debtAppliedBoncuk} Boncuk önceki iade bakiyene uygulandı';
}

String formatLoyaltyHistoryDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.'
      '${local.year}';
}

/// One row in the Boncuk Movements list — used both by the main
/// Boncuklarım screen's recent-movements preview and the full paginated
/// history screen, so the two never visually diverge.
class LoyaltyHistoryTile extends StatelessWidget {
  const LoyaltyHistoryTile({super.key, required this.entry});

  final LoyaltyHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final isPositive = entry.displayBoncukDelta >= 0;
    final amountColor = isPositive ? AppColors.success : AppColors.error;
    final amountText =
        '${isPositive ? '+' : ''}${entry.displayBoncukDelta} Boncuk';
    final subtitle = loyaltyHistoryEntrySubtitle(entry);
    final title = loyaltyHistoryEntryTitle(entry.type);
    final dateText = formatLoyaltyHistoryDate(entry.occurredAt);

    return Semantics(
      label: '$title, $amountText, $dateText'
          '${subtitle != null ? ', $subtitle' : ''}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateText,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            ExcludeSemantics(
              child: Text(
                amountText,
                style: AppTypography.bodyLarge.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
