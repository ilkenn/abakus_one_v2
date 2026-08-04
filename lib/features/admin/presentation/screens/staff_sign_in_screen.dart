import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/bootstrap_first_admin_account.dart';
import 'admin_shell_screen.dart';
import '../../domain/staff/staff_member.dart';
import '../../domain/staff/staff_member_status.dart';
import '../providers/admin_dependencies_provider.dart';
import '../providers/staff_session_controller.dart';

/// The first, and only, place `actorSessionProvider` is ever populated
/// from real (if development-only) user interaction in this app — Phase
/// 6B (`docs/decisions.md` ADR-023). Prior to this screen, no code path
/// anywhere in shipped `lib/` ever constructed a real `ActorSession`.
///
/// **Deliberately not a password/PIN prompt** — "do not create an
/// insecure local password system." Lists already-registered, active
/// `StaffMember`s and signs in by selection only
/// (`DevelopmentStaffAuthRepository`, debug/profile builds only). In
/// release builds `staffAuthRepositoryProvider` resolves to
/// `ProductionUnavailableStaffAuthRepository`, which always fails —
/// "do not claim production backend validation if none exists."
class StaffSignInScreen extends ConsumerStatefulWidget {
  const StaffSignInScreen({super.key});

  @override
  ConsumerState<StaffSignInScreen> createState() => _StaffSignInScreenState();
}

class _StaffSignInScreenState extends ConsumerState<StaffSignInScreen> {
  List<StaffMember>? _members;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final members = await ref.read(staffMemberRepositoryProvider).findAll();
    if (!mounted) return;
    setState(() => _members = members);
  }

  Future<void> _signIn(StaffMember member) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final success =
        await ref.read(staffSessionControllerProvider).signIn(member.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!success) {
      setState(() => _error = 'Oturum açılamadı. Hesap aktif değil olabilir.');
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdminShellScreen()),
    );
  }

  Future<void> _bootstrapFirstAdmin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BootstrapFirstAdminAccount(
        idGenerator: ref.read(staffMemberIdGeneratorProvider),
        repository: ref.read(staffMemberRepositoryProvider),
        auditRepository: ref.read(adminAuditEntryRepositoryProvider),
      )(
        displayName: 'İlk Yönetici',
        organizationId: 'org-1',
        createdAt: DateTime.now(),
      );
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
        title: const Text('Yönetici / Personel Girişi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: members == null
            ? const LoadingView(message: 'Personel listesi yükleniyor...')
            : _buildBody(members),
      ),
    );
  }

  Widget _buildBody(List<StaffMember> members) {
    if (members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EmptyView(
              icon: Icons.admin_panel_settings_outlined,
              message: 'Henüz kayıtlı bir personel hesabı yok.',
              actionLabel: 'İlk Yönetici Hesabını Oluştur',
              onAction: _busy ? null : _bootstrapFirstAdmin,
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
                enabled: member.status == StaffMemberStatus.active && !_busy,
                leading:
                    const Icon(Icons.badge_outlined, color: AppColors.primary),
                title: Text(member.displayName, style: AppTypography.bodyLarge),
                subtitle: Text(
                  member.status == StaffMemberStatus.active
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
