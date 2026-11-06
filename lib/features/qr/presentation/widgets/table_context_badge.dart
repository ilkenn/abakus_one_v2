import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/config/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/table_guest_session_gateway.dart';
import '../../domain/i18n/guest_locale.dart';
import '../../domain/i18n/qr_flow_strings.dart';
import '../providers/active_table_context_provider.dart';
import '../providers/table_guest_session_dependencies_provider.dart';

/// Compact, single-line "you are ordering at this table" indicator —
/// structurally the same shape as `ActiveOrderBanner` (a small pill row,
/// conditional render, no card chrome), shown wherever the customer needs
/// a persistent reminder of the active table without it eating screen
/// space: [MenuScreen]'s title area, [CartScreen]'s top.
///
/// Renders nothing when [activeTableContextProvider] is `null` — every
/// call site can drop this in unconditionally, immediately after whatever
/// it sits below, with no extra spacing to account for either way (the
/// visible pill carries its own top margin; the invisible
/// [SizedBox.shrink] carries none).
///
/// Dine-in Sprint 3 — also carries the two service-request tap targets
/// (garson çağır / hesap iste): this badge is already the one place every
/// dine-in-facing screen renders while a table is active, so the request
/// buttons live here rather than a new widget with its own conditional-
/// render logic to duplicate.
///
/// Self-Order QR Faz 6 (23-rule plan §8, "Kapanış + Google review") — when
/// the visit ends, this badge also offers a Google review link (if
/// [AppConstants.googleReviewUrl] is configured). **Disclosed scope
/// limitation**: "ended" here means exactly what [isStale] below already
/// meant before this phase — local TTL expiry OR a non-`active`
/// `tableGuestSessions.status` — because the backend has no other signal
/// to distinguish a genuine staff-initiated closure from mere staleness:
/// `functions/src/tableGuestSessionConfig.ts` only ever writes `status:
/// 'active'` today ("Phase 3 wires the others"). A future phase that wires
/// a real closure signal (e.g. a trigger propagating the staff-side
/// `tableSessions` closure into this collection) could narrow this to fire
/// only on a genuine closure.
class TableContextBadge extends ConsumerStatefulWidget {
  const TableContextBadge({super.key});

  @override
  ConsumerState<TableContextBadge> createState() => _TableContextBadgeState();
}

