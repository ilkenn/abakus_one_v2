import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/models/customer_profile_completion_state.dart';
import '../providers/customer_registration_providers.dart';
import '../providers/customer_registration_submit_provider.dart';
import '../widgets/onboarding_step_indicator.dart';
import '../widgets/step1_info_form.dart';
import '../widgets/step2_photo_step.dart';

/// Customer Registration CR.1 — the mandatory "Profilini Tamamla" screen.
/// A first-time real customer lands here (via `AppRouteGuard`) between a
/// successful OTP and ever reaching the authenticated customer app.
///
/// Never navigates itself on success — see
/// `CustomerRegistrationSubmitNotifier`'s own doc comment. This screen
/// only ever renders `loading`/`incomplete`/`error`
/// ([CustomerProfileCompletionPhase.complete] briefly shows a plain
/// loading view while the router's own redirect takes over).
class CompleteProfileScreen extends ConsumerWidget {
  const CompleteProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completionState = ref.watch(customerProfileCompletionStateProvider);

    return PopScope(
      // A first-time customer must never be able to back-navigate around
      // mandatory registration into the authenticated app (locked
      // requirement) — this screen is only ever reached via a redirect,
      // ".main" back en route.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: const [_LogoutAction()],
        ),
        body: SafeArea(
          child: switch (completionState.phase) {
            CustomerProfileCompletionPhase.loading => const LoadingView(
                message: 'Hesabın hazırlanıyor...',
              ),
            CustomerProfileCompletionPhase.complete => const LoadingView(),
            CustomerProfileCompletionPhase.error => ErrorView(
                message:
                    'Hesap bilgilerine şu anda ulaşılamıyor. Lütfen tekrar dene.',
                retryLabel: 'Tekrar Dene',
                onRetry: () =>
                    ref.invalidate(customerProfileCompletionResultProvider),
              ),
            CustomerProfileCompletionPhase.incomplete =>
              const _CompleteProfileWizard(),
          },
        ),
      ),
    );
  }
}

class _LogoutAction extends ConsumerWidget {
  const _LogoutAction();

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
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
            onPressed: () {
              Navigator.pop(dialogContext);
              // No manual navigation — go_router's own redirect reacts to
              // authProvider flipping to signed-out (see
              // `_RouterRefreshListenable`) and takes the user to
              // login/onboarding automatically.
              ref.read(authProvider.notifier).logout();
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
    return IconButton(
      key: const Key('completeProfileLogoutButton'),
      icon: const Icon(Icons.logout_rounded, color: AppColors.textSecondary),
      tooltip: 'Çıkış Yap',
      onPressed: () => _showLogoutDialog(context, ref),
    );
  }
}

/// CR.1.2 — owns which of the two onboarding steps is showing. Plain
/// local `State`, deliberately not a Riverpod provider — "do not create a
/// second registration-completion flag" (locked requirement): which step
/// is visible is pure, ephemeral UI state, never anything server truth or
/// the router's redirect logic needs to know about.
class _CompleteProfileWizard extends ConsumerStatefulWidget {
  const _CompleteProfileWizard();

  @override
  ConsumerState<_CompleteProfileWizard> createState() =>
      _CompleteProfileWizardState();
}

class _CompleteProfileWizardState
    extends ConsumerState<_CompleteProfileWizard> {
  OnboardingStep _step = OnboardingStep.info;

  void _finishOnboarding() {
    ref.read(customerRegistrationSubmitProvider.notifier).finishOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profilini Tamamla',
            style: AppTypography.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_step == OnboardingStep.info) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Abaküs deneyimine başlamadan önce birkaç bilgiye ihtiyacımız var.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          OnboardingStepIndicator(currentStep: _step),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: _step == OnboardingStep.info
                ? Step1InfoForm(
                    onSuccess: () =>
                        setState(() => _step = OnboardingStep.photo),
                  )
                : Step2PhotoStep(onFinished: _finishOnboarding),
          ),
        ],
      ),
    );
  }
}
