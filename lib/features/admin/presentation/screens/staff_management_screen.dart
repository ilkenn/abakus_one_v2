import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../navigation/presentation/providers/current_branch_provider.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/staff_role.dart';
import '../../../pos/presentation/providers/actor_session_provider.dart';
import '../../data/staff_account_gateway.dart';
import '../../domain/staff/staff_member.dart';
import '../../domain/staff/staff_member_status.dart';
import '../providers/admin_dependencies_provider.dart';
import '../widgets/staff_account_forms.dart';
import 'staff_detail_screen.dart';

/// Staff roster — Phase 6C (ADR-023), reworked for ADR-085 (revision,
/// 2026-11-13): "Personel Ekle" creates an active account in one step
/// (name, phone, password, roles, branch), and each row offers "Şifre
/// Değiştir", "Rolleri Değiştir" and "Pasife Al" / "Aktifleştir". Who may
/// manage whom is decided by the server (`functions/src/staffAccounts.ts`);
/// a refused action shows its Turkish reason here. A tap still opens
/// [StaffDetailScreen].
class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({
    super.key,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<StaffManagementScreen> createState() =>
      _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen> {
  List<StaffMember>? _members;
  bool _loadFailed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final members = await ref.read(staffMemberRepositoryProvider).findAll();
      if (!mounted) return;
      setState(() => _members = members);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  List<StaffRole> get _assignableRoles => assignableStaffRoles(
        ref.read(actorSessionProvider)?.roles ?? const {},
      );

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.error : null,
    ));
  }

  /// ADR-085 stage 1 — only an admin/owner changes whether staff are active.
  bool get _canChangeActive {
    final roles = ref.read(actorSessionProvider)?.roles ?? const {};
    return effectiveVisibilityRoles(roles).contains(StaffRole.admin);
  }

  /// Runs one staff-account command with a busy state, then reloads.
  /// [action] returns the success message to show.
  Future<void> _run(
    Future<String> Function(StaffAccountGateway gateway, String organizationId)
        action,
  ) async {
    setState(() => _busy = true);
    try {
      final success = await action(
        ref.read(staffAccountGatewayProvider),
        ref.read(currentOrganizationIdProvider),
      );
      if (!mounted) return;
      _showMessage(success);
      await _load();
    } on StaffAccountException catch (error) {
      if (!mounted) return;
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addStaff() async {
    final session = ref.read(actorSessionProvider);
    final currentBranch = ref.read(currentBranchIdProvider);
    final branchIds = {...?session?.branchAccess, currentBranch}.toList()
      ..sort();
    final input = await StaffAccountCreateSheet.show(
      context,
      assignableRoles: _assignableRoles,
      branchIds: branchIds,
      initialBranchId: currentBranch,
    );
    if (input == null || !mounted) return;
    await _run((gateway, organizationId) async {
      final pending = await gateway.createStaffAccount(
        organizationId: organizationId,
        firstName: input.firstName,
        lastName: input.lastName,
        phoneNumber: input.phoneNumber,
        password: input.password,
        roles: input.roles,
        branchAccess: {input.branchId},
      );
      final name = '${input.firstName} ${input.lastName}';
      return pending
          ? '$name eklendi. Yönetici onayından sonra aktif olacak.'
          : '$name eklendi.';
    });
  }

  Future<void> _changePassword(StaffMember member) async {
    final password =
        await showStaffPasswordDialog(context, memberName: member.displayName);
    if (password == null || !mounted) return;
    await _run((gateway, organizationId) async {
      await gateway.setStaffPassword(
        organizationId: organizationId,
        targetUid: member.authUid ?? member.id,
        password: password,
      );
      return 'Şifre değiştirildi.';
    });
  }

  Future<void> _changeRoles(StaffMember member) async {
    final roles = await showStaffRolesDialog(
      context,
      memberName: member.displayName,
      current: member.roles,
      assignableRoles: _assignableRoles,
    );
    if (roles == null || !mounted) return;
    await _run((gateway, organizationId) async {
      await gateway.updateStaffMember(
        organizationId: organizationId,
        targetUid: member.authUid ?? member.id,
        roles: roles,
      );
      return 'Roller güncellendi.';
    });
  }

  Future<void> _toggleActive(StaffMember member) async {
    final activate = !member.isActive;
    await _run((gateway, organizationId) async {
      await gateway.updateStaffMember(
        organizationId: organizationId,
        targetUid: member.authUid ?? member.id,
        active: activate,
      );
      return activate
          ? '${member.displayName} aktifleştirildi.'
          : '${member.displayName} pasife alındı.';
    });
  }

  String _subtitle(StaffMember member) {
    final roles = member.roles.isEmpty
        ? 'Rol atanmadı'
        : member.roles.map(staffRoleLabel).join(', ');
    final status = switch (member.status) {
      StaffMemberStatus.active => 'Aktif',
      StaffMemberStatus.pendingApproval => 'Yönetici Onayı Bekliyor',
      StaffMemberStatus.suspended || StaffMemberStatus.archived => 'Pasif',
    };
    final phone = member.phoneNumber;
    return [if (phone != null) phone, roles, status].join(' · ');
  }

  Widget _body() {
    final members = _members;
    if (_loadFailed) {
      return ErrorView(
        message: 'Personel listesi yüklenemedi.',
        retryLabel: 'Tekrar Dene',
        onRetry: _load,
      );
    }
    if (members == null) {
      return const LoadingView(message: 'Personel listesi yükleniyor...');
    }
    if (members.isEmpty) {
      return EmptyView(
        icon: Icons.badge_outlined,
        message: 'Henüz personel yok.',
        actionLabel: 'Personel Ekle',
        onAction: _busy ? null : _addStaff,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        for (final member in members)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(
                  Icons.badge_outlined,
                  color: member.isActive
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                title: Text(member.displayName, style: AppTypography.bodyLarge),
                subtitle: Text(
                  _subtitle(member),
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
                trailing: PopupMenuButton<String>(
                  key: Key('staffActions-${member.id}'),
                  enabled: !_busy,
                  tooltip: 'İşlemler',
                  onSelected: (action) {
                    switch (action) {
                      case 'password':
                        _changePassword(member);
                      case 'roles':
                        _changeRoles(member);
                      case 'status':
                        _toggleActive(member);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'password',
                      child: Text('Şifre Değiştir'),
                    ),
                    const PopupMenuItem(
                      value: 'roles',
                      child: Text('Rolleri Değiştir'),
                    ),
                    if (_canChangeActive)
                      PopupMenuItem(
                        value: 'status',
                        child:
                            Text(member.isActive ? 'Pasife Al' : 'Aktifleştir'),
                      ),
                  ],
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StaffDetailScreen(
                        staffMemberId: member.id,
                        authorizationPolicy: widget.authorizationPolicy,
                        performedByStaffId: widget.performedByStaffId,
                      ),
                    ),
                  );
                  await _load();
                },
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Personel Yönetimi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: _busy ? null : _addStaff,
            tooltip: 'Personel Ekle',
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }
}
