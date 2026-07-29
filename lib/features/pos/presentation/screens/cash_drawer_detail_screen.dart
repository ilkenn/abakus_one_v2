import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/open_cash_drawer.dart';
import '../../domain/cash/cash_drawer.dart';
import '../../domain/cash/cash_session.dart';
import '../providers/cash_dependencies_provider.dart';
import 'cash_session_screen.dart';

/// A single [CashDrawer]'s detail view — shows whether it currently has
/// an active [CashSession] and, if not, lets staff open a new one with an
/// opening float amount ("Closed → Open Drawer → Cash Session Active").
class CashDrawerDetailScreen extends ConsumerStatefulWidget {
  const CashDrawerDetailScreen({super.key, required this.drawerId});

  final String drawerId;

  @override
  ConsumerState<CashDrawerDetailScreen> createState() =>
      _CashDrawerDetailScreenState();
}

class _CashDrawerDetailScreenState
    extends ConsumerState<CashDrawerDetailScreen> {
  CashDrawer? _drawer;
  CashSession? _activeSession;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final drawer =
        await ref.read(cashDrawerRepositoryProvider).findById(widget.drawerId);
    final activeSession = await ref
        .read(cashSessionRepositoryProvider)
        .findActiveByDrawerId(widget.drawerId);
    if (!mounted) return;
    setState(() {
      _drawer = drawer;
      _activeSession = activeSession;
    });
  }

  Future<void> _openDrawer() async {
    final amountText = await showDialog<String>(
      context: context,
      builder: (context) => const _OpeningFloatDialog(),
    );
    if (amountText == null) return;
    final wholeAmount = double.tryParse(amountText.replaceAll(',', '.'));
    if (wholeAmount == null) return;

    try {
      await OpenCashDrawer(
        clock: ref.read(clockProvider),
        sessionIdGenerator: ref.read(cashSessionIdGeneratorProvider),
        movementIdGenerator: ref.read(cashMovementIdGeneratorProvider),
        drawerRepository: ref.read(cashDrawerRepositoryProvider),
        sessionRepository: ref.read(cashSessionRepositoryProvider),
        movementRepository: ref.read(cashMovementRepositoryProvider),
        auditRepository: ref.read(cashAuditEntryRepositoryProvider),
      )(
        drawerId: widget.drawerId,
        openedByStaffId: 'staff-1',
        openingFloatAmount: Money.fromLegacyDoubleTry(wholeAmount),
      );
      setState(() => _error = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _error = e.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drawer = _drawer;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(drawer?.name ?? 'Kasa'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: drawer == null
            ? const LoadingView(message: 'Kasa yükleniyor...')
            : Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(drawer.name, style: AppTypography.titleLarge),
                    const SizedBox(height: AppSpacing.md),
                    if (_activeSession != null) ...[
                      Text('Aktif oturum: ${_activeSession!.status.name}',
                          style: AppTypography.bodyMedium),
                      const SizedBox(height: AppSpacing.md),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CashSessionScreen(
                              sessionId: _activeSession!.id,
                            ),
                          ));
                        },
                        child: const Text('Oturumu Görüntüle'),
                      ),
                    ] else ...[
                      Text('Bu kasada aktif oturum yok',
                          style: AppTypography.bodyMedium
                              .copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: AppSpacing.md),
                      ElevatedButton(
                        onPressed: drawer.isActive ? _openDrawer : null,
                        child: const Text('Kasayı Aç'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(_error!,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.error)),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _OpeningFloatDialog extends StatefulWidget {
  const _OpeningFloatDialog();

  @override
  State<_OpeningFloatDialog> createState() => _OpeningFloatDialogState();
}

class _OpeningFloatDialogState extends State<_OpeningFloatDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Açılış Kasası'),
      content: TextField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
            labelText: 'Tutar (${Currency.accountingCurrency.symbol})'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Kasayı Aç'),
        ),
      ],
    );
  }
}
