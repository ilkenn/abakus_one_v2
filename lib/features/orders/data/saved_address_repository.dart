import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../domain/models/saved_address.dart';
import 'saved_address_exception.dart';

/// Storage for [SavedAddress] — Faz P.2. **Split write path, matching §7's
/// "Preferred: client sends user-editable metadata; server callable owns
/// provider-verification fields"**:
///
/// - [save] always calls the `saveDeliveryAddress` Cloud Function
///   (`functions/src/deliveryPlaces.ts`) — the only path that can ever
///   set/change [SavedAddress.verificationStatus]/provider-sourced
///   fields, since only that callable independently re-resolves the
///   place server-side (§5). Never a direct Firestore write for these
///   fields — `customerAddresses`' own Security Rules structurally
///   enforce this same boundary (`create: if false`), so this repository
///   couldn't bypass it even if it tried.
/// - [updateMetadata]/[delete]/[listForCurrentUser] are direct Firestore
///   client SDK calls — safe because they only ever touch the explicitly
///   user-owned, non-authoritative fields (or, for delete/list, don't
///   touch authoritative fields at all).
abstract interface class SavedAddressRepository {
  /// Creates a new address (when [addressId] is `null`) or re-verifies
  /// and updates an existing one the caller owns (when [addressId] is
  /// given). [apartmentNo] is always required — Faz P.2 §6, always
  /// customer input, never provider-sourced.
  Future<SavedAddress> save({
    String? addressId,
    required String providerPlaceId,
    required String label,
    bool isDefault = false,
    required String apartmentNo,
    String? floor,
    String? addressDescription,
    String? buildingNoOverride,
  });

  /// Every address belonging to the currently signed-in customer.
  Future<List<SavedAddress>> listForCurrentUser();

  /// Updates only the explicitly user-owned metadata fields — never
  /// touches [SavedAddress.verificationStatus] or any provider-sourced
  /// field. Matches `customerAddresses`' own Security Rules allow-list
  /// exactly (`firestore.rules`).
  Future<void> updateMetadata({
    required String addressId,
    String? label,
    bool? isDefault,
    String? apartmentNo,
    String? floor,
    String? addressDescription,
    String? buildingNoOverride,
  });

  Future<void> delete(String addressId);
}

class FirestoreSavedAddressRepository implements SavedAddressRepository {
  FirestoreSavedAddressRepository({
    fs.FirebaseFirestore? firestore,
    functions.FirebaseFunctions? functionsInstance,
    required String Function() currentUid,
  })  : _firestore = firestore ?? fs.FirebaseFirestore.instance,
        _functions = functionsInstance ?? functions.FirebaseFunctions.instance,
        _currentUid = currentUid;

  final fs.FirebaseFirestore _firestore;
  final functions.FirebaseFunctions _functions;
  final String Function() _currentUid;

  fs.CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('customerAddresses');

  @override
  Future<SavedAddress> save({
    String? addressId,
    required String providerPlaceId,
    required String label,
    bool isDefault = false,
    required String apartmentNo,
    String? floor,
    String? addressDescription,
    String? buildingNoOverride,
  }) async {
    final callable = _functions.httpsCallable('saveDeliveryAddress');
    final String savedAddressId;
    try {
      final result = await callable.call<Map<String, dynamic>>({
        if (addressId != null) 'addressId': addressId,
        'placeId': providerPlaceId,
        'label': label,
        'isDefault': isDefault,
        'apartmentNo': apartmentNo,
        if (floor != null) 'floor': floor,
        if (addressDescription != null)
          'addressDescription': addressDescription,
        if (buildingNoOverride != null)
          'buildingNoOverride': buildingNoOverride,
      });
      savedAddressId = result.data['addressId'] as String;
    } on functions.FirebaseFunctionsException catch (error) {
      throw SavedAddressException(
        error.code,
        error.message ?? 'Adres kaydedilemedi.',
      );
    }

    final doc = await _collection.doc(savedAddressId).get();
    final data = doc.data();
    if (data == null) {
      throw const SavedAddressException(
        'not-found',
        'Adres kaydedildi ancak okunamadı.',
      );
    }
    return _map(doc.id, data);
  }

