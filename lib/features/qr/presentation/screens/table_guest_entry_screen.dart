import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../../core/services/logging/log_level.dart';
import '../../../../core/services/logging/logging_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../navigation/presentation/providers/navigation_provider.dart';
import '../../../navigation/presentation/screens/main_navigation_screen.dart';
import '../../data/table_guest_session_gateway.dart';
import '../providers/active_table_context_provider.dart';
import '../providers/table_guest_session_dependencies_provider.dart';

enum _EntryPhase { resolving, openingSession, error }

/// AP-3 — the non-camera counterpart to [QrScannerScreen]'s in-app scan
/// flow: the exact same server-authoritative table session (the same
/// `resolveTableQrToken`/`openTableGuestSession` Cloud Functions, the same
/// [TableGuestSessionGateway]/[OpenTableGuestSessionFromQrScan] seam) reached
/// by opening a URL/deep link instead of pointing a camera at a physical
/// code.
///
/// **2026-10-29 — zero-friction entry (explicit user decision)**: unlike
/// [TakeawayGuestEntryScreen]'s own "preview, then explicit confirm" shape,
/// this screen opens the real session automatically the instant
/// `resolveTableQrToken` comes back usable — no welcome/confirm screen, no
/// tap. The trade-off this accepts is documented on [_resolve] itself.
///
/// Reached only via [AppRoutes.tableGuestPrefix]/`/table/:token`, a route
/// [AppRouteGuard] never redirects away from onboarding/login/OTP, exactly
/// like the Gel Al QR prefix — a customer opening a table's QR link has not
/// signed in to anything yet.
///
/// The token itself is treated as nothing more than an opaque locator: this
/// screen never parses it or derives organization/restaurant/branch/table
/// identity from its shape — every real fact shown to the customer
/// ([TableQrPreview.tableDisplayName]/[TableQrPreview.branchDisplayName])
/// comes back from the server-authoritative preview call, and the session
/// itself is only ever opened by the same [OpenTableGuestSessionFromQrScan]
/// use case the camera path already uses, so malformed/expired/wrong-
/// tenant/inactive-table/reserved tokens are rejected identically regardless
/// of entry path.
class TableGuestEntryScreen extends ConsumerStatefulWidget {
  final String token;

  const TableGuestEntryScreen({super.key, required this.token});

  @override
  ConsumerState<TableGuestEntryScreen> createState() =>
      _TableGuestEntryScreenState();
}

class _TableGuestEntryScreenState extends ConsumerState<TableGuestEntryScreen> {
  _EntryPhase _phase = _EntryPhase.resolving;
  String? _errorMessage;

  /// Set once `resolveTableQrToken` comes back usable — real, server-
  /// confirmed, never guessed from the token itself. `null` only while
  /// still resolving or on an error (a table name is never shown next to
  /// an error message, since the error means the table was never
  /// confirmed).
  String? _tableDisplayName;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  /// 2026-10-29 — zero-friction dine-in entry: resolves the token, then,
  /// on success, immediately opens the real session and lands on the Menu
  /// tab with no intermediate "Masaya Otur" tap. User-confirmed trade-off:
  /// this removes the deliberate anti-abuse gap that previously meant
  /// `openTableGuestSession` (a real, mutating session-open) never fired
  /// without an explicit human tap — a sufficiently capable link-preview
  /// bot (one that executes JS, not just scrapes HTML) could now open a
  /// real, empty table session just by unfurling a shared QR link. Accepted
  /// explicitly in exchange for true zero-tap entry; `resolveToken` itself
  /// stays a safe, non-mutating preview either way.
  Future<void> _resolve() async {
    setState(() {
      _phase = _EntryPhase.resolving;
      _errorMessage = null;
    });

    if (!ref.read(firebaseReadyProvider)) {
      if (!mounted) return;
      setState(() {
        _phase = _EntryPhase.error;
        _errorMessage =
            'Şu anda bağlantı kurulamıyor. Lütfen daha sonra tekrar dene.';
      });
      return;
    }

    try {
      final preview = await ref
          .read(tableGuestSessionGatewayProvider)
          .resolveToken(widget.token);
      if (!mounted) return;
      if (!preview.isUsable) {
        setState(() {
          _phase = _EntryPhase.error;
          _errorMessage = _messageForStatus(preview.status);
        });
        return;
      }
      setState(() => _tableDisplayName = preview.tableDisplayName);
      await _startOrder();
    } on TableGuestSessionException catch (error, stackTrace) {
      ref.read(loggingServiceProvider).log(
        LogLevel.error,
        'TableGuestEntryScreen._resolve: TableGuestSessionException',
        error: error,
        stackTrace: stackTrace,
        context: {'code': error.code, 'token': widget.token},
      );
      if (!mounted) return;
      setState(() {
        _phase = _EntryPhase.error;
        _errorMessage = _messageForExceptionCode(error.code);
      });
    } catch (error, stackTrace) {
      // 2026-10-29 — logged, not shown raw (CLAUDE.md §9: a thrown
      // exception's own text/stack trace is never surfaced to the user;
      // `ErrorMapper` is the one allowed boundary, and this isn't it). This
      // is exactly the class of failure that previously hid a real cause
      // (Firebase Auth's Anonymous provider disabled on the target
      // project) behind this same generic message — check the browser/
      // Flutter console for this log line before assuming a code bug.
      ref.read(loggingServiceProvider).log(
        LogLevel.error,
        'TableGuestEntryScreen._resolve: unexpected exception',
        error: error,
        stackTrace: stackTrace,
        context: {'token': widget.token},
      );
      if (!mounted) return;
      setState(() {
        _phase = _EntryPhase.error;
        _errorMessage =
            'QR kod okunurken bir sorun oluştu. Lütfen tekrar dene.';
      });
    }
  }

