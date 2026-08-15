/// An immutable, historical record of a delivery address at the moment an
/// [Order] was created — Faz P.1. **Never** built directly from raw
/// customer/client input: [serverVerifiedAt] being a required, non-null
/// field is a deliberate type-level enforcement of the P.1 architecture
/// correction that a client-supplied address (district/neighborhood/
/// street/coordinates), even temporarily, can never be delivery-
/// authorization truth on its own — a [DeliveryAddressSnapshot] can only
/// be constructed once a real address-verification provider has actually
/// verified it (P.2, not yet implemented). No production code path in
/// P.1 constructs one from a real request; see `docs/decisions.md` Faz P.1
/// for the full reasoning.
///
/// Shape mirrors `docs/table_qr_architecture.md`'s own snapshot precedent
/// (`OrderLine` freezing product name/price rather than a live reference):
/// once attached to an [Order], this must never be re-derived from a live
/// `SavedAddress`/provider lookup — a later edit to the customer's saved
/// address must never retroactively change a past order's delivery
/// address.
class DeliveryAddressSnapshot {
  const DeliveryAddressSnapshot({
    required this.savedAddressId,
    required this.label,
    required this.provinceId,
    required this.provinceName,
    required this.districtId,
    required this.districtName,
    this.neighborhoodId,
    this.neighborhoodName,
    this.streetId,
    this.streetName,
    this.buildingNo,
    this.buildingNoSource,
    required this.apartmentNo,
    this.floor,
    this.addressDescription,
    required this.latitude,
    required this.longitude,
    required this.providerSource,
    this.providerPlaceId,
    required this.serverVerifiedAt,
  });

  /// The `SavedAddress.id` this snapshot was captured from, at capture
  /// time — kept only as a historical reference, never re-read live.
  final String savedAddressId;

  /// The customer-facing label at capture time (e.g. "Ev", "İş").
  final String label;

  /// Guaranteed non-null on any snapshot that reached this class through
  /// [SavedAddress.toDeliveryAddressSnapshot] — the backend's own
  /// verification gate (`isSufficientlyResolved`, `functions/src/
  /// googlePlacesFieldMapping.ts`) never marks an address `verified`
  /// without both of these resolved. Required here rather than merely
  /// documented, so that guarantee is a type-level fact for every reader
  /// of an already-attached snapshot, not just a runtime convention.
  final String provinceId;
  final String provinceName;
  final String districtId;
  final String districtName;

  /// `null` where the provider resolved the address but did not supply a
  /// neighborhood/mahalle-level component — Faz P.2's real coverage spike
  /// found this happens for genuine, otherwise-well-resolved places (a
  /// mahalle-only query with no street in it never populates a narrower
  /// component). Unlike [provinceName]/[districtName], **not** required
  /// for [SavedAddress.isDeliveryAuthorized] to be `true`.
  final String? neighborhoodId;
  final String? neighborhoodName;

  /// `null` where the address hierarchy has no street-level entry
  /// available (see P.1 §10 — geography coverage is deliberately not
  /// assumed to always resolve to street granularity).
  final String? streetId;
  final String? streetName;

  /// `null` when neither the provider nor the customer supplied a
  /// building number — Faz P.2 §6/spike evidence: a provider's own
  /// `street_number` component is absent whenever the resolved place has
  /// no street context (e.g. a mahalle-only address), and a customer
  /// override is optional, never fabricated. See [buildingNoSource] for
  /// which source (if any) this value came from.
  final String? buildingNo;

  /// Provenance for [buildingNo] — Faz P.2 §6: "preserve provenance."
  /// `null` iff [buildingNo] is `null`.
  final String? buildingNoSource;

  final String apartmentNo;

  /// Optional — not every address has a meaningful floor.
  final String? floor;

  /// Optional free-text delivery instructions (e.g. "kapıcıya bırakın").
  final String? addressDescription;

  final double latitude;
  final double longitude;

  /// Identifies which address-verification provider (P.2, not yet
  /// implemented) produced this snapshot — e.g. `'manual'` today has no
  /// real meaning since no provider exists yet; reserved so a future
  /// provider identity never has to be retrofitted onto historical orders.
  final String providerSource;

  /// The verifying provider's own place/address id, if it supplies one.
  /// `null` where no such id exists.
  final String? providerPlaceId;

  /// When a real address-verification provider (P.2) confirmed this
  /// address — the one field that makes this snapshot's existence
  /// meaningful as delivery-authorization evidence. Required, never
  /// nullable: see this class's own doc comment.
  final DateTime serverVerifiedAt;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DeliveryAddressSnapshot &&
            other.savedAddressId == savedAddressId &&
            other.label == label &&
            other.provinceId == provinceId &&
            other.provinceName == provinceName &&
            other.districtId == districtId &&
            other.districtName == districtName &&
            other.neighborhoodId == neighborhoodId &&
            other.neighborhoodName == neighborhoodName &&
            other.streetId == streetId &&
            other.streetName == streetName &&
            other.buildingNo == buildingNo &&
            other.buildingNoSource == buildingNoSource &&
            other.apartmentNo == apartmentNo &&
            other.floor == floor &&
            other.addressDescription == addressDescription &&
            other.latitude == latitude &&
            other.longitude == longitude &&
            other.providerSource == providerSource &&
            other.providerPlaceId == providerPlaceId &&
            other.serverVerifiedAt == serverVerifiedAt);
  }

  @override
  int get hashCode => Object.hash(
        savedAddressId,
        label,
        provinceId,
        provinceName,
        districtId,
        districtName,
        neighborhoodId,
        neighborhoodName,
        streetId,
        streetName,
        buildingNo,
        buildingNoSource,
        apartmentNo,
        floor,
        addressDescription,
        latitude,
        longitude,
        providerSource,
        Object.hash(providerPlaceId, serverVerifiedAt),
      );
}
