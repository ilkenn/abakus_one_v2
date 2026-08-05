import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/auth/email_password_auth_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../application/use_cases/bootstrap_first_platform_owner_account.dart';
import '../providers/platform_dependencies_provider.dart';
import '../providers/platform_session_controller.dart';
import 'platform_shell_screen.dart';

/// Platform-owner sign-in — Phase 8 (`docs/decisions.md` ADR-025), mirrors
/// `StaffSignInScreen`'s exact shape one tier up.
///
/// **Sprint 9C** (`docs/decisions.md` ADR-026): a real email/password
/// credential form, not a picker over the platform-member roster — closes
/// the "no-credential member picker" gap structurally: this screen never
/// queries `PlatformMemberRepository.findAll()`, so there is no roster to
/// enumerate regardless of build mode. `platformAuthRepositoryProvider`
/// resolves to `FirebasePlatformAuthRepository` once Firebase is ready, or
/// `ProductionUnavailablePlatformAuthRepository` (always fails)
/// otherwise.
///
/// A successful sign-in pushes [PlatformShellScreen] (Phase 8R) — this
/// screen has no `go_router` route of its own (still a raw
/// `Navigator.push` entry point, matching every other in-app screen
/// transition per `CLAUDE.md` §3); reaching this screen at all still
/// requires a direct `Navigator.push` from calling code since it is
/// intentionally not linked from the tenant-side `AdminShellScreen`.
class PlatformSignInScreen extends ConsumerStatefulWidget {
  const PlatformSignInScreen({super.key});

  @override
  ConsumerState<PlatformSignInScreen> createState() =>
      _PlatformSignInScreenState();
}

class _PlatformSignInScreenState extends ConsumerState<PlatformSignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _showBootstrap = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final success = await ref.read(platformSessionControllerProvider).signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!success) {
      setState(() => _error = 'Giriş başarısız. Bilgilerinizi kontrol edin.');
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PlatformShellScreen()),
    );
  }

  Future<void> _bootstrapFirstOwner() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BootstrapFirstPlatformOwnerAccount(
        idGenerator: ref.read(platformMemberIdGeneratorProvider),
        repository: ref.read(platformMemberRepositoryProvider),
        auditRepository: ref.read(platformAuditEntryRepositoryProvider),
        authClient: DefaultEmailPasswordAuthClient(),
      )(
        displayName: 'İlk Platform Sahibi',
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
        title: const Text('Platform Girişi'),
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
                const SizedBox(height: AppSpacing.xl),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _showBootstrap = true),
                  child: const Text('İlk platform sahibi hesabını oluştur'),
                ),
                if (_showBootstrap) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Yalnızca hiç platform hesabı kayıtlı değilse çalışır — '
                    'yukarıdaki e-posta/şifre ile yeni bir platform sahibi '
                    'hesabı oluşturulur.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: _busy ? null : _bootstrapFirstOwner,
                    style: OutlinedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                    child: const Text('İlk Platform Sahibi Hesabını Oluştur'),
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
