import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/models/order_model.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../qr/presentation/providers/active_table_context_provider.dart';
import '../../../qr/presentation/providers/table_guest_session_dependencies_provider.dart';
import '../../../qr/presentation/widgets/table_context_badge.dart';
import '../providers/cart_provider.dart';
import 'order_success_screen.dart';

/// Checkout for a "Masada Sipariş" (dine-in QR) order — a separate,
/// self-contained screen rather than a conditional branch woven through
/// the existing (delivery-only) `CheckoutScreen`, so that 900-line screen
/// stays completely untouched and this one only ever asks for what a
/// dine-in order actually needs: no delivery address, no delivery timing,
/// no cutlery/courier preferences, no pickup wording. The existing
/// (non-functional) payment-method selector UI is kept as-is — "preserve
/// the current payment architecture."
///
/// `CartScreen`'s "Siparişi Tamamla" button pushes this screen instead of
/// `CheckoutScreen` whenever `activeTableContextProvider` is non-null.
class DineInCheckoutScreen extends ConsumerStatefulWidget {
  const DineInCheckoutScreen({super.key});

  @override
  ConsumerState<DineInCheckoutScreen> createState() =>
      _DineInCheckoutScreenState();
}

class _DineInCheckoutScreenState extends ConsumerState<DineInCheckoutScreen> {
  static const List<String> _paymentMethods = [
    'Online Kredi/Banka Kartı',
    'Kapıda Kredi Kartı',
    'Kapıda Nakit',
  ];

  late final TextEditingController _noteController;
  String? _selectedPaymentMethod;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    _selectedPaymentMethod = _paymentMethods.first;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitOrder() async {
    // Duplicate-submission guard — the button is also disabled while
    // `_isSubmitting`, this is the second, authoritative line of defense.
    if (_isSubmitting) return;

    final tableContext = ref.read(activeTableContextProvider);
    if (tableContext == null) {
      setState(() {
        _submitError =
            'Masa bilgisi bulunamadı. Lütfen QR kodu tekrar okutarak '
            'başla.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    // Re-verify the session is still active right before submitting —
    // against the real, server-authoritative `tableGuestSessions` record
    // (Phase 3), never the client's own possibly-stale copy. The customer
    // may have been sitting on this screen for a while, and an expired/
    // revoked session must never accept a new order — the Firestore
    // Security Rule re-checks this independently at write time regardless
    // of this call; this exists only to show a friendly message instead
    // of a raw write failure.
    final liveSession = await ref
        .read(tableGuestSessionFirestoreClientProvider)
        .findById(tableContext.session.id);
    if (liveSession == null || !liveSession.isActive) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError =
            'Masa oturumun artık aktif değil. Lütfen QR kodu tekrar okut.';
      });
      return;
    }

    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) {
      setState(() {
        _isSubmitting = false;
        _submitError = 'Sepetin boş.';
      });
      return;
    }

