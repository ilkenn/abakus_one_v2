import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/money.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../data/dine_in_counter_proposal_gateway.dart';
import '../../domain/models/dine_in_counter_proposal.dart';
import '../../domain/models/dine_in_line_status.dart';
import '../../domain/models/order_channel.dart';
import '../providers/dine_in_counter_proposal_dependencies_provider.dart';

/// Shows each dine-in QR order line's staff-approval status, and a full
/// accept/reject card for any line currently carrying a pending
/// replacement proposal — AP-3 continuation.
///
/// Polls [canonicalOrderByIdProvider] on a fixed interval while mounted
/// (there is no live order stream in this codebase — see that provider's
/// own doc comment) so a cashier's accept/reject/proposal decision reaches
/// the customer without a manual refresh. Renders nothing at all for a
/// non-[OrderChannel.dineInQr] order, or once every line is
/// [DineInLineStatus.accepted] — this section is meant to disappear once
/// there is nothing left needing the customer's attention.
class DineInLineApprovalSection extends ConsumerStatefulWidget {
  final String orderId;
  final OrderChannel channel;

  const DineInLineApprovalSection({
    super.key,
    required this.orderId,
    required this.channel,
  });

  @override
  ConsumerState<DineInLineApprovalSection> createState() =>
      _DineInLineApprovalSectionState();
}

