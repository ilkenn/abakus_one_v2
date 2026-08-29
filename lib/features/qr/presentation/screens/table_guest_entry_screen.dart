import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../menu/presentation/screens/menu_screen.dart';
import '../../data/table_guest_session_gateway.dart';
import '../providers/active_table_context_provider.dart';
import '../providers/table_guest_session_dependencies_provider.dart';

enum _EntryPhase { resolving, previewReady, openingSession, error }

/// AP-3 — the non-camera counterpart to [QrScannerScreen]'s in-app scan
/// flow: the exact same server-authoritative table session (the same
/// `resolveTableQrToken`/`openTableGuestSession` Cloud Functions, the same
/// [TableGuestSessionGateway]/[OpenTableGuestSessionFromQrScan] seam) reached
/// by opening a URL/deep link instead of pointing a camera at a physical
/// code. Structurally mirrors [TakeawayGuestEntryScreen] exactly (same
/// two-round-trip "preview, then explicit confirm" shape, same phase enum,
/// same error-message vocabulary) — see that screen's own doc comment for
/// the full rationale of why confirmation is never automatic.
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
  String? _tableDisplayName;
  String? _branchDisplayName;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

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
      setState(() {
        _phase = _EntryPhase.previewReady;
        _tableDisplayName = preview.tableDisplayName;
        _branchDisplayName = preview.branchDisplayName;
      });
    } catch (_) {
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
      // Mirrors `TakeawayGuestEntryScreen._startOrder`'s exact reasoning:
      // this entry screen isn't nested inside `MainNavigationScreen`'s own
      // Navigator (it's a top-level deep link), so `TableConfirmedScreen`'s
      // `popUntil(isFirst) + selectTab` — built for the in-shell camera-scan
      // push — would pop back to nothing useful here. Landing directly on
      // `MenuScreen`, which already reads `activeTableContextProvider` for
      // its dine-in scope, is the same "closest analog to home" choice the
      // takeaway entry screen already makes.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MenuScreen()),
      );
    } on TableGuestSessionException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _EntryPhase.error;
        _errorMessage = _messageForExceptionCode(error.code);
      });
    } catch (_) {
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
      _ => 'Masa açılırken bir sorun oluştu. Lütfen tekrar dene.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('QR ile Masaya Otur')),
      body: SafeArea(
        child: switch (_phase) {
          _EntryPhase.resolving =>
            const LoadingView(message: 'QR kod kontrol ediliyor...'),
          _EntryPhase.openingSession =>
            const LoadingView(message: 'Masa açılıyor...'),
          _EntryPhase.error => ErrorView(
              message: _errorMessage!,
              retryLabel: 'Tekrar Dene',
              onRetry: _resolve,
            ),
          _EntryPhase.previewReady => _PreviewConfirm(
              tableDisplayName: _tableDisplayName ?? '',
              branchDisplayName: _branchDisplayName ?? '',
              onConfirm: _startOrder,
            ),
        },
      ),
    );
  }
}

class _PreviewConfirm extends StatelessWidget {
  final String tableDisplayName;
  final String branchDisplayName;
  final VoidCallback onConfirm;

  const _PreviewConfirm({
    required this.tableDisplayName,
    required this.branchDisplayName,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.table_restaurant_rounded,
                size: 56,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              branchDisplayName,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              tableDisplayName,
              style: AppTypography.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Bu masaya oturmak üzeresin. Hesap açmana veya giriş yapmana '
              'gerek yok.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onConfirm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                  ),
                ),
                child: const Text('Masaya Otur'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
