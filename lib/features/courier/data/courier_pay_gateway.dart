import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../core/services/functions/rest_callable_client.dart';
import '../domain/pay/courier_pay_models.dart';

/// A refused courier-pay command, already in Turkish.
class CourierPayException implements Exception {
  const CourierPayException(this.message);
  final String message;
  @override
  String toString() => 'CourierPayException: $message';
}

/// ADR-085 stage 5 — the callables of `functions/src/courierPay.ts`. The
/// server decides who may set a rate, approve a shift or see an earning;
/// this client only carries the request.
abstract interface class CourierPayGateway {
  /// The rate in force for a courier staff account, or `null`.
  Future<CourierPayRate?> currentRate({
    required String organizationId,
    required String targetUid,
  });

  Future<void> setRate({
    required String organizationId,
    required String targetUid,
    required CourierPayRateInput input,
  });

  Future<List<CourierShift>> listOpenShifts({required String organizationId});

  /// [approve] `false` rejects a start. [approvedAt] corrects the pressed
  /// time (then [reason] is required).
  Future<void> reviewShift({
    required String organizationId,
    required String shiftId,
    required bool approve,
    DateTime? approvedAt,
    String? reason,
  });

  /// Ends a running shift the courier forgot to end, at [endedAt], with a
  /// mandatory [reason].
  Future<void> closeShift({
    required String organizationId,
    required String shiftId,
    required DateTime endedAt,
    required String reason,
  });

  Future<CourierEarningsReport> earnings({
    required String organizationId,
    required String fromDate,
    required String toDate,
  });

  Future<MyCourierPay> myPay({
    required String fromDate,
    required String toDate,
  });

  Future<void> startShift();

  Future<void> endShift();
}

class FirebaseCourierPayGateway implements CourierPayGateway {
  FirebaseCourierPayGateway({RestCallableClient? restClient})
      : _restClient = restClient ?? RestCallableClient();

  final RestCallableClient _restClient;

