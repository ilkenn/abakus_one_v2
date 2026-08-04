import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/bootstrap_first_platform_owner_account.dart';
import '../../domain/member/platform_member.dart';
import '../../domain/member/platform_member_status.dart';
import '../providers/platform_dependencies_provider.dart';
import '../providers/platform_session_controller.dart';
import 'platform_shell_screen.dart';

/// Development Login for the platform-owner hierarchy — Phase 8
/// (`docs/decisions.md` ADR-025). Mirrors `StaffSignInScreen`'s exact
/// shape and reasoning one tier up: **deliberately not a password/PIN
/// prompt** ("do not create an insecure local password system"). Lists
/// already-registered, active [PlatformMember]s and signs in by
/// selection only (`DevelopmentPlatformAuthRepository`, debug/profile
/// builds only). In release builds `platformAuthRepositoryProvider`
/// resolves to `ProductionUnavailablePlatformAuthRepository`, which
/// always fails — "release builds must never expose this path."
///
/// "Development login exists solely until real OTP authentication
/// becomes available" — this screen is the one, explicit, temporary
/// substitute for that, not a permanent platform-owner login mechanism.
///
/// A successful sign-in pushes [PlatformShellScreen] (Phase 8R) — this
/// screen has no `go_router` route of its own (still a raw
/// `Navigator.push` entry point, matching every other in-app screen
/// transition per `CLAUDE.md` §3); reaching this screen at all still
/// requires a direct `Navigator.push` from calling code (e.g. a test,
/// or a future hidden platform-owner entry point) since it is
/// intentionally not linked from the tenant-side `AdminShellScreen`.
class PlatformSignInScreen extends ConsumerStatefulWidget {
  const PlatformSignInScreen({super.key});

  @override
  ConsumerState<PlatformSignInScreen> createState() =>
      _PlatformSignInScreenState();
}

class _PlatformSignInScreenState extends ConsumerState<PlatformSignInScreen> {
  List<PlatformMember>? _members;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final members = await ref.read(platformMemberRepositoryProvider).findAll();
    if (!mounted) return;
    setState(() => _members = members);
  }

  Future<void> _signIn(PlatformMember member) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final success =
        await ref.read(platformSessionControllerProvider).signIn(member.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!success) {
      setState(() => _error = 'Oturum açılamadı. Hesap aktif değil olabilir.');
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PlatformShellScreen()),
    );
  }

  Future<void> _bootstrapFirstOwner() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BootstrapFirstPlatformOwnerAccount(
        idGenerator: ref.read(platformMemberIdGeneratorProvider),
        repository: ref.read(platformMemberRepositoryProvider),
        auditRepository: ref.read(platformAuditEntryRepositoryProvider),
      )(displayName: 'İlk Platform Sahibi', createdAt: DateTime.now());
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Platform Girişi (Geliştirme)'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: members == null
            ? const LoadingView(message: 'Platform hesapları yükleniyor...')
            : _buildBody(members),
      ),
    );
  }

  Widget _buildBody(List<PlatformMember> members) {
    if (members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EmptyView(
              icon: Icons.public_outlined,
              message: 'Henüz kayıtlı bir platform hesabı yok.',
              actionLabel: 'İlk Platform Sahibi Hesabını Oluştur',
              onAction: _busy ? null : _bootstrapFirstOwner,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!,
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error)),
            ],
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (_error != null) ...[
          Text(_error!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
          const SizedBox(height: AppSpacing.sm),
        ],
        for (final member in members)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                enabled: member.status == PlatformMemberStatus.active && !_busy,
                leading: const Icon(Icons.public, color: AppColors.primary),
                title: Text(member.displayName, style: AppTypography.bodyLarge),
                subtitle: Text(
                  member.status == PlatformMemberStatus.active
                      ? member.roles.map((r) => r.name).join(', ')
                      : '${member.status.name} — giriş yapılamaz',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _signIn(member),
              ),
            ),
          ),
      ],
    );
  }
}
