import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../domain/print_job.dart';

/// AP-5 Sprint 4 — the real backend boundary for opening/driving a
/// [PrintJob], mirroring `KitchenActionGateway`'s exact shape
/// (`pos/data/kitchen_action_gateway.dart`): an interface, a
/// [FirebasePrintJobActionGateway] backed by the real `requestPrintJob`/
/// `recordPrintOutcome` callables, and a fail-closed
/// [UnavailablePrintJobActionGateway] for when Firebase isn't ready yet —
/// never a silent local simulation.
class PrintJobActionException implements Exception {
  const PrintJobActionException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'PrintJobActionException($code): $message';
}

class PrintJobRequestResult {
  const PrintJobRequestResult({
    required this.printJobId,
    required this.status,
  });

  final String printJobId;
  final PrintJobStatus status;
}

abstract interface class PrintJobActionGateway {
  /// Opens (or, for the non-copy path, idempotently reuses) a print job for
  /// [orderId] at [stationId], then drives it through the server's mock
  /// transport in the same round trip — no real hardware/worker exists yet
  /// to call back separately, so the server itself resolves
  /// `pending -> printing -> success/failed` before responding.
  /// [isCopy] mirrors `KitchenTicket.isCopy`/`KitchenPrintAttempt.isRetry` —
  /// a manual reprint always opens a brand-new job, never mutates a prior
  /// one in place.
  Future<PrintJobRequestResult> requestPrintJob({
    required String orderId,
    required String stationId,
    bool isCopy = false,
  });

  /// Manual fallback: marks an already-open job's outcome directly (e.g.
  /// staff confirming a ticket printed by other means after the mock/real
  /// transport reported failure). Never used for the initial attempt —
  /// that always goes through [requestPrintJob].
  Future<PrintJobRequestResult> recordPrintOutcome({
    required String printJobId,
    required bool success,
  });
}

class FirebasePrintJobActionGateway implements PrintJobActionGateway {
  const FirebasePrintJobActionGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw PrintJobActionException(
      error.code,
      error.message ?? 'Yazdırma işlemi gerçekleştirilemedi.',
    );
  }

  functions.HttpsCallable _fn(String name) =>
      functions.FirebaseFunctions.instance.httpsCallable(name);

  @override
  Future<PrintJobRequestResult> requestPrintJob({
    required String orderId,
    required String stationId,
    bool isCopy = false,
  }) async {
    try {
      final result = await _fn('requestPrintJob').call<Map<String, dynamic>>({
        'orderId': orderId,
        'stationId': stationId,
        'isCopy': isCopy,
      });
      final data = result.data;
      return PrintJobRequestResult(
        printJobId: data['printJobId'] as String,
        status: PrintJobStatus.values.byName(data['status'] as String),
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<PrintJobRequestResult> recordPrintOutcome({
    required String printJobId,
    required bool success,
  }) async {
    try {
      final result =
          await _fn('recordPrintOutcome').call<Map<String, dynamic>>({
        'printJobId': printJobId,
        'outcome': success ? 'success' : 'failed',
      });
      final data = result.data;
      return PrintJobRequestResult(
        printJobId: data['printJobId'] as String,
        status: PrintJobStatus.values.byName(data['status'] as String),
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}

class UnavailablePrintJobActionGateway implements PrintJobActionGateway {
  const UnavailablePrintJobActionGateway();

  Never _unavailable() => throw const PrintJobActionException(
        'unavailable',
        'Yazdırma servisi şu anda kullanılamıyor.',
      );

  @override
  Future<PrintJobRequestResult> requestPrintJob({
    required String orderId,
    required String stationId,
    bool isCopy = false,
  }) async =>
      _unavailable();

  @override
  Future<PrintJobRequestResult> recordPrintOutcome({
    required String printJobId,
    required bool success,
  }) async =>
      _unavailable();
}
