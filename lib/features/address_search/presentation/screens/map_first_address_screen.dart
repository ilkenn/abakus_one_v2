import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../orders/data/saved_address_exception.dart';
import '../../../orders/presentation/providers/saved_address_providers.dart';
import '../../data/address_search_exception.dart';
import '../../domain/models/resolved_address.dart';
import '../providers/address_search_provider.dart';
import 'address_search_screen.dart';

/// Faz P.2.1.2 (map-first UX correction) — the **canonical, primary**
/// address create/edit surface: a Google Map opens immediately (current
/// location if granted, else a safe Istanbul default), a **fixed
/// screen-center pin** (the map pans underneath it — never a tiny
/// draggable marker the customer has to grab precisely), and on every
/// genuine camera-idle event the center coordinate is sent to the
/// server-authoritative `reverseGeocodeAddressPoint` callable to resolve
/// province/district/neighborhood/street/building automatically. "Adres
/// Ara" (secondary) pushes [AddressSearchScreen] purely to re-center the
/// camera at a searched place — the resulting camera move funnels back
/// through the exact same reverse-geocode pipeline, so there is only
/// **one** address-resolution/authorization path in this whole flow,
/// never two.
///
/// [existingAddressId]/[initialLatitude]/[initialLongitude] non-null
/// means "edit an existing SavedAddress" — opens the map already
/// centered at its saved location and immediately resolves it, rather
/// than requesting device location.
class MapFirstAddressScreen extends ConsumerStatefulWidget {
  const MapFirstAddressScreen({
    super.key,
    this.existingAddressId,
    this.initialLatitude,
    this.initialLongitude,
    this.mapReadyTimeout = const Duration(seconds: 5),
  });

  final String? existingAddressId;
  final double? initialLatitude;
  final double? initialLongitude;

  /// Injectable for tests — see [mapReadyTimeout]'s use in
  /// `AddressMapConfirmationCard` (Faz P.2.1) for the same reasoning.
  final Duration mapReadyTimeout;

  /// Istanbul city-center default — used whenever no saved location and
  /// no device location are available. Not a delivery-zone claim, purely
  /// a sensible map starting point (§5).
  static const LatLng istanbulDefault = LatLng(41.0082, 28.9784);

  @override
  ConsumerState<MapFirstAddressScreen> createState() =>
      _MapFirstAddressScreenState();
}

class _MapFirstAddressScreenState extends ConsumerState<MapFirstAddressScreen> {
  GoogleMapController? _mapController;
  late LatLng _cameraTarget;
  LatLng _pendingCameraPosition = MapFirstAddressScreen.istanbulDefault;

  bool _isResolving = false;
  ResolvedAddress? _resolved;
  String? _resolveError;
  int _resolveGeneration = 0;

  bool _locationPermissionGranted = false;
  bool _locationPermanentlyDenied = false;

  bool _mapReady = false;
  bool _mapFailed = false;
  Timer? _mapReadyTimer;
  int _mapRetryGeneration = 0;

  bool _isSaving = false;
  String? _saveError;
  String _label = 'Ev';
  final _apartmentController = TextEditingController();
  final _floorController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _buildingNoOverrideController = TextEditingController();

