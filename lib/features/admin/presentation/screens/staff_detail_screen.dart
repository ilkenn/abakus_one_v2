import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/staff_role.dart';
import '../../application/use_cases/assign_staff_role.dart';
import '../../application/use_cases/revoke_staff_role.dart';
import '../../application/use_cases/revoke_staff_session.dart';
import '../../application/use_cases/set_staff_member_status.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/staff/staff_member.dart';
import '../../domain/staff/staff_member_status.dart';
import '../../domain/staff/staff_role_change_event.dart';
import '../providers/admin_dependencies_provider.dart';

/// One `StaffMember`'s management surface — Phase 6C
/// (`docs/decisions.md` ADR-023). Manager/Admin can inspect held roles,
/// active role's implicit grant, allowed branches, status, and audit
/// history (role-change events + admin audit entries), and act:
/// grant/revoke a role, change status, revoke sessions. "No self-
/// promotion" is enforced by the underlying use cases, not just hidden
/// here — even if a role-grant button were somehow tapped for one's own
/// account, `AssignStaffRole`/`RevokeStaffRole` still reject it.
class StaffDetailScreen extends ConsumerStatefulWidget {
  const StaffDetailScreen({
    super.key,
    required this.staffMemberId,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final String staffMemberId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends ConsumerState<StaffDetailScreen> {
  StaffMember? _member;
  List<StaffRoleChangeEvent> _roleHistory = [];
  List<AdminAuditEntry> _auditHistory = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final member = await ref.read(staffMemberRepositoryProvider).findById(
          widget.staffMemberId,
        );
    final roleHistory = await ref
        .read(staffRoleChangeEventRepositoryProvider)
        .findByStaffMemberId(widget.staffMemberId);
    final auditHistory = await ref
        .read(adminAuditEntryRepositoryProvider)
        .findByTargetEntityId(widget.staffMemberId);
    if (!mounted) return;
    setState(() {
      _member = member;
      _roleHistory = roleHistory;
      _auditHistory = auditHistory;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await action();
      setState(() => _error = null);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _toggleRole(StaffRole role, bool hold) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) return;
    await _run(() async {
      if (hold) {
        await RevokeStaffRole(
          authorizationPolicy: policy,
          repository: ref.read(staffMemberRepositoryProvider),
          roleChangeEventRepository:
              ref.read(staffRoleChangeEventRepositoryProvider),
          idGenerator: ref.read(staffRoleChangeEventIdGeneratorProvider),
          auditRepository: ref.read(adminAuditEntryRepositoryProvider),
        )(
          staffMemberId: widget.staffMemberId,
          role: role,
          performedByStaffId: widget.performedByStaffId,
          performedAt: DateTime.now(),
        );
      } else {
        await AssignStaffRole(
          authorizationPolicy: policy,
          repository: ref.read(staffMemberRepositoryProvider),
          roleChangeEventRepository:
              ref.read(staffRoleChangeEventRepositoryProvider),
          idGenerator: ref.read(staffRoleChangeEventIdGeneratorProvider),
          auditRepository: ref.read(adminAuditEntryRepositoryProvider),
        )(
          staffMemberId: widget.staffMemberId,
          role: role,
          performedByStaffId: widget.performedByStaffId,
          performedAt: DateTime.now(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final member = _member;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(member?.displayName ?? 'Personel'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: member == null
            ? const LoadingView(message: 'Personel bilgisi yükleniyor...')
            : _buildBody(member),
      ),
    );
  }

  Widget _buildBody(StaffMember member) {
    final isSelf = member.id == widget.performedByStaffId;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (_error != null) ...[
          Text(_error!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
          const SizedBox(height: AppSpacing.sm),
        ],
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Durum: ${member.status.name}',
                  style: AppTypography.bodyMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'İzin verilen şubeler: '
                '${member.branchAccess.isEmpty ? 'yok' : member.branchAccess.join(', ')}',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              if (member.sessionsRevokedAt != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Oturumlar iptal edildi: ${member.sessionsRevokedAt}',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Roller', style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        if (isSelf)
          Text(
            'Kendi rollerinizi değiştiremezsiniz (self-promotion engeli).',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final role in StaffRole.values)
                FilterChip(
                  label: Text(role.name),
                  selected: member.roles.contains(role),
                  onSelected: (_) =>
                      _toggleRole(role, member.roles.contains(role)),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            if (member.status != StaffMemberStatus.archived) ...[
              if (member.status == StaffMemberStatus.active)
                OutlinedButton(
                  onPressed: () => _run(() => SetStaffMemberStatus(
                        authorizationPolicy: widget.authorizationPolicy!,
                        repository: ref.read(staffMemberRepositoryProvider),
                        auditRepository:
                            ref.read(adminAuditEntryRepositoryProvider),
                      )(
                        staffMemberId: widget.staffMemberId,
                        newStatus: StaffMemberStatus.suspended,
                        performedByStaffId: widget.performedByStaffId,
                        performedAt: DateTime.now(),
                      )),
                  child: const Text('Askıya Al'),
                ),
              if (member.status == StaffMemberStatus.suspended)
                OutlinedButton(
                  onPressed: () => _run(() => SetStaffMemberStatus(
                        authorizationPolicy: widget.authorizationPolicy!,
                        repository: ref.read(staffMemberRepositoryProvider),
                        auditRepository:
                            ref.read(adminAuditEntryRepositoryProvider),
                      )(
                        staffMemberId: widget.staffMemberId,
                        newStatus: StaffMemberStatus.active,
                        performedByStaffId: widget.performedByStaffId,
                        performedAt: DateTime.now(),
                      )),
                  child: const Text('Aktifleştir'),
                ),
              OutlinedButton(
                onPressed: () => _run(() => SetStaffMemberStatus(
                      authorizationPolicy: widget.authorizationPolicy!,
                      repository: ref.read(staffMemberRepositoryProvider),
                      auditRepository:
                          ref.read(adminAuditEntryRepositoryProvider),
                    )(
                      staffMemberId: widget.staffMemberId,
                      newStatus: StaffMemberStatus.archived,
                      performedByStaffId: widget.performedByStaffId,
                      performedAt: DateTime.now(),
                    )),
                child: const Text('Arşivle'),
              ),
            ],
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => _run(() => RevokeStaffSession(
                    authorizationPolicy: widget.authorizationPolicy!,
                    repository: ref.read(staffMemberRepositoryProvider),
                    auditRepository:
                        ref.read(adminAuditEntryRepositoryProvider),
                  )(
                    staffMemberId: widget.staffMemberId,
                    performedByStaffId: widget.performedByStaffId,
                    performedAt: DateTime.now(),
                  )),
              child: const Text('Oturumları İptal Et'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Denetim Geçmişi', style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        if (_roleHistory.isEmpty && _auditHistory.isEmpty)
          Text('Henüz kayıt yok.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary))
        else ...[
          for (final event in _roleHistory)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${event.changeType.name} — ${event.role.name} '
                '(${event.performedByStaffId}, ${event.occurredAt})',
                style: AppTypography.bodySmall,
              ),
            ),
          for (final entry in _auditHistory)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${entry.type.name} — ${entry.description}',
                style: AppTypography.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}