class _DineInLineApprovalSectionState
    extends ConsumerState<DineInLineApprovalSection> {
  static const _pollInterval = Duration(seconds: 6);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.channel == OrderChannel.dineInQr) {
      _timer = Timer.periodic(_pollInterval, (_) {
        if (mounted) {
          ref.invalidate(canonicalOrderByIdProvider(widget.orderId));
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channel != OrderChannel.dineInQr) {
      return const SizedBox.shrink();
    }
    final orderAsync = ref.watch(canonicalOrderByIdProvider(widget.orderId));
    return orderAsync.when(
      // A polling refresh's brief loading state must never hide the
      // already-shown card, and an initial load with nothing to show yet
      // must never render an empty flash of layout — both collapse to
      // nothing.
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (order) {
        if (order == null) return const SizedBox.shrink();
        final attentionNeeded = order.lineApprovalStates
            .where((s) => s.status != DineInLineStatus.accepted)
            .toList()
          ..sort((a, b) => a.lineIndex.compareTo(b.lineIndex));
        if (attentionNeeded.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final state in attentionNeeded) ...[
                if (state.status == DineInLineStatus.proposedChange &&
                    state.counterProposal != null &&
                    state.counterProposal!.isPending)
                  _CounterProposalCard(
                    orderId: widget.orderId,
                    lineIndex: state.lineIndex,
                    originalProductName:
                        order.lines[state.lineIndex].productName,
                    proposal: state.counterProposal!,
                  )
                else
                  _LineStatusNotice(
                    productName: order.lines[state.lineIndex].productName,
                    status: state.status,
                  ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        );
      },
    );
  }
}

String _formatMoney(Money money) {
  final major = money.minorUnits / money.currency.minorUnitsPerWhole;
  final sign = major < 0 ? '-' : '';
  return '$sign${major.abs().toStringAsFixed(0)} TL';
}

class _LineStatusNotice extends StatelessWidget {
  final String productName;
  final DineInLineStatus status;

  const _LineStatusNotice({required this.productName, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      DineInLineStatus.pendingApproval => (
          'Onay bekliyor',
          AppColors.warning,
          Icons.hourglass_top_rounded,
        ),
      DineInLineStatus.rejected => (
          'Reddedildi',
          AppColors.error,
          Icons.cancel_outlined,
        ),
      // A resolved (accepted/rejected) counter-proposal with no longer-
      // pending status still shows here briefly via the enclosing filter
      // only if `status` itself hasn't caught up to `accepted` yet — kept
      // as a safe, honest fallback label rather than an unreachable throw.
      DineInLineStatus.proposedChange || DineInLineStatus.accepted => (
          'Güncelleniyor',
          AppColors.textSecondary,
          Icons.sync_rounded,
        ),
    };

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(productName, style: AppTypography.bodyMedium),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: AppRadius.kPill,
            ),
            child: Text(
              label,
              style: AppTypography.labelLarge
                  .copyWith(color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterProposalCard extends ConsumerStatefulWidget {
  final String orderId;
  final int lineIndex;
  final String originalProductName;
  final DineInCounterProposal proposal;

  const _CounterProposalCard({
    required this.orderId,
    required this.lineIndex,
    required this.originalProductName,
    required this.proposal,
  });

  @override
  ConsumerState<_CounterProposalCard> createState() =>
      _CounterProposalCardState();
}

class _CounterProposalCardState extends ConsumerState<_CounterProposalCard> {
  bool _responding = false;
  String? _error;

  Future<void> _respond(bool accept) async {
    if (_responding) return;
    setState(() {
      _responding = true;
      _error = null;
    });
    try {
      await ref.read(dineInCounterProposalGatewayProvider).respond(
            orderId: widget.orderId,
            lineIndex: widget.lineIndex,
            accept: accept,
          );
      if (!mounted) return;
      ref.invalidate(canonicalOrderByIdProvider(widget.orderId));
      // Deliberately NOT also invalidating `ordersProvider` here: it's a
      // one-time `findByCustomerId` load, and that query is documented
      // (`CanonicalOrderRepository.findByCustomerId`) to return nothing at
      // all for a guest/dine-in-QR order (`Order.customerId == null` is
      // never queryable that way) — the only reason a guest's own order is
      // visible there at all is `OrdersNotifier.addOrder`'s one-time
      // write-through bridge from checkout. Invalidating would force a
      // real requery that wipes that bridge and makes the order disappear
      // from "Sipariş Takibi" entirely for exactly the guest customers
      // this feature serves (confirmed by testing this exact sequence).
      // Net effect: `ActiveOrderScreen`'s "Sipariş İçeriği"/"Ödeme Özeti"
      // sections (backed by the separate `OrderModel.items` snapshot) stay
      // stale after an accept/reject — a real, known, disclosed gap (see
      // `docs/visual_evidence/ap3/README.md`), left alone rather than
      // "fixed" into a worse regression.
    } on RespondToDineInCounterProposalException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final proposal = widget.proposal;
    final differenceLabel = proposal.differenceFromOriginal.minorUnits == 0
        ? 'Fiyat farkı yok'
        : (proposal.differenceFromOriginal.minorUnits > 0
            ? '+${_formatMoney(proposal.differenceFromOriginal)}'
            : _formatMoney(proposal.differenceFromOriginal));
    final differenceColor = proposal.differenceFromOriginal.minorUnits > 0
        ? AppColors.error
        : (proposal.differenceFromOriginal.minorUnits < 0
            ? AppColors.primary
            : AppColors.textSecondary);
    final minutesLeft = proposal.expiresAt.difference(DateTime.now()).inMinutes;

    return AppCard(
      borderColor: AppColors.accent.withValues(alpha: 0.4),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz_rounded, color: AppColors.accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Değişiklik Önerisi',
                  style: AppTypography.titleMedium
                      .copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '"${widget.originalProductName}" yerine aşağıdaki ürün öneriliyor:',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: AppRadius.kMedium,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${proposal.proposedQuantity}x ${proposal.proposedProductName}',
                        style: AppTypography.bodyLarge
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      _formatMoney(proposal.proposedLineTotal),
                      style: AppTypography.bodyLarge
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (proposal.proposedModifiers.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    proposal.proposedModifiers
                        .map((m) => m.optionName)
                        .join(' · '),
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Fiyat farkı',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
              Text(
                differenceLabel,
                style: AppTypography.bodyMedium.copyWith(
                  color: differenceColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            proposal.reasonMessage,
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            minutesLeft > 0
                ? 'Bu öneri yaklaşık $minutesLeft dakika içinde geçerliliğini yitirecek.'
                : 'Bu önerinin süresi dolmak üzere.',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _responding ? null : () => _respond(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  ),
                  child: const Text('Reddet'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton(
                  onPressed: _responding ? null : () => _respond(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  ),
                  child: _responding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Kabul Et'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
