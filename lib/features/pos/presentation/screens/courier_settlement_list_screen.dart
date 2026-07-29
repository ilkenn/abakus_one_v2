import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/open_courier_settlement_session.dart';
import '../../domain/courier_settlement/courier_settlement_session.dart';
import '../providers/courier_settlement_dependencies_provider.dart';
import 'courier_settlement_detail_screen.dart';

/// Lists a courier's own [CourierSettlementSession]s — "Courier Shift"
/// entry point. Tapping one opens [CourierSettlementDetailScreen];
/// "Vardiya Başlat" opens a new session when the courier has none active.
class CourierSettlementListScreen extends ConsumerStatefulWidget {
  const CourierSettlementListScreen({super.key, required this.courierId});

  final String courierId;

  @override
  ConsumerState<CourierSettlementListScreen> createState() =>
      _CourierSettlementListScreenState();
}

class _CourierSettlementListScreenState
    extends ConsumerState<CourierSettlementListScreen> {
  List<CourierSettlementSession>? _sessions;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final sessions = await ref
        .read(courierSettlementSessionRepositoryProvider)
        .findByCourierId(widget.courierId);
    if (!mounted) return;
    setState(() => _sessions = sessions.reversed.toList());
  }

  Future<void> _startShift() async {
    try {
      await OpenCourierSettlementSession(
        clock: ref.read(clockProvider),
        idGenerator: ref.read(courierSettlementSessionIdGeneratorProvider),
        sessionRepository: ref.read(courierSettlementSessionRepositoryProvider),
      )(courierId: widget.courierId, branchId: 'branch-1');
      setState(() => _error = null);
      await _load();
    } on BusinessRuleViolation catch (e) {
      setState(() => _error = e.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kurye Vardiyalarım'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Vardiya Başlat',
            onPressed: _startShift,
          ),
        ],
      ),
      body: SafeArea(
        child: sessions == null
            ? const LoadingView(message: 'Vardiyalar yükleniyor...')
            : Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(_error!,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.error)),
                    ),
                  Expanded(
                    child: sessions.isEmpty
                        ? EmptyView(
                            icon: Icons.delivery_dining_outlined,
                            message: 'Henüz vardiya yok',
                            actionLabel: 'Vardiya Başlat',
                            onAction: _startShift,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: sessions.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final session = sessions[index];
                              return AppCard(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: InkWell(
                                  onTap: () {
                                    Navigator.of(context)
                                        .push(MaterialPageRoute(
                                      builder: (_) =>
                                          CourierSettlementDetailScreen(
                                        settlementSessionId: session.id,
                                      ),
                                    ));
                                  },
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(session.id,
                                          style: AppTypography.bodyLarge),
                                      Text(
                                        session.status.name,
                                        style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
