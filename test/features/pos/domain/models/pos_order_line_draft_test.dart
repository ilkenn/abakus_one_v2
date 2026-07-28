import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/pos/domain/models/pos_order_line_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PosOrderLineDraft', () {
    test('carries a stable id independent of the wrapped CartItem', () {
      const item = CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1);
      const draft = PosOrderLineDraft(id: 'line-1', item: item);

      expect(draft.id, 'line-1');
      expect(draft.item, item);
    });

    test('copyWith replaces only the given field', () {
      const item = CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1);
      const draft = PosOrderLineDraft(id: 'line-1', item: item);

      final updated = draft.copyWith(
        item: item.copyWith(quantity: 2),
      );

      expect(updated.id, 'line-1');
      expect(updated.item.quantity, 2);
    });
  });
}
