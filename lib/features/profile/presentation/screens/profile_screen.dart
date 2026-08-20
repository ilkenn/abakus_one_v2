import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_hero_card.dart';
import '../widgets/profile_quick_actions.dart';
import '../widgets/profile_loyalty_card.dart';
import '../widgets/profile_account_preferences_section.dart';
import '../widgets/profile_visit_pass_card.dart';
import '../widgets/profile_customer_photos_card.dart';
import '../widgets/profile_support_section.dart';
import '../widgets/profile_business_mode_card.dart';
import '../screens/addresses_screen.dart';
import '../../../orders/presentation/screens/orders_screen.dart';
import '../../../notifications/presentation/screens/notification_settings_screen.dart';
import '../screens/account_data_screen.dart';
import '../screens/saved_cards_screen.dart';
import '../screens/loyalty_screen.dart';
import '../screens/help_screen.dart';
import '../../../favorites/presentation/screens/favorites_screen.dart';
import '../../../crm/presentation/providers/current_customer_provider.dart';
import '../../../feedback/presentation/screens/customer_feedback_screen.dart';
import '../../../navigation/presentation/providers/current_branch_provider.dart';
import '../../../pos/presentation/providers/actor_session_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(
      profileProvider.select((profile) => profile != null),
    );
    // Deny-by-default, unchanged from before P.3 — `actorSessionProvider`
    // itself still defaults to `null`/empty roles for every ordinary
    // customer and guest; this screen only decides whether to *render*
    // the business-mode card, never grants access itself.
    final isAuthorizedActor = ref.watch(
      actorSessionProvider.select(
        (session) => session?.roles.isNotEmpty ?? false,
      ),
    );

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
              const ProfileHeroCard(),
              const SizedBox(height: AppSpacing.lg),
              ProfileQuickActions(
                onBoncuklarim: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoyaltyScreen(),
                  ),
                ),
                onSiparislerim: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const OrdersScreen(),
                  ),
                ),
                onFavorilerim: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FavoritesScreen(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const ProfileLoyaltyCard(),
              const SizedBox(height: AppSpacing.xxl),
              ProfileAccountPreferencesSection(
                onAddresses: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddressesScreen(),
                    ),
                  );
                },
                onPaymentMethods: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SavedCardsScreen(),
                    ),
                  );
                },
                onNotificationSettings: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificationSettingsScreen(),
                    ),
                  );
                },
                onAccountData: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AccountDataScreen(),
                    ),
                  );
                },
              ),
              // P.3.1: a guest has no `currentCustomerProvider` customer to
              // resolve at all — Visit Pass has nothing to show them, so
              // it's not just tap-guarded anymore, it's not rendered.
              if (isAuthenticated) ...[
                const SizedBox(height: AppSpacing.xxl),
                const ProfileVisitPassCard(),
              ],
              // Profile P.4.3A: real photo gallery/upload backend now
              // exists — same "guest has nothing to resolve" reasoning as
              // Visit Pass above, so this is gated the same way (not
              // rendered at all for a guest, not just tap-guarded).
              if (isAuthenticated) ...[
                const SizedBox(height: AppSpacing.lg),
                const ProfileCustomerPhotosCard(),
              ],
              const SizedBox(height: AppSpacing.xxl),
              ProfileSupportSection(
                onFeedback: () {
                  final customer =
                      ref.read(currentCustomerProvider).valueOrNull;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CustomerFeedbackScreen(
                        branchId: ref.read(currentBranchIdProvider),
                        customerId: customer?.id,
                      ),
                    ),
                  );
                },
                onHelp: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HelpScreen(),
                    ),
                  );
                },
              ),
              if (isAuthorizedActor) ...[
                const SizedBox(height: AppSpacing.xxl),
                const ProfileBusinessModeCard(),
              ],
              if (isAuthenticated) ...[
                const SizedBox(height: AppSpacing.xxxl),
                Center(
                  child: InkWell(
                    key: const Key('profileLogoutButton'),
                    onTap: () => _showLogoutDialog(context, ref),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.logout_rounded,
                            color: AppColors.error,
                            size: 18,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Çıkış Yap',
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
