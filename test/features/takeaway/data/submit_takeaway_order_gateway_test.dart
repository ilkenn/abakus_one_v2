import 'package:abakus_one_v2/features/takeaway/data/submit_takeaway_order_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

/// Boncuk Loyalty Program P4-E-B (2026-08-22). `FirebaseSubmitTakeawayOrderGateway`
/// itself talks to the real Cloud Function and cannot be exercised under
/// `flutter test` (unavailable Firebase SDK — see this file's own doc
/// comment on `SubmitTakeawayOrderGateway`); its wire-level behavior
/// (`requestedBoncukAmount` sent only when > 0, no other Boncuk field ever
/// sent, a stable server reason reaching the exception) is instead proven
/// end-to-end through `takeaway_checkout_screen_test.dart`'s own fake
/// gateway, which implements the SAME public interface tested here. This
/// file covers exactly what's testable in isolation: the pure request
/// item/exception types.
void main() {
  group('TakeawayOrderItem.toJson — no price field of any kind', () {
    test('TakeawayProductItem carries no price, only intent', () {
      const item = TakeawayProductItem(
        productId: 'p1',
        quantity: 2,
        selectedModifiers: [(groupId: 'g1', optionId: 'o1')],
        note: 'az baharatlı',
      );
      final json = item.toJson();

      expect(json, {
        'kind': 'product',
        'productId': 'p1',
        'quantity': 2,
        'selectedModifiers': [
          {'groupId': 'g1', 'optionId': 'o1'},
        ],
        'note': 'az baharatlı',
      });
      expect(json.containsKey('price'), isFalse);
      expect(json.containsKey('unitPrice'), isFalse);
    });

    test('TakeawayBowlItem carries no price, only intent', () {
      const item = TakeawayBowlItem(
        quantity: 1,
        ingredientIds: ['ing-1', 'ing-2'],
      );
      final json = item.toJson();

      expect(json, {
        'kind': 'bowl',
        'quantity': 1,
        'ingredientIds': ['ing-1', 'ing-2'],
        'note': '',
      });
      expect(json.containsKey('price'), isFalse);
    });
  });

  group('SubmitTakeawayOrderException — Boncuk Loyalty P4-E-B', () {
    test('boncukErrorReason defaults to null for a non-Boncuk rejection', () {
      const error = SubmitTakeawayOrderException(
        'failed-precondition',
        'Branch is not currently accepting takeaway orders.',
      );

      expect(error.boncukErrorReason, isNull);
      expect(error.toString(), isNot(contains('reason:')));
    });

    test(
        'boncukErrorReason carries the stable server reason when a Boncuk '
        'rejection occurs, distinct from the generic code', () {
      const error = SubmitTakeawayOrderException(
        'invalid-argument',
        'requestedBoncukAmount exceeds the maximum usable Boncuk for this order.',
        boncukErrorReason: 'boncuk/exceeds-max-usable',
      );

      expect(error.code, 'invalid-argument');
      expect(error.boncukErrorReason, 'boncuk/exceeds-max-usable');
      expect(error.toString(), contains('boncuk/exceeds-max-usable'));
    });

    test(
        'the same generic code ("invalid-argument") can occur with or '
        'without a Boncuk reason — proving code alone is never a safe '
        'discriminator for a Boncuk-specific rejection', () {
      const genericValidation = SubmitTakeawayOrderException(
        'invalid-argument',
        'contactPhone is not a valid phone number.',
      );
      const boncukRejection = SubmitTakeawayOrderException(
        'invalid-argument',
        'requestedBoncukAmount exceeds the maximum usable Boncuk for this order.',
        boncukErrorReason: 'boncuk/exceeds-max-usable',
      );

      expect(genericValidation.code, boncukRejection.code);
      expect(genericValidation.boncukErrorReason, isNull);
      expect(boncukRejection.boncukErrorReason, isNotNull);
    });
  });
}
