import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';

/// 2026-11-12 (Faz 3a) — the POS side of the external-courier delivery pool
/// (`functions/src/courierPool.ts`): "Havuza Gönder" / "Havuzdan Geri Al"
/// and approving/rejecting an external courier's request. REST on Windows,
/// like every POS gateway.
abstract interface class CourierPoolGateway {
  Future<void> publish({required String orderId});
  Future<void> withdraw({required String orderId});
  Future<void> respond({required String requestId, required bool approve});

  /// 2026-11-12 (Faz 3b) — the branch's pool region: its default district
  /// and the districts its service areas cover.
  Future<BranchPoolSettings> branchSettings({
    required String organizationId,
    required String branchId,
  });

  /// Manager-and-above. An empty [districtId] clears the default.
  Future<BranchPoolSettings> setDefaultDistrict({
    required String organizationId,
    required String branchId,
    required String districtId,
  });
}

class BranchPoolSettings {
  const BranchPoolSettings({
    required this.defaultDeliveryDistrictId,
    required this.serviceDistrictIds,
  });

  final String? defaultDeliveryDistrictId;
  final List<String> serviceDistrictIds;

  factory BranchPoolSettings.fromWire(Map<String, dynamic> data) =>
      BranchPoolSettings(
        defaultDeliveryDistrictId: data['defaultDeliveryDistrictId'] as String?,
        serviceDistrictIds: [
          for (final d in (data['serviceDistrictIds'] as List?) ?? const [])
            if (d is String) d,
        ],
      );
}

class CourierPoolException implements Exception {
  const CourierPoolException(this.code, this.message);
  final String code;
  final String message;

  bool get isPermissionDenied =>
      code == 'permission-denied' || code == 'permission_denied';

  @override
  String toString() => 'CourierPoolException($code): $message';
}

class FirebaseCourierPoolGateway implements CourierPoolGateway {
  FirebaseCourierPoolGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  bool get _useRest =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    if (_useRest) {
      try {
        return await _restClient.call(name, data);
      } on RestCallableException catch (error) {
        throw CourierPoolException(error.code, error.message);
      }
    }
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(result.data);
    } on functions.FirebaseFunctionsException catch (error) {
      throw CourierPoolException(
          error.code, error.message ?? 'İşlem gerçekleştirilemedi.');
    }
  }

  @override
  Future<void> publish({required String orderId}) =>
      _call('publishOrderToPool', {'orderId': orderId});

  @override
  Future<void> withdraw({required String orderId}) =>
      _call('withdrawOrderFromPool', {'orderId': orderId});

  @override
  Future<void> respond({required String requestId, required bool approve}) =>
      _call('respondToCourierPoolRequest', {
        'requestId': requestId,
        'decision': approve ? 'approve' : 'reject',
      });

  @override
  Future<BranchPoolSettings> branchSettings({
    required String organizationId,
    required String branchId,
  }) async =>
      BranchPoolSettings.fromWire(await _call('getBranchPoolSettings',
          {'organizationId': organizationId, 'branchId': branchId}));

  @override
  Future<BranchPoolSettings> setDefaultDistrict({
    required String organizationId,
    required String branchId,
    required String districtId,
  }) async {
    await _call('setBranchDefaultDeliveryDistrict', {
      'organizationId': organizationId,
      'branchId': branchId,
      'districtId': districtId,
    });
    return branchSettings(organizationId: organizationId, branchId: branchId);
  }
}

class UnavailableCourierPoolGateway implements CourierPoolGateway {
  const UnavailableCourierPoolGateway();

  static const _error = CourierPoolException(
      'unavailable', 'Sunucu bağlantısı hazır değil. Lütfen tekrar deneyin.');

  @override
  Future<void> publish({required String orderId}) async => throw _error;

  @override
  Future<void> withdraw({required String orderId}) async => throw _error;

  @override
  Future<void> respond(
          {required String requestId, required bool approve}) async =>
      throw _error;

  @override
  Future<BranchPoolSettings> branchSettings({
    required String organizationId,
    required String branchId,
  }) async =>
      throw _error;

  @override
  Future<BranchPoolSettings> setDefaultDistrict({
    required String organizationId,
    required String branchId,
    required String districtId,
  }) async =>
      throw _error;
}

/// One pending "Talep Oluştur" from an external courier
/// (`courierPoolRequests`). Never carries the customer's phone or name.
class CourierPoolRequest {
  const CourierPoolRequest({
    required this.requestId,
    required this.orderId,
    required this.orderNumber,
    required this.courierId,
    required this.courierName,
    required this.neighborhoodName,
    required this.amountDueMinorUnits,
    this.createdAt,
  });

  final String requestId;
  final String orderId;
  final String orderNumber;
  final String courierId;
  final String courierName;
  final String neighborhoodName;
  final int amountDueMinorUnits;
  final DateTime? createdAt;

  factory CourierPoolRequest.fromFirestore(
      String id, Map<String, dynamic> data) {
    final created = data['createdAt'];
    return CourierPoolRequest(
      requestId: id,
      orderId: data['orderId'] as String? ?? '',
      orderNumber: data['orderNumber'] as String? ?? '',
      courierId: data['courierId'] as String? ?? '',
      courierName: data['courierName'] as String? ?? '',
      neighborhoodName: data['neighborhoodName'] as String? ?? '',
      amountDueMinorUnits: (data['amountDueMinorUnits'] as num?)?.toInt() ?? 0,
      createdAt: created is fs.Timestamp ? created.toDate() : null,
    );
  }
}

/// The live request panel's read: a Firestore listener on the branch's
/// pending requests (the query pins organizationId + branchId + status, as
/// `firestore.rules` requires), oldest first.
abstract interface class CourierPoolRequestRepository {
  Stream<List<CourierPoolRequest>> watchPending({
    required String organizationId,
    required String branchId,
  });
}

class FirestoreCourierPoolRequestRepository
    implements CourierPoolRequestRepository {
  FirestoreCourierPoolRequestRepository({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  @override
  Stream<List<CourierPoolRequest>> watchPending({
    required String organizationId,
    required String branchId,
  }) {
    return _firestore
        .collection('courierPoolRequests')
        .where('organizationId', isEqualTo: organizationId)
        .where('branchId', isEqualTo: branchId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) {
      final requests = [
        for (final doc in snap.docs)
          CourierPoolRequest.fromFirestore(doc.id, doc.data()),
      ];
      requests.sort((a, b) =>
          (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
      return requests;
    });
  }
}
