import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:flutter/foundation.dart'
    show TargetPlatform, Uint8List, defaultTargetPlatform, kIsWeb;

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
  /// The rate in force for a courier staff account (or `null`) and whether
  /// it sends invoices ("Fatura Keser").
  Future<CourierPayProfileSummary> payProfile({
    required String organizationId,
    required String targetUid,
  });

  /// Stage 6A — the staff form's "Fatura Keser" switch.
  Future<void> setInvoicing({
    required String organizationId,
    required String targetUid,
    required bool issuesInvoice,
  });

  /// Stage 6A — "Fatura Yükle" step 1 (the signed-in courier).
  Future<CourierInvoicePreview> previewInvoice({
    required String periodFrom,
    required String periodTo,
  });

  /// Stage 6A — uploads the file under a one-use grant, then sends the
  /// invoice. [contentType] is `application/pdf`, `image/jpeg` or `image/png`.
  Future<CourierInvoice> submitInvoice({
    required String periodFrom,
    required String periodTo,
    required int invoiceAmountMinorUnits,
    required String invoiceNumber,
    required String note,
    required Uint8List bytes,
    required String contentType,
  });

  Future<CourierInvoiceList> listInvoices({required String organizationId});

  Future<void> reviewInvoice({
    required String organizationId,
    required String invoiceId,
    required bool approve,
    String? reason,
  });

  /// Money out (admin/owner): an invoice payment ([full] = the remainder),
  /// an advance to [targetUid], or the reversal of [reversesPaymentId].
  Future<void> recordPayment({
    required String organizationId,
    required CourierPaymentKind kind,
    String? invoiceId,
    String? targetUid,
    String? reversesPaymentId,
    int? amountMinorUnits,
    bool full = false,
    String? paidDate,
    String? note,
  });

  /// The invoice's file (the sender's own, or a reviewer's branch).
  Future<({Uint8List bytes, String contentType})> invoiceFile({
    required String invoiceId,
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
      case 'courierInvoice/not-invoicing':
        return 'Fatura kesen kurye olarak tanımlı değilsiniz. Şube müdürünüze '
            'başvurun.';
      case 'courierInvoice/period-overlap':
        return 'Bu dönemin bir kısmı için zaten fatura gönderilmiş.';
      case 'courierInvoice/no-lines':
        return 'Bu dönemde faturalanacak kazanç yok.';
      case 'courierInvoice/invalid-period':
        return 'Dönemi kontrol edin: bugünden ileri olamaz, en fazla bir yıl.';
      case 'courierInvoice/invalid-amount':
      case 'courierPayment/invalid-amount':
        return 'Geçerli bir tutar girin.';
      case 'courierInvoice/invalid-file':
        return 'Fatura dosyası PDF, JPEG ya da PNG olmalı (en fazla 5 MB).';
      case 'courierInvoice/file-missing':
        return 'Fatura dosyası yüklenemedi. Tekrar deneyin.';
      case 'courierInvoice/grant-used':
        return 'Bu yükleme zaten kullanıldı. Dosyayı tekrar seçin.';
      case 'courierInvoice/reason-required':
        return 'Reddetmek için gerekçe yazın.';
      case 'courierInvoice/not-pending':
        return 'Bu fatura artık onay beklemiyor.';
      case 'courierPayment/admin-only':
        return 'Ödeme ve avans girişini yalnızca Yönetici veya Sahip yapabilir.';
      case 'courierPayment/invoice-not-approved':
        return 'Yalnızca onaylanmış bir fatura ödenebilir.';
      case 'courierPayment/over-invoice':
        return 'Ödeme, faturada kalan tutardan fazla olamaz.';
      case 'courierPayment/future-date':
        return 'Ödeme tarihi ileri bir tarih olamaz.';
      case 'courierPayment/already-reversed':
        return 'Bu ödeme zaten geri alındı.';
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
  Future<CourierPayProfileSummary> payProfile({
    required String organizationId,
    required String targetUid,
  }) async {
    final result = await _call('getCourierPayProfile', {
      'organizationId': organizationId,
      'targetUid': targetUid,
    });
    final current = result['current'];
    return CourierPayProfileSummary(
      currentRate: current is Map
          ? CourierPayRate.fromJson(Map<String, dynamic>.from(current))
          : null,
      issuesInvoice: result['issuesInvoice'] == true,
    );
  }

  @override
  Future<void> setInvoicing({
    required String organizationId,
    required String targetUid,
    required bool issuesInvoice,
  }) async {
    await _call('setCourierInvoicing', {
      'organizationId': organizationId,
      'targetUid': targetUid,
      'issuesInvoice': issuesInvoice,
    });
  }

  @override
  Future<CourierInvoicePreview> previewInvoice({
    required String periodFrom,
    required String periodTo,
  }) async =>
      CourierInvoicePreview.fromJson(await _call('previewCourierInvoice', {
        'periodFrom': periodFrom,
        'periodTo': periodTo,
      }));

  @override
  Future<CourierInvoice> submitInvoice({
    required String periodFrom,
    required String periodTo,
    required int invoiceAmountMinorUnits,
    required String invoiceNumber,
    required String note,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      throw const CourierPayException(
          'Fatura yalnızca kurye uygulamasından (telefondan) yüklenebilir.');
    }
    final grant = await _call('requestCourierUploadGrant', {
      'purpose': 'invoice',
      'contentType': contentType,
    });
    try {
      await storage.FirebaseStorage.instance
          .ref(grant['objectPath'] as String)
          .putData(bytes, storage.SettableMetadata(contentType: contentType));
    } on storage.FirebaseException {
      throw const CourierPayException(
          'Fatura dosyası yüklenemedi. Bağlantınızı kontrol edip tekrar '
          'deneyin.');
    }
    final result = await _call('submitCourierInvoice', {
      'grantId': grant['grantId'],
      'periodFrom': periodFrom,
      'periodTo': periodTo,
      'invoiceAmountMinorUnits': invoiceAmountMinorUnits,
      'invoiceNumber': invoiceNumber,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    return CourierInvoice.fromJson(
        Map<String, dynamic>.from(result['invoice'] as Map));
  }

  @override
  Future<CourierInvoiceList> listInvoices({
    required String organizationId,
  }) async {
    final result =
        await _call('listCourierInvoices', {'organizationId': organizationId});
    return CourierInvoiceList(
      invoices: [
        for (final invoice in (result['invoices'] as List? ?? const []))
          CourierInvoice.fromJson(Map<String, dynamic>.from(invoice as Map)),
      ],
      canRecordPayments: result['canRecordPayments'] == true,
    );
  }

  @override
  Future<void> reviewInvoice({
    required String organizationId,
    required String invoiceId,
    required bool approve,
    String? reason,
  }) async {
    await _call('reviewCourierInvoice', {
      'organizationId': organizationId,
      'invoiceId': invoiceId,
      'decision': approve ? 'approve' : 'reject',
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  @override
  Future<void> recordPayment({
    required String organizationId,
    required CourierPaymentKind kind,
    String? invoiceId,
    String? targetUid,
    String? reversesPaymentId,
    int? amountMinorUnits,
    bool full = false,
    String? paidDate,
    String? note,
  }) async {
    await _call('recordCourierPayment', {
      'organizationId': organizationId,
      'kind': kind.name,
      if (invoiceId != null) 'invoiceId': invoiceId,
      if (targetUid != null) 'targetUid': targetUid,
      if (reversesPaymentId != null) 'reversesPaymentId': reversesPaymentId,
      if (amountMinorUnits != null) 'amountMinorUnits': amountMinorUnits,
      if (full) 'full': true,
      if (paidDate != null) 'paidDate': paidDate,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  @override
  Future<({Uint8List bytes, String contentType})> invoiceFile({
    required String invoiceId,
  }) async {
    final result =
        await _call('getCourierInvoiceFile', {'invoiceId': invoiceId});
    return (
      bytes: base64Decode(result['base64'] as String? ?? ''),
      contentType: result['contentType'] as String? ?? '',
    );
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
  Future<CourierPayProfileSummary> payProfile({
    required String organizationId,
    required String targetUid,
  }) async =>
      throw _error;

  @override
  Future<void> setInvoicing({
    required String organizationId,
    required String targetUid,
    required bool issuesInvoice,
  }) async =>
      throw _error;

  @override
  Future<CourierInvoicePreview> previewInvoice({
    required String periodFrom,
    required String periodTo,
  }) async =>
      throw _error;

  @override
  Future<CourierInvoice> submitInvoice({
    required String periodFrom,
    required String periodTo,
    required int invoiceAmountMinorUnits,
    required String invoiceNumber,
    required String note,
    required Uint8List bytes,
    required String contentType,
  }) async =>
      throw _error;

  @override
  Future<CourierInvoiceList> listInvoices({
    required String organizationId,
  }) async =>
      throw _error;

  @override
  Future<void> reviewInvoice({
    required String organizationId,
    required String invoiceId,
    required bool approve,
    String? reason,
  }) async =>
      throw _error;

  @override
  Future<void> recordPayment({
    required String organizationId,
    required CourierPaymentKind kind,
    String? invoiceId,
    String? targetUid,
    String? reversesPaymentId,
    int? amountMinorUnits,
    bool full = false,
    String? paidDate,
    String? note,
  }) async =>
      throw _error;

  @override
  Future<({Uint8List bytes, String contentType})> invoiceFile({
    required String invoiceId,
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
