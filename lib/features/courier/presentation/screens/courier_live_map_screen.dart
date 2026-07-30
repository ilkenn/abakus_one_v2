import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/identity/courier.dart';
import '../../domain/location/courier_live_status.dart';
import '../formatters/courier_status_labels.dart';
import '../providers/courier_dependencies_provider.dart';

/// Real manager live map — Sprint 5C Part 4. Uses `flutter_map` +
/// OpenStreetMap tiles (user-approved choice; no API key/billing setup
/// required). Every marker is a real courier position from
/// `CourierLiveStatus` (Sprint 5B's real-GPS data) — never a placeholder
/// or synthetic pin. Couriers with no location reading on record
/// (`hasNeverReportedLocation`) are listed separately below the map, never
/// silently dropped.
class CourierLiveMapScreen extends ConsumerStatefulWidget {
  const CourierLiveMapScreen({super.key, required this.branchId});

  final String branchId;

  @override
  ConsumerState<CourierLiveMapScreen> createState() =>
      _CourierLiveMapScreenState();
}

class _CourierLiveMapScreenState extends ConsumerState<CourierLiveMapScreen> {
  List<(Courier, CourierLiveStatus)>? _entries;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final couriers = await ref
        .read(courierRepositoryProvider)
        .findByBranchId(widget.branchId);
    final statuses = await ref.read(buildCourierLiveStatusForBranchProvider)(
        branchId: widget.branchId);
    final statusByCourierId = {for (final s in statuses) s.courierId: s};
    if (!mounted) return;
    setState(() {
      _entries = [
        for (final courier in couriers)
          if (statusByCourierId[courier.id] != null)
            (courier, statusByCourierId[courier.id]!),
      ];
    });
  }

  void _showDetail(Courier courier, CourierLiveStatus status) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _CourierDetailPanel(courier: courier, status: status),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Canlı Kurye Haritası'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: entries == null
            ? const LoadingView(message: 'Harita yükleniyor...')
            : _buildBody(entries),
      ),
    );
  }

  Widget _buildBody(List<(Courier, CourierLiveStatus)> entries) {
    final located =
        entries.where((e) => !e.$2.hasNeverReportedLocation).toList();
    final unlocated =
        entries.where((e) => e.$2.hasNeverReportedLocation).toList();

    if (entries.isEmpty) {
      return const EmptyView(
        icon: Icons.map_outlined,
        message: 'Bu şubede kayıtlı kurye bulunmuyor.',
      );
    }

    final center = located.isEmpty
        ? const LatLng(41.0082, 28.9784)
        : LatLng(
            located.map((e) => e.$2.latitude!).reduce((a, b) => a + b) /
                located.length,
            located.map((e) => e.$2.longitude!).reduce((a, b) => a + b) /
                located.length,
          );

    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: center, initialZoom: 13),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.abakus.one',
              ),
              MarkerLayer(
                markers: [
                  for (final (courier, status) in located)
                    Marker(
                      point: LatLng(status.latitude!, status.longitude!),
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _showDetail(courier, status),
                        child: _CourierMapPin(status: status),
                      ),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
        ),
        if (unlocated.isNotEmpty)
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.all(AppSpacing.sm),
            width: double.infinity,
            child: Text(
              'Konum verisi olmayan ${unlocated.length} kurye: '
              '${unlocated.map((e) => e.$1.displayName).join(', ')}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }
}

class _CourierMapPin extends StatelessWidget {
  const _CourierMapPin({required this.status});

  final CourierLiveStatus status;

  @override
  Widget build(BuildContext context) {
    final color =
        CourierStatusLabels.availabilityColor(status.availabilityStatus);
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: const Icon(Icons.delivery_dining, color: Colors.white, size: 24),
    );
  }
}

class _CourierDetailPanel extends StatelessWidget {
  const _CourierDetailPanel({required this.courier, required this.status});

  final Courier courier;
  final CourierLiveStatus status;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(courier.displayName, style: AppTypography.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(
                      'Durum',
                      CourierStatusLabels.availability(
                          status.availabilityStatus)),
                  _DetailRow(
                      'Bağlantı', status.isOnline ? 'Çevrimiçi' : 'Çevrimdışı'),
                  _DetailRow('GPS Kalitesi',
                      CourierStatusLabels.signalQuality(status.signalQuality)),
                  _DetailRow('Hareket',
                      CourierStatusLabels.movement(status.movementState)),
                  if (status.batteryLevelPercent != null)
                    _DetailRow('Batarya', '%${status.batteryLevelPercent}'),
                  _DetailRow('Aktif Teslimat Sayısı',
                      '${status.activeDeliveryIds.length}'),
                  if (status.activeDeliveryIds.isNotEmpty)
                    _DetailRow(
                        'Teslimatlar', status.activeDeliveryIds.join(', ')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          Text(value, style: AppTypography.bodyMedium),
        ],
      ),
    );
  }
}
