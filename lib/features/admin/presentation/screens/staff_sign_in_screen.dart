import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_environment_config.dart';
import '../../../../core/services/auth/email_password_auth_client.dart';
import '../../../../core/services/logging/log_level.dart';
import '../../../../core/services/logging/logging_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../application/use_cases/bootstrap_first_admin_account.dart';
import '../../data/staff_auth_repository.dart';
import 'admin_shell_screen.dart';
import '../providers/admin_dependencies_provider.dart';
import '../providers/staff_session_controller.dart';

/// The first, and only, place `actorSessionProvider` is ever populated
/// from real user interaction in this app — Phase 6B
/// (`docs/decisions.md` ADR-023).
///
/// **Sprint 9C** (`docs/decisions.md` ADR-026): this is now a real
/// email/password credential form, not a picker over the staff roster —
/// closes the "no-credential member picker" gap structurally: this screen
/// never queries `StaffMemberRepository.findAll()` at all anymore, so
/// there is no roster to enumerate regardless of build mode.
/// `staffAuthRepositoryProvider` resolves to `FirebaseStaffAuthRepository`
/// once Firebase is ready, or `ProductionUnavailableStaffAuthRepository`
/// (always fails) otherwise — "do not claim production backend
/// validation if none exists." Mirrors `LoginScreen`'s raw
/// `TextFormField`/`ElevatedButton` pattern — `shared/widgets/inputs/
/// app_text_field.dart` and `shared/widgets/buttons/primary_button.dart`
/// are still empty placeholder files (`CLAUDE.md`'s ground-truth-vs-
/// aspirational note), so this screen doesn't invent a dependency on them.
class StaffSignInScreen extends ConsumerStatefulWidget {
  const StaffSignInScreen({super.key});

  @override
  ConsumerState<StaffSignInScreen> createState() => _StaffSignInScreenState();
}

/// Which credential form [StaffSignInScreen] currently shows — a toggle,
/// not two separate screens, since both land on the exact same success
/// path ([AdminShellScreen]) and share the same busy/error state.
enum _SignInMethod { email, phone }

