import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../providers/account_data_provider.dart';
import '../../domain/models/account_data_model.dart';

class AccountDataScreen extends ConsumerStatefulWidget {
  const AccountDataScreen({super.key});

  @override
  ConsumerState<AccountDataScreen> createState() => _AccountDataScreenState();
}

class _AccountDataScreenState extends ConsumerState<AccountDataScreen> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _understandCheck = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _processDeleteAccount() {
    if (!(_formKey.currentState?.validate() ?? false) || !_understandCheck) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Son Onay'),
        content: const Text(
          'Hesabınız ve tüm kişisel verileriniz geri döndürülemez şekilde kalıcı olarak silinecektir. Bu işlemi onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Hesabınız başarıyla silinmiştir. Verileriniz anonimleştirilecektir.',
                  ),
                  backgroundColor: Colors.redAccent,
                ),
              );
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Kalıcı Olarak Sil'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountState = ref.watch(accountDataProvider);
    final notifier = ref.read(accountDataProvider.notifier);

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
                    'KVKK ve yasal mevzuatlar gereği geçmiş sipariş kayıtlarınız, mali yükümlülükler süresince güvenli sistemlerimizde saklanır. Hesap silme sonrasında tüm kişisel verileriniz kalıcı olarak anonimleştirilecektir.',
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
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hesabınızı sildiğinizde kazanılan tüm boncuklar, aktif kuponlar ve tanımlı adresler kalıcı olarak silinecektir. Bu işlem geri alınamaz.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Güvenlik İçin Şifrenizi Girin',
                        hintText: '••••••',
                      ),
                      validator: (val) => (val == null || val.trim().isEmpty)
                          ? 'Güvenlik doğrulaması için şifre gereklidir'
                          : null,
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
                        onPressed:
                            _understandCheck ? _processDeleteAccount : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('Hesap Silme Talebini Onayla'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
