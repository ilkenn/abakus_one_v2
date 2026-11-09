/// ADR-067 (2026-11-09) — the one place an order line's amount is turned
/// into display text, so a sold-by-weight line reads "350 g" / "1,5 kg"
/// everywhere (POS bill, KDS, kitchen ticket) instead of "1x".
library;

/// Server-enforced bounds (`submitTakeawayOrder.ts`'s MIN/MAX_WEIGHT_GRAMS).
const int minWeightGrams = 1;
const int maxWeightGrams = 20000;

/// "2x" for a per-piece line, the formatted weight for a sold-by-weight one.
String orderLineQuantityLabel({required int quantity, int? weightGrams}) {
  if (weightGrams != null) return formatWeightGrams(weightGrams);
  return '${quantity}x';
}

/// `350` → "350 g", `1500` → "1,5 kg", `1250` → "1,25 kg", `2000` → "2 kg".
/// Turkish decimal comma, trailing zeros dropped.
String formatWeightGrams(int grams) {
  if (grams < 1000) return '$grams g';
  final kg = (grams / 1000).toStringAsFixed(3);
  final trimmed = kg.replaceFirst(RegExp(r'\.?0+$'), '');
  return '${trimmed.replaceAll('.', ',')} kg';
}

/// Parses staff input into whole grams, or `null` if it isn't a valid
/// weight within [minWeightGrams]..[maxWeightGrams]:
/// - "250", "250g", "250 gr" → 250 (a bare number is grams);
/// - "1.5kg", "1,5 kg", "0,25kg" → 1500 / 250;
/// - grams with a fraction ("250,5 g") are rounded to the nearest gram.
int? parseWeightInputToGrams(String raw) {
  final text = raw.trim().toLowerCase().replaceAll(' ', '');
  final match = RegExp(r'^(\d+(?:[.,]\d+)?)(kg|g|gr)?$').firstMatch(text);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
  if (value == null) return null;
  final grams = (match.group(2) == 'kg' ? value * 1000 : value).round();
  if (grams < minWeightGrams || grams > maxWeightGrams) return null;
  return grams;
}

/// Estimated price for staff reference only — per-kg price × grams / 1000,
/// half-up to the kuruş, mirroring the server's own rounding
/// (`weightedUnitPriceMinorUnits`). The server's computation is
/// authoritative.
int estimatedWeightPriceMinorUnits({
  required int pricePerKgMinorUnits,
  required int grams,
}) =>
    ((pricePerKgMinorUnits * grams) / 1000).round();