class _StaffSignInScreenState extends ConsumerState<StaffSignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _showBootstrap = false;
  _SignInMethod _method = _SignInMethod.email;

  /// Set once [_sendPhoneCode] succeeds — switches the phone form from
  /// "enter a number" to "enter the code just sent to it." `null` means no
  /// challenge is currently live (including after a successful/failed
  /// verification, so a retry always starts from a clean number field).
  String? _phoneVerificationId;

  /// PC Yönetici İnceleme Modu — a local-development-only shortcut onto
  /// this screen's own real `_signIn()` (real Firebase email/password
  /// auth, real server-side custom-claims sync — nothing about
  /// authorization itself is bypassed). Gated on BOTH `kDebugMode` (never
  /// compiled into a release binary) AND `AppEnvironmentConfig.current
  /// .allowsDebugTooling` (`false` for staging/production even in a debug
  /// build pointed at the wrong project) — defense in depth, matching this
  /// codebase's own established fail-closed discipline.
  ///
  /// The credentials are the real dev admin account
  /// `functions/scripts/seed_dev_staff.mjs` seeds into the local Firebase
  /// emulator (`admin@abakus.dev` / hand-synced password, documented
  /// there) — this button only pre-fills and submits them through the
  /// exact same form `_signIn()` already validates.
  static bool get _devAdminShortcutAvailable =>
      kDebugMode && AppEnvironmentConfig.current.allowsDebugTooling;

  static const String _devAdminEmail = 'admin@abakus.dev';
  static const String _devAdminPassword = 'abakus-dev-admin-2026';

  /// **Retired 2026-09-20** (PC Yönetici İnceleme Modu): a Windows-only
  /// fabricated-`ActorSession` shortcut lived here briefly, because
  /// `syncOwnStaffClaims` was entirely skipped on Windows at the time. That
  /// was exactly the real bug: skipping the sync (not just the transport)
  /// left the real Firebase ID token with genuinely empty claims, which
  /// then made every real server permission check (e.g.
  /// `requestDeviceRegistration`'s "authorization is required for this
  /// organization") correctly deny it — the fabricated local session was
  /// never actually authorized as far as the server was concerned. Now
  /// that `DefaultStaffClaimsSyncClient.syncAndRefresh` routes
  /// `syncOwnStaffClaims` through `RestCallableClient` on Windows instead
  /// of skipping it (`core/services/auth/staff_claims_sync_client.dart`),
  /// the real `_signIn` chain below works end-to-end on Windows too — no
  /// fabrication needed anymore.
  Future<void> _signInAsDevAdmin() async {
    _emailController.text = _devAdminEmail;
    _passwordController.text = _devAdminPassword;
    // Lands directly on the POS branch overview — see AdminShellScreen's
    // own doc comment on `initialNavItemId`. Only this dev shortcut ever
    // passes a value; a real staff/manager/admin sign-in below keeps the
    // shell's existing default landing behavior unchanged.
    await _signIn(initialAdminNavItemId: 'pos');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose();
    super.dispose();
  }

  /// Mirrors `TurkishPhoneNumber.normalize` (`features/auth/domain/
  /// phone_number.dart`) exactly — duplicated locally rather than imported
  /// across features for a 10-line, stateless, single-purpose check (the
  /// customer phone flow's own domain utility isn't yet promoted to
  /// `core`/`shared`, and this screen already imports
  /// `FirebaseAuthClient` from that feature's data layer for the real
  /// verification call itself — see that import's own comment on the
  /// cross-feature-reuse question this raises).
  static String? _normalizeTurkishPhoneNumber(String rawLocalInput) {
    final digitsOnly = rawLocalInput.replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^5\d{9}$').hasMatch(digitsOnly)) return null;
    return '+90$digitsOnly';
  }

  void _completeSignIn(bool success) {
    if (!mounted) return;
    if (!success) {
      setState(() => _error = 'Giriş başarısız. Bilgilerinizi kontrol edin.');
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdminShellScreen()),
    );
  }

  Future<void> _sendPhoneCode() async {
    final normalized = _normalizeTurkishPhoneNumber(_phoneController.text);
    if (normalized == null) {
      setState(
          () => _error = 'Geçerli bir telefon numarası girin (5XX XXX XX XX).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      try {
        await ref.read(staffSessionControllerProvider).signOut();
      } catch (_) {
        // Best-effort — see `_signIn`'s own identical comment on why a
        // failed sign-out must never block the attempt that follows it.
      }
      final verificationId = await ref
          .read(staffSessionControllerProvider)
          .startPhoneSignIn(normalized);
      if (!mounted) return;
      setState(() {
        _phoneVerificationId = verificationId;
        _smsCodeController.clear();
      });
    } on StaffAuthUnavailableException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Beklenmeyen bir sorun oluştu — tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyPhoneCode() async {
    final verificationId = _phoneVerificationId;
    if (verificationId == null) return;
    final code = _smsCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Lütfen size gelen kodu girin.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    bool success;
    try {
      success =
          await ref.read(staffSessionControllerProvider).completePhoneSignIn(
                verificationId: verificationId,
                smsCode: code,
              );
    } on StaffAuthUnavailableException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Beklenmeyen bir sorun oluştu — tekrar deneyin.');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _completeSignIn(success);
  }

  Future<void> _signIn({String? initialAdminNavItemId}) async {
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
      // A stale customer/B2C (or different-staff) Firebase Auth session
      // left over in the browser makes the client keep reading
      // admin-scoped Firestore collections under the WRONG identity while
      // this new sign-in is in flight, which `firestore.rules` correctly
      // denies (`[cloud_firestore/permission-denied]`) — clearing it first
      // removes that ambiguity structurally rather than racing it.
      // Best-effort: a failed sign-out must never block the sign-in
      // attempt that follows it.
      final signOutWatch = Stopwatch()..start();
      logging.log(LogLevel.debug, '[AUTH-TRACE] signOut: start');
      try {
        await ref.read(staffSessionControllerProvider).signOut();
        logging.log(LogLevel.debug,
            '[AUTH-TRACE] signOut: end (${signOutWatch.elapsedMilliseconds}ms)');
      } catch (e, st) {
        logging.log(
          LogLevel.error,
          '[AUTH-TRACE] signOut: failed, ignored '
          '(${signOutWatch.elapsedMilliseconds}ms)',
          error: e,
          stackTrace: st,
        );
        // Swallowed deliberately — see comment above.
      }

      success = await ref.read(staffSessionControllerProvider).signIn(
            email: _emailController.text.trim(),
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
    if (!success) {
      logging.log(
          LogLevel.debug,
          '[AUTH-TRACE] _signIn: signIn() returned false — invalid credential '
          '(${overallWatch.elapsedMilliseconds}ms)');
      setState(() => _error = 'Giriş başarısız. Bilgilerinizi kontrol edin.');
      return;
    }
    if (!mounted) return;
    logging.log(
        LogLevel.debug,
        '[AUTH-TRACE] _signIn: success (${overallWatch.elapsedMilliseconds}ms) '
        '— Navigating to AdminShellScreen');
    logging.log(LogLevel.debug, '[AUTH-TRACE] Navigating to AdminShellScreen');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            AdminShellScreen(initialNavItemId: initialAdminNavItemId),
      ),
    );
  }

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
        email: _emailController.text.trim(),
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
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Yönetici / Personel Girişi'),
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
                SegmentedButton<_SignInMethod>(
                  segments: const [
                    ButtonSegment(
                      value: _SignInMethod.email,
                      label: Text('E-posta'),
                      icon: Icon(Icons.mail_outline_rounded),
                    ),
                    ButtonSegment(
                      value: _SignInMethod.phone,
                      label: Text('Telefon'),
                      icon: Icon(Icons.phone_outlined),
                    ),
                  ],
                  selected: {_method},
                  onSelectionChanged: _busy
                      ? null
                      : (selection) => setState(() {
                            _method = selection.first;
                            _error = null;
                          }),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_method == _SignInMethod.email) ...[
                  TextFormField(
                    controller: _emailController,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'E-posta',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Lütfen e-posta adresinizi girin'
                            : null,
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
                  ),
                ] else ...[
                  if (_phoneVerificationId == null)
                    TextFormField(
                      controller: _phoneController,
                      enabled: !_busy,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Telefon Numarası',
                        prefixIcon: Icon(Icons.phone_outlined),
                        prefixText: '+90 ',
                      ),
                    )
                  else ...[
                    Text(
                      '+90 ${_phoneController.text} numarasına gönderilen '
                      'kodu girin.',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _smsCodeController,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Doğrulama Kodu',
                        prefixIcon: Icon(Icons.sms_outlined),
                      ),
                    ),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_error!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error)),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (_method == _SignInMethod.email) ...[
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
                  if (_devAdminShortcutAvailable) ...[
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _signInAsDevAdmin,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: const BorderSide(color: AppColors.warning),
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      ),
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text(
                          'Dev Admin ile Gir (Yalnızca Development)'),
                    ),
                  ],
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
                      'yukarıdaki e-posta/şifre ile yeni bir yönetici hesabı '
                      'oluşturulur.',
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
                ] else ...[
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : (_phoneVerificationId == null
                            ? _sendPhoneCode
                            : _verifyPhoneCode),
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
                        : Text(_phoneVerificationId == null
                            ? 'Kod Gönder'
                            : 'Doğrula ve Giriş Yap'),
                  ),
                  if (_phoneVerificationId != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _phoneVerificationId = null;
                                _error = null;
                              }),
                      child: const Text('Numarayı Değiştir'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
