import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_environment_config_provider.dart';
import '../../../../core/services/feature_flags/feature_flags_keys.dart';
import '../../../../core/services/feature_flags/feature_flags_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/set_maintenance_mode.dart';
import '../../domain/system/maintenance_mode_state.dart';
import '../providers/admin_dependencies_provider.dart';

const _flagLabels = {
  FeatureFlagsKeys.otpLoginEnabled: 'OTP ile Giriş',
  FeatureFlagsKeys.bowlBuilderEnabled: 'Bowl Builder',
  FeatureFlagsKeys.fortuneWheelEnabled: 'Şans Çarkı',
  FeatureFlagsKeys.reservationsEnabled: 'Rezervasyonlar',
  FeatureFlagsKeys.qrScannerEnabled: 'QR Tarayıcı',
};

/// Feature flags, environment visibility, maintenance mode, and honest
/// system notes — Phase 6O (`docs/decisions.md` ADR-023). "Do not
/// expose secrets" — every environment field shown here
/// (`AppEnvironmentConfig`) is confirmed non-secret (see that class's
/// own doc comment); nothing here reads or displays a token/key.
/// "Do not permit editing immutable environment secrets from UI" — this
/// screen has no edit path for `AppEnvironmentConfig` at all, and
/// feature flags are view-only here (they're sourced from Firebase
/// Remote Config, which has no write API wired in this codebase yet —
/// editing happens in the Firebase console, not this screen).
class SystemHealthAdminScreen extends ConsumerStatefulWidget {
  const SystemHealthAdminScreen({
    super.key,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<SystemHealthAdminScreen> createState() =>
      _SystemHealthAdminScreenState();
}

class _SystemHealthAdminScreenState
    extends ConsumerState<SystemHealthAdminScreen> {
  MaintenanceModeState? _maintenanceState;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMaintenance());
  }

  Future<void> _loadMaintenance() async {
    final state = await ref.read(maintenanceModeStateRepositoryProvider).find();
    if (!mounted) return;
    setState(() =>
        _maintenanceState = state ?? const MaintenanceModeState(revision: 0));
  }

  Future<void> _toggleMaintenance(bool isActive, {String? reason}) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await SetMaintenanceMode(
        authorizationPolicy: policy,
        repository: ref.read(maintenanceModeStateRepositoryProvider),
        auditRepository: ref.read(adminAuditEntryRepositoryProvider),
      )(
        isActive: isActive,
        reason: reason,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      setState(() => _error = null);
      await _loadMaintenance();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _activateWithReason() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bakım Modunu Aç'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Neden (opsiyonel)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Aç'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    await _toggleMaintenance(true,
        reason: reason.trim().isEmpty ? null : reason.trim());
  }

  @override
  Widget build(BuildContext context) {
    final environment = ref.watch(appEnvironmentConfigProvider);
    final flagsService = ref.watch(featureFlagsServiceProvider);
    final maintenance = _maintenanceState;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Sistem Sağlığı ve Ayarlar'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (_error != null) ...[
              Text(_error!,
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error)),
              const SizedBox(height: AppSpacing.sm),
            ],
            const Text('Ortam', style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ortam: ${environment.displayName}',
                      style: AppTypography.bodyMedium),
                  Text('Production: ${environment.isProduction}',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                  Text('Firebase Projesi: ${environment.firebaseProjectId}',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                  Text(
                    'Geliştirici Araçları: ${environment.allowsDebugTooling}',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Özellik Bayrakları', style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Salt okunur — değerler Firebase Remote Config üzerinden '
              'yönetilir, bu ekrandan düzenlenemez.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  for (final entry in _flagLabels.entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.value),
                      trailing: Icon(
                        flagsService.isEnabled(entry.key)
                            ? Icons.check_circle_outline
                            : Icons.radio_button_unchecked,
                        color: flagsService.isEnabled(entry.key)
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Bakım Modu', style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: maintenance == null
                  ? const SizedBox(
                      height: 24,
                      child: Center(child: CircularProgressIndicator()))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          maintenance.isActive
                              ? 'Bakım modu AÇIK'
                              : 'Bakım modu KAPALI',
                          style: AppTypography.bodyLarge.copyWith(
                            color: maintenance.isActive
                                ? AppColors.error
                                : AppColors.success,
                          ),
                        ),
                        if (maintenance.reason != null)
                          Text('Neden: ${maintenance.reason}',
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.textSecondary)),
                        const SizedBox(height: AppSpacing.sm),
                        if (maintenance.isActive)
                          OutlinedButton(
                            onPressed: () => _toggleMaintenance(false),
                            child: const Text('Bakım Modunu Kapat'),
                          )
                        else
                          ElevatedButton(
                            onPressed: _activateWithReason,
                            child: const Text('Bakım Modunu Aç'),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Sistem Notları', style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            const AppCard(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SystemNote('Firebase henüz başlatılmadı — analytics/crash '
                      'reporting/remote config gerçek bir sağlayıcıya bağlı '
                      'değil (NoOp).'),
                  _SystemNote(
                      'Özellik bayrakları bu nedenle her zaman belgelenen '
                      'varsayılan değerlerini döndürür.'),
                  _SystemNote('Bakım modu hiçbir müşteri ekranı veya sipariş '
                      'akışı tarafından henüz okunmuyor — yalnızca '
                      'yönetici görünürlüğü/denetimi sağlar.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemNote extends StatelessWidget {
  const _SystemNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(text,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
