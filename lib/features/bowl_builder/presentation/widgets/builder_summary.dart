import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_constants.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../menu/domain/models/selected_modifier.dart';
import '../../domain/models/bowl_builder_category.dart';
import '../providers/bowl_builder_provider.dart';

/// Final review step ("Bowlu Hazır 🎉") — B.3 (2026-08-18) information-
/// focused redesign, replacing the previous live `BowlCanvas` bowl
/// preview (product decision: the visual preview is cancelled entirely,
/// not deferred). Top to bottom: one macro summary card (price/kcal/
/// protein/fat/carbs), an allergen section, selected ingredients grouped
/// by category, then the order-quantity stepper and note. There is no
/// starting price (product decision, 2026-07-23) — an empty selection
/// prices at 0 TL, and this screen says so plainly rather than implying a
/// base charge that no longer exists.
///
/// [categories] is the catalog's own category list, in its canonical
/// display order — used only to group/label [selectedModifiers] for
/// display (and, for the one category with a customer-facing override —
/// "Ekstralar" vs. the catalog's internal "Diğerleri" — to show the
/// correct label; `SelectedModifier.groupName` itself is left exactly as
/// `bowlBuilderSelectedModifiersProvider` computes it, since that value
/// also flows into cart/order persistence and this task's scope is
/// display-only).
class BuilderSummary extends StatelessWidget {
  final List<SelectedModifier> selectedModifiers;
  final List<BowlBuilderCategory> categories;
  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final TextEditingController noteController;
  final ValueChanged<String> onNoteChanged;
  final VoidCallback onEditSelections;

  const BuilderSummary({
    super.key,
    required this.selectedModifiers,
    required this.categories,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
    required this.noteController,
    required this.onNoteChanged,
    required this.onEditSelections,
  });

