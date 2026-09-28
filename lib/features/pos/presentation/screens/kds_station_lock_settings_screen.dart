import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/option_selection_card.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/kds/kitchen_station.dart';
import '../../domain/kds/kitchen_station_labels.dart';
import '../providers/kds_dependencies_provider.dart';

/// Lets this physical KDS device lock itself to a single [KitchenStation]
/// so `KitchenDisplayBoardScreen` always opens pre-filtered to it, even
/// after an app restart. Local-only device preference — see
/// `KdsStationLockStore`'s own doc comment for why this is deliberately not
/// the server-facing multi-device registry.
///
/// Explicit pick-then-"Kaydet" flow rather than apply-on-tap: locking a
/// kiosk's board is consequential enough (hides every other station's
/// tickets from whoever works this screen next) to warrant a confirm step,
/// not a single fat-fingered tap.
class KdsStationLockSettingsScreen extends ConsumerStatefulWidget {
  const KdsStationLockSettingsScreen({super.key});

  @override
  ConsumerState<KdsStationLockSettingsScreen> createState() =>
      _KdsStationLockSettingsScreenState();
}

class _KdsStationLockSettingsScreenState
    extends ConsumerState<KdsStationLockSettingsScreen> {
  KitchenStation? _currentLock;
  KitchenStation? _pendingSelection;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final store = await ref.read(kdsStationLockStoreProvider.future);
      final lock = await store.currentLock();
      if (!mounted) return;
      setState(() {
        _currentLock = lock;
        _pendingSelection = lock;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'İstasyon kilidi yüklenirken bir sorun oluştu.';
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    final store = await ref.read(kdsStationLockStoreProvider.future);
    final selection = _pendingSelection;
    if (selection == null) {
      await store.clearLock();
    } else {
      await store.setLock(selection);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('İstasyon Ayarları'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingView(message: 'Yükleniyor...');
    }
    final error = _errorMessage;
    if (error != null) {
      return ErrorView(
        message: error,
        retryLabel: 'Tekrar Dene',
        onRetry: _load,
      );
    }

    final statusText = _currentLock == null
        ? 'Şu anda kilit yok — Tümü gösteriliyor'
        : 'Şu anda kilitli: ${kitchenStationLabels[_currentLock]}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(statusText,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            children: [
              for (final entry in kitchenStationLabels.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: OptionSelectionCard(
                    name: entry.value,
                    extraPrice: 0,
                    isSelected: _pendingSelection == entry.key,
                    onTap: () => setState(() => _pendingSelection = entry.key),
                  ),
                ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: OptionSelectionCard(
                  name: 'Kilidi Kaldır / Tümünü Göster',
                  extraPrice: 0,
                  isSelected: _pendingSelection == null,
                  onTap: () => setState(() => _pendingSelection = null),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              child: const Text('Kaydet'),
            ),
          ),
        ),
      ],
    );
  }
}
