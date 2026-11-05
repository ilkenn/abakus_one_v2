import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/menu/domain/models/selected_modifier.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';

void main() {
  const baseItem = CartItem(
    id: 'prod-1',
    name: 'Test Ürün',
    desc: 'açıklama',
    price: 50,
    quantity: 2,
  );

  test('unitPrice toplar: price + extraCostPerUnit + modifier extraPrice', () {
    const item = CartItem(
      id: 'prod-1',
      name: 'Test',
      desc: '',
      price: 50,
      quantity: 1,
      extraCostPerUnit: 5,
      selectedModifiers: [
        SelectedModifier(
          groupId: 'g1',
          groupName: 'Grup',
          optionId: 'o1',
          optionName: 'Opsiyon',
          extraPrice: 10,
        ),
      ],
    );

    expect(item.unitPrice, 65);
  });

  test('totalRowPrice = unitPrice * quantity', () {
    const item = CartItem(
      id: 'prod-1',
      name: 'Test',
      desc: '',
      price: 50,
      quantity: 3,
    );

    expect(item.totalRowPrice, 150);
  });

  test(
      'addedBySubAccountId varsayılan olarak null — Self-Order QR Faz 3 '
      'öncesi/dışı her item için', () {
    expect(baseItem.addedBySubAccountId, isNull);
  });

  test('copyWith addedBySubAccountId ayarlayabilir', () {
    final updated =
        baseItem.copyWith(addedBySubAccountId: 'subaccount-ts-1-uid-1');

    expect(updated.addedBySubAccountId, 'subaccount-ts-1-uid-1');
    // Diğer alanlar değişmeden kalır.
    expect(updated.id, baseItem.id);
    expect(updated.quantity, baseItem.quantity);
  });

  test('copyWith hiçbir alan verilmezse orijinal degerleri korur', () {
    const original = CartItem(
      id: 'prod-1',
      name: 'Test',
      desc: 'açıklama',
      price: 50,
      quantity: 2,
      pricedForChannel: OrderChannel.dineInQr,
      addedBySubAccountId: 'subaccount-ts-1-uid-1',
    );

    final copy = original.copyWith();

    expect(copy.pricedForChannel, OrderChannel.dineInQr);
    expect(copy.addedBySubAccountId, 'subaccount-ts-1-uid-1');
  });
}
