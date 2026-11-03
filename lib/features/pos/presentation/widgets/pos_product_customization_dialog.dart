import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/option_selection_card.dart';
import '../../../../shared/widgets/images/product_image.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/domain/models/modifier_group.dart';
import '../../../menu/domain/models/product_nutrition.dart';
import '../../../menu/domain/models/selected_modifier.dart';
import '../../../menu/domain/services/allergen_icons.dart';
import '../../../menu/domain/services/modifier_option_image_resolver.dart';

/// What the staff confirmed in [PosProductCustomizationDialog] — the
/// caller (`PosTableWorkspaceScreen`) is the one place that turns this
/// into a `_StaffEntryCartLine`; this dialog never touches cart state
/// itself.
class PosProductCustomizationResult {
  const PosProductCustomizationResult({
    required this.quantity,
    required this.selectedModifiers,
    required this.excludedIngredients,
    required this.note,
  });

  final int quantity;
  final List<SelectedModifier> selectedModifiers;
  final List<String> excludedIngredients;
  final String note;
}

/// Touch-POS product customization modal — opened for any product with at
/// least one `ModifierGroup` (Bowl, Burger/Wrap, and anything else the
/// catalog attaches modifiers to). Mirrors `ProductDetailScreen`'s
/// selection/validation rules (same `ModifierGroup.isSatisfiedBy`, same
/// "İçinden Çıkar" removable-ingredients section, same default-option
/// preselection) but as a POS-sized two-pane dialog rather than a
/// full-screen push — staff never leaves the table workspace to configure
/// a line.
class PosProductCustomizationDialog extends StatefulWidget {
  const PosProductCustomizationDialog({super.key, required this.product});

  final MenuProduct product;

  static Future<PosProductCustomizationResult?> show(
    BuildContext context,
    MenuProduct product,
  ) {
    return showDialog<PosProductCustomizationResult>(
      context: context,
      builder: (_) => PosProductCustomizationDialog(product: product),
    );
  }

  @override
  State<PosProductCustomizationDialog> createState() =>
      _PosProductCustomizationDialogState();
}

