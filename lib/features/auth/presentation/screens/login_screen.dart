import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/app_environment_config.dart';
import '../../../../core/router/app_route_guard.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/dev_login_config.dart';
import '../../domain/phone_number.dart';
import '../providers/auth_provider.dart';
import '../providers/dev_login_provider.dart';

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

  // TEMPORARY_DEVELOPER_LOGIN — see `DevLoginConfig`'s own doc comment for
  // the full removal-marker file list. Continues through the exact same
  // post-login navigation [OtpScreen]'s own successful `_submit` uses — no
  // separate "dev login" destination.
  void _onDevLoginSuccess() {
    if (!mounted) return;
    final sanitizedReturnTo = AppRouteGuard.sanitizeReturnTo(widget.returnTo);
    context.go(sanitizedReturnTo ?? AppRoutes.main);
  }

  /// PC Yönetici İnceleme Modu — a debug-only corner shortcut onto the real
  /// staff/admin entry point (`AppRoutes.admin` -> `AdminShellScreen`,
  /// which already shows `StaffSignInScreen` internally whenever there is
  /// no active `actorSessionProvider` session — reused as-is, never a
  /// direct cross-feature import of that screen from here, which this
  /// codebase's own layering rules forbid). Same defense-in-depth gate as
  /// `StaffSignInScreen`'s own "Dev Admin ile Gir" shortcut: `kDebugMode`
  /// (never compiled into a release binary) AND `AppEnvironmentConfig
  /// .current.allowsDebugTooling` (already `false` for staging/production
  /// even in a debug build pointed at the wrong project).
  static bool get _staffEntryShortcutAvailable =>
      kDebugMode && AppEnvironmentConfig.current.allowsDebugTooling;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
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
                        onPressed:
                            authState.isLoading ? null : _continueAsGuest,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.kExtraLarge,
                          ),
                        ),
                        child: const Text('Misafir Olarak Devam Et'),
                      ),
                      if (DevLoginConfig.isAvailable) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _DevLoginSection(onSuccess: _onDevLoginSuccess),
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
            // Painted (and hit-tested) LAST so it sits above the scrollable
            // form beneath it — a Stack child earlier in this list would
            // have its taps swallowed by the form's own scroll gesture
            // detector, even where nothing is visibly drawn over it.
            if (_staffEntryShortcutAvailable)
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: Tooltip(
                  message: 'Personel / POS Girişi (Yalnızca Development)',
                  child: IconButton(
                    onPressed: () => context.push(AppRoutes.admin),
                    icon: const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// TEMPORARY_DEVELOPER_LOGIN — see `DevLoginConfig`'s own doc comment for
// the full removal-marker file list. Supersedes the old one-tap "Hızlı
// Test Girişi" button (removed, not left rendering alongside this — "do
// not leave two overlapping developer-auth mechanisms visible").
//
/// Deliberately styled to look nothing like the real "Devam Et"/"Misafir
/// Olarak Devam Et" fields above it — a dashed, warning-colored outline
/// and a science/dev icon, so it reads unmistakably as development
/// tooling, never as a real product affordance a screenshot or a QA pass
/// could mistake for one. Only ever built at all when
/// [DevLoginConfig.isAvailable] — see the call site. The PIN field is
/// never read from anywhere but its own local [TextEditingController],
/// and that controller is disposed (never written to any storage) —
/// "PIN must not be persisted."
class _DevLoginSection extends ConsumerStatefulWidget {
  const _DevLoginSection({required this.onSuccess});

  final VoidCallback onSuccess;

  @override
  ConsumerState<_DevLoginSection> createState() => _DevLoginSectionState();
}

class _DevLoginSectionState extends ConsumerState<_DevLoginSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneController;
  late final TextEditingController _pinController;

  @override
  void initState() {
    super.initState();
    _phoneController =
        TextEditingController(text: DevLoginConfig.developerPhoneLocalInput);
    _pinController = TextEditingController();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final success = await ref.read(devLoginProvider.notifier).run(
          phoneInput: _phoneController.text,
          pin: _pinController.text,
        );
    if (success) widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    final devLoginState = ref.watch(devLoginProvider);
    final authState = ref.watch(authProvider);
    final disabled = authState.isLoading || devLoginState.isRunning;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Geliştirici Girişi',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.warning,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            style: AppTypography.bodyLarge,
            decoration: const InputDecoration(
              labelText: 'Telefon Numarası',
              prefixText: '+90 ',
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadius.kExtraLarge,
                borderSide: BorderSide(color: AppColors.warning),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.kExtraLarge,
                borderSide: BorderSide(color: AppColors.warning),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.kExtraLarge,
                borderSide: BorderSide(color: AppColors.warning, width: 1.5),
              ),
            ),
            validator: (value) {
              final digits = value ?? '';
              if (!TurkishPhoneNumber.isValidLocalNumber(digits)) {
                return 'Lütfen geçerli bir telefon numarası giriniz';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AppTypography.bodyLarge,
            decoration: const InputDecoration(
              labelText: 'Geliştirici PIN',
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadius.kExtraLarge,
                borderSide: BorderSide(color: AppColors.warning),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.kExtraLarge,
                borderSide: BorderSide(color: AppColors.warning),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.kExtraLarge,
                borderSide: BorderSide(color: AppColors.warning, width: 1.5),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'PIN gerekli';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: disabled ? null : _submit,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: AppColors.warning,
              side: const BorderSide(color: AppColors.warning, width: 1.5),
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.kExtraLarge,
              ),
            ),
            icon: devLoginState.isRunning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.science_outlined),
            label: const Text('Geliştirici Olarak Giriş Yap'),
          ),
          if (devLoginState.error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              devLoginState.error!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
