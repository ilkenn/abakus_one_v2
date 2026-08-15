import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../cart/presentation/providers/shopping_channel_provider.dart';
import '../../../menu/presentation/screens/menu_screen.dart';
import '../../data/takeaway_guest_session_gateway.dart';
import '../providers/takeaway_guest_dependencies_provider.dart';

enum _EntryPhase { resolving, previewReady, openingSession, error }

/// Public, login-free Gel Al QR guest entry point — Faz D.4. Reached only
/// via [AppRoutes.takeawayGuest]/`/takeaway/:token`, a route
/// [AppRouteGuard] deliberately never redirects away from onboarding/
/// login/OTP, regardless of the caller's current session state (none, a
/// real customer, or an existing anonymous guest).
///
/// Two server round-trips, in order, exactly matching the architecture's
/// own "preview before commit" contract:
/// 1. [TakeawayGuestSessionGateway.resolveToken] — a public, unauthenticated
///    preview. Only [TakeawayQrPreview.branchDisplayName] is ever shown to
///    the customer; this screen never derives organization/restaurant/
///    branch identity from the raw token itself.
/// 2. On explicit confirmation only (never automatically, so a stray URL
///    prefetch — a chat app's link-preview bot, for instance — can never
///    silently mint a real anonymous session) —
///    [OpenTakeawayGuestSessionFromQr], which establishes the technical
///    identity ([TechnicalIdentityProvider.ensureSignedIn], reusing any
///    existing session, real or guest, rather than overwriting it) and
///    opens the real, server-authoritative `takeawayGuestSessions` record.
///
/// On success: [takeawayGuestContextProvider] is set, then
/// [shoppingChannelProvider] is switched to [OrderChannel.takeaway] with
/// the session's own server-derived branch scope — the exact same
/// two-step [TakeawayBranchSelectionScreen] already performs for the
/// authenticated flow — before pushing [MenuScreen] directly (this screen
/// is not inside [MainNavigationScreen]'s tab shell, so there is no
/// "select the menu tab" step the way `TableConfirmedScreen` does).
class TakeawayGuestEntryScreen extends ConsumerStatefulWidget {
  final String token;

  const TakeawayGuestEntryScreen({super.key, required this.token});

  @override
  ConsumerState<TakeawayGuestEntryScreen> createState() =>
      _TakeawayGuestEntryScreenState();
}

class _TakeawayGuestEntryScreenState
    extends ConsumerState<TakeawayGuestEntryScreen> {
  _EntryPhase _phase = _EntryPhase.resolving;
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
          .read(takeawayGuestSessionGatewayProvider)
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
      final guestContext = await ref
          .read(openTakeawayGuestSessionFromQrProvider)
          .call(widget.token);

      ref.read(takeawayGuestContextProvider.notifier).set(guestContext);
      ref.read(shoppingChannelProvider.notifier).selectTakeaway(
            restaurantId: guestContext.restaurantId,
            branchId: guestContext.branchId,
            branchDisplayName: guestContext.branchDisplayName,
          );

      if (!mounted) return;
      // `pushReplacement`, not `push`: this entry screen's own state
      // (`_phase`) is meaningless once a session is open — a customer
      // popping back to "Ana Sayfaya Dön" from a later success screen
      // should land on the branch's menu (this flow's closest analog to
      // "home"), never back on a stale "Sipariş başlatılıyor..." spinner
      // this screen would otherwise still be showing.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MenuScreen()),
      );
    } on TakeawayGuestSessionException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _EntryPhase.error;
        _errorMessage = _messageForExceptionCode(error.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _EntryPhase.error;
        _errorMessage =
            'Sipariş başlatılırken bir sorun oluştu. Lütfen tekrar dene.';
      });
    }
  }

  /// [status] is [TakeawayQrPreview.status] verbatim — mirrors
  /// `QrScannerScreen._messageFor`'s exact vocabulary/reasoning.
  String _messageForStatus(String status) {
    return switch (status) {
      'notFound' => 'Bu QR kod tanınmadı. Lütfen kasadaki QR kodu tekrar okut.',
      'invalid' =>
        'Bu QR kod şu anda geçerli değil. Lütfen bir çalışana bildir.',
      'expired' => 'Bu QR kodun süresi dolmuş. Lütfen bir çalışana bildir.',
      _ => 'Bu QR kod şu anda kullanılamıyor. Lütfen tekrar dene.',
    };
  }

  String _messageForExceptionCode(String code) {
    return switch (code) {
      'not-found' =>
        'Bu QR kod tanınmadı. Lütfen kasadaki QR kodu tekrar okut.',
      'failed-precondition' =>
        'Bu QR kod şu anda kullanılamıyor. Lütfen bir çalışana bildir.',
      _ => 'Sipariş başlatılırken bir sorun oluştu. Lütfen tekrar dene.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Gel Al')),
      body: SafeArea(
        child: switch (_phase) {
          _EntryPhase.resolving =>
            const LoadingView(message: 'QR kod kontrol ediliyor...'),
          _EntryPhase.openingSession =>
            const LoadingView(message: 'Sipariş başlatılıyor...'),
          _EntryPhase.error => ErrorView(
              message: _errorMessage!,
              retryLabel: 'Tekrar Dene',
              onRetry: _resolve,
            ),
          _EntryPhase.previewReady => _PreviewConfirm(
              branchDisplayName: _branchDisplayName!,
              onConfirm: _startOrder,
            ),
        },
      ),
    );
  }
}

class _PreviewConfirm extends StatelessWidget {
  final String branchDisplayName;
  final VoidCallback onConfirm;

  const _PreviewConfirm({
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
                Icons.storefront_rounded,
                size: 56,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              branchDisplayName,
              style: AppTypography.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Bu şubeden Gel Al siparişi vermek üzeresin. Hesap açmana veya '
              'giriş yapmana gerek yok.',
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
                child: const Text('Siparişe Başla'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
