import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/account_data_model.dart';

class AccountDataNotifier extends Notifier<AccountDataModel> {
  @override
  AccountDataModel build() {
    return const AccountDataModel();
  }

  void requestDataExport() {
    if (state.exportStatus != DataExportStatus.none) return;

    state = state.copyWith(exportStatus: DataExportStatus.preparing);

    // Mock olarak durum güncelleme tetikleyicisi kurgulanmıştır
    Future.delayed(const Duration(seconds: 4), () {
      state = state.copyWith(
        exportStatus: DataExportStatus.ready,
        exportAvailableUntil: '25.07.2026',
      );
    });
  }

  void completeDataDownload() {
    state = state.copyWith(exportStatus: DataExportStatus.completed);
  }

  void resetExportStatus() {
    state = const AccountDataModel();
  }
}

final accountDataProvider =
    NotifierProvider<AccountDataNotifier, AccountDataModel>(() {
  return AccountDataNotifier();
});
