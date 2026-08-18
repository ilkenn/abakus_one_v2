import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// The persistent bottom action area — replaces the old per-step Geri/Devam
/// Et bar. Two modes, matching the same `isSummary` branch the screen
/// already used inline before this was extracted:
///
/// - Picking mode (any category): a compact price/calorie/protein readout
///   plus "Bowlu İncele", which moves to the summary step.
/// - Summary mode: "Sepete Ekle · N TL", which finalizes the order — the
///   only primary action on that step, matching today's behavior.
///
/// B.3.2 (2026-08-18): in summary mode, the CTA is only enabled once
/// [hasSelection] is true — an empty bowl's price is still legitimately
/// 0 TL (product decision, 2026-07-23, unchanged), but a customer should
/// never be able to tap what reads as a live "Sepete Ekle" button while
/// nothing is actually selected. Disabling `onPressed` uses this app's
/// existing `ElevatedButton` disabled-state theme (`disabledBackgroundColor`/
/// `disabledForegroundColor` in `AppTheme`) rather than a bespoke visual
/// treatment.
class BowlBuilderActionBar extends StatelessWidget {
  final bool isSummary;
  final bool hasSelection;
  final double grandTotal;
  final double totalCalories;
  final double totalProtein;
  final VoidCallback onPrimaryAction;

  const BowlBuilderActionBar({
    super.key,
    required this.isSummary,
    required this.hasSelection,
    required this.grandTotal,
    required this.totalCalories,
    required this.totalProtein,
    required this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: isSummary ? _summaryContent() : _pickingContent(),
      ),
    );
  }

  Widget _summaryContent() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: hasSelection ? onPrimaryAction : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        ),
        child: Text(
          'Sepete Ekle · ${grandTotal.toStringAsFixed(0)} TL',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _pickingContent() {
    return Row(
      children: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: _StatChip(
                  value: '${grandTotal.toStringAsFixed(0)} TL',
                  semanticLabel: 'Toplam fiyat',
                  emphasize: true,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: _StatChip(
                  value: '${totalCalories.toStringAsFixed(0)} kcal',
                  semanticLabel: 'Toplam kalori',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: _StatChip(
                  value: '${totalProtein.toStringAsFixed(0)} g protein',
                  semanticLabel: 'Toplam protein',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        // Flexible (not a bare ElevatedButton) so this can shrink at large
        // accessibility text scale instead of forcing a RenderFlex
        // overflow — the stats section above already yields space first,
        // but on very narrow screens the button still needs to be able to
        // give ground too.
        Flexible(
          child: ElevatedButton(
            onPressed: onPrimaryAction,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
            ),
            child: const Text(
              'Bowlu İncele',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String semanticLabel;
  final bool emphasize;

  const _StatChip({
    required this.value,
    required this.semanticLabel,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    // B.4: without this, a screen reader would just read the bare number
    // ("120 TL", "450 kcal", ...) with no indication of which running
    // total it is — the visual order is the only thing that currently
    // conveys that.
    return Semantics(
      label: '$semanticLabel: $value',
      excludeSemantics: true,
      child: Text(
        value,
        style: AppTypography.bodySmall.copyWith(
          fontWeight: FontWeight.bold,
          color: emphasize ? AppColors.primary : AppColors.textSecondary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
