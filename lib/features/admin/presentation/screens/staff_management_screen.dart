import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/register_staff_member.dart';
import '../../domain/staff/staff_member.dart';
import '../../domain/staff/staff_member_status.dart';
import '../providers/admin_dependencies_provider.dart';
import 'staff_detail_screen.dart';

/// Staff roster — Phase 6C (`docs/decisions.md` ADR-023). Lists every
/// `StaffMember`; a tap opens `StaffDetailScreen` for roles/branch
/// access/status/session management. New members register with **no
/// roles at all** (`RegisterStaffMember`'s own documented rule) — a role
/// must be granted separately, from the detail screen.
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
  String? _error;

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

  Future<void> _register() async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Personel'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Ad Soyad'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      await RegisterStaffMember(
        authorizationPolicy: policy,
        idGenerator: ref.read(staffMemberIdGeneratorProvider),
        repository: ref.read(staffMemberRepositoryProvider),
        auditRepository: ref.read(adminAuditEntryRepositoryProvider),
      )(
        displayName: name.trim(),
        performedByStaffId: widget.performedByStaffId,
        createdAt: DateTime.now(),
      );
      setState(() => _error = null);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
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
            onPressed: _register,
            tooltip: 'Yeni Personel',
          ),
        ],
      ),
      body: SafeArea(
        child: members == null
            ? const LoadingView(message: 'Personel listesi yükleniyor...')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_error != null) ...[
                    Text(_error!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  for (final member in members)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          leading: Icon(
                            Icons.badge_outlined,
                            color: member.status == StaffMemberStatus.active
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          title: Text(member.displayName,
                              style: AppTypography.bodyLarge),
                          subtitle: Text(
                            member.roles.isEmpty
                                ? 'Rol atanmadı · ${member.status.name}'
                                : '${member.roles.map((r) => r.name).join(', ')} '
                                    '· ${member.status.name}',
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => StaffDetailScreen(
                                  staffMemberId: member.id,
                                  authorizationPolicy:
                                      widget.authorizationPolicy,
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
              ),
      ),
    );
  }
}
