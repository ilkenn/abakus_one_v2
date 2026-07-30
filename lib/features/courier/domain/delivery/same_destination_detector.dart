/// One delivery's id paired with the destination text to compare it
/// against — Sprint 5C Part 6. The text itself is sourced by the caller
/// (`Order.deliveryAddressText`, the only delivery-destination text this
/// codebase has — no verified/geocoded coordinates exist anywhere in the
/// domain model, confirmed during this sprint's architecture analysis).
/// `SameDestinationDetector` stays agnostic of `Order` entirely — no new
/// `courier` → `orders` dependency, mirrors `CalculateShiftHourlyEarnings`
/// (Sprint 5A)'s "the caller's explicit responsibility" precedent for the
/// identical kind of cross-feature data gap.
class DeliveryDestinationEntry {
  const DeliveryDestinationEntry({
    required this.deliveryId,
    required this.destinationText,
  });

  final String deliveryId;
  final String destinationText;
}

/// Detects deliveries sharing the same destination via **normalized
/// destination text** — "detection must use normalized destination or
/// verified coordinates"; verified coordinates do not exist anywhere in
/// this codebase (see `DeliveryDestinationEntry`'s doc comment), so text
/// normalization is the honest, available option, not a downgrade
/// silently substituted for the brief's first choice. A pure, stateless
/// calculator — no I/O, mirrors `GeofenceEvaluator`'s shape.
abstract final class SameDestinationDetector {
  SameDestinationDetector._();

  /// Lowercase, trimmed, internal whitespace collapsed to a single space,
  /// common punctuation stripped — enough to match `'Ev - Kadıköy, ...'`
  /// against a re-typed `'ev-kadıköy ...'` without claiming true address
  /// geocoding this codebase cannot honestly perform.
  static String normalize(String destinationText) {
    return destinationText
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.,;:\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Returns only groups of size 2+ (a genuine "same destination
  /// detected" case) — a delivery with a unique or empty destination text
  /// never appears in the result. Empty/blank destination text is never
  /// grouped, even with another empty one — "unknown destination" is not
  /// "same destination."
  static List<List<String>> detectGroups(
    List<DeliveryDestinationEntry> deliveries,
  ) {
    final byNormalized = <String, List<String>>{};
    for (final entry in deliveries) {
      final key = normalize(entry.destinationText);
      if (key.isEmpty) continue;
      byNormalized.putIfAbsent(key, () => []).add(entry.deliveryId);
    }
    return [
      for (final group in byNormalized.values)
        if (group.length > 1) group,
    ];
  }
}
