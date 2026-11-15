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

enum CourierAlertType {
  cashLimit,
  late;

  static CourierAlertType parse(Object? raw) =>
      raw == 'courierLate' ? CourierAlertType.late : CourierAlertType.cashLimit;
}

/// ADR-085 stage 6C-1 — an open field alert: a courier over the cash
/// limit, or a package late on the road.
class CourierOperationalAlert {
  const CourierOperationalAlert({
    required this.alertId,
    required this.type,
    required this.courierName,
    required this.orderId,
    required this.orderNumber,
    required this.amountMinorUnits,
    required this.limitMinorUnits,
    required this.minutes,
    required this.openedAt,
  });

  final String alertId;
  final CourierAlertType type;
  final String courierName;
  final String? orderId;
  final String? orderNumber;
  final int? amountMinorUnits;
  final int? limitMinorUnits;
  final int? minutes;
  final DateTime openedAt;

  factory CourierOperationalAlert.fromJson(Map<String, dynamic> json) =>
      CourierOperationalAlert(
        alertId: json['alertId'] as String? ?? '',
        type: CourierAlertType.parse(json['type']),
        courierName: json['courierName'] as String? ?? '',
        orderId: json['orderId'] as String?,
        orderNumber: json['orderNumber'] as String?,
        amountMinorUnits: (json['amountMinorUnits'] as num?)?.toInt(),
        limitMinorUnits: (json['limitMinorUnits'] as num?)?.toInt(),
        minutes: (json['minutes'] as num?)?.toInt(),
        openedAt: DateTime.fromMillisecondsSinceEpoch(
                (json['openedAtMillis'] as num?)?.toInt() ?? 0,
                isUtc: true)
            .toLocal(),
      );
}

/// The branch's courier cash limit and late threshold.
typedef CourierOperationSettings = ({
  int cashLimitMinorUnits,
  int lateDeliveryMinutes,
});

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

  /// Stage 6C-1 — open field alerts of the caller's branches.
  Future<List<CourierOperationalAlert>> alerts({
    required String organizationId,
  });

  Future<CourierOperationSettings> settings({
    required String organizationId,
    required String branchId,
  });

  Future<void> saveSettings({
    required String organizationId,
    required String branchId,
    required CourierOperationSettings settings,
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
      case 'courierSettings/invalid-cash-limit':
        return 'Geçerli bir nakit limiti girin.';
      case 'courierSettings/invalid-late-minutes':
        return 'Gecikme süresi 5 ile 240 dakika arasında olmalı.';
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

  @override
  Future<List<CourierOperationalAlert>> alerts({
    required String organizationId,
  }) async {
    final result = await _call(
        'listOperationalAlerts', {'organizationId': organizationId});
    return [
      for (final alert in (result['alerts'] as List? ?? const []))
        CourierOperationalAlert.fromJson(
            Map<String, dynamic>.from(alert as Map)),
    ];
  }

  @override
  Future<CourierOperationSettings> settings({
    required String organizationId,
    required String branchId,
  }) async {
    final result = await _call('getBranchCourierSettings',
        {'organizationId': organizationId, 'branchId': branchId});
    return (
      cashLimitMinorUnits:
          (result['cashLimitMinorUnits'] as num?)?.toInt() ?? 300000,
      lateDeliveryMinutes:
          (result['lateDeliveryMinutes'] as num?)?.toInt() ?? 35,
    );
  }

  @override
  Future<void> saveSettings({
    required String organizationId,
    required String branchId,
    required CourierOperationSettings settings,
  }) async {
    await _call('setBranchCourierSettings', {
      'organizationId': organizationId,
      'branchId': branchId,
      'cashLimitMinorUnits': settings.cashLimitMinorUnits,
      'lateDeliveryMinutes': settings.lateDeliveryMinutes,
    });
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

  @override
  Future<List<CourierOperationalAlert>> alerts({
    required String organizationId,
  }) async =>
      throw _error;

  @override
  Future<CourierOperationSettings> settings({
    required String organizationId,
    required String branchId,
  }) async =>
      throw _error;

  @override
  Future<void> saveSettings({
    required String organizationId,
    required String branchId,
    required CourierOperationSettings settings,
  }) async =>
      throw _error;
}
