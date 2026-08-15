import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_route_guard.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_theme_constants.dart';
import '../../data/repositories/development_local_auth_repository.dart';
import '../../domain/models/otp_challenge.dart';
import '../providers/auth_provider.dart';
import '../providers/otp_provider.dart';

/// Masks a normalized `+905XXXXXXXXX` phone number for display, e.g.
/// `+90 5•• ••• •• 34` — only the country/leading digit and the last two
/// digits are shown.
String _maskPhoneNumber(String normalized) {
  if (normalized.length < 5) return normalized;
  final leading = normalized.substring(0, 4); // "+905"
  final last2 = normalized.substring(normalized.length - 2);
  return '$leading•• ••• •• $last2';
}

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, this.returnTo});

  /// Faz R.2 — forwarded from [LoginScreen]. Re-sanitized on read here
  /// (never trusted verbatim, even though this screen itself only ever
  /// received it via [AppRouteGuard]/[LoginScreen]'s own forwarding) —
  /// `/login`/`/otp` are reachable by direct deep link with an arbitrary
  /// query string, so this is the defense-in-depth boundary, independent
  /// of whatever produced the value.
  final String? returnTo;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  late final TextEditingController _codeController;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final result = await ref.read(otpProvider.notifier).submit();
    if (!mounted || result != OtpVerificationResult.success) return;

    final sanitizedReturnTo = AppRouteGuard.sanitizeReturnTo(widget.returnTo);
    context.go(sanitizedReturnTo ?? AppRoutes.main);
  }

  void _changePhoneNumber() {
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final phoneNumber = ref.watch(authProvider).pendingPhoneNumber ?? '';
    final otpState = ref.watch(otpProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _changePhoneNumber,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.sms_outlined,
                size: 56,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Doğrulama Kodu',
                style: AppTypography.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${_maskPhoneNumber(phoneNumber)} numarasına gönderilen 6 haneli kodu gir.',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              Semantics(
                label: 'Doğrulama kodu, 6 hane',
                textField: true,
                child: TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: 6,
                  style: AppTypography.headlineMedium.copyWith(
                    letterSpacing: 8,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '••••••',
                  ),
                  onChanged: (value) {
                    ref.read(otpProvider.notifier).updateEnteredCode(value);
                  },
                ),
              ),
              if (!kReleaseMode) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Geliştirme kodu: ${DevelopmentLocalAuthRepository.developmentOtpCode}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (otpState.screenError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  otpState.screenError!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                onPressed: otpState.isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  minimumSize: const Size.fromHeight(
                    AppThemeConstants.minTapTargetSize,
                  ),
                ),
                child: otpState.isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Doğrula'),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: TextButton(
                  onPressed: otpState.cooldownSeconds > 0
                      ? null
                      : () => ref.read(otpProvider.notifier).resend(),
                  child: Text(
                    otpState.cooldownSeconds > 0
                        ? 'Yeniden gönder (${otpState.cooldownSeconds}s)'
                        : 'Kodu yeniden gönder',
                  ),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: _changePhoneNumber,
                  child: const Text('Telefon numarasını değiştir'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