    // Phase 3.1 — canonical customer detection, client-side: `authProvider`
    // is the app's own trustworthy signal for "a real, phone-verified
    // Abaküs customer is signed in" (it never reacts to
    // `signInAnonymously()` — see `TechnicalIdentityProvider`'s doc
    // comment). `guestAuthUid` is always the raw technical uid the active
    // Table Guest Session was actually opened with — set regardless of
    // whether that uid also belongs to a real customer.
    final authSession = ref.read(authProvider).session;
    final technicalUid = ref.read(technicalIdentityProviderProvider).currentUid;
    if (technicalUid == null) {
      // The Table Guest Session couldn't have been opened without a
      // Firebase Auth identity — this should be unreachable in practice.
      // Fail closed rather than submit an order with no ownership at all.
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError =
            'Sipariş gönderilirken bir sorun oluştu. Lütfen tekrar dene.';
      });
      return;
    }
    if (authSession != null &&
        !authSession.isExpired &&
        authSession.uid != technicalUid) {
      // The app believes a specific real customer is signed in, but the
      // actual current Firebase Auth uid disagrees — never guess which
      // one is right. Fail closed rather than risk attaching the wrong
      // customerId to a real order.
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError =
            'Sipariş gönderilirken bir sorun oluştu. Lütfen tekrar dene.';
      });
      return;
    }
    final customerId = (authSession != null && !authSession.isExpired)
        ? authSession.uid
        : null;

    try {
      final order = await ref.read(submitCustomerOrderProvider).call(
            cartItems: cartItems,
            customerId: customerId,
            channel: OrderChannel.dineInQr,
            // The QR-resolved branch/restaurant this table actually
            // belongs to, not submitCustomerOrderProvider's constructor
            // default — closes the "Order.branchId/restaurantId never
            // reflected the scanned table's real scope" gap the Gel Al
            // architecture analysis found (Faz B/B.1). Harmless today
            // (both currently resolve to the same single seeded
            // restaurant/branch) and correct once a second one exists —
            // and firestore.rules' tableGuestSessionMatchesOrderScope()
            // already requires the order's restaurantId to match the
            // session's, so submitting the real value (rather than always
            // 'restaurant-1') is what makes that check meaningful instead
            // of trivially true by coincidence.
            branchId: tableContext.branchId,
            restaurantId: tableContext.restaurantId,
            tableId: tableContext.tableId,
            tableSessionId: tableContext.session.id,
            guestSessionId: tableContext.guestSession.id,
            guestAuthUid: technicalUid,
            // Server-generated snapshot from when this session was opened
            // (Faz R.1C.2) — carried straight through, never re-derived
            // here; `null` for the ordinary walk-in case.
            reservationContextId: tableContext.reservationContextId,
            customerNote: _noteController.text.trim(),
          );

      // Local-only bookkeeping via the existing domain seam
      // (`TableSession.withOrderAdded`) — `tableGuestSessions` has no
      // client-writable order-list field (Cloud-Function/Admin-SDK-write-
      // only), so unlike the pre-Phase-3 in-memory flow this updates only
      // the client-held context, never a server record.
      final updatedSession =
          tableContext.session.withOrderAdded(order.id.value);
      ref.read(activeTableContextProvider.notifier).set(
            tableContext.copyWith(session: updatedSession),
          );

      await ref.read(ordersProvider.notifier).addOrder(
            OrderModel.fromCanonicalOrder(order).copyWith(
              tableName: tableContext.tableName,
            ),
          );
      ref.read(cartProvider.notifier).clearCart();

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => OrderSuccessScreen(
            orderId: order.id.value,
            dineInBranchName: tableContext.branchName,
            dineInTableName: tableContext.tableName,
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError =
            'Sipariş gönderilirken bir sorun oluştu. Lütfen tekrar dene.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final totalPrice = ref.watch(cartTotalPriceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Siparişi Tamamla'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: TableContextBadge(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sipariş Özeti',
                          style: AppTypography.titleMedium
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        for (final item in cartItems) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${item.quantity}x ${item.name}',
                                  style: AppTypography.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${item.totalRowPrice.toStringAsFixed(0)} TL',
                                style: AppTypography.bodyMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                        ],
                        const Divider(height: AppSpacing.lg),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Toplam',
                              style: AppTypography.titleMedium
                                  .copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${totalPrice.toStringAsFixed(0)} TL',
                              style: AppTypography.titleLarge.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Ödeme Yöntemi',
                    style: AppTypography.titleMedium
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  RadioGroup<String>(
                    groupValue: _selectedPaymentMethod,
                    onChanged: (value) =>
                        setState(() => _selectedPaymentMethod = value),
                    child: Column(
                      children: [
                        for (final method in _paymentMethods)
                          RadioListTile<String>(
                            value: method,
                            title: Text(method),
                            contentPadding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Sipariş Notu',
                    style: AppTypography.titleMedium
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _noteController,
                    maxLength: 200,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'Siparişinle ilgili bir not ekle...',
                    ),
                  ),
                  if (_submitError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _submitError!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitOrder,
                    style: ElevatedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Siparişi Ver · ${totalPrice.toStringAsFixed(0)} TL',
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
