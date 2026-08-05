import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/account_deletion/domain/account_deletion_request.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../providers/account_data_provider.dart';
import '../../domain/models/account_data_model.dart';

/// Sprint 9G (`docs/decisions.md` ADR-026): the delete-account flow here
/// is now backed by a real `AccountDeletionRequest`
/// (`core/account_deletion`), not a UI-only confirmation dialog. There is
/// no password field — this app has no password-based auth at all
/// (phone + OTP only, `CLAUDE.md` §3/§9); the caller's already-
/// authenticated session is this sprint's identity verification for
/// *requesting* deletion (see `AccountDataNotifier.requestAccountDeletion`'s
/// own doc comment for the fuller reasoning, including why cancellation
/// does not force a sign-out first).
class AccountDataScreen extends ConsumerStatefulWidget {
  const AccountDataScreen({super.key});

  @override
  ConsumerState<AccountDataScreen> createState() => _AccountDataScreenState();
}

class _AccountDataScreenState extends ConsumerState<AccountDataScreen> {
  bool _understandCheck = false;
  bool _busy = false;

  Future<void> _processDeleteAccount() async {
    if (!_understandCheck) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Son Onay'),
        content: const Text(
          'Hesabınız $_coolingOffDaysLabel gün içinde geri alınamaz şekilde '
          'silinecektir. Bu süre içinde talebinizi iptal edebilirsiniz. '
          'Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Silme Talebini Başlat'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final success =
        await ref.read(accountDataProvider.notifier).requestAccountDeletion();
    if (!mounted) return;
    setState(() => _busy = false);

    if (!success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Hesap silme talebiniz alındı. Bekleme süresi boyunca bu ekrandan '
          'iptal edebilirsiniz.',
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Future<void> _cancelDeletion() async {
    setState(() => _busy = true);
    final success =
        await ref.read(accountDataProvider.notifier).cancelAccountDeletion();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Hesap silme talebiniz iptal edildi.'
              : 'Talep artık iptal edilemiyor.',
        ),
      ),
    );
  }

  static const String _coolingOffDaysLabel = '7';

  @override
  Widget build(BuildContext context) {
    final accountState = ref.watch(accountDataProvider);
    final notifier = ref.read(accountDataProvider.notifier);
    final deletionRequest = accountState.deletionRequest;
    final isCoolingOff =
        deletionRequest?.status == AccountDeletionStatus.coolingOff;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hesap ve Verilerim'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: AppRadius.kMedium,
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Yasal Saklama ve Anonimleştirme',
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'KVKK ve yasal mevzuatlar gereği geçmiş sipariş kayıtlarınız, '
                    'mali yükümlülükler süresince güvenli sistemlerimizde saklanır. '
                    'Hesap silme sonrasında tüm kişisel verileriniz kalıcı olarak '
                    'anonimleştirilecektir.\n\n'
                    'TASLAK — HUKUKİ İNCELEME GEREKLİ (DRAFT — LEGAL REVIEW '
                    'REQUIRED): Bu metin nihai bir gizlilik politikası veya yasal '
                    'metin değildir.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Kişisel Verileri İndir',
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.kMedium,
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Uygulama üzerindeki profil, adres ve geçmiş sipariş verilerinizin bir kopyasını JSON formatında talep edebilirsiniz.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (accountState.exportStatus == DataExportStatus.none)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.download_rounded),
                        onPressed: () => notifier.requestDataExport(),
                        label: const Text('Veri Arşivi Talep Et'),
                      ),
                    )
                  else if (accountState.exportStatus ==
                      DataExportStatus.preparing)
                    const Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text(
                          'Veri arşiviniz hazırlanıyor, lütfen bekleyin...',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    )
                  else if (accountState.exportStatus == DataExportStatus.ready)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Veri arşiviniz hazır! (Son Tarih: ${accountState.exportAvailableUntil})',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(
                                  Icons.file_download_done_rounded,
                                ),
                                onPressed: () {
                                  notifier.completeDataDownload();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Veri arşivi cihazınıza indirildi.',
                                      ),
                                    ),
                                  );
                                },
                                label: const Text('İndir'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            TextButton(
                              onPressed: () => notifier.resetExportStatus(),
                              child: const Text('Temizle'),
                            ),
                          ],
                        ),
                      ],
                    )
                  else if (accountState.exportStatus ==
                      DataExportStatus.completed)
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.green,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Text(
                          'Talep Tamamlandı',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => notifier.resetExportStatus(),
                          child: const Text('Yeni Talep'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Hesabı Kalıcı Olarak Sil',
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.kMedium,
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: isCoolingOff
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hesap silme talebiniz beklemede. '
                          '${deletionRequest!.coolingOffEndsAt.day.toString().padLeft(2, '0')}.'
                          '${deletionRequest.coolingOffEndsAt.month.toString().padLeft(2, '0')}.'
                          '${deletionRequest.coolingOffEndsAt.year} tarihinde '
                          'kalıcı olarak silinecektir.',
                          style: AppTypography.bodyMedium.copyWith(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _busy ? null : _cancelDeletion,
                            child: const Text('Silme Talebini İptal Et'),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hesabınızı sildiğinizde $_coolingOffDaysLabel günlük '
                          'bekleme süresinin ardından kazanılan tüm boncuklar, '
                          'aktif kuponlar ve tanımlı adresler kalıcı olarak '
                          'silinecektir. Bekleme süresi içinde talebinizi iptal '
                          'edebilirsiniz.',
                          style: AppTypography.bodyMedium.copyWith(
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CheckboxListTile(
                          title: const Text(
                            'Hesabımın ve verilerimin kalıcı olarak silineceğini anlıyorum.',
                          ),
                          value: _understandCheck,
                          activeColor: Colors.red,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) =>
                              setState(() => _understandCheck = val ?? false),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (_understandCheck && !_busy)
                                ? _processDeleteAccount
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('Hesap Silme Talebini Onayla'),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
