import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../orders/data/saved_address_exception.dart';
import '../../../orders/presentation/providers/saved_address_providers.dart';
import '../../data/address_search_exception.dart';
import '../../domain/models/resolved_address.dart';
import '../providers/address_search_provider.dart';
import '../widgets/address_map_confirmation_card.dart';

/// **Superseded, not deleted** — Faz P.2.1.2's map-first UX correction
/// made `MapFirstAddressScreen` the sole canonical create/edit surface;
/// nothing in `lib/` navigates to this screen anymore (confirmed via
/// grep before this note was added). Kept rather than removed per
/// `CLAUDE.md`'s "never delete without explicit approval" — it remains a
/// real, tested, working search-then-resolve-then-form flow that a
/// future product decision could revive (e.g. as a non-map fallback for
/// a platform where Maps SDK is unavailable). Its own architecture is
/// still sound and still documents real P.2/P.2.1 decisions accurately;
/// only its *reachability* changed.
///
/// Original doc comment, preserved for history: Faz P.2 §3 / Faz P.2.1 —
/// the "resolve canonical address components → show resolved address →
/// map pin confirmation → allow building number correction → apartment
/// number → optional floor → address description" steps, in one screen.
/// The map (`AddressMapConfirmationCard`) renders a real Google Map —
/// Faz P.2 originally deferred this specifically because Google's own
/// Places API policy requires Places-derived data shown on a map to
/// render on a Google Map, and this app only had `flutter_map`/
/// OpenStreetMap at the time; Faz P.2.1 added `google_maps_flutter` to
/// close that gap. Dragging the map pin is a user-intent hint only — see
/// [_confirmMovedPin]'s own doc comment for why it can never become
/// delivery-authorization truth by itself.
class AddressDetailsFormScreen extends ConsumerStatefulWidget {
  const AddressDetailsFormScreen({
    super.key,
    required this.providerPlaceId,
    required this.sessionToken,
    this.existingAddressId,
  });

  final String providerPlaceId;
  final String sessionToken;

  /// Non-null when editing/re-verifying an existing saved address rather
  /// than creating a new one.
  final String? existingAddressId;

  @override
  ConsumerState<AddressDetailsFormScreen> createState() =>
      _AddressDetailsFormScreenState();
}

