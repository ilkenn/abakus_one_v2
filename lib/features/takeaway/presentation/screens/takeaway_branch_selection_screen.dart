import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../cart/presentation/providers/shopping_channel_provider.dart';
import '../../../menu/presentation/screens/menu_screen.dart';
import '../../application/use_cases/list_takeaway_eligible_branches.dart';
import '../../../../core/auth/real_customer_check.dart';
import '../providers/takeaway_dependencies_provider.dart';

/// Entry point for Gel Al (Faz C) — pushed from Home's "Gel Al"
/// [OrderModeCard]. Gates on a real, phone-verified, non-expired customer
/// session (never a guest, never an anonymous technical identity — see
/// [AuthState.isAuthenticated]/[AuthState.isGuest]/[AuthSession.isExpired]),
/// then lists Gel Al-eligible branches and lets the customer pick one.
class TakeawayBranchSelectionScreen extends ConsumerWidget {
  const TakeawayBranchSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Gel Al')),
      body: SafeArea(
        child: isRealCustomer(authState)
            ? _BranchList(
                onBranchSelected: (branch) =>
                    _onBranchSelected(context, ref, branch),
              )
            : _LoginRequiredPrompt(
                onLoginTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                ),
              ),
      ),
    );
  }

  void _onBranchSelected(
    BuildContext context,
    WidgetRef ref,
    TakeawayEligibleBranch branch,
  ) {
    ref.read(shoppingChannelProvider.notifier).selectTakeaway(
          restaurantId: branch.restaurantId,
          branchId: branch.id,
          branchDisplayName: branch.displayName,
        );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MenuScreen()),
    );
  }
}

class _LoginRequiredPrompt extends StatelessWidget {
  final VoidCallback onLoginTap;

  const _LoginRequiredPrompt({required this.onLoginTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.storefront_rounded,
              size: 64,
              color: AppColors.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Gel Al siparişi vermek için giriş yapmalısın.',
              style: AppTypography.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: onLoginTap,
              child: const Text('Giriş Yap'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchList extends ConsumerWidget {
  final void Function(TakeawayEligibleBranch branch) onBranchSelected;

  const _BranchList({required this.onBranchSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(takeawayEligibleBranchesProvider);

    return branchesAsync.when(
      loading: () => const LoadingView(message: 'Şubeler yükleniyor...'),
      error: (error, stackTrace) => ErrorView(
        message: 'Şubeler yüklenirken bir sorun oluştu.',
        retryLabel: 'Tekrar Dene',
        onRetry: () => ref.invalidate(takeawayEligibleBranchesProvider),
      ),
      data: (branches) {
        if (branches.isEmpty) {
          return const EmptyView(
            icon: Icons.storefront_outlined,
            message: 'Şu anda Gel Al siparişi kabul eden bir şube yok.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: branches.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            final branch = branches[index];
            return AppCard(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                leading: const Icon(
                  Icons.storefront_rounded,
                  color: AppColors.primary,
                ),
                title: Text(
                  branch.displayName,
                  style: AppTypography.bodyLarge,
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.kMedium,
                ),
                onTap: () => onBranchSelected(branch),
              ),
            );
          },
        );
      },
    );
  }
}