  /// Turkish text for a refused call: the server's detail code first, then
  /// the callable error code.
  static String messageFor(String code, String? detailCode) {
    switch (detailCode) {
      case 'courierPay/backdated':
        return 'Ücret geçmiş bir tarihten başlatılamaz.';
      case 'courierPay/invalid-date':
        return 'Başlangıç tarihi en geç bir yıl sonrası olabilir.';
      case 'courierPay/invalid-rate':
        return 'Ücretleri kontrol edin: en az biri sıfırdan büyük olmalı.';
      case 'courierPay/pool-needs-admin':
        return 'Havuz kuryesi ücretini yalnızca Yönetici veya Sahip '
            'belirleyebilir.';
      case 'courierPay/not-courier':
        return 'Bu personel kurye değil.';
      case 'courierShift/no-hourly-rate':
        return 'Saatlik ücretiniz tanımlı değil. Şube müdürünüze başvurun.';
      case 'courierShift/already-open':
        return 'Açık bir vardiyanız zaten var.';
      case 'courierShift/start-not-approved':
        return 'Vardiya başlangıcınız henüz onaylanmadı.';
      case 'courierShift/end-requested':
        return 'Vardiya bitişiniz zaten onaya gönderildi.';
      case 'courierShift/none-open':
        return 'Açık vardiyanız yok.';
      case 'courierShift/pool-courier':
        return 'Havuz kuryeleri vardiya kullanmaz.';
      case 'courierShift/reason-required':
        return 'Saati değiştirdiğinizde gerekçe yazmanız gerekir.';
      case 'courierShift/future-time':
        return 'Onaylanan saat ileri bir saat olamaz.';
      case 'courierShift/adjust-too-far':
        return 'Düzeltilen saat, basılan saatten en fazla 12 saat farklı '
            'olabilir.';
      case 'courierShift/end-before-start':
        return 'Bitiş saati başlangıçtan sonra olmalı.';
      case 'courierShift/end-not-rejectable':
        return 'Vardiya bitişi reddedilemez; gerekirse saati düzeltin.';
      case 'courierShift/not-pending':
        return 'Bu vardiya artık onay beklemiyor.';
      case 'courierShift/not-running':
        return 'Bu vardiya artık sürmüyor.';
      case 'courierShift/end-time-required':
        return 'Vardiyanın bittiği saati seçin.';
      case 'courierShift/too-long':
        return 'Bir vardiya en fazla 24 saat sürebilir.';
    }
    switch (code) {
      case 'permission-denied':
      case 'permission_denied':
        return 'Bu işlem için yetkiniz yok.';
      case 'not-found':
      case 'not_found':
        return 'Kayıt bulunamadı.';
      case 'invalid-argument':
      case 'invalid_argument':
        return 'Bilgileri kontrol edin.';
      case 'unauthenticated':
        return 'Oturumunuz sona ermiş. Lütfen tekrar giriş yapın.';
      default:
        return 'İşlem tamamlanamadı. Bağlantınızı kontrol edip tekrar deneyin.';
    }
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final useRest = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (useRest) {
      try {
        return await _restClient.call(name, data);
      } on RestCallableException catch (error) {
        throw CourierPayException(
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
      throw CourierPayException(messageFor(
          error.code, details is Map ? details['code'] as String? : null));
    }
  }

  @override
  Future<CourierPayRate?> currentRate({
    required String organizationId,
    required String targetUid,
  }) async {
    final result = await _call('getCourierPayProfile', {
      'organizationId': organizationId,
      'targetUid': targetUid,
    });
    final current = result['current'];
    return current is Map
        ? CourierPayRate.fromJson(Map<String, dynamic>.from(current))
        : null;
  }

  @override
  Future<void> setRate({
    required String organizationId,
    required String targetUid,
    required CourierPayRateInput input,
  }) async {
    await _call('setCourierPayRate', {
      'organizationId': organizationId,
      'targetUid': targetUid,
      ...input.toJson(),
    });
  }

  @override
  Future<List<CourierShift>> listOpenShifts({
    required String organizationId,
  }) async {
    final result =
        await _call('listCourierShifts', {'organizationId': organizationId});
    return [
      for (final shift in (result['shifts'] as List? ?? const []))
        CourierShift.fromJson(Map<String, dynamic>.from(shift as Map)),
    ];
  }

  @override
  Future<void> reviewShift({
    required String organizationId,
    required String shiftId,
    required bool approve,
    DateTime? approvedAt,
    String? reason,
  }) async {
    await _call('reviewCourierShift', {
      'organizationId': organizationId,
      'shiftId': shiftId,
      'decision': approve ? 'approve' : 'reject',
      if (approvedAt != null)
        'approvedAtMillis': approvedAt.millisecondsSinceEpoch,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  @override
  Future<void> closeShift({
    required String organizationId,
    required String shiftId,
    required DateTime endedAt,
    required String reason,
  }) async {
    await _call('reviewCourierShift', {
      'organizationId': organizationId,
      'shiftId': shiftId,
      'decision': 'close',
      'approvedAtMillis': endedAt.millisecondsSinceEpoch,
      'reason': reason.trim(),
    });
  }

  @override
  Future<CourierEarningsReport> earnings({
    required String organizationId,
    required String fromDate,
    required String toDate,
  }) async =>
      CourierEarningsReport.fromJson(await _call('getCourierEarnings', {
        'organizationId': organizationId,
        'fromDate': fromDate,
        'toDate': toDate,
      }));

  @override
  Future<MyCourierPay> myPay({
    required String fromDate,
    required String toDate,
  }) async =>
      MyCourierPay.fromJson(await _call(
          'getMyCourierPay', {'fromDate': fromDate, 'toDate': toDate}));

  @override
  Future<void> startShift() async {
    await _call('courierStartShift', {});
  }

  @override
  Future<void> endShift() async {
    await _call('courierEndShift', {});
  }
}

/// Selected whenever Firebase isn't ready — every command fails honestly.
class UnavailableCourierPayGateway implements CourierPayGateway {
  const UnavailableCourierPayGateway();

  static const _error = CourierPayException(
      'Sunucu bağlantısı hazır değil. Lütfen tekrar deneyin.');

  @override
  Future<CourierPayRate?> currentRate({
    required String organizationId,
    required String targetUid,
  }) async =>
      throw _error;

  @override
  Future<void> setRate({
    required String organizationId,
    required String targetUid,
    required CourierPayRateInput input,
  }) async =>
      throw _error;

  @override
  Future<List<CourierShift>> listOpenShifts({
    required String organizationId,
  }) async =>
      throw _error;

  @override
  Future<void> reviewShift({
    required String organizationId,
    required String shiftId,
    required bool approve,
    DateTime? approvedAt,
    String? reason,
  }) async =>
      throw _error;

  @override
  Future<void> closeShift({
    required String organizationId,
    required String shiftId,
    required DateTime endedAt,
    required String reason,
  }) async =>
      throw _error;

  @override
  Future<CourierEarningsReport> earnings({
    required String organizationId,
    required String fromDate,
    required String toDate,
  }) async =>
      throw _error;

  @override
  Future<MyCourierPay> myPay({
    required String fromDate,
    required String toDate,
  }) async =>
      throw _error;

  @override
  Future<void> startShift() async => throw _error;

  @override
  Future<void> endShift() async => throw _error;
}
