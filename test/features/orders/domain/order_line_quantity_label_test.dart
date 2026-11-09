import 'package:abakus_one_v2/features/orders/domain/order_line_quantity_label.dart';
import 'package:flutter_test/flutter_test.dart';

// ADR-067 (2026-11-09).
void main() {
  test('per-piece lines keep the "2x" label', () {
    expect(orderLineQuantityLabel(quantity: 2), '2x');
  });

  test('weights read as grams below 1 kg, Turkish-decimal kg above', () {
    expect(formatWeightGrams(350), '350 g');
    expect(formatWeightGrams(1000), '1 kg');
    expect(formatWeightGrams(1500), '1,5 kg');
    expect(formatWeightGrams(1250), '1,25 kg');
    expect(formatWeightGrams(2005), '2,005 kg');
    expect(orderLineQuantityLabel(quantity: 1, weightGrams: 350), '350 g');
  });

  test('parses grams, kg, comma or dot decimals; rejects out of range', () {
    expect(parseWeightInputToGrams('250'), 250);
    expect(parseWeightInputToGrams('250g'), 250);
    expect(parseWeightInputToGrams(' 250 gr '), 250);
    expect(parseWeightInputToGrams('1.5kg'), 1500);
    expect(parseWeightInputToGrams('1,5 kg'), 1500);
    expect(parseWeightInputToGrams('0,25kg'), 250);
    expect(parseWeightInputToGrams('250,6 g'), 251);
    expect(parseWeightInputToGrams(''), isNull);
    expect(parseWeightInputToGrams('abc'), isNull);
    expect(parseWeightInputToGrams('0'), isNull);
    expect(parseWeightInputToGrams('25 kg'), isNull);
    expect(parseWeightInputToGrams('-5'), isNull);
  });

  test('estimate mirrors the server: per-kg × grams / 1000, half-up', () {
    expect(
        estimatedWeightPriceMinorUnits(pricePerKgMinorUnits: 48000, grams: 350),
        16800);
    expect(
        estimatedWeightPriceMinorUnits(pricePerKgMinorUnits: 12550, grams: 1),
        13);
  });
}
