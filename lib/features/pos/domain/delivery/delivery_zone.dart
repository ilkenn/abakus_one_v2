/// 2026-11-12 (Faz 4, ADR-081) — one neighborhood rule of a branch
/// ("Teslimat Bölgeleri"): the minimum basket and the estimated delivery
/// time. Server-written only (`deliveryZones.ts`); the server is the
/// authority for the minimum-order gate — the POS uses these only to warn
/// early and to show the rule.
class DeliveryZone {
  const DeliveryZone({
    required this.id,
    required this.districtId,
    required this.neighborhoodId,
    required this.neighborhoodName,
    required this.minimumOrderMinorUnits,
    required this.estimatedDeliveryMinutes,
    required this.enabled,
  });

  final String id;
  final String districtId;
  final String neighborhoodId;
  final String neighborhoodName;
  final int minimumOrderMinorUnits;
  final int? estimatedDeliveryMinutes;
  final bool enabled;
}

class BranchDeliveryZones {
  const BranchDeliveryZones({
    required this.defaultDeliveryDistrictId,
    required this.zones,
  });

  final String? defaultDeliveryDistrictId;
  final List<DeliveryZone> zones;

  /// The enabled rule for a hand-typed neighborhood name, or `null`. Mirrors
  /// `resolveBranchZone` in `functions/src/deliveryZones.ts` (match on the
  /// neighborhood key; two districts sharing a name → the default district).
  DeliveryZone? zoneFor(String neighborhoodName) {
    final key = neighborhoodKey(neighborhoodName);
    if (key.isEmpty) return null;
    final matches =
        zones.where((z) => z.enabled && z.neighborhoodId == key).toList();
    if (matches.length == 1) return matches.single;
    for (final zone in matches) {
      if (zone.districtId == defaultDeliveryDistrictId) return zone;
    }
    return null;
  }

  static const empty =
      BranchDeliveryZones(defaultDeliveryDistrictId: null, zones: []);
}

/// The neighborhood matching key — a hand-kept mirror of the server's
/// `slugifyAddressComponent` ("Caferağa" → "caferaga", "Moda Mah." →
/// "moda_mah"), the same "no Dart↔TypeScript sharing" precedent as the
/// other mirrored rules.
String neighborhoodKey(String input) {
  const replacements = {
    'ç': 'c',
    'ğ': 'g',
    'ı': 'i',
    'i̇': 'i',
    'ö': 'o',
    'ş': 's',
    'ü': 'u',
  };
  var result = input.replaceAll('İ', 'i').replaceAll('I', 'i').toLowerCase();
  replacements.forEach((from, to) => result = result.replaceAll(from, to));
  result = result.trim().replaceAll(RegExp(r'\s+'), '_');
  return result.replaceAll(RegExp(r'[^a-z0-9_]'), '');
}
