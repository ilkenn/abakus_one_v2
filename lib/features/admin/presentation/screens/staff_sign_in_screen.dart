import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_environment_config.dart';
import '../../../../core/services/auth/email_password_auth_client.dart';
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

class _StaffSignInScreenState extends ConsumerState<StaffSignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _showBootstrap = false;

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
    super.dispose();
  }

  Future<void> _signIn({String? initialAdminNavItemId}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
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
      try {
        await ref.read(staffSessionControllerProvider).signOut();
      } catch (_) {
        // Swallowed deliberately — see comment above.
      }

      success = await ref.read(staffSessionControllerProvider).signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } on StaffAuthUnavailableException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Beklenmeyen bir sorun oluştu — tekrar deneyin.');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!success) {
      setState(() => _error = 'Giriş başarısız. Bilgilerinizi kontrol edin.');
      return;
    }
    if (!mounted) return;
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
                TextFormField(
                  controller: _emailController,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
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
                    label: const Text('Dev Admin ile Gir (Yalnızca Development)'),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