class _PosProductCustomizationDialogState
    extends State<PosProductCustomizationDialog> {
  int _quantity = 1;
  final Map<String, List<String>> _selections = {};
  final Set<String> _excludedIngredients = {};
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    for (final group in widget.product.modifierGroups) {
      final defaults =
          group.options.where((o) => o.isDefault).map((o) => o.id).toList();
      if (defaults.isNotEmpty) _selections[group.id] = defaults;
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _selectSingle(ModifierGroup group, String optionId) {
    HapticFeedback.selectionClick();
    setState(() {
      final current = _selections[group.id] ?? const [];
      _selections[group.id] = (current.length == 1 && current.first == optionId)
          ? const []
          : [optionId];
    });
  }

  void _toggleMultiple(ModifierGroup group, String optionId) {
    final current = List<String>.from(_selections[group.id] ?? const []);
    if (!current.contains(optionId) && current.length >= group.maxSelections) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      if (current.contains(optionId)) {
        current.remove(optionId);
      } else {
        current.add(optionId);
      }
      _selections[group.id] = current;
    });
  }

  void _toggleExcludedIngredient(String ingredient) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_excludedIngredients.remove(ingredient)) {
        _excludedIngredients.add(ingredient);
      }
    });
  }

  bool get _allGroupsValid => widget.product.modifierGroups
      .every((group) => group.isSatisfiedBy(_selections[group.id] ?? const []));

  List<SelectedModifier> get _selectedModifiers {
    final result = <SelectedModifier>[];
    for (final group in widget.product.modifierGroups) {
      final selectedIds = _selections[group.id] ?? const [];
      for (final option in group.options) {
        if (selectedIds.contains(option.id)) {
          result.add(SelectedModifier(
            groupId: group.id,
            groupName: group.name,
            optionId: option.id,
            optionName: option.name,
            extraPrice: option.extraPrice,
          ));
        }
      }
    }
    return result;
  }

  double get _unitPrice =>
      widget.product.basePrice +
      _selectedModifiers.fold(0.0, (sum, m) => sum + m.extraPrice);

  double get _totalPrice => _unitPrice * _quantity;

  void _confirm() {
    if (!_allGroupsValid) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(PosProductCustomizationResult(
      quantity: _quantity,
      selectedModifiers: _selectedModifiers,
      excludedIngredients: _excludedIngredients.toList(),
      note: _noteController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final nutrition = product.nutrition;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.kLarge),
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: SizedBox(
        width: 880,
        height: 620,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: AppRadius.kMedium,
                              child: ProductImage(
                                imageKey: product.imageKey,
                                categoryId: product.categoryId,
                                width: double.infinity,
                                height: 150,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(product.name, style: AppTypography.titleLarge),
                            const SizedBox(height: AppSpacing.xs),
                            Text('${product.basePrice.toStringAsFixed(0)} TL',
                                style: AppTypography.priceLarge),
                            if ((nutrition != null && nutrition.hasAnyValue) ||
                                product.allergens.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.sm),
                              PosNutritionAllergenBadge(
                                nutrition: nutrition,
                                allergens: product.allergens,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                const Text('Adet',
                                    style: AppTypography.titleMedium),
                                const Spacer(),
                                IconButton(
                                  onPressed: _quantity > 1
                                      ? () => setState(() => _quantity--)
                                      : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                Text('$_quantity',
                                    style: AppTypography.titleMedium),
                                IconButton(
                                  onPressed: () => setState(() => _quantity++),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: AppSpacing.xs,
                              children: [
                                for (final n in const [1, 2, 3, 4, 5])
                                  ChoiceChip(
                                    label: Text('$n'),
                                    selected: _quantity == n,
                                    onSelected: (_) =>
                                        setState(() => _quantity = n),
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            const Text('Sipariş Notu',
                                style: AppTypography.titleMedium),
                            const SizedBox(height: AppSpacing.xs),
                            TextField(
                              controller: _noteController,
                              maxLength: 200,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                hintText: 'Örn: Sosu ayrı olsun',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _allGroupsValid ? _confirm : null,
                        child: Text(
                            'Kaydet (${_totalPrice.toStringAsFixed(0)} TL)'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1, color: AppColors.border),
            Expanded(
              flex: 5,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (product.removableIngredients.isNotEmpty) ...[
                    const Text('İçinden Çıkar',
                        style: AppTypography.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    for (final ingredient in product.removableIngredients)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: OptionSelectionCard(
                          name: '$ingredient İstemiyorum',
                          extraPrice: 0,
                          isSelected: _excludedIngredients.contains(ingredient),
                          onTap: () => _toggleExcludedIngredient(ingredient),
                        ),
                      ),
                    const Divider(height: AppSpacing.xl),
                  ],
                  for (final group in product.modifierGroups) ...[
                    Text(group.name, style: AppTypography.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    for (final option in group.options)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: OptionSelectionCard(
                          name: option.name,
                          extraPrice: option.extraPrice,
                          isSelected: (_selections[group.id] ?? const [])
                              .contains(option.id),
                          imageKey: ModifierOptionImageResolver.imageKeyFor(
                              option.id),
                          onTap: () {
                            if (group.selectionType ==
                                ModifierSelectionType.single) {
                              _selectSingle(group, option.id);
                            } else {
                              _toggleMultiple(group, option.id);
                            }
                          },
                        ),
                      ),
                    const Divider(height: AppSpacing.xl),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "🔥 560 kcal" + one pictogram per allergen (replacing a generic "⚠️"
/// triangle, product owner 2026-11-03) — shown both on the POS product
/// grid card ([dense]: small icons, no pill background — the card is
/// small) and inside the customization modal ([dense]: false — full
/// pill-chip row, more room). Each allergen icon carries a [Tooltip] with
/// its name, shown on hover/long-press. Renders nothing when [nutrition]
/// has no values and [allergens] is empty, rather than an empty row.
class PosNutritionAllergenBadge extends StatelessWidget {
  const PosNutritionAllergenBadge({
    super.key,
    required this.nutrition,
    this.allergens = const [],
    this.dense = false,
  });

  final ProductNutrition? nutrition;
  final List<String> allergens;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final calories = nutrition?.calories;
    if (calories == null && allergens.isEmpty) return const SizedBox.shrink();

    final iconSize = dense ? 14.0 : 16.0;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (calories != null)
          dense
              ? Text(
                  '🔥 $calories kcal',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : _badge(Text('🔥 $calories kcal', style: _badgeTextStyle)),
        for (final allergen in allergens)
          Tooltip(
            message: allergen,
            child: dense
                ? Icon(AllergenIcons.iconFor(allergen),
                    size: iconSize, color: AppColors.textSecondary)
                : _badge(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AllergenIcons.iconFor(allergen),
                          size: iconSize, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(allergen, style: _badgeTextStyle),
                    ],
                  )),
          ),
      ],
    );
  }

  static const TextStyle _badgeTextStyle =
      TextStyle(fontSize: 12, color: AppColors.textSecondary);

  Widget _badge(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.kPill,
      ),
      child: child,
    );
  }
}
