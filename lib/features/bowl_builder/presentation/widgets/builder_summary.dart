import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_constants.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../menu/domain/models/selected_modifier.dart';

/// Final review step: every selected ingredient grouped by category, the
/// bowl's order-quantity stepper, an optional order note, and the dynamic
/// total price. There is no starting price (product decision, 2026-07-23) —
/// an empty selection prices at 0 TL, and this screen says so plainly
/// rather than implying a base charge that no longer exists.
class BuilderSummary extends StatelessWidget {
  final List<SelectedModifier> selectedModifiers;
  final double grandTotal;
  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final TextEditingController noteController;
  final ValueChanged<String> onNoteChanged;

  const BuilderSummary({
    super.key,
    required this.selectedModifiers,
    required this.grandTotal,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
    required this.noteController,
    required this.onNoteChanged,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, List<SelectedModifier>> byGroup = {};
    for (final modifier in selectedModifiers) {
      byGroup.putIfAbsent(modifier.groupName, () => []).add(modifier);
    }
    final unitPrice =
        selectedModifiers.fold(0.0, (sum, m) => sum + m.extraPrice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bowl Özeti',
          style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (byGroup.isEmpty)
                const Text(
                  'Henüz malzeme seçmedin — sepete eklemeden önce önceki adımlara dönebilirsin.',
                  style: AppTypography.bodyMedium,
                )
              else
                for (final entry in byGroup.entries) ...[
                  Text(
                    entry.key,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _describeSelections(entry.value),
                    style: AppTypography.bodyLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              const Divider(),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Adet', style: AppTypography.titleMedium),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: AppRadius.kPill,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: onDecrement,
                          icon: const Icon(Icons.remove_rounded),
                          color: AppColors.textSecondary,
                          constraints: const BoxConstraints(
                            minWidth: AppThemeConstants.minTapTargetSize,
                            minHeight: AppThemeConstants.minTapTargetSize,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: Text('$quantity',
                              style: AppTypography.titleMedium),
                        ),
                        IconButton(
                          onPressed: onIncrement,
                          icon: const Icon(Icons.add_rounded),
                          color: AppColors.primary,
                          constraints: const BoxConstraints(
                            minWidth: AppThemeConstants.minTapTargetSize,
                            minHeight: AppThemeConstants.minTapTargetSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Sipariş Notu',
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: noteController,
                onChanged: onNoteChanged,
                maxLength: 200,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Bowlunla ilgili bir not ekle...',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Divider(),
              const SizedBox(height: AppSpacing.sm),
              if (quantity > 1) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Birim fiyat',
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    Text(
                      '${unitPrice.toStringAsFixed(0)} TL',
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Toplam',
                    style: AppTypography.titleMedium
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${grandTotal.toStringAsFixed(0)} TL',
                    style: AppTypography.priceLarge,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Renders a category's selections as "Izgara Tavuk × 3, Kinoa" — a
  /// quantity-N ingredient (Proteinler/Karbonhidratlar) arrives here as N
  /// separate [SelectedModifier] entries sharing the same `optionName` (see
  /// `bowlBuilderSelectedModifiersProvider`); this collapses those into one
  /// "× N" mention instead of repeating the name N times.
  String _describeSelections(List<SelectedModifier> modifiers) {
    final countByName = <String, int>{};
    final order = <String>[];
    for (final modifier in modifiers) {
      if (!countByName.containsKey(modifier.optionName)) {
        order.add(modifier.optionName);
      }
      countByName[modifier.optionName] =
          (countByName[modifier.optionName] ?? 0) + 1;
    }
    return order
        .map((name) =>
            countByName[name]! > 1 ? '$name × ${countByName[name]}' : name)
        .join(', ');
  }
}