  bool get _isEditing => widget.existingAddressId != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _cameraTarget = LatLng(widget.initialLatitude!, widget.initialLongitude!);
      _pendingCameraPosition = _cameraTarget;
      _locationPermissionGranted = true;
      _resolveCenter(_cameraTarget);
    } else {
      _cameraTarget = MapFirstAddressScreen.istanbulDefault;
      _pendingCameraPosition = _cameraTarget;
      _initializeFromDeviceLocation();
    }
    _armMapReadyTimeout();
  }

  @override
  void dispose() {
    _mapReadyTimer?.cancel();
    _apartmentController.dispose();
    _floorController.dispose();
    _descriptionController.dispose();
    _buildingNoOverrideController.dispose();
    super.dispose();
  }

  void _armMapReadyTimeout() {
    _mapReadyTimer?.cancel();
    _mapReadyTimer = Timer(widget.mapReadyTimeout, () {
      if (!_mapReady && mounted) setState(() => _mapFailed = true);
    });
  }

  Future<void> _initializeFromDeviceLocation() async {
    final position =
        await ref.read(addressLocationGatewayProvider).currentPosition();
    if (!mounted) return;
    if (position != null) {
      final target = LatLng(position.latitude, position.longitude);
      setState(() {
        _cameraTarget = target;
        _pendingCameraPosition = target;
        _locationPermissionGranted = true;
      });
      await _mapController
          ?.animateCamera(CameraUpdate.newLatLngZoom(target, 17));
      await _resolveCenter(target);
    } else {
      final permanentlyDenied = await ref
          .read(addressLocationGatewayProvider)
          .isPermissionPermanentlyDenied();
      if (!mounted) return;
      setState(() => _locationPermanentlyDenied = permanentlyDenied);
      // §5 — never block address creation: still resolve the default
      // (Istanbul) center so the customer has a starting point to pan
      // away from.
      await _resolveCenter(_cameraTarget);
    }
  }

  /// §4 — the *only* place this screen ever calls the server. Camera
  /// movement alone (`onCameraMove`) never reaches here; only a genuine
  /// `onCameraIdle` (or an explicit search re-center) does. A generation
  /// counter discards a stale in-flight response if the camera moved
  /// again before it returned — mirrors `AddressSearchNotifier`'s own
  /// debounce/discard pattern.
  Future<void> _resolveCenter(LatLng position) async {
    final generation = ++_resolveGeneration;
    setState(() {
      _isResolving = true;
      _resolveError = null;
    });
    try {
      final resolved =
          await ref.read(addressSearchProviderProvider).reverseGeocode(
                latitude: position.latitude,
                longitude: position.longitude,
              );
      if (generation != _resolveGeneration || !mounted) return;
      setState(() {
        _resolved = resolved;
        _isResolving = false;
      });
    } on AddressSearchException catch (error) {
      if (generation != _resolveGeneration || !mounted) return;
      setState(() {
        _isResolving = false;
        _resolveError = error.message;
      });
    }
  }

  void _onCameraMove(CameraPosition position) {
    // Deliberately no server call, no setState requiring a rebuild here
    // — this must stay cheap, it fires continuously during a pan (§3:
    // "Do not reverse-geocode every animation frame").
    _pendingCameraPosition = position.target;
  }

  void _onCameraIdle() {
    _resolveCenter(_pendingCameraPosition);
  }

  Future<void> _recenterOnCurrentLocation() async {
    final position =
        await ref.read(addressLocationGatewayProvider).currentPosition();
    if (position == null || !mounted) return;
    final target = LatLng(position.latitude, position.longitude);
    await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 17));
    _pendingCameraPosition = target;
    await _resolveCenter(target);
  }

  Future<void> _openSearch() async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => const AddressSearchScreen()),
    );
    if (result == null || !mounted) return;
    await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(result, 17));
    _pendingCameraPosition = result;
    await _resolveCenter(result);
  }

  void _retryMap() {
    setState(() {
      _mapFailed = false;
      _mapReady = false;
      _mapRetryGeneration++;
    });
    _armMapReadyTimeout();
  }

  Future<void> _save() async {
    final resolved = _resolved;
    if (resolved == null || resolved.providerPlaceId.isEmpty) return;
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
      await ref.read(savedAddressListProvider.notifier).refresh();
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
      appBar: AppBar(
        title: Text(_isEditing ? 'Konumu Güncelle' : 'Yeni Adres Ekle'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _openSearch,
            icon: const Icon(Icons.search),
            label: const Text('Adres Ara'),
          ),
        ],
      ),
      body: _mapFailed ? _buildMapFailedFallback() : _buildMapWithCard(),
      floatingActionButton: _mapFailed
          ? null
          : FloatingActionButton.small(
              heroTag: 'recenter-current-location',
              onPressed: _recenterOnCurrentLocation,
              child: const Icon(Icons.my_location),
            ),
    );
  }

  Widget _buildMapWithCard() {
    return Stack(
      children: [
        GoogleMap(
          key: ValueKey('map-first-$_mapRetryGeneration'),
          initialCameraPosition:
              CameraPosition(target: _cameraTarget, zoom: 16),
          myLocationEnabled: _locationPermissionGranted,
          myLocationButtonEnabled: _locationPermissionGranted,
          onMapCreated: (controller) {
            _mapController = controller;
            _mapReadyTimer?.cancel();
            if (mounted) setState(() => _mapReady = true);
          },
          onCameraMove: _onCameraMove,
          onCameraIdle: _onCameraIdle,
        ),
        // §2/§7 — the fixed center pin: a plain overlay widget, never a
        // `Marker` (which would move with the map) — the map pans
        // underneath this fixed point instead.
        const IgnorePointer(
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(
                Icons.location_on,
                size: 48,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        Positioned(
          top: AppSpacing.md,
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.kMedium,
            ),
            child: const Text(
              'İşaretçiyi bina girişinizin üzerine getirin.',
              style: AppTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        if (_locationPermanentlyDenied)
          Positioned(
            top: AppSpacing.xxxl,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: AppRadius.kMedium,
              ),
              child: const Text(
                'Konum iznini ayarlardan açabilirsiniz.',
                style: AppTypography.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _buildAddressCard(),
        ),
      ],
    );
  }

  Widget _buildAddressCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Seçilen Konum', style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (_isResolving)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_resolveError != null)
              Text(
                _resolveError!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              )
            else if (_resolved != null) ...[
              Text(
                _resolved!.formattedAddress ?? 'Adres bulunamadı',
                style: AppTypography.bodyMedium,
              ),
              if (!_resolved!.isSufficientlyResolved)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'Bu konum tam olarak dogrulanamadi.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.warning),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
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
              const SizedBox(height: AppSpacing.md),
              if (_resolved!.streetNumber == null) ...[
                TextField(
                  controller: _buildingNoOverrideController,
                  decoration: const InputDecoration(
                    labelText: 'Bina No',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              TextField(
                controller: _apartmentController,
                decoration: const InputDecoration(
                  labelText: 'Daire No *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _floorController,
                decoration: const InputDecoration(
                  labelText: 'Kat (opsiyonel)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Adres Tarifi (opsiyonel)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_saveError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _saveError!,
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Bu Konumu Kullan'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMapFailedFallback() {
    return ErrorView(
      message: 'Harita yüklenemedi. Lütfen tekrar deneyin veya adres arayın.',
      retryLabel: 'Tekrar Dene',
      onRetry: _retryMap,
    );
  }
}
