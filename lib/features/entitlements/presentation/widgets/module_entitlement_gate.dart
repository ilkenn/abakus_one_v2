import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/entitlement_module.dart';
import '../../domain/entitlement_scope_type.dart';
import '../../domain/module_access_denial_reason.dart';
import '../providers/entitlement_dependencies_provider.dart';

const _denialMessages = {
  ModuleAccessDenialReason.notEntitled:
      'Bu modül aboneliğinizde bulunmuyor. Etkinleştirmek için yöneticinizle '
          'iletişime geçin.',
  ModuleAccessDenialReason.featureDisabled:
      'Bu özellik henüz etkinleştirilmedi.',
  ModuleAccessDenialReason.permissionDenied: 'Bu ekrana erişim yetkiniz yok.',
};

/// Screen-level gate composing all three Phase 7 authorization axes —
/// entitlement, feature flag, role permission — "all three must
/// authorize access" (`docs/decisions.md` ADR-024). Mirrors
/// `RoleGate`'s precedent: **the screen itself** denies, not just the
/// admin-shell navigation entry point that led to it, so a deep link
/// re-checks every time, and a denial names which of the three layers
/// actually blocked access rather than one undifferentiated message.
class ModuleEntitlementGate extends ConsumerStatefulWidget {
  const ModuleEntitlementGate({
    super.key,
    required this.module,
    required this.scopeType,
    required this.scopeId,
    required this.actorStaffId,
    required this.child,
  });

  final EntitlementModule module;
  final EntitlementScopeType scopeType;
  final String scopeId;
  final String actorStaffId;
  final Widget child;

  @override
  ConsumerState<ModuleEntitlementGate> createState() =>
      _ModuleEntitlementGateState();
}

class _ModuleEntitlementGateState extends ConsumerState<ModuleEntitlementGate> {
  ModuleAccessDenialReason? _denialReason;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final result = await ref.read(checkModuleAccessProvider).call(
          module: widget.module,
          scopeType: widget.scopeType,
          scopeId: widget.scopeId,
          actorStaffId: widget.actorStaffId,
        );
    if (!mounted) return;
    setState(() {
      _denialReason = result.denialReason;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: SafeArea(child: LoadingView(message: 'Kontrol ediliyor...')),
      );
    }
    if (_denialReason != null) {
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
                    _denialMessages[_denialReason]!,
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
    return widget.child;
  }
}
