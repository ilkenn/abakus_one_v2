import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/domain/models/modifier_group.dart';
import 'package:abakus_one_v2/features/menu/domain/models/modifier_option.dart';
import 'package:abakus_one_v2/features/menu/domain/models/selected_modifier.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/pos/application/identity/pos_order_line_draft_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/add_product_to_pos_order.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/pos_test_fixtures.dart';

AddProductToPosOrder _useCase(FakeClock clock) => AddProductToPosOrder(
      clock: clock,
      draftIdGenerator: SequentialPosOrderLineDraftIdGenerator(),
    );

const _simpleProduct = MenuProduct(
  id: 'prod_ayran',
  categoryId: 'cat_drinks',
  name: 'Ayran',
  description: '',
  basePrice: 25.0,
  imageKey: 'ayran',
);

const _bowlWithProtein = MenuProduct(
  id: 'prod_bowl',
  categoryId: 'cat_bowl',
  name: 'Mexifit Bowl',
  description: '',
  basePrice: 194.0,
  imageKey: 'bowl',
  modifierGroups: [
    ModifierGroup(
      id: 'protein',
      name: 'Protein',
      selectionType: ModifierSelectionType.single,
      isRequired: true,
      minSelections: 1,
      maxSelections: 1,
      options: [
        ModifierOption(id: 'chicken', name: 'Izgara Tavuk', extraPrice: 40.0),
        ModifierOption(id: 'beef', name: 'Dana', extraPrice: 70.0, isAvailable: false),
      ],
    ),
  ],
);

void main() {
  group('AddProductToPosOrder — no modifiers', () {
    test('adds a line and recalculates totals', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());
      final useCase = _useCase(clock);

      final updated = useCase(session: session, product: _simpleProduct);

      expect(updated.lines, hasLength(1));
      expect(updated.lines.single.item.name, 'Ayran');
      expect(updated.pricing.grossSubtotal.isPositive, isTrue);
    });

    test('bumps lastUpdatedAt via the injected clock', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());
      clock.advance(const Duration(minutes: 3));

      final updated = _useCase(clock)(
        session: session,
        product: _simpleProduct,
      );

      expect(updated.lastUpdatedAt, DateTime(2026, 7, 29, 12, 3));
    });

    test('rejects a non-positive quantity', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());

      expect(
        () => _useCase(clock)(
          session: session,
          product: _simpleProduct,
          quantity: 0,
        ),
        throwsA(isA<NonPositiveQuantityViolation>()),
      );
    });
  });

  group('AddProductToPosOrder — modifier validation (reuses ModifierValidator)', () {
    test('accepts a valid required-group selection', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());

      final updated = _useCase(clock)(
        session: session,
        product: _bowlWithProtein,
        selectedModifiers: const [
          SelectedModifier(
            groupId: 'protein',
            groupName: 'Protein',
            optionId: 'chicken',
            optionName: 'Izgara Tavuk',
            extraPrice: 40.0,
          ),
        ],
      );

      expect(updated.lines, hasLength(1));
    });

    test('rejects adding the product when a required modifier group has no selection', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());

      expect(
        () => _useCase(clock)(
          session: session,
          product: _bowlWithProtein,
        ),
        throwsA(isA<RequiredModifierGroupMissingViolation>()),
      );
    });

    test('rejects an unavailable modifier option', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());

      expect(
        () => _useCase(clock)(
          session: session,
          product: _bowlWithProtein,
          selectedModifiers: const [
            SelectedModifier(
              groupId: 'protein',
              groupName: 'Protein',
              optionId: 'beef',
              optionName: 'Dana',
              extraPrice: 70.0,
            ),
          ],
        ),
        throwsA(isA<ModifierOptionUnavailableViolation>()),
      );
    });

    test('a failed validation never partially adds the line', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());

      try {
        _useCase(clock)(
          session: session,
          product: _bowlWithProtein,
        );
      } on RequiredModifierGroupMissingViolation {
        // expected
      }

      expect(session.lines, isEmpty);
    });

    test('per-channel modifier availability is enforced through the session channel', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      const qrOnlyGroup = ModifierGroup(
        id: 'qr_only',
        name: 'QR Only',
        selectionType: ModifierSelectionType.single,
        options: [ModifierOption(id: 'x', name: 'X')],
        visibleChannels: {OrderChannel.dineInQr},
      );
      const product = MenuProduct(
        id: 'prod_qr',
        categoryId: 'cat',
        name: 'QR Only Product',
        description: '',
        basePrice: 50.0,
        imageKey: 'x',
        modifierGroups: [qrOnlyGroup],
      );
      // Session channel is dineInStaff, but the group only allows dineInQr.
      final session = buildTestSession(
        openedAt: clock.now(),
        channel: OrderChannel.dineInStaff,
      );

      expect(
        () => _useCase(clock)(
          session: session,
          product: product,
          selectedModifiers: const [
            SelectedModifier(
              groupId: 'qr_only',
              groupName: 'QR Only',
              optionId: 'x',
              optionName: 'X',
            ),
          ],
        ),
        throwsA(isA<ModifierGroupUnavailableInChannelViolation>()),
      );
    });
  });
}
