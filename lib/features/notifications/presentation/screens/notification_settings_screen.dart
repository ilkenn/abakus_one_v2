import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../providers/notifications_provider.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  void _openDeviceSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uygulama Ayarları'),
        content: const Text(
          'Cihazınızın sistem ayarları sayfasına yönlendiriliyorsunuz. Lütfen Abaküs Bowl için bildirim izinlerini aktif hale getirin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);

    final switchTrackColor = WidgetStateProperty.resolveWith<Color?>((
      Set<WidgetState> states,
    ) {
      if (states.contains(WidgetState.selected)) {
        return AppColors.primary;
      }
      return null;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirim Ayarları'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            if (settings.systemPermissionStatus == 'prompt')
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                margin: const EdgeInsets.only(bottom: AppSpacing.xl),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: AppRadius.kMedium,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sistem Bildirim İzinleri',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Sipariş durumları ve anlık kurye konum takibi bildirimlerini kaçırmamak için sistem iznini açmanızı öneririz.',
                      style: AppTypography.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => notifier.denySystemPermission(),
                          child: const Text(
                            'Daha Sonra',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () => notifier.requestSystemPermission(),
                          child: const Text('İzin Ver'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else if (settings.systemPermissionStatus == 'denied')
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                margin: const EdgeInsets.only(bottom: AppSpacing.xl),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: AppRadius.kMedium,
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'Bildirim İzni Kapatıldı',
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Cihazınızda uygulama bildirim izinleri reddedilmiş durumda. Bildirim alabilmek için lütfen sistem ayarlarından bildirimleri aktif edin.',
                      style: AppTypography.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.settings_applications_rounded),
                        onPressed: () => _openDeviceSettings(context),
                        label: const Text('Uygula Ayarlarını Aç'),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'Kategoriler',
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.kMedium,
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Sipariş Durumu'),
                    subtitle: const Text(
                      'Siparişinizin onaylanması, hazırlanması adımları',
                    ),
                    value: settings.orderStatus,
                    trackColor: switchTrackColor,
                    onChanged: (val) => notifier.toggleOrderStatus(val),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Kurye Yaklaşıyor'),
                    subtitle: const Text(
                      'Kurye adresinize yaklaştığında anlık uyarılar',
                    ),
                    value: settings.courierApproaching,
                    trackColor: switchTrackColor,
                    onChanged: (val) => notifier.toggleCourierApproaching(val),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Kampanyalar'),
                    subtitle: const Text(
                      'Dönemsel festivaller ve yeni restoran duyuruları',
                    ),
                    value: settings.campaigns,
                    trackColor: switchTrackColor,
                    onChanged: (val) => notifier.toggleCampaigns(val),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Kuponlar'),
                    subtitle: const Text(
                      'Hesabınıza özel indirim kupon tanımlamaları',
                    ),
                    value: settings.coupons,
                    trackColor: switchTrackColor,
                    onChanged: (val) => notifier.toggleCoupons(val),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Sadakat Puanı'),
                    subtitle: const Text(
                      'Kazanılan boncuklar ve harcama hatırlatmaları',
                    ),
                    value: settings.loyaltyPoints,
                    trackColor: switchTrackColor,
                    onChanged: (val) => notifier.toggleLoyaltyPoints(val),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Önemli Hesap Bildirimleri'),
                    subtitle: const Text(
                      'Güvenlik, şifre ve yasal bilgilendirmeler (Zorunlu)',
                    ),
                    value: settings.accountSecurity,
                    trackColor: switchTrackColor,
                    onChanged: null,
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
