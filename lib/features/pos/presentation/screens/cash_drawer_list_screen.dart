import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/create_cash_drawer.dart';
import '../../domain/cash/cash_drawer.dart';
import '../providers/cash_dependencies_provider.dart';
import 'cash_drawer_detail_screen.dart';

/// Lists every [CashDrawer] registered at a branch — a branch may have
/// several. Tapping one opens [CashDrawerDetailScreen].
class CashDrawerListScreen extends ConsumerStatefulWidget {
  const CashDrawerListScreen({super.key, required this.branchId});

  final String branchId;

  @override
  ConsumerState<CashDrawerListScreen> createState() =>
      _CashDrawerListScreenState();
}

class _CashDrawerListScreenState extends ConsumerState<CashDrawerListScreen> {
  List<CashDrawer>? _drawers;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final drawers = await ref
        .read(cashDrawerRepositoryProvider)
        .findByBranchId(widget.branchId);
    if (!mounted) return;
    setState(() => _drawers = drawers);
  }

  Future<void> _addDrawer() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NewDrawerNameDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    await CreateCashDrawer(
      idGenerator: ref.read(cashDrawerIdGeneratorProvider),
      repository: ref.read(cashDrawerRepositoryProvider),
    )(branchId: widget.branchId, name: name.trim());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final drawers = _drawers;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kasalar'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Kasa Ekle',
            onPressed: _addDrawer,
          ),
        ],
      ),
      body: SafeArea(
        child: drawers == null
            ? const LoadingView(message: 'Kasalar yükleniyor...')
            : drawers.isEmpty
                ? EmptyView(
                    icon: Icons.point_of_sale_outlined,
                    message: 'Bu şubede henüz kasa yok',
                    actionLabel: 'Kasa Ekle',
                    onAction: _addDrawer,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: drawers.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final drawer = drawers[index];
                      return AppCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => CashDrawerDetailScreen(
                                drawerId: drawer.id,
                              ),
                            ));
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(drawer.name, style: AppTypography.bodyLarge),
                              Text(
                                drawer.isActive ? 'Aktif' : 'Arşivlendi',
                                style: AppTypography.bodySmall.copyWith(
                                  color: drawer.isActive
                                      ? AppColors.success
                                      : AppColors.textSecondary,
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

class _NewDrawerNameDialog extends StatefulWidget {
  const _NewDrawerNameDialog();

  @override
  State<_NewDrawerNameDialog> createState() => _NewDrawerNameDialogState();
}

class _NewDrawerNameDialogState extends State<_NewDrawerNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kasa Ekle'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(labelText: 'Kasa Adı'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
