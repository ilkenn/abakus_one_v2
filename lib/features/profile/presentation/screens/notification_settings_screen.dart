import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../providers/notification_settings_provider.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirim Ayarları'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              'Uygulama Bildirimleri',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.primary,
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
                    value: settings.orderStatus,
                    onChanged: notifier.toggleOrderStatus,
                    title: const Text(
                      'Sipariş Durumu Bildirimleri',
                      style: AppTypography.bodyLarge,
                    ),
                    activeThumbColor: AppColors.primary,
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  SwitchListTile(
                    value: settings.campaigns,
                    onChanged: notifier.toggleCampaigns,
                    title: const Text(
                      'Kampanya Bildirimleri',
                      style: AppTypography.bodyLarge,
                    ),
                    activeThumbColor: AppColors.primary,
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  SwitchListTile(
                    value: settings.newProducts,
                    onChanged: notifier.toggleNewProducts,
                    title: const Text(
                      'Yeni Ürün Bildirimleri',
                      style: AppTypography.bodyLarge,
                    ),
                    activeThumbColor: AppColors.primary,
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  SwitchListTile(
                    value: settings.loyaltyPoints,
                    onChanged: notifier.toggleLoyaltyPoints,
                    title: const Text(
                      'Sadakat Boncuğu Bildirimleri',
                      style: AppTypography.bodyLarge,
                    ),
                    activeThumbColor: AppColors.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Diğer İletişim Kanalları',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.primary,
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
                    value: settings.emailNotifications,
                    onChanged: notifier.toggleEmailNotifications,
                    title: const Text(
                      'E-posta Bildirimleri',
                      style: AppTypography.bodyLarge,
                    ),
                    activeThumbColor: AppColors.primary,
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  SwitchListTile(
                    value: settings.smsNotifications,
                    onChanged: notifier.toggleSmsNotifications,
                    title: const Text(
                      'SMS Bildirimleri',
                      style: AppTypography.bodyLarge,
                    ),
                    activeThumbColor: AppColors.primary,
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
