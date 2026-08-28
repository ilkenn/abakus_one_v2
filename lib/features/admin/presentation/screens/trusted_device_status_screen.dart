import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../application/use_cases/trusted_device_session_controller.dart';
import '../../domain/trusted_device/device_registration_state.dart';
import '../providers/trusted_device_session_providers.dart';

/// The full trusted-device POS UX state machine, rendered — AP-3
/// continuation (`docs/decisions.md` ADR-041). Every
/// [DeviceRegistrationState] subtype has its own explicit branch here;
/// there is no default/fallback case that could silently hide an
/// unhandled state.
class TrustedDeviceStatusScreen extends ConsumerWidget {
  const TrustedDeviceStatusScreen({super.key, required this.capabilities});

  /// The capability set this screen registers a device for — e.g.
  /// `['POS']`. Kept explicit at the call site rather than hardcoded here,
  /// since KDS/PRINTER_CONTROLLER surfaces will want their own instance of
  /// this same screen later.
  final List<String> capabilities;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = ref.watch(currentTrustedDeviceSessionControllerProvider);
    if (args == null) {
      return const _BranchSelectionRequired();
    }
    final state = ref.watch(trustedDeviceSessionControllerProvider(args));
    final controller =
        ref.read(trustedDeviceSessionControllerProvider(args).notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Güvenilir Cihaz'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _buildForState(context, state, controller),
        ),
      ),
    );
  }

  Widget _buildForState(
    BuildContext context,
    DeviceRegistrationState state,
    TrustedDeviceSessionController controller,
  ) {
    return switch (state) {
      UnsupportedPlatform() => const _StatusCard(
          key: Key('deviceState_unsupportedPlatform'),
          icon: Icons.block_rounded,
          color: AppColors.error,
          title: 'Bu Platform Desteklenmiyor',
          message: 'Güvenilir cihaz oturumu yalnızca Android, iOS, Windows '
              've macOS üzerinde kullanılabilir. Web üzerinde operasyonel '
              'POS oturumu açılamaz.',
        ),
      NotRegistered() => _RegisterCard(
          key: const Key('deviceState_notRegistered'),
          onRegister: () => controller.register(capabilities: capabilities),
        ),
      RegistrationRequested() => const _StatusCard(
          key: Key('deviceState_registrationRequested'),
          icon: Icons.hourglass_top_rounded,
          color: AppColors.warning,
          title: 'Yönetici Onayı Bekleniyor',
          message: 'Cihaz kaydı oluşturuldu. Bir yönetici onaylayana kadar '
              'bu cihaz POS işlemleri gerçekleştiremez.',
        ),
      ActivationRequired() => _ActivationRequiredCard(
          key: const Key('deviceState_activationRequired'),
          onActivate: controller.activateOrRefresh,
        ),
      Activating() => const _StatusCard(
          key: Key('deviceState_activating'),
          icon: Icons.sync_rounded,
          color: AppColors.primary,
          title: 'Etkinleştiriliyor',
          message: 'Kimlik doğrulanıyor, lütfen bekleyin...',
          showProgress: true,
        ),
      ActiveSession(:final expiresAt) => _ActiveSessionCard(
          key: const Key('deviceState_active'),
          expiresAt: expiresAt,
        ),
      ExpiringRefreshing() => const _StatusCard(
          key: Key('deviceState_expiringRefreshing'),
          icon: Icons.sync_rounded,
          color: AppColors.primary,
          title: 'Oturum Yenileniyor',
          message: 'Cihaz oturumunuz sorunsuz şekilde yenileniyor...',
          showProgress: true,
        ),
      DeviceSuspended() => const _StatusCard(
          key: Key('deviceState_suspended'),
          icon: Icons.pause_circle_outline,
          color: AppColors.error,
          title: 'Cihaz Askıya Alındı',
          message: 'Bu cihaz bir yönetici tarafından askıya alındı. '
              'Devam etmek için bir yöneticiyle iletişime geçin.',
        ),
      DeviceRevoked() => _RecoverableTerminalCard(
          key: const Key('deviceState_revoked'),
          icon: Icons.cancel_outlined,
          title: 'Cihaz Yetkisi İptal Edildi',
          message: 'Bu cihazın güvenilir cihaz yetkisi iptal edildi. '
              'Devam etmek için cihazı yeniden kaydetmeniz gerekiyor.',
          onReregister: controller.resetAndReregister,
        ),
      DeviceRetired() => _RecoverableTerminalCard(
          key: const Key('deviceState_retired'),
          icon: Icons.archive_outlined,
          title: 'Cihaz Kullanımdan Kaldırıldı',
          message: 'Bu cihaz kalıcı olarak kullanımdan kaldırıldı. '
              'Devam etmek için yeni bir cihaz olarak kaydolun.',
          onReregister: controller.resetAndReregister,
        ),
      KeyStorageCorrupted() => _RecoverableTerminalCard(
          key: const Key('deviceState_keyStorageCorrupted'),
          icon: Icons.error_outline,
          title: 'Cihaz Anahtarı Okunamadı',
          message: 'Cihazın güvenli depolamasındaki anahtar bilgisi '
              'bozulmuş görünüyor. Güvenlik nedeniyle otomatik olarak yeni '
              'bir anahtar oluşturulmadı — devam etmek için cihazı '
              'yeniden kaydetmeniz gerekiyor.',
          onReregister: controller.resetAndReregister,
        ),
      DeviceNetworkError(:final message) => _RetryableErrorCard(
          key: const Key('deviceState_networkError'),
          message: message,
          onRetry: () => controller.register(capabilities: capabilities),
        ),
      DeviceEntitlementDenied(:final message) => _StatusCard(
          key: const Key('deviceState_entitlementDenied'),
          icon: Icons.lock_outline,
          color: AppColors.error,
          title: 'Modül Yetkisi Yok',
          message: message,
        ),
    };
  }
}

