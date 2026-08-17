import 'package:cloud_functions/cloud_functions.dart' as functions;

/// The advisory-only result of a `checkDeliveryEligibility` call — Paket
/// Servis P.3. **Never authorization**: `submitDeliveryOrder` always
/// independently re-reads and re-validates the address/service-area/
/// minimum-order rules for itself; this result exists only to let the
/// checkout screen show an early, honest UX signal before the customer
/// commits to "Siparişi Ver".
class DeliveryEligibilityResult {
  final bool eligible;

  /// One of `'address_not_verified'` / `'not_covered'` /
  /// `'ambiguous_configuration'` — `null` when [eligible] is `true`.
  final String? reason;

  /// `null` when ineligible for a reason unrelated to a minimum (or when
  /// no matching service area was found at all).
  final int? minimumOrderMinorUnits;

  const DeliveryEligibilityResult({
    required this.eligible,
    required this.reason,
    required this.minimumOrderMinorUnits,
  });
}

class CheckDeliveryEligibilityException implements Exception {
  final String code;
  final String message;

  const CheckDeliveryEligibilityException(this.code, this.message);

  @override
  String toString() => 'CheckDeliveryEligibilityException($code): $message';
}

abstract interface class CheckDeliveryEligibilityGateway {
  Future<DeliveryEligibilityResult> check({required String savedAddressId});
}

class FirebaseCheckDeliveryEligibilityGateway
    implements CheckDeliveryEligibilityGateway {
  const FirebaseCheckDeliveryEligibilityGateway();

  @override
  Future<DeliveryEligibilityResult> check({
    required String savedAddressId,
  }) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'checkDeliveryEligibility',
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'savedAddressId': savedAddressId,
      });
      final data = result.data;
      return DeliveryEligibilityResult(
        eligible: data['eligible'] as bool,
        reason: data['reason'] as String?,
        minimumOrderMinorUnits:
            (data['minimumOrderMinorUnits'] as num?)?.toInt(),
      );
    } on functions.FirebaseFunctionsException catch (error) {
      throw CheckDeliveryEligibilityException(
        error.code,
        error.message ?? 'Teslimat uygunluğu kontrol edilemedi.',
      );
    }
  }
}
