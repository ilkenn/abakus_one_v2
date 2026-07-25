import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../providers/profile_provider.dart';
import '../screens/addresses_screen.dart';
import '../../../orders/presentation/screens/orders_screen.dart';
import '../../../notifications/presentation/screens/notification_settings_screen.dart';
import '../screens/account_data_screen.dart';
import '../screens/saved_cards_screen.dart';
import '../screens/loyalty_screen.dart';
import '../screens/help_screen.dart';
import '../../../favorites/presentation/screens/favorites_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _showImagePickerDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: AppColors.primary,
                ),
                title: const Text('Galeriden Fotoğraf Seç'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromGallery(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text('Fotoğrafı Kaldır ve Varsayılana Dön'),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(profileProvider.notifier).removeProfilePicture();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Profil fotoğrafı kaldırıldı.'),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Hesabından çıkış yapmak istediğine emin misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await ref.read(authProvider.notifier).logout();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text(
              'Çıkış Yap',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _pickImageFromGallery(BuildContext context, WidgetRef ref) {
    const String mockSelectedPath =
        '/data/user/0/com.abakus.bowl/cache/profile_mock.png';
    ref.read(profileProvider.notifier).updateProfilePicture(mockSelectedPath);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profil fotoğrafı başarıyla güncellendi!')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final bool hasCustomImage = profile.profilePicturePath != null && !kIsWeb;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profilim',
                style: AppTypography.headlineMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Center(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.1,
                          ),
                          backgroundImage: hasCustomImage
                              ? FileImage(File(profile.profilePicturePath!))
                              : null,
                          child: !hasCustomImage
                              ? const Icon(
                                  Icons.person_rounded,
                                  size: 48,
                                  color: AppColors.primary,
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => _showImagePickerDialog(context, ref),
                            child: const CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.primary,
                              child: Icon(
                                Icons.edit_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      profile.name,
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      profile.email,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Hesap Ayarları',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.kMedium,
                  border: Border.all(color: AppColors.border),
                ),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: AppRadius.kMedium,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.location_on_outlined,
                          color: AppColors.primary,
                        ),
                        title: const Text('Adreslerim'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AddressesScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.credit_card_rounded,
                          color: AppColors.primary,
                        ),
                        title: const Text('Ödeme Yöntemlerim'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SavedCardsScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.shopping_bag_outlined,
                          color: AppColors.primary,
                        ),
                        title: const Text('Siparişlerim'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const OrdersScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.favorite_border_rounded,
                          color: AppColors.primary,
                        ),
                        title: const Text('Favorilerim'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const FavoritesScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.stars_rounded,
                          color: AppColors.primary,
                        ),
                        title: const Text('Sadakat Boncuklarım'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoyaltyScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.notifications_none_rounded,
                          color: AppColors.primary,
                        ),
                        title: const Text('Bildirim Ayarları'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const NotificationSettingsScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.shield_outlined,
                          color: AppColors.primary,
                        ),
                        title: const Text('Hesap ve Verilerim'),
                        subtitle:
                            const Text('Veri indirme, Hesap kalıcı silme'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AccountDataScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.help_outline_rounded,
                          color: AppColors.primary,
                        ),
                        title: const Text('Yardım ve Destek'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const HelpScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.logout_rounded,
                          color: AppColors.error,
                        ),
                        title: const Text(
                          'Çıkış Yap',
                          style: TextStyle(color: AppColors.error),
                        ),
                        onTap: () => _showLogoutDialog(context, ref),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
