import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/presentation/widgets/role_gate.dart';
import '../providers/admin_reservation_list_provider.dart';
import '../widgets/reservation_ops/reservation_calendar_view.dart';
import '../widgets/reservation_ops/reservation_detail_panel.dart';
import '../widgets/reservation_ops/reservation_list_view.dart';
import 'branch_operating_hours_screen.dart';

/// Faz R.3A §1 — the admin "Rezervasyonlar" module entry point. Desktop
/// (>=1000px, matching `AdminShellScreen`'s own breakpoint exactly):
/// list/calendar + a selected-reservation detail side panel. Tablet
/// (600-1000px): same split, narrower. Mobile (<600px): list only, detail
/// pushes as its own screen — `AppBreakpoints`/`AdminShellScreen`'s own
/// "do not render the mobile bottom-nav layout on desktop" rule extended
/// to this module's own list/detail relationship.
class ReservationOperationsScreen extends StatefulWidget {
  const ReservationOperationsScreen({super.key});

  @override
  State<ReservationOperationsScreen> createState() =>
      _ReservationOperationsScreenState();
}

enum _ReservationTab { today, upcoming, all, calendar }

class _ReservationOperationsScreenState
    extends State<ReservationOperationsScreen> {
  _ReservationTab _tab = _ReservationTab.today;
  String? _selectedReservationId;

  AdminReservationListQuery _queryForTab(_ReservationTab tab) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    switch (tab) {
      case _ReservationTab.today:
        return AdminReservationListQuery(
          dateFrom: startOfToday,
          dateTo: DateTime(now.year, now.month, now.day, 23, 59, 59),
          pageSize: 100,
        );
      case _ReservationTab.upcoming:
        return AdminReservationListQuery(
          dateFrom: startOfToday.add(const Duration(days: 1)),
          dateTo: startOfToday.add(const Duration(days: 31)),
          pageSize: 100,
        );
      case _ReservationTab.all:
        return AdminReservationListQuery(
          dateFrom: startOfToday.subtract(const Duration(days: 31)),
          dateTo: startOfToday.add(const Duration(days: 31)),
          pageSize: 100,
        );
      case _ReservationTab.calendar:
        return AdminReservationListQuery(
            dateFrom: startOfToday, dateTo: startOfToday);
    }
  }

  void _selectReservation(
      BuildContext context, String reservationId, bool isDesktopOrTablet) {
    if (isDesktopOrTablet) {
      setState(() => _selectedReservationId = reservationId);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Rezervasyon Detayı')),
          body: ReservationDetailPanel(reservationId: reservationId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktopOrTablet = width >= 600;
        final isDesktop = width >= 1000;

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _buildTopBar(context),
                _buildTabBar(),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: isDesktop ? 3 : 1,
                        child: _buildTabContent(isDesktopOrTablet),
                      ),
                      if (isDesktopOrTablet &&
                          _selectedReservationId != null) ...[
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: isDesktop ? 420 : 340,
                          child: ReservationDetailPanel(
                            key: ValueKey(_selectedReservationId),
                            reservationId: _selectedReservationId!,
                            onClose: () =>
                                setState(() => _selectedReservationId = null),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
      child: Row(
        children: [
          const Expanded(
            child: Text('Rezervasyonlar', style: AppTypography.headlineMedium),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                // Faz R.3A.1 — branch hours are a manageBranch-scoped
                // destination, distinct from this screen's own
                // manageReservations gate; reached here only via a raw
                // Navigator.push (no go_router route), so the destination
                // itself is the actual security boundary, not this button.
                builder: (context) => RoleGate.forAction(
                  PosAuthorizedAction.manageBranch,
                  child: const BranchOperatingHoursScreen(),
                ),
              ),
            ),
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: const Text('Çalışma Saatleri'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          _TabChip(
            label: 'Bugün',
            selected: _tab == _ReservationTab.today,
            onTap: () => setState(() => _tab = _ReservationTab.today),
          ),
          _TabChip(
            label: 'Yaklaşan',
            selected: _tab == _ReservationTab.upcoming,
            onTap: () => setState(() => _tab = _ReservationTab.upcoming),
          ),
          _TabChip(
            label: 'Tümü',
            selected: _tab == _ReservationTab.all,
            onTap: () => setState(() => _tab = _ReservationTab.all),
          ),
          _TabChip(
            label: 'Takvim',
            selected: _tab == _ReservationTab.calendar,
            onTap: () => setState(() => _tab = _ReservationTab.calendar),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(bool isDesktopOrTablet) {
    if (_tab == _ReservationTab.calendar) {
      return ReservationCalendarView(
        onSelect: (id) => _selectReservation(context, id, isDesktopOrTablet),
      );
    }
    final labels = {
      _ReservationTab.today: 'Bugün için rezervasyon bulunmuyor.',
      _ReservationTab.upcoming: 'Yaklaşan rezervasyon bulunmuyor.',
      _ReservationTab.all: 'Rezervasyon bulunmuyor.',
    };
    return ReservationListView(
      key: ValueKey(_tab),
      query: _queryForTab(_tab),
      emptyMessage: labels[_tab]!,
      onSelect: (id) => _selectReservation(context, id, isDesktopOrTablet),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withValues(alpha: 0.12),
      labelStyle: AppTypography.labelMedium.copyWith(
        color: selected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
      ),
      backgroundColor: AppColors.surface,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
    );
  }
}
