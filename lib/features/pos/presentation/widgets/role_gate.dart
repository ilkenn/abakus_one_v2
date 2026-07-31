import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/authorization/actor_session.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/authorization/role_permission_map.dart';
import '../../domain/authorization/staff_role.dart';
import '../providers/actor_session_provider.dart';

/// Screen-level authorization gate — Sprint 5E Part 2. Wraps a screen so
/// **the screen itself** denies an unauthorized actor, not just the
/// navigation entry point that led to it — "unauthorized deep links must
/// fail safely" and "never authorize based only on the screen being
/// visible" (`docs/decisions.md` ADR-022).
///
/// Lives in `features/pos` (not `shared/`) because it depends on
/// `PosAuthorizedAction`/`RolePermissionMap`, and `shared -> feature` is a
/// forbidden dependency direction (`CLAUDE.md` §3) — courier/crm/feedback
/// screens importing this from `features/pos` instead is consistent with
/// the same precedent those features already follow for
/// `PosAuthorizedAction`/`PosAuthorizationPolicy` themselves (ADR-013
/// onward: a deliberately reusable, generic, non-payment-specific
/// contract).
///
/// Reads [actorSessionProvider] directly (not a constructor parameter) —
/// every gated screen re-checks on every rebuild, so a sign-out or role
/// switch mid-session takes effect immediately, not just on next
/// navigation.
class RoleGate extends ConsumerWidget {
  const RoleGate({super.key, required this.isAllowed, required this.child});

  /// Convenience: gate on whether any of the actor's roles permit
  /// [action] per [RolePermissionMap] — the single source of truth for
  /// "who can do this," reused rather than re-specified.
  factory RoleGate.forAction(
    PosAuthorizedAction action, {
    Key? key,
    required Widget child,
  }) {
    return RoleGate(
      key: key,
      isAllowed: (session) => RolePermissionMap.allows(session.roles, action),
      child: child,
    );
  }

  /// Convenience: gate on holding any of [roles] at all, regardless of
  /// fine-grained action permissions — for screens that are role-scoped
  /// rather than single-action-scoped (e.g. "any courier/manager/admin
  /// may view courier operations").
  factory RoleGate.forRoles(
    Set<StaffRole> roles, {
    Key? key,
    required Widget child,
  }) {
    return RoleGate(
      key: key,
      isAllowed: (session) => session.roles.any(roles.contains),
      child: child,
    );
  }

  final bool Function(ActorSession session) isAllowed;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(actorSessionProvider);
    if (session == null || !isAllowed(session)) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Erişim Reddedildi'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline,
                      size: 48, color: AppColors.textSecondary),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Bu ekrana erişim yetkiniz yok.',
                    style: AppTypography.bodyLarge
                        .copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return child;
  }
}
