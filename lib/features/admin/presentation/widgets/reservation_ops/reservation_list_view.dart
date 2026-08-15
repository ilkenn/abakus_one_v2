import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../../shared/widgets/feedback/error_view.dart';
import '../../../../../shared/widgets/feedback/loading_view.dart';
import '../../../domain/reservations/admin_reservation_error_messages.dart';
import '../../../data/admin_reservation_gateway.dart';
import '../../providers/admin_reservation_list_provider.dart';
import 'reservation_list_card.dart';

/// The "Bugün"/"Yaklaşan"/"Tümü" tab content — Faz R.3A §2. Each tab is
/// just a different [AdminReservationListQuery] date range/status filter
/// over the exact same list widget; no separate screen per tab.
class ReservationListView extends ConsumerWidget {
  const ReservationListView({
    super.key,
    required this.query,
    required this.onSelect,
    required this.emptyMessage,
  });

  final AdminReservationListQuery query;
  final ValueChanged<String> onSelect;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(adminReservationListProvider(query));

    return pageAsync.when(
      loading: () => const LoadingView(message: 'Rezervasyonlar yükleniyor...'),
      error: (error, stackTrace) => ErrorView(
        message: error is AdminReservationException
            ? adminReservationErrorMessage(error)
            : 'Rezervasyonlar yüklenirken bir sorun oluştu.',
        retryLabel: 'Tekrar Dene',
        onRetry: () => ref.invalidate(adminReservationListProvider(query)),
      ),
      data: (page) {
        if (page.reservations.isEmpty) {
          return EmptyView(
              icon: Icons.event_busy_rounded, message: emptyMessage);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount:
              page.reservations.length + (page.nextCursor != null ? 1 : 0),
          separatorBuilder: (context, index) =>
              const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            if (index >= page.reservations.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: TextButton(
                    onPressed: () => ref.read(adminReservationListProvider(
                      AdminReservationListQuery(
                        dateFrom: query.dateFrom,
                        dateTo: query.dateTo,
                        statuses: query.statuses,
                        areaId: query.areaId,
                        cursor: page.nextCursor,
                        pageSize: query.pageSize,
                      ),
                    ).future),
                    child: const Text('Daha Fazla Yükle'),
                  ),
                ),
              );
            }
            final reservation = page.reservations[index];
            return ReservationListCard(
              reservation: reservation,
              onTap: () => onSelect(reservation.id),
            );
          },
        );
      },
    );
  }
}

/// A small, reusable summary strip shown above a list — "N rezervasyon".
class ReservationListCountLabel extends StatelessWidget {
  const ReservationListCountLabel({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$count rezervasyon',
      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
    );
  }
}
