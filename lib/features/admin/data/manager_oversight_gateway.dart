import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';

/// A refused "Müdür İşlemleri" command, already in Turkish.
class ManagerOversightException implements Exception {
  const ManagerOversightException(this.message);
  final String message;
  @override
  String toString() => 'ManagerOversightException: $message';
}

/// ADR-085 stage 6C-2 — what a branch manager did at once, without a second
/// person's approval.
enum ManagerActionType {
  comp,
  lineCancellation,
  orderCancellation,
  cashVariance;

  static ManagerActionType parse(Object? raw) => switch (raw) {
        'managerLineCancellation' => ManagerActionType.lineCancellation,
        'managerOrderCancellation' => ManagerActionType.orderCancellation,
        'managerCashVariance' => ManagerActionType.cashVariance,
        _ => ManagerActionType.comp,
      };

  String get label => switch (this) {
        ManagerActionType.comp => 'İkram / İndirim',
        ManagerActionType.lineCancellation => 'Ürün İptali',
        ManagerActionType.orderCancellation => 'Sipariş İptali',
        ManagerActionType.cashVariance => 'Kasa Sayım Farkı',
      };
}

/// One manager action alert (server-written, never edited except "Görüldü").
class ManagerActionAlert {
  const ManagerActionAlert({
    required this.alertId,
    required this.branchId,
    required this.type,
    required this.actorName,
    required this.orderNumber,
    required this.amountMinorUnits,
    required this.detail,
    required this.reason,
    required this.createdAt,
    required this.acknowledged,
  });

  final String alertId;
  final String branchId;
  final ManagerActionType type;
  final String? actorName;
  final String? orderNumber;
  final int? amountMinorUnits;

  /// Comp kind (`complimentary`/`percentage`/`fixedAmount`), cash `over`/
  /// `short`, the cancelled product or the cancellation reason code.
  final String? detail;
  final String reason;
  final DateTime createdAt;
  final bool acknowledged;

  /// A cash shortfall reads as a negative amount.
  int? get signedAmountMinorUnits {
    final amount = amountMinorUnits;
    if (amount == null) return null;
    return type == ManagerActionType.cashVariance && detail == 'short'
        ? -amount
        : amount;
  }

  factory ManagerActionAlert.fromJson(Map<String, dynamic> json) =>
      ManagerActionAlert(
        alertId: json['alertId'] as String? ?? '',
        branchId: json['branchId'] as String? ?? '',
        type: ManagerActionType.parse(json['type']),
        actorName: json['actorName'] as String?,
        orderNumber: json['orderNumber'] as String?,
        amountMinorUnits: (json['amountMinorUnits'] as num?)?.toInt(),
        detail: json['detail'] as String?,
        reason: json['reason'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
                (json['createdAtMillis'] as num?)?.toInt() ?? 0,
                isUtc: true)
            .toLocal(),
        acknowledged: json['acknowledged'] == true,
      );
}

abstract interface class ManagerOversightGateway {
  Future<List<ManagerActionAlert>> alerts({required String organizationId});

  Future<void> acknowledge({
    required String organizationId,
    required String alertId,
  });
}

class FirebaseManagerOversightGateway implements ManagerOversightGateway {
  FirebaseManagerOversightGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  static String messageFor(String code) => switch (code) {
        'permission-denied' ||
        'permission_denied' =>
          'Müdür işlemlerini yalnızca Yönetici ve İşletme Sahibi görebilir.',
        'not-found' || 'not_found' => 'Kayıt bulunamadı.',
        _ => 'İşlem tamamlanamadı. Bağlantınızı kontrol edip tekrar deneyin.',
      };

  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      try {
        return await _restClient.call(name, data);
      } on RestCallableException catch (error) {
        throw ManagerOversightException(messageFor(error.code));
      }
    }
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(result.data);
    } on functions.FirebaseFunctionsException catch (error) {
      throw ManagerOversightException(messageFor(error.code));
    }
  }

  @override
  Future<List<ManagerActionAlert>> alerts(
      {required String organizationId}) async {
    final data =
        await _call('listOversightAlerts', {'organizationId': organizationId});
    return [
      for (final raw in (data['alerts'] as List?) ?? const [])
        ManagerActionAlert.fromJson(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  @override
  Future<void> acknowledge({
    required String organizationId,
    required String alertId,
  }) async {
    await _call('acknowledgeOversightAlert',
        {'organizationId': organizationId, 'alertId': alertId});
  }
}

class UnavailableManagerOversightGateway implements ManagerOversightGateway {
  const UnavailableManagerOversightGateway();

  static const _error =
      ManagerOversightException('Müdür işlemleri şu anda yüklenemiyor.');

  @override
  Future<List<ManagerActionAlert>> alerts(
          {required String organizationId}) async =>
      throw _error;

  @override
  Future<void> acknowledge({
    required String organizationId,
    required String alertId,
  }) async =>
      throw _error;
}