class _AddressDetailsFormScreenState
    extends ConsumerState<AddressDetailsFormScreen> {
  ResolvedAddress? _resolved;
  String? _resolveError;
  bool _isResolving = true;
  bool _isSaving = false;
  String? _saveError;

  /// Faz P.2.1 §2 — set only while the customer has dragged the map pin
  /// away from the server-resolved position and that move hasn't been
  /// confirmed/re-verified yet. Never read by [_save] — only
  /// [_confirmMovedPin] ever consumes it, and only to call the backend's
  /// own independent re-resolution, never to write it directly anywhere.
  LatLng? _pendingPinPosition;
  bool _isReverifyingPin = false;
  String? _reverifyError;

  String _label = 'Ev';
  final _apartmentController = TextEditingController();
  final _floorController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _buildingNoOverrideController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _apartmentController.dispose();
    _floorController.dispose();
    _descriptionController.dispose();
    _buildingNoOverrideController.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    setState(() {
      _isResolving = true;
      _resolveError = null;
    });
    try {
      final resolved =
          await ref.read(addressSearchProviderProvider).resolvePlace(
                placeId: widget.providerPlaceId,
                sessionToken: widget.sessionToken,
              );
      if (!mounted) return;
      setState(() {
        _resolved = resolved;
        _isResolving = false;
      });
    } on AddressSearchException catch (error) {
      if (!mounted) return;
      setState(() {
        _isResolving = false;
        _resolveError = error.message;
      });
    }
  }

  void _onPinMoved(LatLng position) {
    setState(() {
      _pendingPinPosition = position;
      _reverifyError = null;
    });
  }

  /// Faz P.2.1 §2 — the *only* effect a moved pin may ever have: an
  /// independent server-side reverse-geocode. On success, [_resolved] is
  /// replaced wholesale by the server's own response (never merged with
  /// or influenced by the client-side dragged coordinates themselves) —
  /// the existing [_save] path then uses that new
  /// [ResolvedAddress.providerPlaceId] exactly as it already would for
  /// any other resolved address, with no special case. On failure,
  /// [_resolved] is left completely untouched.
  Future<void> _confirmMovedPin() async {
    final position = _pendingPinPosition;
    if (position == null) return;

    setState(() {
      _isReverifyingPin = true;
      _reverifyError = null;
    });
    try {
      final reResolved =
          await ref.read(addressSearchProviderProvider).reverseGeocode(
                latitude: position.latitude,
                longitude: position.longitude,
              );
      if (!mounted) return;
      if (!reResolved.isSufficientlyResolved &&
          reResolved.providerPlaceId.isEmpty) {
        setState(() {
          _isReverifyingPin = false;
          _reverifyError = 'Bu konum çözümlenemedi. Lütfen tekrar deneyin.';
        });
        return;
      }
      setState(() {
        _resolved = reResolved;
        _pendingPinPosition = null;
        _isReverifyingPin = false;
      });
    } on AddressSearchException catch (error) {
      if (!mounted) return;
      setState(() {
        _isReverifyingPin = false;
        _reverifyError = error.message;
      });
    }
  }

  Future<void> _save() async {
    final resolved = _resolved;
    if (resolved == null) return;
    if (_apartmentController.text.trim().isEmpty) {
      setState(() => _saveError = 'Daire numarası gereklidir.');
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      await ref.read(savedAddressRepositoryProvider).save(
            addressId: widget.existingAddressId,
            providerPlaceId: resolved.providerPlaceId,
            label: _label,
            apartmentNo: _apartmentController.text.trim(),
            floor: _floorController.text.trim().isEmpty
                ? null
                : _floorController.text.trim(),
            addressDescription: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            buildingNoOverride:
                _buildingNoOverrideController.text.trim().isEmpty
                    ? null
                    : _buildingNoOverrideController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SavedAddressException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Adresi Onayla'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: _isResolving
          ? const LoadingView(message: 'Adres çözümleniyor...')
          : _resolveError != null
              ? ErrorView(
                  message: _resolveError!,
                  retryLabel: 'Tekrar Dene',
                  onRetry: _resolve,
                )
              : _buildForm(_resolved!),
    );
  }

  Widget _buildForm(ResolvedAddress resolved) {
    final needsBuildingNoOverride = resolved.streetNumber == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.kMedium,
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resolved.formattedAddress ?? 'Adres',
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (!resolved.isSufficientlyResolved)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      'Bu adres tam olarak dogrulanamadi. Kaydedilecek '
                      'ancak teslimat icin once yeniden dogrulanmasi '
                      'gerekecek.',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.warning),
                    ),
                  ),
                _InfoRow(label: 'Il', value: resolved.provinceName),
                _InfoRow(label: 'Ilce', value: resolved.districtName),
                _InfoRow(label: 'Mahalle', value: resolved.neighborhoodName),
                _InfoRow(label: 'Sokak/Cadde', value: resolved.routeName),
                _InfoRow(label: 'Bina No', value: resolved.streetNumber),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (resolved.latitude != null && resolved.longitude != null) ...[
            AddressMapConfirmationCard(
              latitude: resolved.latitude!,
              longitude: resolved.longitude!,
              formattedAddress: resolved.formattedAddress,
              onPinMoved: _onPinMoved,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_pendingPinPosition != null) ...[
              Text(
                'Konumu taşıdınız. Bu yeni konumu kullanmak için '
                'aşağıdan onaylayın — yoksa aramada bulunan adres '
                'kullanılacaktır.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: _isReverifyingPin ? null : _confirmMovedPin,
                child: _isReverifyingPin
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Konumu Onayla'),
              ),
            ],
            if (_reverifyError != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  _reverifyError!,
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error),
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.xl),
          const Text('Adres Etiketi', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final option in const ['Ev', 'Is', 'Diger'])
                ChoiceChip(
                  label: Text(option),
                  selected: _label == option,
                  onSelected: (_) => setState(() => _label = option),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (needsBuildingNoOverride) ...[
            TextField(
              controller: _buildingNoOverrideController,
              decoration: const InputDecoration(
                labelText: 'Bina No (saglayici bulamadi, siz girin)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          TextField(
            controller: _apartmentController,
            decoration: const InputDecoration(
              labelText: 'Daire No *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _floorController,
            decoration: const InputDecoration(
              labelText: 'Kat (opsiyonel)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _descriptionController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Adres Tarifi (opsiyonel)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _saveError!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.kMedium,
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Text('Adresi Kaydet'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '-',
              style: AppTypography.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
