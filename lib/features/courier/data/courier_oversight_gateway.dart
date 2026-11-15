import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, Uint8List, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';

/// A refused oversight command, already in Turkish.
class CourierOversightException implements Exception {
  const CourierOversightException(this.message);
  final String message;
  @override
  String toString() => 'CourierOversightException: $message';
}

enum CourierPaymentChangeStatus {
  pendingReview,
  reviewed;

  String get label => this == CourierPaymentChangeStatus.pendingReview
      ? 'İnceleme Bekliyor'
      : 'İncelendi';
}

/// ADR-085 stage 6B — a courier switched the payment method at the door.
class CourierPaymentChange {
  const CourierPaymentChange({
    required this.orderId,
    required this.orderNumber,
    required this.courierName,
    required this.fromLabel,
    required this.toLabel,
    required this.amountDueMinorUnits,
    required this.hasSlip,
    required this.status,
    required this.reportedAt,
    required this.reviewNote,
  });

  final String orderId;
  final String orderNumber;
  final String courierName;
  final String fromLabel;
  final String toLabel;
  final int amountDueMinorUnits;
  final bool hasSlip;
  final CourierPaymentChangeStatus status;
  final DateTime reportedAt;
  final String? reviewNote;

  factory CourierPaymentChange.fromJson(Map<String, dynamic> json) =>
      CourierPaymentChange(
        orderId: json['orderId'] as String? ?? '',
        orderNumber: json['orderNumber'] as String? ?? '',
        courierName: json['courierName'] as String? ?? '',
        fromLabel: json['fromMethodLabel'] as String? ?? '-',
        toLabel: json['toMethodLabel'] as String? ?? '-',
        amountDueMinorUnits:
            (json['amountDueMinorUnits'] as num?)?.toInt() ?? 0,
        hasSlip: json['hasSlip'] == true,
        status: json['status'] == 'reviewed'
            ? CourierPaymentChangeStatus.reviewed
            : CourierPaymentChangeStatus.pendingReview,
        reportedAt: DateTime.fromMillisecondsSinceEpoch(
                (json['reportedAtMillis'] as num?)?.toInt() ?? 0,
                isUtc: true)
            .toLocal(),
        reviewNote: json['reviewNote'] as String?,
      );
}

/// The panel's courier oversight: payment-method changes and their slips
/// (`functions/src/courierDeliveryControls.ts`). The server limits a
/// manager to its branches.
abstract interface class CourierOversightGateway {
  Future<List<CourierPaymentChange>> paymentChanges({
    required String organizationId,
  });

  Future<void> markReviewed({
    required String organizationId,
    required String orderId,
    String? note,
  });

  Future<Uint8List> slipPhoto({
    required String organizationId,
    required String orderId,
  });
}

class FirebaseCourierOversightGateway implements CourierOversightGateway {
  FirebaseCourierOversightGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  static String messageFor(String code, String? detailCode) {
    switch (detailCode) {
      case 'courierPaymentChange/already-reviewed':
        return 'Bu değişiklik zaten incelendi.';
      case 'courierDelivery/no-slip':
        return 'Bu siparişin slip fotoğrafı yok.';
    }
    switch (code) {
      case 'permission-denied':
      case 'permission_denied':
        return 'Bu işlem için yetkiniz yok.';
      case 'not-found':
      case 'not_found':
        return 'Kayıt bulunamadı.';
      default:
        return 'İşlem tamamlanamadı. Bağlantınızı kontrol edip tekrar deneyin.';
    }
  }

  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      try {
        return await _restClient.call(name, data);
      } on RestCallableException catch (error) {
        throw CourierOversightException(
            messageFor(error.code, error.details?['code'] as String?));
      }
    }
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(result.data);
    } on functions.FirebaseFunctionsException catch (error) {
      final details = error.details;
      throw CourierOversightException(messageFor(
          error.code, details is Map ? details['code'] as String? : null));
    }
  }

  @override
  Future<List<CourierPaymentChange>> paymentChanges({
    required String organizationId,
  }) async {
    final result = await _call(
        'listCourierPaymentChanges', {'organizationId': organizationId});
    return [
      for (final change in (result['changes'] as List? ?? const []))
        CourierPaymentChange.fromJson(Map<String, dynamic>.from(change as Map)),
    ];
  }

  @override
  Future<void> markReviewed({
    required String organizationId,
    required String orderId,
    String? note,
  }) async {
    await _call('reviewCourierPaymentChange', {
      'organizationId': organizationId,
      'orderId': orderId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  @override
  Future<Uint8List> slipPhoto({
    required String organizationId,
    required String orderId,
  }) async {
    final result = await _call('getCourierPaymentSlip',
        {'organizationId': organizationId, 'orderId': orderId});
    return base64Decode(result['base64'] as String? ?? '');
  }
}

class UnavailableCourierOversightGateway implements CourierOversightGateway {
  const UnavailableCourierOversightGateway();

  static const _error = CourierOversightException(
      'Sunucu bağlantısı hazır değil. Lütfen tekrar deneyin.');

  @override
  Future<List<CourierPaymentChange>> paymentChanges({
    required String organizationId,
  }) async =>
      throw _error;

  @override
  Future<void> markReviewed({
    required String organizationId,
    required String orderId,
    String? note,
  }) async =>
      throw _error;

  @override
  Future<Uint8List> slipPhoto({
    required String organizationId,
    required String orderId,
  }) async =>
      throw _error;
}