  @override
  Widget build(BuildContext context) {
    final groups = _groupSelectionsByCategory(selectedModifiers, categories);
    final unitPrice =
        selectedModifiers.fold(0.0, (sum, m) => sum + m.extraPrice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // B.3.4: "Seçimleri Düzenle" is the one visible way back into
        // ingredient picking from this screen — a secondary TextButton
        // (not styled as a primary CTA) next to the heading. Both the
        // title and the button are flexible (Expanded/Flexible) so at
        // large accessibility text scale each gives ground and ellipsizes
        // instead of forcing a RenderFlex overflow — same guard already
        // used for the picking-mode action bar's stat-chips-plus-button
        // row in `bowl_builder_action_bar.dart`.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Sipariş Özeti',
                style: AppTypography.titleLarge
                    .copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(
              child: TextButton(
                key: const Key('editSelectionsButton'),
                onPressed: onEditSelections,
                child: const Text(
                  'Seçimleri Düzenle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // Macro summary — the one aggregate nutrition/price card on this
        // screen (locked: no second one elsewhere here).
        const _MacroSummaryCard(),
        const SizedBox(height: AppSpacing.md),
        // Allergens — see class-level note in `_AllergenSection` for why
        // this always shows the "data unknown" state today, never a
        // "no allergens" claim.
        const _AllergenSection(),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seçilen Malzemeler',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'Henüz malzeme seçmedin — sepete eklemeden önce '
                    'önceki adımlara dönebilirsin.',
                    style: AppTypography.bodyMedium,
                  ),
                )
              else
                for (final group in groups) ...[
                  Text(
                    group.categoryLabel,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (final row in group.rows) _SelectedIngredientLine(row),
                  const SizedBox(height: AppSpacing.sm),
                ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(
                    child: Text('Adet', style: AppTypography.titleMedium),
                  ),
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
                          tooltip: 'Adet azalt',
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
                          tooltip: 'Adet arttır',
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
              // B.3.2: the standalone "Toplam" row is gone — the same
              // price already leads the macro summary card above and
              // anchors the bottom "Sepete Ekle" CTA below, so a third
              // copy here was pure duplication. "Birim fiyat" stays: at
              // quantity > 1 it's genuinely different information (the
              // per-bowl price), not a restatement of the total.
              if (quantity > 1) ...[
                const SizedBox(height: AppSpacing.sm),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Birim fiyat',
                        style: AppTypography.bodyMedium
                            .copyWith(color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${unitPrice.toStringAsFixed(0)} TL',
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One category's selected ingredients, already deduplicated/counted and
/// labeled for display.
class _SelectionGroup {
  final String categoryLabel;
  final List<_SelectedIngredientRow> rows;

  const _SelectionGroup({required this.categoryLabel, required this.rows});
}

class _SelectedIngredientRow {
  final String name;
  final int quantity;
  final double unitPrice;

  const _SelectedIngredientRow({
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });
}

/// Groups [selectedModifiers] by [BowlBuilderCategory.id] (via
/// `SelectedModifier.groupId`, which already equals the ingredient's
/// `categoryId`), in the catalog's own canonical category order — not
/// insertion/selection order — and collapses a quantity-N ingredient
/// (which arrives as N separate same-`optionName` entries, see
/// `bowlBuilderSelectedModifiersProvider`) into one row carrying that
/// count. Categories with no selections are simply absent from the
/// result, never rendered as an empty section.
List<_SelectionGroup> _groupSelectionsByCategory(
  List<SelectedModifier> selectedModifiers,
  List<BowlBuilderCategory> categories,
) {
  final byCategoryId = <String, List<SelectedModifier>>{};
  for (final modifier in selectedModifiers) {
    byCategoryId.putIfAbsent(modifier.groupId, () => []).add(modifier);
  }

  final groups = <_SelectionGroup>[];
  for (final category in categories) {
    final modifiers = byCategoryId[category.id];
    if (modifiers == null || modifiers.isEmpty) continue;

    final order = <String>[];
    final countByName = <String, int>{};
    final priceByName = <String, double>{};
    for (final modifier in modifiers) {
      if (!countByName.containsKey(modifier.optionName)) {
        order.add(modifier.optionName);
        priceByName[modifier.optionName] = modifier.extraPrice;
      }
      countByName[modifier.optionName] =
          (countByName[modifier.optionName] ?? 0) + 1;
    }

    groups.add(
      _SelectionGroup(
        categoryLabel: category.displayName ?? category.name,
        rows: [
          for (final name in order)
            _SelectedIngredientRow(
              name: name,
              quantity: countByName[name]!,
              unitPrice: priceByName[name]!,
            ),
        ],
      ),
    );
  }
  return groups;
}

/// One selected-ingredient line: name (+ "× N" once quantity > 1) on the
/// left, that line's total surcharge on the right when it's non-zero.
/// Deliberately no nutrition figures here — the macro card above already
/// owns the aggregate, and repeating per-ingredient kcal/protein/fat/carbs
/// would just be noise at this level of the review.
class _SelectedIngredientLine extends StatelessWidget {
  final _SelectedIngredientRow row;

  const _SelectedIngredientLine(this.row);

  @override
  Widget build(BuildContext context) {
    final lineTotal = row.unitPrice * row.quantity;
    final label = row.quantity > 1 ? '${row.name} × ${row.quantity}' : row.name;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyLarge,
            ),
          ),
          if (lineTotal > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              '+${lineTotal.toStringAsFixed(0)} TL',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The one macro summary card on the review screen — Fiyat/Kalori/
/// Protein/Yağ/Karbonhidrat, all sourced directly from
/// `bowl_builder_provider.dart`'s derived providers (no local math).
/// Deliberately omits an ingredient count (unlike the picking-step-era
/// `BowlBuilderLiveMetrics`, now unused/orphaned — see
/// `bowl_builder_screen.dart`'s class doc comment) since "Seçilen
/// Malzemeler" below already lists every selection individually.
class _MacroSummaryCard extends ConsumerWidget {
  const _MacroSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grandTotal = ref.watch(bowlBuilderGrandTotalProvider);
    final calories = ref.watch(bowlBuilderTotalCaloriesProvider);
    final protein = ref.watch(bowlBuilderTotalProteinProvider);
    final fat = ref.watch(bowlBuilderTotalFatProvider);
    final carbs = ref.watch(bowlBuilderTotalCarbsProvider);

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              label: 'Fiyat',
              value: '${grandTotal.toStringAsFixed(0)} TL',
              emphasize: true,
            ),
          ),
          _divider(),
          Expanded(
            child: _Metric(
              label: 'Kalori',
              value: '${calories.toStringAsFixed(0)} kcal',
            ),
          ),
          _divider(),
          Expanded(
            child: _Metric(
              label: 'Protein',
              value: '${protein.toStringAsFixed(0)} g',
            ),
          ),
          _divider(),
          Expanded(
            child: _Metric(label: 'Yağ', value: '${fat.toStringAsFixed(0)} g'),
          ),
          _divider(),
          Expanded(
            child: _Metric(
              label: 'Karbonhidrat',
              value: '${carbs.toStringAsFixed(0)} g',
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        color: AppColors.border,
      );
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _Metric({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    // B.4: a single combined Semantics node ("Fiyat: 120 TL", label before
    // value — the natural reading order, reversed from the visual layout
    // below) instead of two separate unlabeled text nodes, so a screen
    // reader states what each number means rather than just reading two
    // bare strings in visual (value-then-label) order.
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: (emphasize
                    ? AppTypography.titleMedium
                    : AppTypography.labelLarge)
                .copyWith(
              fontWeight: FontWeight.bold,
              color: emphasize ? AppColors.primary : AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// The "Alerjenler" section — deliberately reads from real selected-
/// ingredient data only, never infers from a name and never fabricates a
/// value.
///
/// `BowlBuilderIngredient` (the Bowl Builder catalog's own ingredient
/// model) carries no `allergens` field today — there is no existing
/// Bowl-Builder-specific allergen data anywhere to derive from. Critically,
/// this means the model cannot today distinguish "we checked this
/// ingredient and it has no declared allergens" (CONFIRMED_NONE) from "no
/// one has ever recorded allergen data for it" (UNKNOWN) — those are not
/// the same claim, and showing a reassuring "no allergens" message for the
/// second case would be a safety-relevant false confidence, not just an
/// empty-state nicety (B.3.1 correction, 2026-08-18). So
/// [_aggregateAllergens] always reports `isKnown: false` right now, and
/// the UI below always shows the neutral "data not available yet" copy —
/// never "no allergens" — until a real source can actually make that
/// distinction.
///
/// A real, separate ingredient-allergen-declaration system exists
/// (`features/allergens/`, Phase 7/ADR-024), but nothing in this codebase
/// links a Bowl Builder ingredient id to it yet — wiring that is a data-
/// model/integration decision outside this task's scope, so it wasn't
/// made silently here. The aggregation/dedup/rendering logic below is
/// written for real per-ingredient allergen data regardless, so wiring a
/// real source later (including a genuine CONFIRMED_NONE state) is a
/// data-plumbing change, not a redesign of this widget.
class _AllergenSection extends ConsumerWidget {
  const _AllergenSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedModifiers = ref.watch(bowlBuilderSelectedModifiersProvider);
    final allergens = _aggregateAllergens(selectedModifiers);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alerjenler',
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!allergens.isKnown) ...[
            Text(
              'Alerjen bilgisi henüz mevcut değil',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'İçerik ve alerjen bilgileri tamamlandığında burada '
              'gösterilecek.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ] else if (allergens.labels.isEmpty)
            // Only reachable once a real source can distinguish
            // CONFIRMED_NONE from UNKNOWN — not reachable today.
            Text(
              'Bilinen alerjen bulunmuyor',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final label in allergens.labels) _AllergenChip(label),
              ],
            ),
        ],
      ),
    );
  }
}

/// [isKnown] is `false` whenever no data source exists to check
/// allergens at all — a different claim from "checked, and there are
/// none" ([isKnown] `true` with an empty [labels]). See
/// `_AllergenSection`'s class doc comment.
class _AllergenAggregationResult {
  final bool isKnown;
  final List<String> labels;

  const _AllergenAggregationResult({
    required this.isKnown,
    required this.labels,
  });
}

/// Deduplicated, sorted allergen labels declared on the selected
/// ingredients, plus whether that data is actually available at all —
/// currently always `isKnown: false`; see `_AllergenSection`'s class doc
/// comment for exactly why.
_AllergenAggregationResult _aggregateAllergens(
  List<SelectedModifier> selected,
) {
  // No `allergens` field exists on `BowlBuilderIngredient`/
  // `SelectedModifier` yet, so there is nothing to iterate and no way to
  // claim this data is known — this deliberately doesn't loop over
  // `selected` today. Left as a named, real (if currently trivial)
  // aggregation step rather than inlining the unknown state at the call
  // site, so the one place that needs to change when real allergen data
  // exists is this function.
  return const _AllergenAggregationResult(isKnown: false, labels: []);
}

class _AllergenChip extends StatelessWidget {
  final String label;

  const _AllergenChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.kPill,
      ),
      child: Text(
        label,
        style: AppTypography.labelLarge.copyWith(
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
