import 'package:cloud_functions/cloud_functions.dart' as functions;

/// Mirrors `AdminReservationException`'s exact shape — deliberately
/// duplicated rather than shared, matching that file's own established
/// precedent for a staff-facing, feature-scoped error type.
class TrustedDeviceException implements Exception {
  const TrustedDeviceException(this.code, this.message, [this.details]);

  final String code;
  final String message;
  final Map<String, dynamic>? details;

  @override
  String toString() => 'TrustedDeviceException($code): $message';
}

/// AP-2 final wiring — the real mutation surface for the Admin Devices
/// screen's Trusted Devices tab. Deliberately does NOT include
/// registration (`requestDeviceRegistration` is called by the physical
/// device itself during its own onboarding, never by a staff member
/// tapping a button in this app) or activation (activation is never a
/// direct mutation — it only ever happens through
/// `respondToApprovalRequest`, surfaced by the Approval Inbox).
abstract interface class TrustedDeviceGateway {
  Future<void> suspendDevice({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String reason,
  });

  Future<void> revokeDevice({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String reason,
  });

  Future<void> retireDevice({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String reason,
  });
}

class FirebaseTrustedDeviceGateway implements TrustedDeviceGateway {
  const FirebaseTrustedDeviceGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw TrustedDeviceException(
      error.code,
      error.message ?? 'İşlem tamamlanamadı.',
      error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : null,
    );
  }

  @override
  Future<void> suspendDevice({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String reason,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('suspendTrustedDevice');
    try {
      await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'deviceId': deviceId,
        'reason': reason,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> revokeDevice({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String reason,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('revokeTrustedDevice');
    try {
      await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'deviceId': deviceId,
        'reason': reason,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> retireDevice({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String reason,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('retireTrustedDevice');
    try {
      await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'deviceId': deviceId,
        'reason': reason,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

/// `firebaseReadyProvider` is false — every mutation fails closed with an
/// explicit, typed exception rather than silently no-op'ing.
class UnavailableTrustedDeviceGateway implements TrustedDeviceGateway {
  const UnavailableTrustedDeviceGateway();

  Never _unavailable() => throw const TrustedDeviceException(
      'unavailable', 'Cihaz yönetimi backend\'i bu ortamda kullanılamıyor.');

  @override
  Future<void> suspendDevice({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String reason,
  }) async =>
      _unavailable();

  @override
  Future<void> revokeDevice({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String reason,
  }) async =>
      _unavailable();

  @override
  Future<void> retireDevice({
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String reason,
  }) async =>
      _unavailable();
}
