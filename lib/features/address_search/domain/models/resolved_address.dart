/// A server-resolved address preview — Faz P.2 §3's "resolve canonical
/// address components → show resolved address" step, shown to the
/// customer before they fill in apartment/floor/description and confirm
/// save. Provider-neutral: no Google Places SDK/response type appears
/// here.
///
/// **Not itself delivery-authorization evidence** — this is a preview
/// value object only; `saveDeliveryAddress` independently re-resolves the
/// same `providerPlaceId` server-side at actual save time rather than
/// trusting this value (Faz P.2 §5). See `SavedAddress`/
/// `DeliveryAddressSnapshot` for the types that matter for authorization.
class ResolvedAddress {
  const ResolvedAddress({
    required this.providerPlaceId,
    required this.formattedAddress,
    required this.provinceName,
    required this.districtName,
    required this.neighborhoodName,
    required this.routeName,
    required this.streetNumber,
    required this.latitude,
    required this.longitude,
    required this.isSufficientlyResolved,
  });

  final String providerPlaceId;
  final String? formattedAddress;
  final String? provinceName;
  final String? districtName;

  /// `null` where the provider did not supply a neighborhood/mahalle-level
  /// component — genuinely optional (`docs/decisions.md` Faz P.2's real
  /// coverage-spike finding), never treated as an error by itself.
  final String? neighborhoodName;

  final String? routeName;
  final String? streetNumber;
  final double? latitude;
  final double? longitude;

  /// Mirrors the backend's own `isSufficientlyResolved`
  /// (`functions/src/googlePlacesFieldMapping.ts`) — `true` iff province,
  /// district, and coordinates are all present. `false` means saving this
  /// place will result in an [AddressVerificationStatus.unverified]
  /// `SavedAddress`, never [AddressVerificationStatus.verified] — shown to
  /// the customer so they aren't surprised later.
  final bool isSufficientlyResolved;
}
