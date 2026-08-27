import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../navigation/presentation/providers/current_branch_provider.dart';
import '../providers/admin_context_provider.dart';
import '../providers/admin_dependencies_provider.dart';

/// AP-2 closure correction — the real multi-organization/multi-branch
/// context resolution gate. Sits between `AdminShellScreen`'s own
/// staff-session check and the shell's actual content: a valid staff
/// session alone is not enough to know WHICH organization/branch the
/// shell should operate against when the actor has access to more than
/// one (or, just as importantly, to detect that a previously-valid
/// selection has since been revoked).
///
/// Always re-fetches [typedActorContextProvider] fresh (never trusts a
/// value read once and held) — "Cached locator'ın backend tarafından
/// yeniden doğrulanması" is satisfied structurally: every render of this
/// gate re-derives from the current `AsyncValue`, and [_retry] explicitly
/// invalidates the provider to force a genuinely fresh backend call.
class AdminContextGate extends ConsumerWidget {
  const AdminContextGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Real multi-org/multi-branch resolution requires a real backend to
    // resolve against. Without one (every `flutter test` run; local dev
    // without the emulator connected), this app's only real tenant
    // context comes from `ActorSession`/custom claims already resolved by
    // `staffAuthRepositoryProvider` — falling through to [child] here
    // preserves that exact, already-correct, already-tested behavior
    // rather than showing a false "no access" state for a condition (no
    // Firebase) that has nothing to do with the actor's real access.
    final isFirebaseReady = ref.watch(firebaseReadyProvider);
    if (!isFirebaseReady) {
      return child;
    }

    final contextAsync = ref.watch(typedActorContextProvider);

    return contextAsync.when(
      loading: () => const Scaffold(
        body: SafeArea(
          child: LoadingView(
              message: 'Erişilebilir işletmeler kontrol ediliyor...'),
        ),
      ),
      error: (error, stackTrace) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: ErrorView(
            message: 'İşletme/şube erişimi doğrulanamadı.',
            retryLabel: 'Tekrar Dene',
            onRetry: () => ref.invalidate(resolvedActorContextProvider),
          ),
        ),
      ),
      data: (organizations) {
        if (organizations.isEmpty) {
          // Access revoked/inactive/never-granted — never silently fall
          // back to the stale org-1/branch-1 default while showing the
          // shell as if everything were fine.
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: EmptyView(
                icon: Icons.block_outlined,
                message: 'Bu hesap için erişilebilir bir işletme bulunamadı. '
                    'Yöneticinizle iletişime geçin.',
                actionLabel: 'Tekrar Dene',
                onAction: () => ref.invalidate(resolvedActorContextProvider),
              ),
            ),
          );
        }

        final currentOrgId = ref.watch(currentOrganizationIdProvider);
        final currentBranchId = ref.watch(currentBranchIdProvider);
        final activeOrg = organizations
            .where((o) => o.organizationId == currentOrgId)
            .firstOrNull;

        // The previously-active organization is no longer in the caller's
        // real access list (revoked) — never keep showing its data.
        if (activeOrg == null) {
          if (organizations.length == 1) {
            // Riverpod forbids writing to a provider mid-build (two
            // widgets watching the same provider could otherwise observe
            // inconsistent state) — deferred to the next frame, exactly
            // mirroring `ModuleEntitlementGate`'s own established
            // `addPostFrameCallback` pattern for this same class of
            // async-triggered-from-build side effect.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _autoSelect(ref, organizations.first);
            });
            return const Scaffold(
              body:
                  SafeArea(child: LoadingView(message: 'İşletme seçiliyor...')),
            );
          }
          return _OrganizationPickerScreen(organizations: organizations);
        }

        // The previously-active branch is no longer part of this
        // organization's real access list (revoked) — same treatment.
        if (!activeOrg.branchIds.contains(currentBranchId)) {
          if (activeOrg.branchIds.length == 1) {
            final onlyBranchId = activeOrg.branchIds.first;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(currentBranchIdProvider.notifier).state = onlyBranchId;
            });
            return const Scaffold(
              body: SafeArea(child: LoadingView(message: 'Şube seçiliyor...')),
            );
          }
          return _BranchPickerScreen(org: activeOrg);
        }

        return child;
      },
    );
  }

  void _autoSelect(WidgetRef ref, ActorOrganizationAccess org) {
    ref.read(currentOrganizationIdProvider.notifier).state = org.organizationId;
    if (org.branchIds.length == 1) {
      ref.read(currentBranchIdProvider.notifier).state = org.branchIds.first;
    }
  }
}

class _OrganizationPickerScreen extends ConsumerWidget {
  const _OrganizationPickerScreen({required this.organizations});

