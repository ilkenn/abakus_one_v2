import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// **Superseded, not deleted** — Faz P.2.1.2's map-first UX made this
/// small draggable-marker card unused; its only caller
/// (`AddressDetailsFormScreen`) is itself superseded. Kept per
/// `CLAUDE.md`'s "never delete without explicit approval." See
/// `MapFirstAddressScreen` for the canonical, full-screen, fixed-center-
/// pin map picker that replaced this widget's role.
///
/// Original doc comment, preserved for history — Faz P.2.1 §1/§2:
/// renders the server-resolved address location on a
/// **Google Map** (never `flutter_map`/OpenStreetMap): Google's own
/// Places API policy requires Places-derived data shown on a map to be
/// shown on a Google Map specifically (`docs/decisions.md` Faz P.2 D6).
///
/// The marker is draggable **as a user-intent hint only** — dragging it
/// updates only this widget's own local visual state and calls
/// [onPinMoved] with the new position; it never mutates [latitude]/
/// [longitude] directly, and this widget itself never calls any backend.
/// The caller (`AddressDetailsFormScreen`) is the one that decides what
/// to do with a moved pin — reverse-geocode it server-side before
/// treating it as anything authoritative (Faz P.2.1 §2).
///
/// §7 — if the Google Map SDK cannot initialize within [mapReadyTimeout]
/// (covers both a genuine native init failure and this app's own
/// `flutter test` environment, which has no real platform view support),
/// shows a safe address-summary fallback with a retry action — never a
/// silent `flutter_map`/OSM substitution.
class AddressMapConfirmationCard extends StatefulWidget {
  const AddressMapConfirmationCard({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
    required this.onPinMoved,
    this.mapReadyTimeout = const Duration(seconds: 5),
  });

  final double latitude;
  final double longitude;
  final String? formattedAddress;
  final ValueChanged<LatLng> onPinMoved;

  /// Injectable for tests — the real default (5s) would make a test that
  /// exercises the fallback path slow for no reason.
  final Duration mapReadyTimeout;

  @override
  State<AddressMapConfirmationCard> createState() =>
      _AddressMapConfirmationCardState();
}

class _AddressMapConfirmationCardState
    extends State<AddressMapConfirmationCard> {
  late LatLng _markerPosition;
  bool _mapReady = false;
  bool _mapFailed = false;
  Timer? _timeoutTimer;
  int _retryGeneration = 0;

  @override
  void initState() {
    super.initState();
    _markerPosition = LatLng(widget.latitude, widget.longitude);
    _armTimeout();
  }

  @override
  void didUpdateWidget(covariant AddressMapConfirmationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A successful server-side reverse-geocode (handled by the parent)
    // pushes new authoritative coordinates down — re-center the marker
    // on them. A failed one leaves latitude/longitude unchanged, so this
    // branch simply doesn't fire and the pin stays wherever the customer
    // last dropped it.
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _markerPosition = LatLng(widget.latitude, widget.longitude);
    }
  }

  void _armTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(widget.mapReadyTimeout, () {
      if (!_mapReady && mounted) setState(() => _mapFailed = true);
    });
  }

  void _retry() {
    setState(() {
      _mapFailed = false;
      _mapReady = false;
      _retryGeneration++;
    });
    _armTimeout();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_mapFailed) return _buildFallback();

    return ClipRRect(
      borderRadius: AppRadius.kMedium,
      child: SizedBox(
        height: 220,
        child: GoogleMap(
          key: ValueKey('map-$_retryGeneration'),
          initialCameraPosition: CameraPosition(
            target: LatLng(widget.latitude, widget.longitude),
            zoom: 16,
          ),
          markers: {
            Marker(
              markerId: const MarkerId('selected-address'),
              position: _markerPosition,
              draggable: true,
              onDragEnd: (newPosition) {
                setState(() => _markerPosition = newPosition);
                widget.onPinMoved(newPosition);
              },
            ),
          },
          onMapCreated: (_) {
            _timeoutTimer?.cancel();
            if (mounted) setState(() => _mapReady = true);
          },
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      key: const ValueKey('address-map-fallback'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.kMedium,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map_outlined, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Harita yüklenemedi.',
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          if (widget.formattedAddress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(widget.formattedAddress!, style: AppTypography.bodySmall),
          ],
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: _retry, child: const Text('Tekrar Dene')),
        ],
      ),
    );
  }
}
