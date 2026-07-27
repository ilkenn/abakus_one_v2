import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/menu/domain/models/modifier_group.dart';
import 'package:abakus_one_v2/features/menu/domain/models/modifier_option.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/modifiers/modifier_selection_input.dart';
import 'package:abakus_one_v2/features/orders/domain/modifiers/modifier_validation_result.dart';
import 'package:abakus_one_v2/features/orders/domain/modifiers/modifier_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const proteinGroup = ModifierGroup(
    id: 'protein',
    name: 'Protein',
    selectionType: ModifierSelectionType.single,
    isRequired: true,
    minSelections: 1,
    maxSelections: 1,
    options: [
      ModifierOption(id: 'chicken', name: 'Tavuk'),
      ModifierOption(id: 'beef', name: 'Dana', isAvailable: false),
    ],
  );

  const extrasGroup = ModifierGroup(
    id: 'extras',
    name: 'Ekstra',
    selectionType: ModifierSelectionType.multiple,
    minSelections: 0,
    maxSelections: 3,
    options: [
      ModifierOption(id: 'cheese', name: 'Peynir'),
      ModifierOption(id: 'avocado', name: 'Avokado'),
    ],
  );

  const qrOnlyGroup = ModifierGroup(
    id: 'qr_only',
    name: 'QR Only',
    selectionType: ModifierSelectionType.single,
    options: [ModifierOption(id: 'x', name: 'X')],
    visibleChannels: {OrderChannel.dineInQr},
  );

  group('ModifierValidator.validateGroup — required', () {
    test('a required group with no selection is invalid', () {
      final result = ModifierValidator.validateGroup(
        group: proteinGroup,
        selections: const [],
        channel: OrderChannel.dineInQr,
      );

      expect(result, isA<ModifierValidationInvalid>());
      expect(
        (result as ModifierValidationInvalid).violations,
        contains(isA<RequiredModifierGroupMissingViolation>()),
      );
    });

    test('a required group with a valid selection is valid', () {
      final result = ModifierValidator.validateGroup(
        group: proteinGroup,
        selections: const [
          ModifierSelectionInput(optionId: 'chicken', quantity: 1)
        ],
        channel: OrderChannel.dineInQr,
      );

      expect(result, isA<ModifierValidationValid>());
    });
  });

  group('ModifierValidator.validateGroup — min/max, quantity-aware', () {
    test('below minSelections is invalid', () {
      const belowMin = ModifierGroup(
        id: 'g',
        name: 'g',
        selectionType: ModifierSelectionType.multiple,
        isRequired: false,
        minSelections: 2,
        maxSelections: 3,
        options: [
          ModifierOption(id: 'a', name: 'A'),
          ModifierOption(id: 'b', name: 'B'),
        ],
      );
      final result = ModifierValidator.validateGroup(
        group: belowMin,
        selections: const [ModifierSelectionInput(optionId: 'a', quantity: 1)],
        channel: OrderChannel.dineInQr,
      );

      expect(result, isA<ModifierValidationInvalid>());
      expect(
        (result as ModifierValidationInvalid).violations,
        contains(isA<ModifierSelectionCountViolation>()),
      );
    });

    test('above maxSelections is invalid', () {
      final result = ModifierValidator.validateGroup(
        group: extrasGroup,
        selections: const [
          ModifierSelectionInput(optionId: 'cheese', quantity: 2),
          ModifierSelectionInput(optionId: 'avocado', quantity: 2),
        ],
        channel: OrderChannel.dineInQr,
      );

      expect(result, isA<ModifierValidationInvalid>());
      expect(
        (result as ModifierValidationInvalid).violations,
        contains(isA<ModifierSelectionCountViolation>()),
      );
    });

    test(
        'quantity-aware: a single option selected at quantity 3 counts toward max the same as 3 distinct selections',
        () {
      final result = ModifierValidator.validateGroup(
        group: extrasGroup, // max 3
        selections: const [
          ModifierSelectionInput(optionId: 'cheese', quantity: 3)
        ],
        channel: OrderChannel.dineInQr,
      );

      expect(result, isA<ModifierValidationValid>());
    });

    test('quantity-aware: quantity 4 of one option exceeds a max of 3', () {
      final result = ModifierValidator.validateGroup(
        group: extrasGroup,
        selections: const [
          ModifierSelectionInput(optionId: 'cheese', quantity: 4)
        ],
        channel: OrderChannel.dineInQr,
      );

      expect(result, isA<ModifierValidationInvalid>());
    });

    test('a selection with zero or negative quantity is invalid', () {
      final result = ModifierValidator.validateGroup(
        group: extrasGroup,
        selections: const [
          ModifierSelectionInput(optionId: 'cheese', quantity: 0)
        ],
        channel: OrderChannel.dineInQr,
      );

      expect(result, isA<ModifierValidationInvalid>());
      expect(
        (result as ModifierValidationInvalid).violations,
        contains(isA<InvalidModifierQuantityViolation>()),
      );
    });

    test('a non-required group within [min, max] and zero selections is valid',
        () {
      final result = ModifierValidator.validateGroup(
        group: extrasGroup,
        selections: const [],
        channel: OrderChannel.dineInQr,
      );

      expect(result, isA<ModifierValidationValid>());
    });
  });

  group('ModifierValidator.validateGroup — availability and unknown options',
      () {
    test(
        'an unavailable option is rejected even if otherwise a valid selection',
        () {
      final result = ModifierValidator.validateGroup(
        group: proteinGroup,
        selections: const [
          ModifierSelectionInput(optionId: 'beef', quantity: 1)
        ],
        channel: OrderChannel.dineInQr,
      );

      expect(result, isA<ModifierValidationInvalid>());
      expect(
        (result as ModifierValidationInvalid).violations,
        contains(isA<ModifierOptionUnavailableViolation>()),
      );
    });

    test('an option id that does not belong to the group is rejected', () {
      final result = ModifierValidator.validateGroup(
        group: proteinGroup,
        selections: const [
          ModifierSelectionInput(optionId: 'not_real', quantity: 1)
        ],
        channel: OrderChannel.dineInQr,
      );

      expect(result, isA<ModifierValidationInvalid>());
      expect(
        (result as ModifierValidationInvalid).violations,
        contains(isA<UnknownModifierOptionViolation>()),
      );
    });
  });

  group('ModifierValidator.validateGroup — per-channel availability', () {
    test('a group not visible on the given channel is rejected', () {
      final result = ModifierValidator.validateGroup(
        group: qrOnlyGroup,
        selections: const [ModifierSelectionInput(optionId: 'x', quantity: 1)],
        channel: OrderChannel.takeaway,
      );

      expect(result, isA<ModifierValidationInvalid>());
      expect(
        (result as ModifierValidationInvalid).violations,
        contains(isA<ModifierGroupUnavailableInChannelViolation>()),
      );
    });

    test('a group visible on the given channel passes the channel check', () {
      final result = ModifierValidator.validateGroup(
        group: qrOnlyGroup,
        selections: const [ModifierSelectionInput(optionId: 'x', quantity: 1)],
        channel: OrderChannel.dineInQr,
      );

      expect(result, isA<ModifierValidationValid>());
    });
  });
}
