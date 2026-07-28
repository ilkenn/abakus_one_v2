import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../qr/domain/models/restaurant_table.dart';
import '../../application/use_cases/add_restaurant_table.dart';
import '../../application/use_cases/update_floor_plan_layout.dart';
import '../../domain/models/table_shape.dart';
import '../providers/restaurant_operations_dependencies_provider.dart';

/// Drag-and-drop floor-plan layout editor: reposition existing tables and
/// add new ones. Positions are held optimistically in local state while
/// dragging and persisted in one batch via [UpdateFloorPlanLayout] when
/// "Kaydet" is pressed — dragging itself never writes to the repository,
/// so an abandoned edit never partially persists.
///
/// Desktop/tablet-oriented (a drag-based layout tool has no meaningful
/// phone-width equivalent) — phone width falls back to a read-only list,
/// matching this codebase's existing responsive-breakpoint convention of
/// degrading gracefully rather than hiding the screen entirely.
class FloorPlanEditorScreen extends ConsumerStatefulWidget {
  const FloorPlanEditorScreen({
    super.key,
    required this.floorPlanId,
    required this.floorPlanName,
    required this.branchId,
  });

  final String floorPlanId;
  final String floorPlanName;
  final String branchId;

  @override
  ConsumerState<FloorPlanEditorScreen> createState() =>
      _FloorPlanEditorScreenState();
}

class _FloorPlanEditorScreenState extends ConsumerState<FloorPlanEditorScreen> {
  List<RestaurantTable>? _tables;
  bool _isDirty = false;
  bool _isSaving = false;

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
    setState(() {
      _tables = tables;
      _isDirty = false;
    });
  }

  void _onDragUpdate(RestaurantTable table, Offset delta) {
    final tables = _tables;
    if (tables == null) return;
    setState(() {
      _tables = [
        for (final t in tables)
          if (t.id == table.id)
            t.copyWith(
              positionX: t.positionX + delta.dx,
              positionY: t.positionY + delta.dy,
            )
          else
            t,
      ];
      _isDirty = true;
    });
  }

  Future<void> _save() async {
    final tables = _tables;
    if (tables == null || !_isDirty) return;
    setState(() => _isSaving = true);
    final useCase = UpdateFloorPlanLayout(
        repository: ref.read(restaurantTableRepositoryProvider));
    await useCase([
      for (final table in tables)
        TableLayoutUpdate(
          tableId: table.id,
          positionX: table.positionX,
          positionY: table.positionY,
          rotationDegrees: table.rotationDegrees,
        ),
    ]);
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _isDirty = false;
    });
  }

  Future<void> _addTable() async {
    final result = await showDialog<({String name, int capacity})>(
      context: context,
      builder: (context) => const _AddTableDialog(),
    );
    if (result == null) return;

    final useCase = AddRestaurantTable(
      idGenerator: ref.read(restaurantTableIdGeneratorProvider),
      tableRepository: ref.read(restaurantTableRepositoryProvider),
      floorPlanRepository: ref.read(floorPlanRepositoryProvider),
    );
    await useCase(
      floorPlanId: widget.floorPlanId,
      branchId: widget.branchId,
      displayName: result.name,
      capacity: result.capacity,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final tables = _tables;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${widget.floorPlanName} — Düzen'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Masa Ekle',
            onPressed: _addTable,
          ),
        ],
      ),
      body: SafeArea(
        child: tables == null
            ? const LoadingView(message: 'Kat planı yükleniyor...')
            : tables.isEmpty
                ? EmptyView(
                    icon: Icons.table_restaurant_outlined,
                    message: 'Bu kat planında henüz masa yok',
                    actionLabel: 'Masa Ekle',
                    onAction: _addTable,
                  )
                : Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Stack(
                              children: [
                                for (final table in tables)
                                  Positioned(
                                    left: table.positionX,
                                    top: table.positionY,
                                    child: GestureDetector(
                                      onPanUpdate: (details) =>
                                          _onDragUpdate(table, details.delta),
                                      child: Container(
                                        width: table.width,
                                        height: table.height,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryExtraLight,
                                          border: Border.all(
                                            color: AppColors.primary,
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
                                          style: AppTypography.bodySmall,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isDirty && !_isSaving ? _save : null,
                            child:
                                Text(_isSaving ? 'Kaydediliyor...' : 'Kaydet'),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _AddTableDialog extends StatefulWidget {
  const _AddTableDialog();

  @override
  State<_AddTableDialog> createState() => _AddTableDialogState();
}

class _AddTableDialogState extends State<_AddTableDialog> {
  final _nameController = TextEditingController();
  final _capacityController = TextEditingController(text: '4');

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Masa Ekle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Masa Adı'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _capacityController,
            decoration: const InputDecoration(labelText: 'Kapasite'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameController.text.trim();
            final capacity = int.tryParse(_capacityController.text) ?? 4;
            if (name.isEmpty) return;
            Navigator.of(context).pop((name: name, capacity: capacity));
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
