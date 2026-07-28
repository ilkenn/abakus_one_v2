import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../cart/domain/models/cart_item.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/domain/models/selected_modifier.dart';
import '../../../orders/domain/modifiers/modifier_selection_input.dart';
import '../../../orders/domain/modifiers/modifier_validation_result.dart';
import '../../../orders/domain/modifiers/modifier_validator.dart';
import '../../domain/models/pos_order_line_draft.dart';
import '../../domain/models/pos_order_session.dart';
import '../identity/pos_order_line_draft_id_generator.dart';
import 'calculate_pos_order_totals.dart';

/// Adds one [MenuProduct] (with its selected modifiers) as a new line to a
/// [PosOrderSession].
///
/// Every one of [product]'s [MenuProduct.modifierGroups] is validated via
/// [ModifierValidator] against [selectedModifiers] and [session]'s channel
/// before the line is ever added — required/min/max, per-channel
/// availability, and unavailable-option rejection all reuse the exact
/// same domain validator POS and every other channel share. Throws the
/// first [BusinessRuleViolation] `ModifierValidator` reports; the line is
/// never partially added.
///
/// The new line's [PosOrderLineDraft.id] is generated here, via
/// [PosOrderLineDraftIdGenerator] — the UI never generates or sees it, it
/// only calls this use case (Phase 3 Sprint 3C, `docs/decisions.md`
/// ADR-012).
class AddProductToPosOrder {
  const AddProductToPosOrder({
    required Clock clock,
    required PosOrderLineDraftIdGenerator draftIdGenerator,
  })  : _clock = clock,
        _draftIdGenerator = draftIdGenerator,
        _calculateTotals = const CalculatePosOrderTotals();

  final Clock _clock;
  final PosOrderLineDraftIdGenerator _draftIdGenerator;
  final CalculatePosOrderTotals _calculateTotals;

  PosOrderSession call({
    required PosOrderSession session,
    required MenuProduct product,
    List<SelectedModifier> selectedModifiers = const [],
    int quantity = 1,
    String note = '',
  }) {
    if (quantity <= 0) {
      throw NonPositiveQuantityViolation(
        context: 'AddProductToPosOrder.quantity',
        quantity: quantity,
      );
    }

    for (final group in product.modifierGroups) {
      final selectionsForGroup = selectedModifiers
          .where((modifier) => modifier.groupId == group.id)
          .map(
            (modifier) =>
                ModifierSelectionInput(optionId: modifier.optionId, quantity: 1),
          )
          .toList();

      final result = ModifierValidator.validateGroup(
        group: group,
        selections: selectionsForGroup,
        channel: session.channel,
      );
      if (result is ModifierValidationInvalid) {
        throw result.violations.first;
      }
    }

    final item = CartItem(
      id: product.id,
      name: product.name,
      desc: product.description,
      price: product.basePrice,
      quantity: quantity,
      selectedModifiers: selectedModifiers,
      note: note,
    );
    final draft = PosOrderLineDraft(
      id: _draftIdGenerator.nextDraftId(),
      item: item,
    );

    final updated = session.copyWith(
      lines: [...session.lines, draft],
      lastUpdatedAt: _clock.now(),
    );
    return updated.copyWith(pricing: _calculateTotals(updated));
  }
}
