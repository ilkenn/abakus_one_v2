import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

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
  Future<void> reportDelivered(String orderId, String paymentMethodId);
}

class CourierWorkException implements Exception {
  const CourierWorkException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'CourierWorkException($code): $message';
}

class FirebaseCourierWorkGateway implements CourierWorkGateway {
  FirebaseCourierWorkGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  bool get _useRest =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> _call(String name, Map<String, dynamic> data) async {
    if (_useRest) {
      try {
        await _restClient.call(name, data);
        return;
      } on RestCallableException catch (error) {
        throw CourierWorkException(error.code, error.message);
      }
    }
    try {
      await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
    } on functions.FirebaseFunctionsException catch (error) {
      throw CourierWorkException(
          error.code, error.message ?? 'İşlem gerçekleştirilemedi.');
    }
  }

  @override
  Future<void> requestPoolOrder(String orderId) =>
      _call('requestPoolOrder', {'orderId': orderId});

  @override
  Future<void> markDeparted(String orderId) =>
      _call('courierMarkDeparted', {'orderId': orderId});

  @override
  Future<void> reportDelivered(String orderId, String paymentMethodId) => _call(
      'courierReportDelivered',
      {'orderId': orderId, 'paymentMethodId': paymentMethodId});
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
  Future<void> reportDelivered(String orderId, String paymentMethodId) async =>
      throw _error;
}
