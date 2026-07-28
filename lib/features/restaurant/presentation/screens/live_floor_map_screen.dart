import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../qr/domain/models/restaurant_table.dart';
import '../../application/use_cases/set_table_status.dart';
import '../../domain/models/table_shape.dart';
import '../providers/restaurant_operations_dependencies_provider.dart';

/// Read-only, responsive live view of a floor plan's tables, colored by
/// [TableStatus]. Tapping a table cycles it to the next operational status
/// — the smallest useful staff interaction this foundation supports; a
/// dedicated table-detail/reservation panel is future work.
///
/// Standalone: no `go_router` route, no staff-auth gate, matching every
/// other POS-facing screen built so far this project (`PosCashierScreen`,
/// `PosPaymentScreen`).
class LiveFloorMapScreen extends ConsumerStatefulWidget {
  const LiveFloorMapScreen({
    super.key,
    required this.floorPlanId,
    required this.floorPlanName,
  });

  final String floorPlanId;
  final String floorPlanName;

  @override
  ConsumerState<LiveFloorMapScreen> createState() => _LiveFloorMapScreenState();
}

class _LiveFloorMapScreenState extends ConsumerState<LiveFloorMapScreen> {
  List<RestaurantTable>? _tables;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final tables = await ref
        .read(restaurantTableRepositoryProvider)
        .findByFloorPlanId(widget.floorPlanId);
    if (!mounted) return;
    setState(() => _tables = tables);
  }

  Future<void> _cycleStatus(RestaurantTable table) async {
    const order = [
      TableStatus.available,
      TableStatus.occupied,
      TableStatus.reserved,
      TableStatus.cleaning,
      TableStatus.disabled,
    ];
    final next = order[(order.indexOf(table.status) + 1) % order.length];
    final useCase =
        SetTableStatus(repository: ref.read(restaurantTableRepositoryProvider));
    await useCase(tableId: table.id, status: next);
    await _load();
  }

  Color _colorFor(TableStatus status) {
    switch (status) {
      case TableStatus.available:
        return AppColors.success;
      case TableStatus.occupied:
        return AppColors.error;
      case TableStatus.reserved:
        return AppColors.warning;
      case TableStatus.cleaning:
        return AppColors.info;
      case TableStatus.disabled:
        return AppColors.textDisabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tables = _tables;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.floorPlanName),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: tables == null
            ? const LoadingView(message: 'Kat planı yükleniyor...')
            : tables.isEmpty
                ? const EmptyView(
                    icon: Icons.table_restaurant_outlined,
                    message: 'Bu kat planında henüz masa yok',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return InteractiveViewer(
                        maxScale: 3,
                        minScale: 0.5,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: Stack(
                            children: [
                              for (final table in tables)
                                Positioned(
                                  left: table.positionX,
                                  top: table.positionY,
                                  child: GestureDetector(
                                    onTap: () => _cycleStatus(table),
                                    child: Transform.rotate(
                                      angle: table.rotationDegrees *
                                          3.14159265 /
                                          180,
                                      child: Container(
                                        width: table.width,
                                        height: table.height,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: _colorFor(table.status)
                                              .withValues(alpha: 0.18),
                                          border: Border.all(
                                            color: _colorFor(table.status),
                                            width: 2,
                                          ),
                                          borderRadius:
                                              table.shape == TableShape.round
                                                  ? BorderRadius.circular(
                                                      table.width)
                                                  : AppRadius.kSmall,
                                        ),
                                        child: Text(
                                          table.displayName,
                                          textAlign: TextAlign.center,
                                          style:
                                              AppTypography.bodySmall.copyWith(
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
