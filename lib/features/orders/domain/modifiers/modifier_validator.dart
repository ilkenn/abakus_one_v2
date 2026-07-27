import '../../../../core/errors/business_rule_violation.dart';
import '../../../menu/domain/models/modifier_group.dart';
import '../../../menu/domain/models/modifier_option.dart';
import '../models/order_channel.dart';
import 'modifier_selection_input.dart';
import 'modifier_validation_result.dart';

/// Validates a set of candidate modifier selections against one
/// [ModifierGroup]'s required/min/max, per-channel visibility, and
/// per-option availability rules — the domain-level gate a POS/cart-to-
/// order boundary runs selections through before they're allowed to become
/// frozen [OrderLineModifierSelection]s.
///
/// **Quantity-aware**: [minSelections]/[maxSelections] are checked against
/// the *sum of selected quantities*, not the count of distinct options —
/// selecting "extra cheese ×2" counts as 2 toward a group's max, the same
/// as selecting two different options once each. Every existing modifier
/// dataset naturally has quantity `1` per selection (see
/// `CartToOrderMapper`), so this is strictly additive: it changes nothing
/// for data that never uses quantity > 1.
abstract final class ModifierValidator {
  ModifierValidator._();

  static ModifierValidationResult validateGroup({
    required ModifierGroup group,
    required List<ModifierSelectionInput> selections,
    required OrderChannel channel,
  }) {
    final violations = <BusinessRuleViolation>[];

    if (!group.visibleChannels.contains(channel)) {
      violations.add(
        ModifierGroupUnavailableInChannelViolation(
          groupId: group.id,
          channelName: channel.name,
        ),
      );
      // A group that isn't even visible on this channel can't be
      // meaningfully checked further (required/min/max/availability all
      // presuppose the group is actually offered here).
      return ModifierValidationInvalid(violations);
    }

    for (final selection in selections) {
      if (selection.quantity <= 0) {
        violations.add(
          InvalidModifierQuantityViolation(
            optionId: selection.optionId,
            quantity: selection.quantity,
          ),
        );
        continue;
      }
      ModifierOption? option;
      for (final candidate in group.options) {
        if (candidate.id == selection.optionId) {
          option = candidate;
          break;
        }
      }
      if (option == null) {
        violations.add(
          UnknownModifierOptionViolation(
            groupId: group.id,
            optionId: selection.optionId,
          ),
        );
        continue;
      }
      if (!option.isAvailable) {
        violations.add(
          ModifierOptionUnavailableViolation(optionId: option.id),
        );
      }
    }

    final selectedQuantity =
        selections.fold<int>(0, (sum, selection) => sum + selection.quantity);

    if (group.isRequired && selectedQuantity == 0) {
      violations.add(
        RequiredModifierGroupMissingViolation(groupId: group.id),
      );
    } else if (selectedQuantity < group.minSelections ||
        selectedQuantity > group.maxSelections) {
      violations.add(
        ModifierSelectionCountViolation(
          groupId: group.id,
          selectedCount: selectedQuantity,
          minSelections: group.minSelections,
          maxSelections: group.maxSelections,
        ),
      );
    }

    if (violations.isNotEmpty) {
      return ModifierValidationInvalid(violations);
    }
    return const ModifierValidationValid();
  }
}