class _BranchSelectionRequired extends StatelessWidget {
  const _BranchSelectionRequired();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'Devam etmeden önce bir şube seçilmelidir.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge,
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.showProgress = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProgress)
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(),
              )
            else
              Icon(icon, size: 40, color: color),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RegisterCard extends StatelessWidget {
  const _RegisterCard({super.key, required this.onRegister});
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phonelink_setup_outlined,
                size: 40, color: AppColors.primary),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Cihaz Kayıtlı Değil',
              style: AppTypography.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'POS işlemlerine başlamadan önce bu cihazı güvenilir cihaz '
              'olarak kaydetmeniz gerekiyor. Kayıt sonrası bir yöneticinin '
              'onayı beklenecektir.',
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: onRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
              child: const Text('Cihazı Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivationRequiredCard extends StatelessWidget {
  const _ActivationRequiredCard({super.key, required this.onActivate});
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_outlined,
                size: 40, color: AppColors.primary),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Onaylandı — Etkinleştirme Gerekli',
              style: AppTypography.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Cihazınız bir yönetici tarafından onaylandı. POS '
              'işlemlerine başlamak için oturumu etkinleştirin.',
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: onActivate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
              child: const Text('Oturumu Etkinleştir'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveSessionCard extends StatelessWidget {
  const _ActiveSessionCard({super.key, required this.expiresAt});
  final DateTime expiresAt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 40, color: AppColors.primary),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Cihaz Etkin',
              style: AppTypography.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Oturum süresi: ${expiresAt.hour.toString().padLeft(2, '0')}:'
              '${expiresAt.minute.toString().padLeft(2, '0')}\'a kadar',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoverableTerminalCard extends StatelessWidget {
  const _RecoverableTerminalCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.onReregister,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onReregister;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppCard(
        borderColor: AppColors.error.withValues(alpha: 0.3),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: AppTypography.titleMedium
                  .copyWith(color: AppColors.error, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(message,
                style: AppTypography.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: onReregister,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Yeniden Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryableErrorCard extends StatelessWidget {
  const _RetryableErrorCard({
    super.key,
    required this.message,
    required this.onRetry,
  });
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            const Text('Bağlantı Sorunu', style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(message,
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }
}
