import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:flutter/foundation.dart'
    show TargetPlatform, Uint8List, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';
import '../domain/work/courier_work_models.dart';

/// 2026-11-12 (Faz 3b) — the courier app's server read model: the signed-in
/// courier's own account link (`courierAccounts/{uid}`), its orders
/// (`courierAssignedOrders`, the only place it sees a customer phone), the
/// open pool packages of its districts (`deliveryPoolListings`, external
/// couriers only) and its own pool requests. Every query pins what
/// `firestore.rules` requires (organizationId, the courier's uid, one
/// district + status).
abstract interface class CourierWorkRepository {
  Stream<CourierWorkAccount?> watchAccount(String uid);

  Stream<List<CourierWorkOrder>> watchAssignedOrders({
    required String uid,
    required String organizationId,
  });

  Stream<List<CourierPoolPackage>> watchPoolPackages({
    required String organizationId,
    required List<String> districtIds,
  });

  Stream<List<CourierOwnPoolRequest>> watchOwnRequests({
    required String uid,
    required String organizationId,
  });
}

class FirestoreCourierWorkRepository implements CourierWorkRepository {
  FirestoreCourierWorkRepository({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _db =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  @override
  Stream<CourierWorkAccount?> watchAccount(String uid) => _db
      .collection('courierAccounts')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists
          ? CourierWorkAccount.fromFirestore(uid, doc.data()!)
          : null);

  @override
  Stream<List<CourierWorkOrder>> watchAssignedOrders({
    required String uid,
    required String organizationId,
  }) =>
      _db
          .collection('courierAssignedOrders')
          .where('organizationId', isEqualTo: organizationId)
          .where('courierAuthUid', isEqualTo: uid)
          .snapshots()
          .map((snap) {
        final orders = [
          for (final doc in snap.docs)
            CourierWorkOrder.fromFirestore(doc.id, doc.data()),
        ]..sort((a, b) => a.statusRank.compareTo(b.statusRank));
        return orders;
      });

  @override
  Stream<List<CourierPoolPackage>> watchPoolPackages({
    required String organizationId,
    required List<String> districtIds,
  }) {
    if (districtIds.isEmpty) return Stream.value(const []);
    // One listener per district: the rule checks `districtId in` the
    // courier's districts, which a single `==` filter lets it prove.
    final latest = <String, List<CourierPoolPackage>>{};
    final controller = StreamController<List<CourierPoolPackage>>();
    final subscriptions = <StreamSubscription<void>>[];
    void emit() {
      if (latest.length < districtIds.length) return;
      final all = [for (final list in latest.values) ...list]..sort((a, b) =>
          (a.publishedAt ?? DateTime(0))
              .compareTo(b.publishedAt ?? DateTime(0)));
      controller.add(all);
    }

    controller.onListen = () {
      for (final districtId in districtIds) {
        subscriptions.add(_db
            .collection('deliveryPoolListings')
            .where('organizationId', isEqualTo: organizationId)
            .where('districtId', isEqualTo: districtId)
            .where('status', isEqualTo: 'open')
            .snapshots()
            .listen((snap) {
          latest[districtId] = [
            for (final doc in snap.docs)
              CourierPoolPackage.fromFirestore(doc.id, doc.data()),
          ];
          emit();
        }, onError: controller.addError));
      }
    };
    controller.onCancel = () async {
      for (final s in subscriptions) {
        await s.cancel();
      }
    };
    return controller.stream;
  }

  @override
  Stream<List<CourierOwnPoolRequest>> watchOwnRequests({
    required String uid,
    required String organizationId,
  }) =>
      _db
          .collection('courierPoolRequests')
          .where('organizationId', isEqualTo: organizationId)
          .where('courierAuthUid', isEqualTo: uid)
          .snapshots()
          .map((snap) {
        final requests = [
          for (final doc in snap.docs)
            CourierOwnPoolRequest.fromFirestore(doc.id, doc.data()),
        ]..sort((a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
        return requests;
      });
}

/// The courier's own actions — `requestPoolOrder`, `courierMarkDeparted`,
/// `courierReportDelivered` (`functions/src/courierPool.ts`).
abstract interface class CourierWorkGateway {
  Future<void> requestPoolOrder(String orderId);
  Future<void> markDeparted(String orderId);

  /// "Teslim Ettim". [paymentMethodId] is `null` for an order paid online.
  /// A card or meal card needs [slipPhoto] (a camera photo, JPEG) — ADR-085
  /// stage 6B; it is uploaded under a one-use grant first.
  Future<void> reportDelivered(
    String orderId,
    String? paymentMethodId, {
    Uint8List? slipPhoto,
  });

  /// "İptal Talebi Gönder" (stage 6B) — goes to the Onay Kutusu.
  Future<void> requestCancellation(String orderId, String reason);
}

class CourierWorkException implements Exception {
  const CourierWorkException(this.code, this.message, {this.detailCode});
  final String code;
  final String message;

  /// The server's `details.code` (e.g. `courierDelivery/slip-required`).
  final String? detailCode;

  @override
  String toString() => 'CourierWorkException($code): $message';
}

class FirebaseCourierWorkGateway implements CourierWorkGateway {
  FirebaseCourierWorkGateway({RestCallableClient? restClient})
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
        throw CourierWorkException(error.code, error.message,
            detailCode: error.details?['code'] as String?);
      }
    }
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(result.data);
    } on functions.FirebaseFunctionsException catch (error) {
      final details = error.details;
      throw CourierWorkException(
          error.code, error.message ?? 'İşlem gerçekleştirilemedi.',
          detailCode: details is Map ? details['code'] as String? : null);
    }
  }

  @override
  Future<void> requestPoolOrder(String orderId) async {
    await _call('requestPoolOrder', {'orderId': orderId});
  }

  @override
  Future<void> markDeparted(String orderId) async {
    await _call('courierMarkDeparted', {'orderId': orderId});
  }

  @override
  Future<void> reportDelivered(
    String orderId,
    String? paymentMethodId, {
    Uint8List? slipPhoto,
  }) async {
    String? slipGrantId;
    if (slipPhoto != null) {
      final grant = await _call('requestCourierUploadGrant', {
        'purpose': 'paymentSlip',
        'orderId': orderId,
        'contentType': 'image/jpeg',
      });
      try {
        await storage.FirebaseStorage.instance
            .ref(grant['objectPath'] as String)
            .putData(
                slipPhoto, storage.SettableMetadata(contentType: 'image/jpeg'));
      } on storage.FirebaseException {
        throw const CourierWorkException('slip-upload', 'Upload failed.',
            detailCode: 'courierDelivery/slip-missing');
      }
      slipGrantId = grant['grantId'] as String?;
    }
    await _call('courierReportDelivered', {
      'orderId': orderId,
      if (paymentMethodId != null) 'paymentMethodId': paymentMethodId,
      if (slipGrantId != null) 'slipGrantId': slipGrantId,
    });
  }

  @override
  Future<void> requestCancellation(String orderId, String reason) async {
    await _call('courierRequestCancellation',
        {'orderId': orderId, 'reason': reason.trim()});
  }
}

class UnavailableCourierWorkGateway implements CourierWorkGateway {
  const UnavailableCourierWorkGateway();

  static const _error = CourierWorkException(
      'unavailable', 'Sunucu bağlantısı hazır değil. Lütfen tekrar deneyin.');

  @override
  Future<void> requestPoolOrder(String orderId) async => throw _error;

  @override
  Future<void> markDeparted(String orderId) async => throw _error;

  @override
  Future<void> reportDelivered(
    String orderId,
    String? paymentMethodId, {
    Uint8List? slipPhoto,
  }) async =>
      throw _error;

  @override
  Future<void> requestCancellation(String orderId, String reason) async =>
      throw _error;
}
