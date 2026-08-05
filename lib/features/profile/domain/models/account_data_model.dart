import '../../../../core/account_deletion/domain/account_deletion_request.dart';

enum DataExportStatus { none, preparing, ready, completed }

class AccountDataModel {
  final DataExportStatus exportStatus;
  final String? exportAvailableUntil;

  /// The signed-in user's own account-deletion request, if any — Sprint
  /// 9G (`docs/decisions.md` ADR-026). Replaces the old
  /// `deleteRequestInitiated: bool`, which was never actually set to
  /// `true` anywhere (a fake flag on a fake flow).
  final AccountDeletionRequest? deletionRequest;

  const AccountDataModel({
    this.exportStatus = DataExportStatus.none,
    this.exportAvailableUntil,
    this.deletionRequest,
  });

  AccountDataModel copyWith({
    DataExportStatus? exportStatus,
    String? exportAvailableUntil,
    AccountDeletionRequest? deletionRequest,
  }) {
    return AccountDataModel(
      exportStatus: exportStatus ?? this.exportStatus,
      exportAvailableUntil: exportAvailableUntil ?? this.exportAvailableUntil,
      deletionRequest: deletionRequest ?? this.deletionRequest,
    );
  }
}