class _TableContextBadgeState extends ConsumerState<TableContextBadge> {
  ServiceRequestType? _busyType;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    // Client Staleness Check — forces a rebuild every minute so the local
    // `expiresAt` comparison (DateTime.now()) is re-evaluated even when
    // nothing about the live Firestore stream changes. A no-op setState
    // when the badge is currently hidden (no active table context).
    _tickTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestService(
    String guestSessionId,
    ServiceRequestType type, {
    String? note,
  }) async {
    if (_busyType != null) return;
    setState(() => _busyType = type);
    try {
      await ref.read(tableGuestSessionGatewayProvider).createServiceRequest(
            guestSessionId: guestSessionId,
            type: type,
            note: note,
          );
      if (!mounted) return;
      final strings = QrFlowStrings.of(ref.read(guestLocaleProvider));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.serviceRequestSent)),
      );
    } on TableGuestSessionException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      final strings = QrFlowStrings.of(ref.read(guestLocaleProvider));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.serviceRequestFailedGeneric)),
      );
    } finally {
      if (mounted) setState(() => _busyType = null);
    }
  }

  /// Self-Order QR Faz 5 (23-rule plan §5) — the single "Talep İlet" entry
  /// point: a bottom sheet listing all 5 options. Tapping "Özel Not"
  /// swaps the sheet's own content for a text field + send button
  /// (`StatefulBuilder`-managed) rather than opening a second, stacked
  /// dialog on top of this one.
  void _openRequestSheet(
    BuildContext context,
    String guestSessionId,
    QrFlowStrings strings,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        bool showNoteInput = false;
        final noteController = TextEditingController();
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void requestAndClose(ServiceRequestType type, {String? note}) {
              Navigator.pop(sheetContext);
              _requestService(guestSessionId, type, note: note);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.requestSheetTitle,
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (!showNoteInput) ...[
                      _RequestOptionRow(
                        icon: Icons.local_cafe_outlined,
                        label: strings.requestTeaOption,
                        onTap: () =>
                            requestAndClose(ServiceRequestType.callWaiter),
                      ),
                      _RequestOptionRow(
                        icon: Icons.receipt_long_outlined,
                        label: strings.requestBillOption,
                        onTap: () =>
                            requestAndClose(ServiceRequestType.requestBill),
                      ),
                      _RequestOptionRow(
                        icon: Icons.cleaning_services_outlined,
                        label: strings.requestAshtrayOrServiceOption,
                        onTap: () => requestAndClose(
                          ServiceRequestType.ashtrayOrService,
                        ),
                      ),
                      _RequestOptionRow(
                        icon: Icons.table_bar_outlined,
                        label: strings.requestClearTableOption,
                        onTap: () =>
                            requestAndClose(ServiceRequestType.clearTable),
                      ),
                      _RequestOptionRow(
                        icon: Icons.sticky_note_2_outlined,
                        label: strings.requestCustomNoteOption,
                        onTap: () => setSheetState(() => showNoteInput = true),
                      ),
                    ] else ...[
                      TextField(
                        controller: noteController,
                        autofocus: true,
                        maxLength: 300,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: strings.customNoteInputHint,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: Text(strings.dismissLabel),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          ElevatedButton(
                            onPressed: () {
                              final note = noteController.text.trim();
                              if (note.isEmpty) return;
                              requestAndClose(
                                ServiceRequestType.customNote,
                                note: note,
                              );
                            },
                            child: Text(strings.customNoteSendLabel),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openGoogleReview(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      final strings = QrFlowStrings.of(ref.read(guestLocaleProvider));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.serviceRequestFailedGeneric)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tableContext = ref.watch(activeTableContextProvider);
    if (tableContext == null) return const SizedBox.shrink();
    final guestSessionId = tableContext.session.id;
    final locale = ref.watch(guestLocaleProvider);
    final strings = QrFlowStrings.of(locale);

    final localExpired = tableContext.session.expiresAt != null &&
        DateTime.now().isAfter(tableContext.session.expiresAt!);
    final liveAsync =
        ref.watch(tableGuestSessionLivenessProvider(guestSessionId));
    // The stream not having delivered data yet (loading/error, e.g. a
    // transient reconnect) must never itself read as stale — only a real
    // snapshot saying so does. `orElse` deliberately stays `false`.
    final liveStale = liveAsync.maybeWhen(
      data: (snapshot) => snapshot == null || !snapshot.isActive,
      orElse: () => false,
    );
    final isStale = localExpired || liveStale;

    final accentColor = isStale ? AppColors.error : AppColors.primary;
    const reviewUrl = AppConstants.googleReviewUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isStale
                  ? AppColors.error.withValues(alpha: 0.1)
                  : AppColors.primaryExtraLight,
              borderRadius: AppRadius.kPill,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isStale
                      ? Icons.warning_amber_rounded
                      : Icons.table_restaurant_rounded,
                  size: 16,
                  color: accentColor,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    isStale
                        ? strings.badgeExpiredMessage
                        : '${tableContext.branchName} · ${tableContext.tableName}',
                    style: AppTypography.labelLarge.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _LanguageSwitcher(current: locale),
                if (!isStale) ...[
                  const SizedBox(width: AppSpacing.sm),
                  _ServiceRequestTapTarget(
                    icon: Icons.campaign_outlined,
                    tooltip: strings.requestHelpTooltip,
                    busy: _busyType != null,
                    onTap: () =>
                        _openRequestSheet(context, guestSessionId, strings),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (isStale && reviewUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: const BoxDecoration(
                color: AppColors.primaryExtraLight,
                borderRadius: AppRadius.kMedium,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      strings.reviewPromptMessage,
                      style: AppTypography.labelLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(
                    onPressed: () => _openGoogleReview(reviewUrl),
                    child: Text(strings.reviewPromptCta),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Self-Order QR Faz 1 — the guest's manual TR/EN override, placed in the
/// one spot every dine-in-facing screen already renders while a table is
/// active (this badge). Only the two [GuestLocale] values with real
/// content are offered — never a flag for a language this phase has no
/// translated strings for, which would misrepresent unfinished work as
/// available.
class _LanguageSwitcher extends ConsumerWidget {
  const _LanguageSwitcher({required this.current});

  final GuestLocale current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final locale in GuestLocale.values) ...[
          _FlagTapTarget(
            locale: locale,
            selected: locale == current,
            onTap: locale == current
                ? null
                : () => ref
                    .read(activeTableContextProvider.notifier)
                    .setLanguage(locale.languageCode),
          ),
          if (locale != GuestLocale.values.last)
            const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _FlagTapTarget extends StatelessWidget {
  const _FlagTapTarget({
    required this.locale,
    required this.selected,
    required this.onTap,
  });

  final GuestLocale locale;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.kPill,
      onTap: onTap,
      child: Opacity(
        opacity: selected ? 1.0 : 0.45,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Text(locale.flagEmoji, style: const TextStyle(fontSize: 14)),
        ),
      ),
    );
  }
}

/// Self-Order QR Faz 5 — one row within the "Talep İlet" bottom sheet.
class _RequestOptionRow extends StatelessWidget {
  const _RequestOptionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.kMedium,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: AppSpacing.md),
              Text(label, style: AppTypography.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceRequestTapTarget extends StatelessWidget {
  const _ServiceRequestTapTarget({
    required this.icon,
    required this.tooltip,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: AppRadius.kPill,
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              : Icon(icon, size: 16, color: AppColors.primary),
        ),
      ),
    );
  }
}
