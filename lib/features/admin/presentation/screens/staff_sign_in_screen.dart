import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/auth/email_password_auth_client.dart';
import '../../../../core/services/logging/log_level.dart';
import '../../../../core/services/logging/logging_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/domain/phone_number.dart';
import '../../../auth/domain/staff_login_email.dart';
import '../../application/use_cases/bootstrap_first_admin_account.dart';
import '../../data/staff_auth_repository.dart';
import 'admin_shell_screen.dart';
import '../providers/admin_dependencies_provider.dart';
import '../providers/staff_session_controller.dart';

/// Staff sign-in for the Windows POS and for a panel opened without a
/// session — Phase 6B (`docs/decisions.md` ADR-023), Sprint 9C (ADR-026).
///
/// **ADR-085 (revision, 2026-11-13): phone number + password.** Staff type
/// their phone number and the password a manager set in the panel; the
/// app derives the account's hidden sign-in e-mail from the number
/// ([staffLoginEmailForPhone]) and signs in through the same real
/// e-mail/password path as before, which already works on Windows. The
/// SMS tab (Firebase phone verification is not available on Windows) and
/// the emulator-only "Dev Admin" shortcut are gone. One message covers
/// every wrong-credential case, so the screen never reveals whether a
/// number belongs to staff.
///
/// `staffAuthRepositoryProvider` resolves to `FirebaseStaffAuthRepository`
/// once Firebase is ready, or `ProductionUnavailableStaffAuthRepository`
/// (always fails) otherwise.
class StaffSignInScreen extends ConsumerStatefulWidget {
  const StaffSignInScreen({super.key});

  @override
  ConsumerState<StaffSignInScreen> createState() => _StaffSignInScreenState();
}

class _StaffSignInScreenState extends ConsumerState<StaffSignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _showBootstrap = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// The typed number as the account's hidden sign-in e-mail. Only called
  /// after the form validated the number.
  String _signInEmail() => staffLoginEmailForPhone(
        TurkishPhoneNumber.normalize(_phoneController.text)!,
      );

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Temporary diagnostic tracing (PC Yönetici İnceleme Modu — Chrome
    // latency report, 2026-09-11) — see `FirebaseStaffAuthRepository`'s own
    // `_logging` doc comment for why this goes through `LoggingService`
    // rather than a raw print. Remove once the latency question this was
    // added to answer is settled.
    final logging = ref.read(loggingServiceProvider);
    final overallWatch = Stopwatch()..start();
    logging.log(LogLevel.debug, '[AUTH-TRACE] _signIn: start');
    setState(() {
      _busy = true;
      _error = null;
    });
    bool success = false;
    try {
      // A stale customer (or different-staff) Firebase Auth session left
      // over makes the client keep reading admin-scoped collections under
      // the WRONG identity while this new sign-in is in flight, which
      // `firestore.rules` correctly denies — clearing it first removes that
      // ambiguity structurally rather than racing it. Best-effort: a failed
      // sign-out must never block the sign-in attempt that follows it.
      try {
        await ref.read(staffSessionControllerProvider).signOut();
      } catch (e, st) {
        logging.log(
          LogLevel.error,
          '[AUTH-TRACE] signOut: failed, ignored',
          error: e,
          stackTrace: st,
        );
      }

      success = await ref.read(staffSessionControllerProvider).signIn(
            email: _signInEmail(),
            password: _passwordController.text,
          );
    } on StaffAuthUnavailableException catch (e, st) {
      logging.log(
        LogLevel.error,
        '[AUTH-TRACE] _signIn: StaffAuthUnavailableException '
        '(${overallWatch.elapsedMilliseconds}ms)',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() => _error = e.message);
      return;
    } catch (e, st) {
      logging.log(
        LogLevel.error,
        '[AUTH-TRACE] _signIn: unexpected exception '
        '(${overallWatch.elapsedMilliseconds}ms)',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() => _error = 'Beklenmeyen bir sorun oluştu — tekrar deneyin.');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (!success) {
      setState(() => _error = 'Telefon numarası veya şifre hatalı.');
      return;
    }
    logging.log(
        LogLevel.debug,
        '[AUTH-TRACE] _signIn: success (${overallWatch.elapsedMilliseconds}ms) '
        '— Navigating to AdminShellScreen');
    _passwordController.clear();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdminShellScreen()),
    );
  }

  /// First-run only: creates the organization's first admin with the typed
  /// phone number + password (the server refuses once any staff exists).
  Future<void> _bootstrapFirstAdmin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BootstrapFirstAdminAccount(
        idGenerator: ref.read(staffMemberIdGeneratorProvider),
        repository: ref.read(staffMemberRepositoryProvider),
        auditRepository: ref.read(adminAuditEntryRepositoryProvider),
        authClient: DefaultEmailPasswordAuthClient(),
      )(
        displayName: 'İlk Yönetici',
        organizationId: 'org-1',
        createdAt: DateTime.now(),
        email: _signInEmail(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      setState(() {
        _error = null;
        _showBootstrap = false;
      });
      await _signIn();
    } on EmailPasswordAuthClientException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Beklenmeyen bir sorun oluştu — tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Personel Girişi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Telefon numaranız ve yöneticinizin belirlediği şifre ile '
                  'giriş yapın.',
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _phoneController,
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Telefon Numarası',
                    prefixIcon: Icon(Icons.phone_outlined),
                    prefixText: '+90 ',
                    hintText: '5XX XXX XX XX',
                  ),
                  validator: (value) => TurkishPhoneNumber.isValidLocalNumber(
                          value ?? '')
                      ? null
                      : 'Geçerli bir telefon numarası girin (5XX XXX XX XX)',
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _passwordController,
                  enabled: !_busy,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                    labelText: 'Şifre',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                  validator: (value) => (value == null || value.isEmpty)
                      ? 'Lütfen şifrenizi girin'
                      : null,
                  onFieldSubmitted: (_) => _busy ? null : _signIn(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_error!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error)),
                ],
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  onPressed: _busy ? null : _signIn,
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Giriş Yap'),
                ),
                const SizedBox(height: AppSpacing.xl),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _showBootstrap = true),
                  child: const Text('İlk yönetici hesabını oluştur'),
                ),
                if (_showBootstrap) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Yalnızca hiç personel hesabı kayıtlı değilse çalışır — '
                    'yukarıdaki telefon numarası ve şifre ile yeni bir '
                    'yönetici hesabı oluşturulur.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: _busy ? null : _bootstrapFirstAdmin,
                    style: OutlinedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                    child: const Text('İlk Yönetici Hesabını Oluştur'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