  final List<ActorOrganizationAccess> organizations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('İşletme Seçin'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: organizations.length,
          itemBuilder: (context, index) {
            final org = organizations[index];
            return Semantics(
              button: true,
              label: 'İşletme ${org.organizationId} seç',
              child: Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title:
                      Text(org.organizationId, style: AppTypography.bodyLarge),
                  subtitle: Text('${org.branchIds.length} şube'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    ref.read(currentOrganizationIdProvider.notifier).state =
                        org.organizationId;
                    if (org.branchIds.length == 1) {
                      ref.read(currentBranchIdProvider.notifier).state =
                          org.branchIds.first;
                    }
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// AP-2 closure correction — opens the on-demand organization/branch
/// switcher as a modal bottom sheet (desktop/tablet: centered dialog-sized
/// sheet via `showModalBottomSheet`'s own responsive default; mobile:
/// full-width sheet) — used by `AdminShellScreen`'s `_TopBar` context
/// indicator for a VOLUNTARY switch, distinct from `AdminContextGate`'s
/// own forced picker (shown only when the active selection has actually
/// become invalid). Both read the same [typedActorContextProvider], so
/// there is exactly one source of truth for "what can this actor switch
/// to," never two independently-maintained lists.
Future<void> showAdminContextSwitcherSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
    ),
    builder: (context) => const _AdminContextSwitcherSheetContent(),
  );
}

class _AdminContextSwitcherSheetContent extends ConsumerWidget {
  const _AdminContextSwitcherSheetContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contextAsync = ref.watch(typedActorContextProvider);
    final currentOrgId = ref.watch(currentOrganizationIdProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('İşletme / Şube Değiştir',
                style: AppTypography.titleMedium,
                semanticsLabel: 'İşletme ve şube değiştirme paneli'),
            const SizedBox(height: AppSpacing.md),
            contextAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: LoadingView(message: 'Yükleniyor...'),
              ),
              error: (error, stackTrace) => ErrorView(
                message: 'İşletme/şube listesi yüklenemedi.',
                retryLabel: 'Tekrar Dene',
                onRetry: () => ref.invalidate(resolvedActorContextProvider),
              ),
              data: (organizations) {
                if (organizations.isEmpty) {
                  return const EmptyView(
                    icon: Icons.block_outlined,
                    message: 'Erişilebilir işletme bulunamadı.',
                  );
                }
                final activeOrg = organizations
                    .where((o) => o.organizationId == currentOrgId)
                    .firstOrNull;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (organizations.length > 1) ...[
                      const Text('İşletme', style: AppTypography.labelMedium),
                      const SizedBox(height: AppSpacing.xs),
                      for (final org in organizations)
                        Semantics(
                          button: true,
                          selected: org.organizationId == currentOrgId,
                          label: 'İşletme ${org.organizationId}',
                          child: ListTile(
                            selected: org.organizationId == currentOrgId,
                            leading: Icon(
                              org.organizationId == currentOrgId
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: org.organizationId == currentOrgId
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                            title: Text(org.organizationId),
                            onTap: () {
                              ref
                                  .read(currentOrganizationIdProvider.notifier)
                                  .state = org.organizationId;
                              if (org.branchIds.length == 1) {
                                ref
                                    .read(currentBranchIdProvider.notifier)
                                    .state = org.branchIds.first;
                              }
                            },
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (activeOrg != null &&
                        activeOrg.branchIds.length > 1) ...[
                      const Text('Şube', style: AppTypography.labelMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Consumer(builder: (context, ref, _) {
                        final currentBranchId =
                            ref.watch(currentBranchIdProvider);
                        final deviceBoundBranchId =
                            ref.watch(deviceBoundBranchIdProvider);
                        return Column(
                          children: [
                            for (final branchId in activeOrg.branchIds)
                              Builder(builder: (context) {
                                final blockedByDevice =
                                    deviceBoundBranchId != null &&
                                        deviceBoundBranchId != branchId;
                                final selected = branchId == currentBranchId;
                                return Semantics(
                                  button: !blockedByDevice,
                                  selected: selected,
                                  label: 'Şube $branchId',
                                  child: ListTile(
                                    enabled: !blockedByDevice,
                                    selected: selected,
                                    leading: Icon(
                                      selected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked,
                                      color: blockedByDevice
                                          ? AppColors.textSecondary
                                              .withValues(alpha: 0.4)
                                          : selected
                                              ? AppColors.primary
                                              : AppColors.textSecondary,
                                    ),
                                    title: Text(branchId),
                                    subtitle: blockedByDevice
                                        ? const Text(
                                            'Bu cihaz farklı bir şubeye bağlı')
                                        : null,
                                    onTap: blockedByDevice
                                        ? null
                                        : () => ref
                                            .read(currentBranchIdProvider
                                                .notifier)
                                            .state = branchId,
                                  ),
                                );
                              }),
                          ],
                        );
                      }),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Kapat'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchPickerScreen extends ConsumerWidget {
  const _BranchPickerScreen({required this.org});

  final ActorOrganizationAccess org;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceBoundBranchId = ref.watch(deviceBoundBranchIdProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Şube Seçin'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: org.branchIds.length,
          itemBuilder: (context, index) {
            final branchId = org.branchIds[index];
            final blockedByDevice =
                deviceBoundBranchId != null && deviceBoundBranchId != branchId;
            return Semantics(
              button: !blockedByDevice,
              label: 'Şube $branchId seç',
              child: Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: ListTile(
                  leading: Icon(
                    Icons.storefront_outlined,
                    color: blockedByDevice ? AppColors.textSecondary : null,
                  ),
                  title: Text(branchId, style: AppTypography.bodyLarge),
                  subtitle: blockedByDevice
                      ? const Text(
                          'Bu cihaz farklı bir şubeye bağlı — buradan geçiş yapılamaz.')
                      : null,
                  enabled: !blockedByDevice,
                  onTap: blockedByDevice
                      ? null
                      : () => ref.read(currentBranchIdProvider.notifier).state =
                          branchId,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
