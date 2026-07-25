import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../providers/notifications_provider.dart';
import 'notification_settings_screen.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mevcut bildirim sayaç provider'ı izleniyor
    final unreadCount = ref.watch(unreadNotificationsCountProvider);

    // Mock bildirim listesi verisi linter kurallarına ve mimariye tam uyumlu tutulmuştur
    final List<Map<String, dynamic>> mockNotifications = [
      {
        'id': 'notif_1',
        'title': 'Siparişiniz Yola Çıktı! 🥣',
        'body':
            'Protein Bowl siparişiniz kuryemiz tarafından teslim alındı, hızlıca geliyor.',
        'time': '5 dk önce',
        'isRead': false,
      },
      {
        'id': 'notif_2',
        'title': 'Yeni Kupon Hesabınızda! 🌟',
        'body':
            'Hafta sonuna özel %10 indirim kuponu ABAKUS10 profilinize tanımlandı.',
        'time': '2 saat önce',
        'isRead': false,
      },
      {
        'id': 'notif_3',
        'title': 'Siparişiniz Teslim Edildi',
        'body':
            'ORD-2026-001 numaralı siparişiniz afiyetle tüketmeniz için teslim edilmiştir.',
        'time': '1 gün önce',
        'isRead': true,
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirim Merkezim'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationSettingsScreen(),
                ),
              );
            },
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (unreadCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$unreadCount okunmamış bildiriminiz var',
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // Tümünü okundu olarak işaretleme aksiyon noktası
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Tüm bildirimler okundu olarak işaretlendi.',
                            ),
                          ),
                        );
                      },
                      child: const Text('Tümünü Okundu Yap'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.xl),
                itemCount: mockNotifications.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final notif = mockNotifications[index];
                  final bool isRead = notif['isRead'] as bool;

                  return InkWell(
                    onTap: () {
                      // Tekil bildirim okuma aksiyon noktası
                    },
                    borderRadius: AppRadius.kMedium,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: isRead
                            ? AppColors.surface
                            : AppColors.primary.withValues(alpha: 0.03),
                        borderRadius: AppRadius.kMedium,
                        border: Border.all(
                          color: isRead
                              ? AppColors.border
                              : AppColors.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: isRead
                                  ? AppColors.surfaceVariant
                                  : AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isRead
                                  ? Icons.notifications_none_rounded
                                  : Icons.notifications_active_rounded,
                              color: isRead
                                  ? AppColors.textSecondary
                                  : AppColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        notif['title'] as String,
                                        style:
                                            AppTypography.titleMedium.copyWith(
                                          fontWeight: isRead
                                              ? FontWeight.normal
                                              : FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      notif['time'] as String,
                                      style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  notif['body'] as String,
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: isRead
                                        ? AppColors.textSecondary
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