  Future<void> _startOrder() async {
    setState(() => _phase = _EntryPhase.openingSession);

    try {
      final tableContext = await ref
          .read(openTableGuestSessionFromQrScanProvider)
          .call(widget.token);

      ref.read(activeTableContextProvider.notifier).set(tableContext);

      if (!mounted) return;
      // AP-3 wave 7 fix — this used to `pushReplacement` a bare `MenuScreen`
      // (not nested inside `MainNavigationScreen`'s tab shell, reasoning:
      // this entry screen isn't nested inside that Navigator either, so
      // `TableConfirmedScreen`'s in-shell `popUntil(isFirst) + selectTab`
      // has nothing to pop back to here). That "closest analog to home"
      // choice was never actually equivalent: `MenuScreen` on its own has
      // no cart entry point at all (cart is one of the shell's four
      // persistent bottom-nav tabs, not something Menu can navigate to by
      // itself) — a guest could add items but never reach checkout. Push
      // the real shell instead, pre-selecting its Menu tab exactly like the
      // in-shell QR-scanner path does, so Cart/Home/Profile stay reachable.
      ref.read(navigationProvider.notifier).selectTab(AppTab.menu);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
      );
    } on TableGuestSessionException catch (error, stackTrace) {
      ref.read(loggingServiceProvider).log(
        LogLevel.error,
        'TableGuestEntryScreen._startOrder: TableGuestSessionException',
        error: error,
        stackTrace: stackTrace,
        context: {'code': error.code, 'token': widget.token},
      );
      if (!mounted) return;
      setState(() {
        _phase = _EntryPhase.error;
        _errorMessage = _messageForExceptionCode(error.code);
      });
    } catch (error, stackTrace) {
      // See `_resolve`'s identical catch-all comment — the same "a generic
      // message here previously hid a real cause" lesson applies.
      ref.read(loggingServiceProvider).log(
        LogLevel.error,
        'TableGuestEntryScreen._startOrder: unexpected exception',
        error: error,
        stackTrace: stackTrace,
        context: {'token': widget.token},
      );
      if (!mounted) return;
      setState(() {
        _phase = _EntryPhase.error;
        _errorMessage = 'Masa açılırken bir sorun oluştu. Lütfen tekrar dene.';
      });
    }
  }

  /// [status] is [TableQrPreview.status] verbatim — mirrors
  /// `QrScannerScreen._messageFor`'s exact vocabulary.
  String _messageForStatus(String status) {
    return switch (status) {
      'notFound' => 'Bu QR kod tanınmadı. Lütfen masandaki kodu tekrar okut.',
      'invalid' =>
        'Bu QR kod şu anda geçerli değil. Lütfen masandaki kodu kontrol et '
            'veya bir çalışana bildir.',
      'expired' => 'Bu QR kodun süresi dolmuş. Lütfen bir çalışana bildir.',
      'reserved' => 'Bu masa rezerve edilmiştir. Lütfen yetkili ile görüşün.',
      _ => 'Bu QR kod şu anda kullanılamıyor. Lütfen tekrar dene.',
    };
  }

  String _messageForExceptionCode(String code) {
    return switch (code) {
      'not-found' => 'Bu QR kod tanınmadı. Lütfen masandaki kodu tekrar okut.',
      'failed-precondition' =>
        'Bu QR kod şu anda kullanılamıyor. Lütfen bir çalışana bildir.',
      'resource-exhausted' =>
        'Çok fazla deneme yapıldı. Lütfen biraz bekleyip tekrar dene.',
      _ => 'Masa açılırken bir sorun oluştu. Lütfen tekrar dene.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: switch (_phase) {
          _EntryPhase.resolving => const _BrandedWelcome(
              statusMessage: 'QR kod kontrol ediliyor...',
            ),
          _EntryPhase.openingSession => _BrandedWelcome(
              tableDisplayName: _tableDisplayName,
              statusMessage: 'Masa açılıyor...',
            ),
          _EntryPhase.error => ErrorView(
              message: _errorMessage!,
              retryLabel: 'Tekrar Dene',
              onRetry: _resolve,
            ),
        },
      ),
    );
  }
}

/// 2026-10-29 (branding) — the only thing a guest sees during the
/// zero-tap resolve→open transition (normally a few hundred ms). Shows the
/// real brand name, never the technical `abakus_one_v2` package name
/// (CLAUDE.md §1), and the table name only once it's actually known from
/// the server (never guessed/shown early).
class _BrandedWelcome extends StatelessWidget {
  final String? tableDisplayName;
  final String statusMessage;

  const _BrandedWelcome({this.tableDisplayName, required this.statusMessage});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Abaküs Street Food\'a Hoş Geldiniz',
              style: AppTypography.headlineMedium,
              textAlign: TextAlign.center,
            ),
            if (tableDisplayName != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Masa: $tableDisplayName',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              statusMessage,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
