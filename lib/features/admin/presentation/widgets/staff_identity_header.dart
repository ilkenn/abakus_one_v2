import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../pos/domain/authorization/actor_session.dart';
import '../../../pos/domain/authorization/staff_role.dart';
import '../../../pos/presentation/providers/actor_session_provider.dart';
import '../../data/own_staff_name_repository.dart';
import '../providers/admin_dependencies_provider.dart';
import '../../../../bootstrap/firebase_ready_provider.dart';
import 'staff_account_forms.dart';

final ownStaffNameRepositoryProvider = Provider<OwnStaffNameRepository>((ref) {
  if (ref.watch(firebaseReadyProvider)) {
    return const FirebaseOwnStaffNameRepository();
  }
  return const UnavailableOwnStaffNameRepository();
});

/// The signed-in person's own name, for the panel header (ADR-085 stage 3).
final ownStaffNameProvider = FutureProvider.autoDispose<String?>((ref) async {
  final session = ref.watch(actorSessionProvider);
  if (session == null) return null;
  return ref.watch(ownStaffNameRepositoryProvider).ownName(
        organizationId: ref.watch(currentOrganizationIdProvider),
        uid: session.actorId,
      );
});

/// The roles an admin/owner can preview, in the order the menu offers them.
const staffRolePreviewOptions = <StaffRole, String>{
  StaffRole.manager: 'Müdür',
  StaffRole.cashier: 'Kasiyer',
  StaffRole.courier: 'Kurye',
  StaffRole.packingLead: 'Paketleme',
};

/// The highest role a person holds — the one the header names.
StaffRole headlineRole(Set<StaffRole> roles) {
  const order = [
    StaffRole.tenantOwner,
    StaffRole.admin,
    StaffRole.manager,
    StaffRole.cashier,
    StaffRole.packingLead,
    StaffRole.staff,
    StaffRole.courier,
  ];
  return order.firstWhere(roles.contains, orElse: () => StaffRole.staff);
}

/// Top of the panel's sidebar/drawer: name, surname and role, and for an
/// admin/owner the "Rol Değiştir" preview menu. The preview only narrows
/// what the panel shows; the server still decides every action with the
/// real account.
class StaffIdentityHeader extends ConsumerWidget {
  const StaffIdentityHeader({super.key, required this.session});

  /// The real session — never the preview.
  final ActorSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(ownStaffNameProvider).valueOrNull;
    final preview = ref.watch(staffRolePreviewProvider);
    final roleLabel = staffRoleLabel(headlineRole(session.roles));
    return Padding(
      key: const Key('staffIdentityHeader'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary,
            child: Icon(Icons.person_outline, color: AppColors.surface),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? roleLabel,
                  key: const Key('staffIdentityName'),
                  style: AppTypography.titleMedium
                      .copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  preview == null
                      ? roleLabel
                      : '$roleLabel · Önizleme: ${staffRolePreviewOptions[preview]}',
                  key: const Key('staffIdentityRole'),
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (canPreviewRoles(session))
            PopupMenuButton<StaffRole>(
              key: const Key('staffRolePreviewMenu'),
              tooltip: 'Rol Değiştir',
              icon: const Icon(Icons.swap_horiz_rounded),
              onSelected: (role) =>
                  ref.read(staffRolePreviewProvider.notifier).state = role,
              itemBuilder: (_) => [
                for (final entry in staffRolePreviewOptions.entries)
                  PopupMenuItem(
                    key: Key('staffRolePreview-${entry.key.name}'),
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// While a preview is on, a strip above the panel names the previewed role
/// and returns to the real one in one tap — also above the courier screen,
/// which has no sidebar.
class StaffRolePreviewBanner extends ConsumerWidget {
  const StaffRolePreviewBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(staffRolePreviewProvider);
    if (preview == null) return child;
    return Column(
      children: [
        Material(
          color: AppColors.warning,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined,
                      color: AppColors.surface, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Rol önizlemesi: ${staffRolePreviewOptions[preview]}',
                      key: const Key('staffRolePreviewLabel'),
                      style: AppTypography.labelLarge
                          .copyWith(color: AppColors.surface),
                    ),
                  ),
                  TextButton(
                    key: const Key('staffRolePreviewExit'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.surface),
                    onPressed: () => ref
                        .read(staffRolePreviewProvider.notifier)
                        .state = null,
                    child: const Text('Kendi Rolüme Dön'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
