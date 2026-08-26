import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/account_deletion/account_deletion_providers.dart';
import '../../../../core/errors/business_rule_violation.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/models/account_data_model.dart';

class AccountDataNotifier extends Notifier<AccountDataModel> {
  @override
  AccountDataModel build() {
    return const AccountDataModel();
  }

  /// Records that the customer asked for their data — real data export
  /// itself remains explicitly deferred (Sprint 9G, `docs/decisions.md`
  /// ADR-026): assembling a real cross-feature JSON export is separate,
  /// future work. This no longer claims an archive was produced or
  /// downloaded — closure audit fix, customer-side closure/cleanup phase
  /// (`docs/decisions.md`): the previous flow faked a "ready"/"downloaded"
  /// outcome with a hardcoded, already-past expiry date, telling the
  /// customer something happened when nothing did.
  void requestDataExport() {
    if (state.exportStatus != DataExportStatus.none) return;

    state = state.copyWith(exportStatus: DataExportStatus.preparing);

    Future.delayed(const Duration(seconds: 1), () {
      state = state.copyWith(exportStatus: DataExportStatus.requested);
    });
  }

  void resetExportStatus() {
    state = const AccountDataModel();
  }

  /// Real account-deletion request — Sprint 9G (`docs/decisions.md`
  /// ADR-026), replacing the previous UI-only fake dialog. Idempotent
  /// (`RequestAccountDeletion` itself returns the existing active
  /// request rather than duplicating one). Returns `false` without
  /// effect if there is no signed-in session — this action is only ever
  /// reachable from an authenticated screen, but never assumes that.
  ///
  /// Deliberately does **not** force-sign-out the current session
  /// afterward: doing so would make `CancelAccountDeletionRequest`
  /// unreachable (`AuthNotifier` blocks *new* sign-in attempts for a
  /// `coolingOff` account — see its own doc comment), which would
  /// contradict "request cancellable after identity verification."
  /// "Session revocation" is instead enforced going forward, for any
  /// future sign-in attempt — the same accepted limitation this
  /// codebase already documents for staff forced-revocation (nothing can
  /// reach into an already-running client and invalidate it live).
  Future<bool> requestAccountDeletion() async {
    final session = ref.read(authProvider).session;
    if (session == null) return false;

    final request = await ref.read(requestAccountDeletionProvider).call(
          uid: session.uid,
          now: DateTime.now(),
        );
    state = state.copyWith(deletionRequest: request);
    return true;
  }

  /// Cancels the current cooling-off request, if one exists and is still
  /// cancellable. Returns `false` (state left unchanged) if there is
  /// nothing to cancel or the window has already elapsed — "deny by
  /// default" extends to this action too.
  Future<bool> cancelAccountDeletion() async {
    final request = state.deletionRequest;
    final session = ref.read(authProvider).session;
    if (request == null || session == null) return false;

    try {
      final cancelled =
          await ref.read(cancelAccountDeletionRequestProvider).call(
                requestId: request.id,
                uid: session.uid,
                now: DateTime.now(),
              );
      state = state.copyWith(deletionRequest: cancelled);
      return true;
    } on AccountDeletionRequestNotCancellableViolation {
      return false;
    }
  }
}

final accountDataProvider =
    NotifierProvider<AccountDataNotifier, AccountDataModel>(() {
  return AccountDataNotifier();
});
