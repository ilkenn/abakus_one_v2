import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../domain/models/branch_takeaway_settings.dart';

/// AP-6 Sprint 1 — the real backend boundary for changing a branch's
/// takeaway operational mode, mirroring `PrintJobActionGateway`'s exact
/// shape: an interface, a [FirebaseTakeawayOperationsGateway] backed by the
/// real `updateTakeawayOperationStatus` callable, and a fail-closed
/// [UnavailableTakeawayOperationsGateway] for when Firebase isn't ready yet
/// — never a silent local simulation.
class TakeawayOperationsException implements Exception {
  const TakeawayOperationsException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'TakeawayOperationsException($code): $message';
}

class TakeawayOperationStatusUpdateResult {
  const TakeawayOperationStatusUpdateResult({
    required this.branchId,
    required this.status,
    required this.revision,
  });

  final String branchId;
  final TakeawayOperationStatus status;
  final int revision;
}

abstract interface class TakeawayOperationsGateway {
  /// Changes [branchId]'s takeaway mode. [busyDelayMinutes] is meaningful
  /// only for [TakeawayOperationStatus.busy] (one of
  /// [kTakeawayBusyDelayMinuteOptions]); [pausedUntil] is required for
  /// [TakeawayOperationStatus.paused] and must already be a fully-resolved
  /// absolute instant — the four fixed presets (30 min / 1 hour / 2 hours /
  /// end-of-day) and the custom-date option are all resolved to this exact
  /// shape by the caller (the mode-change dialog) before this method is
  /// ever called; this gateway performs no duration arithmetic itself.
  Future<TakeawayOperationStatusUpdateResult> updateTakeawayOperationStatus({
    required String organizationId,
    required String branchId,
    required TakeawayOperationStatus status,
    int busyDelayMinutes = 0,
    DateTime? pausedUntil,
  });
}

class FirebaseTakeawayOperationsGateway implements TakeawayOperationsGateway {
  const FirebaseTakeawayOperationsGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw TakeawayOperationsException(
      error.code,
      error.message ?? 'Paket servis durumu güncellenemedi.',
    );
  }

  @override
  Future<TakeawayOperationStatusUpdateResult> updateTakeawayOperationStatus({
    required String organizationId,
    required String branchId,
    required TakeawayOperationStatus status,
    int busyDelayMinutes = 0,
    DateTime? pausedUntil,
  }) async {
    try {
      final result = await functions.FirebaseFunctions.instance
          .httpsCallable('updateTakeawayOperationStatus')
          .call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'status': status.name,
        if (status == TakeawayOperationStatus.busy)
          'busyDelayMinutes': busyDelayMinutes,
        if (status == TakeawayOperationStatus.paused)
          'pausedUntil': pausedUntil!.toUtc().toIso8601String(),
      });
      final data = result.data;
      return TakeawayOperationStatusUpdateResult(
        branchId: data['branchId'] as String,
        status: TakeawayOperationStatus.values.byName(data['status'] as String),
        revision: (data['revision'] as num).toInt(),
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

class UnavailableTakeawayOperationsGateway implements TakeawayOperationsGateway {
  const UnavailableTakeawayOperationsGateway();

  @override
  Future<TakeawayOperationStatusUpdateResult> updateTakeawayOperationStatus({
    required String organizationId,
    required String branchId,
    required TakeawayOperationStatus status,
    int busyDelayMinutes = 0,
    DateTime? pausedUntil,
  }) async =>
      throw const TakeawayOperationsException(
        'unavailable',
        'Paket servis durumu servisi şu anda kullanılamıyor.',
      );
}
