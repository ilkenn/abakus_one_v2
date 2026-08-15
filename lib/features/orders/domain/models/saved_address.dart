import '../../../../core/errors/business_rule_violation.dart';
import 'delivery_address_snapshot.dart';

/// How trustworthy a [SavedAddress] currently is as delivery-authorization
/// evidence — Faz P.1.
///
/// - [unverified]: exactly what the customer typed/picked, never checked
///   against a real address-verification provider. The only status a
///   newly created [SavedAddress] can ever start in.
/// - [verified]: a real provider (P.2, not yet implemented) has confirmed
///   this address resolves to a real, deliverable location.
/// - [stale]: was [verified] once, but something about the address
///   changed since (the customer edited a field, or the provider's own
///   data expired) — no longer trustworthy without re-verification, but
///   distinct from [unverified] so a UI can say "re-verify" rather than
///   "verify for the first time."
enum AddressVerificationStatus { unverified, verified, stale }

/// A customer's saved delivery address — Faz P.1. **Deliberately a new,
/// separate type from the legacy `AddressModel`**
/// (`features/profile/domain/models/address_model.dart`), mirroring the
/// same "canonical vs. legacy prototype" split already established
/// between this codebase's canonical `Order` and the legacy `OrderModel`
/// (`order.dart`'s own doc comment): `AddressModel` is a pure, in-memory
/// UI prototype with no owner/verification concept at all; this type is
/// the real domain foundation P.2's address-verification provider will
/// populate [verificationStatus] against.
///
/// **The central Faz P.1 architecture rule, enforced structurally**: a
/// [SavedAddress] the customer entered/edited is never, by itself,
/// evidence a delivery order may be authorized against — only
/// [AddressVerificationStatus.verified] is. [isDeliveryAuthorized] is the
/// one place that check happens; [toDeliveryAddressSnapshot] refuses to
/// produce a [DeliveryAddressSnapshot] (throwing
/// [AddressNotVerifiedForDeliveryViolation]) unless it holds. No
/// production code path in P.1 calls [toDeliveryAddressSnapshot] with a
/// real, provider-verified address — no such provider exists yet (P.2).
class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.customerId,
    required this.label,
    this.provinceId,
    this.provinceName,
    this.districtId,
    this.districtName,
    this.neighborhoodId,
    this.neighborhoodName,
    this.streetId,
    this.streetName,
    this.buildingNo,
    this.buildingNoSource,
    required this.apartmentNo,
    this.floor,
    this.addressDescription,
    this.latitude,
    this.longitude,
    this.verificationStatus = AddressVerificationStatus.unverified,
    this.verifiedAt,
    this.providerSource,
    this.providerPlaceId,
    this.isDefault = false,
    this.formattedAddress,
  });

  final String id;

  /// The owning customer's uid — every read/write of this address must be
  /// scoped to `customerId == request.auth.uid` — enforced in production
  /// by `customerAddresses`' Firestore Rules (Faz P.2, `docs/decisions.md`).
  final String customerId;

  final String label;

  /// All nullable — Faz P.2 correction to P.1's original (incorrect)
  /// assumption that these were always resolvable: the real coverage
  /// spike found genuine places where the provider does not return a
  /// district (`docs/decisions.md` Faz P.2 D-something), and a
  /// [SavedAddress] is persisted (as [AddressVerificationStatus.unverified])
  /// even when resolution is incomplete — see this file's own §5 handling
  /// in `saveDeliveryAddress` (`functions/src/deliveryPlaces.ts`). Only a
  /// [AddressVerificationStatus.verified] address is guaranteed to have
  /// [provinceName]/[districtName] — enforced defensively in
  /// [toDeliveryAddressSnapshot], not merely assumed.
  final String? provinceId;
  final String? provinceName;
  final String? districtId;
  final String? districtName;

  /// `null` where the provider resolved the address but did not supply a
  /// neighborhood/mahalle-level component — genuinely optional, never
  /// required even for [isDeliveryAuthorized].
  final String? neighborhoodId;
  final String? neighborhoodName;

  /// `null` where the address hierarchy has no street-level entry
  /// available.
  final String? streetId;
  final String? streetName;

  /// `null` when neither the provider nor the customer supplied a
  /// building number. See [buildingNoSource] for provenance.
  final String? buildingNo;

  /// `'provider'` or `'customer'` — which source [buildingNo] came from
  /// (Faz P.2 §6: "preserve provenance," never silently treat a
  /// customer-supplied value as provider-verified). `null` iff
  /// [buildingNo] is `null`.
  final String? buildingNoSource;

  final String apartmentNo;
  final String? floor;
  final String? addressDescription;

  /// `null` until the customer has pinned a map location (or a provider
  /// has geocoded the address) — unlike [DeliveryAddressSnapshot], a
  /// draft [SavedAddress] is not required to have coordinates yet.
  final double? latitude;
  final double? longitude;

  final AddressVerificationStatus verificationStatus;

  /// When [verificationStatus] last became [AddressVerificationStatus.verified]
  /// — `null` while [verificationStatus] is [AddressVerificationStatus.unverified].
  /// Still non-`null` while [AddressVerificationStatus.stale] (records when
  /// the now-stale verification happened).
  final DateTime? verifiedAt;

  /// Which address-verification provider (P.2, not yet implemented)
  /// produced the current [verificationStatus] — `null` while
  /// [AddressVerificationStatus.unverified].
  final String? providerSource;
  final String? providerPlaceId;

  /// Faz P.2.1.2 — at most one of a customer's addresses may be default at
  /// a time, enforced server-side (`saveDeliveryAddress`'s own
  /// transaction unsets any prior default). Purely customer-owned
  /// metadata — never treated as delivery-authorization evidence.
  final bool isDefault;

  /// The provider's own human-readable formatted address (Faz P.2.1.2) —
  /// safe, display-only customer UI text. `null` for an address that
  /// never successfully resolved even partially.
  final String? formattedAddress;

  /// Whether this address, as it currently stands, may authorize a
  /// delivery order — true if and only if it is
  /// [AddressVerificationStatus.verified]. A [AddressVerificationStatus.stale]
  /// address is explicitly **not** authorized, same as
  /// [AddressVerificationStatus.unverified] — it must be re-verified
  /// first.
  bool get isDeliveryAuthorized =>
      verificationStatus == AddressVerificationStatus.verified;

  /// Freezes this address into a [DeliveryAddressSnapshot] for attaching
  /// to an [Order] — the one sanctioned way to produce one from a
  /// [SavedAddress]. Throws [AddressNotVerifiedForDeliveryViolation] if
  /// [isDeliveryAuthorized] is `false`, or if [latitude]/[longitude]/
  /// [verifiedAt]/[providerSource]/[provinceName]/[provinceId]/
  /// [districtName]/[districtId] are missing — a verified address is
  /// expected (by the backend's own verification gate,
  /// `isSufficientlyResolved` in `functions/src/googlePlacesFieldMapping
  /// .ts`) to always carry these, but this check enforces it defensively
  /// at the type level rather than trusting that invariant blindly.
  DeliveryAddressSnapshot toDeliveryAddressSnapshot() {
    final lat = latitude;
    final lng = longitude;
    final verifiedAtValue = verifiedAt;
    final providerSourceValue = providerSource;
    final provinceIdValue = provinceId;
    final provinceNameValue = provinceName;
    final districtIdValue = districtId;
    final districtNameValue = districtName;
    if (!isDeliveryAuthorized ||
        lat == null ||
        lng == null ||
        verifiedAtValue == null ||
        providerSourceValue == null ||
        provinceIdValue == null ||
        provinceNameValue == null ||
        districtIdValue == null ||
        districtNameValue == null) {
      throw AddressNotVerifiedForDeliveryViolation(addressId: id);
    }
    return DeliveryAddressSnapshot(
      savedAddressId: id,
      label: label,
      provinceId: provinceIdValue,
      provinceName: provinceNameValue,
      districtId: districtIdValue,
      districtName: districtNameValue,
      neighborhoodId: neighborhoodId,
      neighborhoodName: neighborhoodName,
      streetId: streetId,
      streetName: streetName,
      buildingNo: buildingNo,
      buildingNoSource: buildingNoSource,
      apartmentNo: apartmentNo,
      floor: floor,
      addressDescription: addressDescription,
      latitude: lat,
      longitude: lng,
      providerSource: providerSourceValue,
      providerPlaceId: providerPlaceId,
      serverVerifiedAt: verifiedAtValue,
    );
  }

  SavedAddress copyWith({
    String? id,
    String? customerId,
    String? label,
    String? provinceId,
    String? provinceName,
    String? districtId,
    String? districtName,
    String? neighborhoodId,
    String? neighborhoodName,
    String? streetId,
    String? streetName,
    String? buildingNo,
    String? buildingNoSource,
    String? apartmentNo,
    String? floor,
    String? addressDescription,
    double? latitude,
    double? longitude,
    AddressVerificationStatus? verificationStatus,
    DateTime? verifiedAt,
    String? providerSource,
    String? providerPlaceId,
    bool? isDefault,
    String? formattedAddress,
  }) {
    return SavedAddress(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      label: label ?? this.label,
      provinceId: provinceId ?? this.provinceId,
      provinceName: provinceName ?? this.provinceName,
      districtId: districtId ?? this.districtId,
      districtName: districtName ?? this.districtName,
      neighborhoodId: neighborhoodId ?? this.neighborhoodId,
      neighborhoodName: neighborhoodName ?? this.neighborhoodName,
      streetId: streetId ?? this.streetId,
      streetName: streetName ?? this.streetName,
      buildingNo: buildingNo ?? this.buildingNo,
      buildingNoSource: buildingNoSource ?? this.buildingNoSource,
      apartmentNo: apartmentNo ?? this.apartmentNo,
      floor: floor ?? this.floor,
      addressDescription: addressDescription ?? this.addressDescription,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      providerSource: providerSource ?? this.providerSource,
      providerPlaceId: providerPlaceId ?? this.providerPlaceId,
      isDefault: isDefault ?? this.isDefault,
      formattedAddress: formattedAddress ?? this.formattedAddress,
    );
  }
}
