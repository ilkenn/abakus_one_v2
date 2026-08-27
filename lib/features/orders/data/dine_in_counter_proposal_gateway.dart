import 'package:cloud_functions/cloud_functions.dart' as functions;

/// What a successful `respondToDineInCounterProposal` call returns.
class RespondToDineInCounterProposalResult {
  final String orderId;
  final int lineIndex;

  /// `"accepted"` or `"rejected"` — mirrors the callable's own wire value
  /// verbatim (the accepted line's [DineInLineStatus], or `rejected` for
  /// both an explicit rejection and an expired/replayed-after-expiry
  /// response).
  final String status;

  /// `true` when this call was a safe, idempotent replay of an already-
  /// recorded decision (mirrors the backend's own idempotency contract) —
  /// the UI should treat this exactly like a fresh success, never as an
  /// error.
  final bool idempotent;

  const RespondToDineInCounterProposalResult({
    required this.orderId,
    required this.lineIndex,
    required this.status,
    required this.idempotent,
  });
}

/// Thrown for an expected, non-exceptional-in-nature rejection — mirrors
/// the Cloud Function's own `HttpsError` codes verbatim, the same pattern
/// `SubmitDineInOrderException` uses.
class RespondToDineInCounterProposalException implements Exception {
  final String code;
  final String message;

  const RespondToDineInCounterProposalException(this.code, this.message);

  @override
  String toString() =>
      'RespondToDineInCounterProposalException($code): $message';
}

/// The one client-facing boundary onto the server-authoritative
/// `respondToDineInCounterProposal` Cloud Function — AP-3 continuation. The
/// only way a customer may accept/reject a staff-proposed line replacement;
/// there is no client-side price recomputation of any kind — the server
/// applies the frozen proposal snapshot exactly as proposed, or fails
/// closed (`failed-precondition`/`aborted`) on a stale-catalog re-check,
/// expiry, or already-resolved proposal.
abstract interface class DineInCounterProposalGateway {
  Future<RespondToDineInCounterProposalResult> respond({
    required String orderId,
    required int lineIndex,
    required bool accept,
  });
}

class FirebaseDineInCounterProposalGateway
    implements DineInCounterProposalGateway {
  const FirebaseDineInCounterProposalGateway();

  @override
  Future<RespondToDineInCounterProposalResult> respond({
    required String orderId,
    required int lineIndex,
    required bool accept,
  }) async {
    final callable = functions.FirebaseFunctions.instance.httpsCallable(
      'respondToDineInCounterProposal',
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'orderId': orderId,
        'lineIndex': lineIndex,
        'decision': accept ? 'accept' : 'reject',
      });
      final data = result.data;
      return RespondToDineInCounterProposalResult(
        orderId: data['orderId'] as String,
        lineIndex: data['lineIndex'] as int,
        status: data['status'] as String,
        idempotent: data['idempotent'] as bool,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      throw RespondToDineInCounterProposalException(
        error.code,
        error.message ?? 'İşlem gerçekleştirilemedi.',
      );
    }
  }
}