  @override
  Future<List<SavedAddress>> listForCurrentUser() async {
    final snapshot =
        await _collection.where('uid', isEqualTo: _currentUid()).get();
    return [for (final doc in snapshot.docs) _map(doc.id, doc.data())];
  }

  @override
  Future<void> updateMetadata({
    required String addressId,
    String? label,
    bool? isDefault,
    String? apartmentNo,
    String? floor,
    String? addressDescription,
    String? buildingNoOverride,
  }) async {
    final update = <String, dynamic>{
      'updatedAt': DateTime.now().toIso8601String(),
      if (label != null) 'label': label,
      if (isDefault != null) 'isDefault': isDefault,
      if (apartmentNo != null) 'apartmentNo': apartmentNo,
      if (floor != null) 'floor': floor,
      if (addressDescription != null) 'addressDescription': addressDescription,
      if (buildingNoOverride != null) 'buildingNoOverride': buildingNoOverride,
    };
    await _collection.doc(addressId).update(update);
  }

  @override
  Future<void> delete(String addressId) async {
    await _collection.doc(addressId).delete();
  }

  SavedAddress _map(String id, Map<String, dynamic> data) {
    final verificationStatusName =
        data['verificationStatus'] as String? ?? 'unverified';
    return SavedAddress(
      id: id,
      customerId: data['uid'] as String,
      label: data['label'] as String? ?? '',
      provinceId: data['provinceName'] == null
          ? null
          : slugifyAddressComponent(data['provinceName'] as String),
      provinceName: data['provinceName'] as String?,
      districtId: data['districtName'] == null
          ? null
          : slugifyAddressComponent(data['districtName'] as String),
      districtName: data['districtName'] as String?,
      neighborhoodId: data['neighborhoodName'] == null
          ? null
          : slugifyAddressComponent(data['neighborhoodName'] as String),
      neighborhoodName: data['neighborhoodName'] as String?,
      streetId: data['streetName'] == null
          ? null
          : slugifyAddressComponent(data['streetName'] as String),
      streetName: data['streetName'] as String?,
      buildingNo: data['buildingNo'] as String?,
      buildingNoSource: data['buildingNoSource'] as String?,
      apartmentNo: data['apartmentNo'] as String? ?? '',
      floor: data['floor'] as String?,
      addressDescription: data['addressDescription'] as String?,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      verificationStatus: AddressVerificationStatus.values.byName(
        verificationStatusName,
      ),
      verifiedAt: data['verifiedAt'] == null
          ? null
          : DateTime.parse(data['verifiedAt'] as String),
      providerSource: data['providerSource'] as String?,
      providerPlaceId: data['providerPlaceId'] as String?,
      isDefault: data['isDefault'] as bool? ?? false,
      formattedAddress: data['formattedAddress'] as String?,
    );
  }
}

/// Faz P.2 — derives a provisional, name-based identifier for a
/// province/district/neighborhood/street when no canonical internal
/// reference-data source exists yet (that's Faz P.3's authoritative zone
/// registry, not built here — `docs/decisions.md` Faz P.2). Deliberately
/// simple (lowercase, Turkish-character folding, whitespace to
/// underscore) — good enough to compare/group by today, explicitly not
/// claimed to be a stable, canonical id that will survive a future P.3
/// migration unchanged.
String slugifyAddressComponent(String input) {
  const replacements = {
    'ç': 'c',
    'Ç': 'c',
    'ğ': 'g',
    'Ğ': 'g',
    'ı': 'i',
    'I': 'i',
    'İ': 'i',
    'i': 'i',
    'ö': 'o',
    'Ö': 'o',
    'ş': 's',
    'Ş': 's',
    'ü': 'u',
    'Ü': 'u',
  };
  var result = input.toLowerCase();
  replacements.forEach((from, to) {
    result = result.replaceAll(from.toLowerCase(), to);
  });
  result = result.trim().replaceAll(RegExp(r'\s+'), '_');
  result = result.replaceAll(RegExp(r'[^a-z0-9_]'), '');
  return result;
}
