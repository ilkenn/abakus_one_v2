import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/mark_kitchen_ticket_line_ready.dart';
import '../../domain/kitchen/kitchen_ticket.dart';
import '../../domain/kitchen/kitchen_ticket_line.dart';
import '../providers/kitchen_ticket_dependencies_provider.dart';

/// The main kitchen screen (KDS foundation) — every fired [KitchenTicket]
/// for one branch, on a single queue by default. Station-based filtering
/// is present in the UI (per the requirement that the infrastructure be
/// retained for future branches) but only "Tümü" is selectable this
/// sprint — every product, including drinks and cold items, always
/// appears together for the current Abaküs configuration.
///
/// Elapsed time is computed at load/refresh time, not live-ticking via a
/// periodic timer — a deliberate simplification: a `Timer.periodic`
/// rebuild would fight `tester.pumpAndSettle()` in widget tests (a well-
/// known Flutter testing hazard). Staff refresh via the app bar action or
/// any action that reloads the list.
class KitchenDisplayScreen extends ConsumerStatefulWidget {
  const KitchenDisplayScreen({super.key, required this.branchId});

  final String branchId;

  @override
  ConsumerState<KitchenDisplayScreen> createState() =>
      _KitchenDisplayScreenState();
}

class _KitchenDisplayScreenState extends ConsumerState<KitchenDisplayScreen> {
  List<KitchenTicket>? _tickets;
  DateTime? _now;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final tickets = await ref
        .read(kitchenTicketRepositoryProvider)
        .findActiveByBranch(widget.branchId);
    if (!mounted) return;
    setState(() {
      _tickets = tickets;
      _now = ref.read(clockProvider).now();
    });
  }

  Future<void> _markLineReady(KitchenTicket ticket, String lineId) async {
    final useCase = MarkKitchenTicketLineReady(
      clock: ref.read(clockProvider),
      repository: ref.read(kitchenTicketRepositoryProvider),
    );
    await useCase(ticketId: ticket.id, lineId: lineId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final tickets = _tickets;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mutfak Ekranı'),
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
        child: tickets == null
            ? const LoadingView(message: 'Fişler yükleniyor...')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                    child: Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        ChoiceChip(label: Text('Tümü'), selected: true),
                        ChoiceChip(
                          label: Text('Sıcak'),
                          selected: false,
                          onSelected: null,
                        ),
                        ChoiceChip(
                          label: Text('Soğuk'),
                          selected: false,
                          onSelected: null,
                        ),
                        ChoiceChip(
                          label: Text('İçecek'),
                          selected: false,
                          onSelected: null,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: tickets.isEmpty
                        ? const EmptyView(
                            icon: Icons.receipt_long_outlined,
                            message: 'Bekleyen fiş yok',
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 320,
                              mainAxisSpacing: AppSpacing.md,
                              crossAxisSpacing: AppSpacing.md,
                              childAspectRatio: 0.8,
                            ),
                            itemCount: tickets.length,
                            itemBuilder: (context, index) {
                              return _TicketCard(
                                ticket: tickets[index],
                                now: _now ?? DateTime.now(),
                                onLineTap: (lineId) =>
                                    _markLineReady(tickets[index], lineId),
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

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.now,
    required this.onLineTap,
  });

  final KitchenTicket ticket;
  final DateTime now;
  final ValueChanged<String> onLineTap;

  @override
  Widget build(BuildContext context) {
    final elapsedMinutes = now.difference(ticket.firedAt).inMinutes;
    final isDelayed = elapsedMinutes >= 10;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderColor: isDelayed ? AppColors.error : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  ticket.header.orderNumber,
                  style: AppTypography.bodyLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${elapsedMinutes}dk',
                style: AppTypography.bodySmall.copyWith(
                  color: isDelayed ? AppColors.error : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          Text(
            '${ticket.header.channelLabel} • ${ticket.type.name}${ticket.isCopy ? ' • KOPYA' : ''}',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView(
              children: [
                for (final line in ticket.lines)
                  _LineTile(
                    line: line,
                    isReady: ticket.completedLineIds.contains(line.id),
                    onTap: () => onLineTap(line.id),
                  ),
              ],
            ),
          ),
          if (ticket.isFullyReady)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              decoration: const BoxDecoration(
                color: AppColors.success,
                borderRadius: AppRadius.kSmall,
              ),
              alignment: Alignment.center,
              child: const Text('HAZIR',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.isReady,
    required this.onTap,
  });

  final KitchenTicketLine line;
  final bool isReady;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isReady ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: isReady ? AppColors.success : AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${line.quantity}x ${line.productName}',
                    style: AppTypography.bodyMedium.copyWith(
                      decoration: isReady ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  for (final ingredient in line.ingredientSummary)
                    Text('- $ingredient',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                  if (line.note.isNotEmpty)
                    Text(line.note,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.warning)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
