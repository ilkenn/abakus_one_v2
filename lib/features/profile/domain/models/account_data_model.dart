import '../../../../core/account_deletion/domain/account_deletion_request.dart';

/// `ready`/`completed` (a fake "your archive is ready, download it" step
/// with no real archive ever produced) removed during the customer-side
/// closure audit — no real data-export pipeline exists yet (Sprint 9G,
/// `docs/decisions.md` ADR-026), so the UI must never claim one succeeded.
/// `requested` is the honest terminal state: the request was received, a
/// real archive is not produced by this app today.
enum DataExportStatus { none, preparing, requested }

class AccountDataModel {
  final DataExportStatus exportStatus;

  /// The signed-in user's own account-deletion request, if any — Sprint
  /// 9G (`docs/decisions.md` ADR-026). Replaces the old
  /// `deleteRequestInitiated: bool`, which was never actually set to
  /// `true` anywhere (a fake flag on a fake flow).
  final AccountDeletionRequest? deletionRequest;

  const AccountDataModel({
    this.exportStatus = DataExportStatus.none,
    this.deletionRequest,
  });

  AccountDataModel copyWith({
    DataExportStatus? exportStatus,
    AccountDeletionRequest? deletionRequest,
  }) {
    return AccountDataModel(
      exportStatus: exportStatus ?? this.exportStatus,
      deletionRequest: deletionRequest ?? this.deletionRequest,
    );
  }
}
