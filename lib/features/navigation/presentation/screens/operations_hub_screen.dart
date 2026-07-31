import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../courier/presentation/screens/courier_dispatch_dashboard_screen.dart';
import '../../../courier/presentation/screens/courier_home_screen.dart';
import '../../../crm/presentation/screens/customer_notification_campaigns_admin_screen.dart';
import '../../../crm/presentation/screens/customer_segmentation_admin_screen.dart';
import '../../../crm/presentation/screens/survey_admin_screen.dart';
import '../../../crm/presentation/screens/visit_reward_rules_admin_screen.dart';
import '../../../feedback/presentation/screens/feedback_admin_screen.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/staff_role.dart';
import '../../../pos/presentation/providers/actor_session_provider.dart';
import '../../../pos/presentation/widgets/role_gate.dart';
import '../providers/current_branch_provider.dart';

/// The single role-based entry point into every Phase 5 manager/courier/
/// admin screen — Sprint 5E Part 2, resolving the "zero Phase 5 screens
/// are reachable from app navigation" phase-gate blocker
/// (`docs/decisions.md` ADR-022). Deliberately **not** a bottom-nav tab
/// ("do not place every screen directly in the primary bottom
/// navigation... use logical role-based hubs") — reached from
/// `ProfileScreen`, itself only shown there when the current actor holds
/// any staff-tier role.
///
/// Every individual destination is wrapped in its own [RoleGate] — this
/// hub only *lists* sections a role-appropriate actor can see; it is not
/// itself the security boundary (`CLAUDE.md`'s "never authorize based
/// only on the screen being visible").
class OperationsHubScreen extends ConsumerWidget {
  const OperationsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(actorSessionProvider);
    final branchId = ref.watch(currentBranchIdProvider);

    return RoleGate.forRoles(
      const {
        StaffRole.courier,
        StaffRole.staff,
        StaffRole.manager,
        StaffRole.admin,
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('İşlem Merkezi'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _Section(
                title: 'Kurye Operasyonları',
                children: [
                  _HubEntry(
                    icon: Icons.dashboard_outlined,
                    label: 'Sevkiyat Kontrol Merkezi',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RoleGate.forRoles(
                        const {StaffRole.manager, StaffRole.admin},
                        child: CourierDispatchDashboardScreen(
                          branchId: branchId,
                          authorizationPolicy:
                              ref.read(posAuthorizationPolicyProvider),
                          performedByStaffId: session?.actorId ?? '',
                        ),
                      ),
                    )),
                  ),
                  _HubEntry(
                    icon: Icons.delivery_dining_outlined,
                    label: 'Kurye Vardiya ve Teslimatlarım',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RoleGate.forRoles(
                        const {StaffRole.courier},
                        child: CourierHomeScreen(
                          courierId: session?.actorId ?? '',
                          branchId: branchId,
                        ),
                      ),
                    )),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _Section(
                title: 'CRM / Sadakat',
                children: [
                  _HubEntry(
                    icon: Icons.people_outline,
                    label: 'Müşteri Segmentasyonu',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RoleGate.forRoles(
                        const {StaffRole.manager, StaffRole.admin},
                        child: const CustomerSegmentationAdminScreen(),
                      ),
                    )),
                  ),
                  _HubEntry(
                    icon: Icons.card_giftcard_outlined,
                    label: 'Ziyaret Ödül Kuralları',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RoleGate.forAction(
                        PosAuthorizedAction.manageVisitRewardRules,
                        child: VisitRewardRulesAdminScreen(
                          authorizationPolicy:
                              ref.read(posAuthorizationPolicyProvider),
                          performedByStaffId: session?.actorId ?? '',
                        ),
                      ),
                    )),
                  ),
                  _HubEntry(
                    icon: Icons.poll_outlined,
                    label: 'Anketler',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RoleGate.forAction(
                        PosAuthorizedAction.manageSurveys,
                        child: SurveyAdminScreen(
                          authorizationPolicy:
                              ref.read(posAuthorizationPolicyProvider),
                          performedByStaffId: session?.actorId ?? '',
                        ),
                      ),
                    )),
                  ),
                  _HubEntry(
                    icon: Icons.campaign_outlined,
                    label: 'Bildirim Kampanyaları',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RoleGate.forAction(
                        PosAuthorizedAction.manageCustomerNotificationCampaigns,
                        child: CustomerNotificationCampaignsAdminScreen(
                          authorizationPolicy:
                              ref.read(posAuthorizationPolicyProvider),
                          performedByStaffId: session?.actorId ?? '',
                        ),
                      ),
                    )),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _Section(
                title: 'Geri Bildirim',
                children: [
                  _HubEntry(
                    icon: Icons.feedback_outlined,
                    label: 'Geri Bildirim Yönetimi',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RoleGate.forAction(
                        PosAuthorizedAction.manageCustomerFeedback,
                        child: FeedbackAdminScreen(
                          branchId: branchId,
                          authorizationPolicy:
                              ref.read(posAuthorizationPolicyProvider),
                          performedByStaffId: session?.actorId ?? '',
                        ),
                      ),
                    )),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _HubEntry extends StatelessWidget {
  const _HubEntry({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label, style: AppTypography.bodyMedium),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}
