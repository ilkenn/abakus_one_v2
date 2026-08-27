import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../domain/trusted_device/trusted_device.dart';

/// AP-2 final wiring — direct Firestore reads staff are already permitted
/// to make (`trustedDeviceRegistrations`'s own rule:
/// `isOrgMember(...) && hasBranchAccess(...)`, unchanged this pass). No
/// list/read callable exists or is needed — mirrors
/// `AdminReservationRepository`'s exact "read the canonical backend-written
/// document directly" shape.
abstract interface class TrustedDeviceRepository {
  /// A live stream of every device registered for this branch, most
  /// recently registered first. Backend-unavailable (no Firebase, or the
  /// read itself fails) surfaces as a stream error — the caller is
  /// expected to render this as an explicit "backend unavailable" state,
  /// never a silent empty list.
  Stream<List<TrustedDevice>> watchDevicesForBranch({
    required String organizationId,
    required String branchId,
  });
}

class FirestoreTrustedDeviceRepository implements TrustedDeviceRepository {
  FirestoreTrustedDeviceRepository({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  // Lazily resolved — see `FirebasePlatformMemberRepository`'s identical
  // doc comment for why construction alone must never require a real
  // `Firebase.initializeApp()`.
  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  @override
  Stream<List<TrustedDevice>> watchDevicesForBranch({
    required String organizationId,
    required String branchId,
  }) {
    return _firestore
        .collection('trustedDeviceRegistrations')
        .where('organizationId', isEqualTo: organizationId)
        .where('branchId', isEqualTo: branchId)
        .orderBy('registeredAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            [for (final doc in snapshot.docs) _mapDevice(doc.data())]);
  }

  TrustedDevice _mapDevice(Map<String, dynamic> data) {
    return TrustedDevice(
      deviceId: data['deviceId'] as String,
      organizationId: data['organizationId'] as String,
      branchId: data['branchId'] as String,
      platform: trustedDevicePlatformFromWire(data['platform'] as String),
      capabilities: [
        for (final c in (data['capabilities'] as List))
          trustedDeviceCapabilityFromWire(c as String),
      ],
      status: trustedDeviceStatusFromWire(data['status'] as String),
      trustTier: trustedDeviceTrustTierFromWire(data['trustTier'] as String),
      registeredByUid: data['registeredByUid'] as String,
      registeredAt: (data['registeredAt'] as fs.Timestamp).toDate(),
      activatedAt: (data['activatedAt'] as fs.Timestamp?)?.toDate(),
      lastSeenAt: (data['lastSeenAt'] as fs.Timestamp?)?.toDate(),
      revokedAt: (data['revokedAt'] as fs.Timestamp?)?.toDate(),
      revokedReason: data['revokedReason'] as String?,
      version: data['version'] as int,
    );
  }
}

/// `firebaseReadyProvider` is false — an explicit, disclosed "backend
/// unavailable" stream rather than an empty list, so the UI renders a real
/// error state instead of a silently-empty (and misleading) device roster.
class UnavailableTrustedDeviceRepository implements TrustedDeviceRepository {
  const UnavailableTrustedDeviceRepository();

  @override
  Stream<List<TrustedDevice>> watchDevicesForBranch({
    required String organizationId,
    required String branchId,
  }) {
    return Stream.error(
        StateError('Trusted device backend is not available in this build.'));
  }
}
