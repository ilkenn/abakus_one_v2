import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_route_guard.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/quick_test_login_config.dart';
import '../../domain/phone_number.dart';
import '../providers/auth_provider.dart';
import '../providers/quick_test_login_provider.dart';

/// MVP customer authentication is phone number + OTP only — no email, no
/// password. See `docs/master_spec_migration.md` for the Authentication
/// phase's design decisions.
///
/// The interactive Hero Abacus (`shared/widgets/hero/hero_abacus.dart`) has
/// been removed from this screen — it remains a valid, tested, reusable
/// component (see `HeroAbacusLabScreen`), just no longer used here. This
/// screen instead opens on the static Abaküs Street Food logo with a
/// single, one-shot entrance animation.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.returnTo});

  /// Faz R.2 — an already-sanitized-by-the-guard location to return to
  /// after a successful OTP verification (e.g. `/reservation`). Forwarded
  /// verbatim to [OtpScreen], never acted on here — this screen never
  /// itself decides where "success" leads.
  final String? returnTo;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneController;

  late final AnimationController _logoController;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<Offset> _logoSlide;

  /// `errorBuilder` below falls back to a plain text wordmark if this asset
  /// is ever missing (e.g. a fresh checkout before assets are pulled), so
  /// the screen never breaks.
  static const String _logoAssetPath = 'assets/images/branding/abakus_logo.png';

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    final curved = CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOutCubic,
    );
    _logoFade = curved;
    _logoScale = Tween<double>(begin: 0.96, end: 1.0).animate(curved);
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(curved);

    final reduceMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (reduceMotion) {
      _logoController.value = 1.0;
    } else {
      _logoController.forward();
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _logoController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final sent = await ref.read(authProvider.notifier).requestOtp(
          _phoneController.text,
        );
    if (!mounted || !sent) return;

    context.push(
      widget.returnTo == null
          ? AppRoutes.otp
          : AppRoutes.withReturnTo(AppRoutes.otp, widget.returnTo!),
    );
  }

  void _continueAsGuest() {
    ref.read(authProvider.notifier).loginAsGuest();
    context.go(AppRoutes.main);
  }

  /// "Hızlı Test Girişi" — development-only, see `QuickTestLoginConfig`'s
  /// own doc comment. Drives the real phone-verification flow end-to-end
  /// (`QuickTestLoginNotifier.run`), then continues through the exact same
  /// post-login navigation [OtpScreen]'s own successful `_submit` uses —
  /// no separate "quick login" destination.
  Future<void> _submitQuickTestLogin() async {
    final success = await ref.read(quickTestLoginProvider.notifier).run();
    if (!mounted || !success) return;

    final sanitizedReturnTo = AppRouteGuard.sanitizeReturnTo(widget.returnTo);
    context.go(sanitizedReturnTo ?? AppRoutes.main);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final quickTestLoginState = ref.watch(quickTestLoginProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: FadeTransition(
                      opacity: _logoFade,
                      child: SlideTransition(
                        position: _logoSlide,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: Image.asset(
                            _logoAssetPath,
                            width: 220,
                            filterQuality: FilterQuality.high,
                            isAntiAlias: true,
                            errorBuilder: (context, error, stackTrace) {
                              return const Text(
                                'abaküs',
                                style: AppTypography.headlineLarge,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Text(
                    'Abaküs\'e Hoş Geldiniz',
                    style: AppTypography.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Giriş yapmak için telefon numaranı gir, sana bir kod gönderelim.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    style: AppTypography.bodyLarge,
                    decoration: const InputDecoration(
                      labelText: 'Telefon Numarası',
                      prefixText: '+90 ',
                      prefixIcon: Icon(Icons.phone_iphone_rounded),
                      hintText: '5XX XXX XX XX',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: AppSpacing.lg,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: AppRadius.kExtraLarge,
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppRadius.kExtraLarge,
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppRadius.kExtraLarge,
                        borderSide: BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    validator: (value) {
                      final digits = value ?? '';
                      if (digits.isEmpty) {
                        return 'Lütfen telefon numaranızı giriniz';
                      }
                      if (!TurkishPhoneNumber.isValidLocalNumber(digits)) {
                        return 'Lütfen geçerli bir telefon numarası giriniz';
                      }
                      return null;
                    },
                  ),
                  if (authState.error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      authState.error!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  ElevatedButton(
                    onPressed: authState.isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.kExtraLarge,
                      ),
                    ),
                    child: authState.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Devam Et'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: authState.isLoading ? null : _continueAsGuest,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.kExtraLarge,
                      ),
                    ),
                    child: const Text('Misafir Olarak Devam Et'),
                  ),
                  if (QuickTestLoginConfig.isAvailable) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _QuickTestLoginButton(
                      isBusy: quickTestLoginState.isRunning,
                      disabled: authState.isLoading,
                      error: quickTestLoginState.error,
                      onPressed: _submitQuickTestLogin,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Devam ederek Kullanım Koşulları ve Gizlilik Politikası\'nı kabul etmiş olursun.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Deliberately styled to look nothing like the real "Devam Et"/"Misafir
/// Olarak Devam Et" buttons above it — a dashed, warning-colored outline
/// and a science/dev icon, so it reads unmistakably as development
/// tooling, never as a real product affordance a screenshot or a QA pass
/// could mistake for one. Only ever built at all when
/// [QuickTestLoginConfig.isAvailable] — see the call site.
class _QuickTestLoginButton extends StatelessWidget {
  const _QuickTestLoginButton({
    required this.isBusy,
    required this.disabled,
    required this.error,
    required this.onPressed,
  });

  final bool isBusy;
  final bool disabled;
  final String? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: (disabled || isBusy) ? null : onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            foregroundColor: AppColors.warning,
            side: const BorderSide(color: AppColors.warning, width: 1.5),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.kExtraLarge,
            ),
          ),
          icon: isBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.science_outlined),
          label: const Text(
            'Hızlı Test Girişi (DEV: '
            '+90 ${QuickTestLoginConfig.developmentPhoneLocalInput})',
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            error!,
            style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
