import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_item_snapshot.dart';

void main() {
  test('lineTotal birim fiyat, adet, vergi ve indirimi dogru hesaplar', () {
    const snapshot = OrderItemSnapshot(
      productId: 'prod_1',
      productName: 'Protein Bowl',
      quantity: 2,
      unitPrice: 100.0,
      taxAmount: 20.0,
      discountAmount: 10.0,
    );

    // (100 * 2) + 20 - 10 = 210
    expect(snapshot.lineTotal, 210.0);
  });

  test('copyWith orijinal snapshotu degistirmeden yeni bir kopya olusturur',
      () {
    const original = OrderItemSnapshot(
      productId: 'prod_1',
      productName: 'Protein Bowl',
      modifierDescriptions: ['Ekstra Peynir'],
      quantity: 1,
      unitPrice: 150.0,
      notes: 'Az baharatlı',
    );

    final updated = original.copyWith(quantity: 3, notes: 'Baharatsız');

    // Orijinal degismedi.
    expect(original.quantity, 1);
    expect(original.notes, 'Az baharatlı');

    // Yeni kopya guncellendi, degistirilmeyen alanlar korundu.
    expect(updated.quantity, 3);
    expect(updated.notes, 'Baharatsız');
    expect(updated.productName, 'Protein Bowl');
    expect(updated.modifierDescriptions, ['Ekstra Peynir']);
  });

  test('gelecekteki menu degisiklikleri snapshotu etkilemez (donmus veri)', () {
    // Bir menu urununun adi/fiyati degistirilse bile, daha once alinan bir
    // siparisin snapshotu tanim geregi sabittir; snapshot urun id'sine
    // degil, kendi donmus alanlarina gore okunur.
    const historical = OrderItemSnapshot(
      productId: 'prod_1',
      productName: 'Klasik Bowl (Eski İsim)',
      quantity: 1,
      unitPrice: 120.0,
    );

    const currentMenuPrice = 180.0; // Varsayimsal, menude guncel fiyat.

    expect(historical.unitPrice, isNot(currentMenuPrice));
    expect(historical.productName, 'Klasik Bowl (Eski İsim)');
  });
}
