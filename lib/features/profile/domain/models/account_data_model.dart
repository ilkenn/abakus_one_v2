enum DataExportStatus { none, preparing, ready, completed }

class AccountDataModel {
  final DataExportStatus exportStatus;
  final String? exportAvailableUntil;
  final bool deleteRequestInitiated;

  const AccountDataModel({
    this.exportStatus = DataExportStatus.none,
    this.exportAvailableUntil,
    this.deleteRequestInitiated = false,
  });

  AccountDataModel copyWith({
    DataExportStatus? exportStatus,
    String? exportAvailableUntil,
    bool? deleteRequestInitiated,
  }) {
    return AccountDataModel(
      exportStatus: exportStatus ?? this.exportStatus,
      exportAvailableUntil: exportAvailableUntil ?? this.exportAvailableUntil,
      deleteRequestInitiated:
          deleteRequestInitiated ?? this.deleteRequestInitiated,
    );
  }
}
