import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/auth/real_customer_check.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/models/cart_item.dart';
import '../../../loyalty/domain/models/loyalty_reward.dart';
import '../../../loyalty/presentation/providers/loyalty_providers.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../orders/domain/models/order_model.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../qr/presentation/providers/active_table_context_provider.dart';
import '../../../qr/presentation/providers/table_guest_session_dependencies_provider.dart';
import '../../../qr/presentation/widgets/table_context_badge.dart';
import '../../data/submit_dine_in_order_gateway.dart';
import '../providers/cart_provider.dart';
import '../providers/dine_in_order_dependencies_provider.dart';
import '../widgets/catalog_reward_card.dart';
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
/// Boncuk Loyalty Program P7-D.1 (2026-08-24) — submission now goes
/// through the server-authoritative `submitDineInOrder` Cloud Function
/// (`SubmitDineInOrderGateway`), never a direct client Firestore write.
/// Catalog-reward selection ([CatalogRewardCard]) is offered ONLY to a
/// real, phone-verified customer ([isRealCustomer]) — an anonymous table
/// guest sees no reward/Loyalty control of any kind, not even a disabled
/// one (never leaks account-existence/balance information a guest has no
/// business seeing). There is no cash-Boncuk-redemption control on this
/// screen at all — dine-in cash Boncuk redemption is not a supported
/// product behavior (`submitDineInOrder.ts`'s own doc comment,
/// BR-LOYALTY-019).
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
  late final String _submissionKey;
  String? _selectedPaymentMethod;
  String? _selectedRewardId;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    _selectedPaymentMethod = _paymentMethods.first;
    _submissionKey = DateTime.now().microsecondsSinceEpoch.toString();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool _isBowlCartItem(CartItem item) => item.id.startsWith('custom_bowl_');

  List<DineInOrderItem> _buildOrderItems(List<CartItem> cartItems) {
    return [
      for (final item in cartItems)
        if (_isBowlCartItem(item))
          DineInBowlItem(
            quantity: item.quantity,
            ingredientIds: [
              for (final modifier in item.selectedModifiers) modifier.optionId,
            ],
            note: item.note,
          )
        else
          DineInProductItem(
            productId: item.id,
            quantity: item.quantity,
            selectedModifiers: [
              for (final modifier in item.selectedModifiers)
                (groupId: modifier.groupId, optionId: modifier.optionId),
            ],
            note: item.note,
          ),
    ];
  }

  void _onRewardSelect(String? rewardId) {
    setState(() {
      _selectedRewardId = rewardId;
      _submitError = null;
    });
  }

  /// Mirrors `DeliveryCheckoutScreen._handleCartMightHaveInvalidatedReward`
  /// exactly.
  void _handleCartMightHaveInvalidatedReward() {
    final rewardId = _selectedRewardId;
    if (rewardId == null) return;
    final rewards = ref.read(loyaltyRewardCatalogProvider).valueOrNull;
    final reward = rewards?.where((r) => r.rewardId == rewardId).firstOrNull;
    final cartProductIds = ref
        .read(cartProvider)
        .where((item) => !_isBowlCartItem(item))
        .map((item) => item.id)
        .toSet();
    if (reward == null || !reward.isEligibleForCart(cartProductIds)) {
      setState(() => _selectedRewardId = null);
    }
  }

  /// Mirrors `DeliveryCheckoutScreen`'s own `_errorMessageFor` catalog-
  /// reward branches exactly — no cash-Boncuk cases exist here at all,
  /// since this channel never offers that control.
  String _errorMessageFor(SubmitDineInOrderException error) {
    final reason = error.boncukErrorReason;
    if (reason != null) {
      switch (reason) {
        case 'catalogReward/reward-not-found':
        case 'catalogReward/reward-not-currently-valid':
          return 'Seçtiğin ödül artık kullanılamıyor. Lütfen tekrar seçim '
              'yap veya ödül kullanmadan devam et.';
        case 'catalogReward/product-not-in-cart':
          return 'Seçtiğin ödül için uygun bir ürün sepetinde bulunamadı. '
              'Lütfen sepetini kontrol et.';
        case 'catalogReward/insufficient-balance':
          return 'Bu ödül için yeterli Boncuk bakiyen yok. Bilgileri '
              'güncelledik; ödül kullanmadan devam edebilirsin.';
        case 'catalogReward/account-unavailable':
          return 'Boncuk hesabına şu anda ulaşılamıyor. Tekrar deneyebilir '
              'veya ödül kullanmadan devam edebilirsin.';
        case 'catalogReward/benefit-stacking-not-allowed':
          return 'Aynı anda birden fazla avantaj kullanılamaz.';
        case 'catalogReward/channel-not-eligible':
          return 'Seçtiğin ödül Masa siparişleri için kullanılamıyor. '
              'Lütfen tekrar seçim yap veya ödül kullanmadan devam et.';
        case 'boncuk/redemption-not-allowed':
          return 'Boncuk Masa siparişlerinde şu anda kullanılamıyor.';
      }
    }
    return error.message;
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
    // against the real, server-authoritative `tableGuestSessions` record,
    // never the client's own possibly-stale copy. `submitDineInOrder`
    // independently re-checks this itself regardless; this exists only to
    // show a friendly message instead of a raw callable failure.
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

    try {
      final gateway = ref.read(submitDineInOrderGatewayProvider);
      final result = await gateway.submit(
        submissionKey: _submissionKey,
        tableSessionId: tableContext.session.id,
        items: _buildOrderItems(cartItems),
        customerNote: _noteController.text.trim(),
        selectedRewardId: _selectedRewardId,
      );

      final order = await ref
          .read(canonicalOrderRepositoryProvider)
          .findById(OrderId(result.orderId));
      if (order == null) {
        throw StateError(
          'submitDineInOrder succeeded but the resulting order could not '
          'be read back (orderId: ${result.orderId}).',
        );
      }

      // Local-only bookkeeping via the existing domain seam
      // (`TableSession.withOrderAdded`) — `tableGuestSessions` has no
      // client-writable order-list field, so this updates only the
      // client-held context, never a server record.
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

      // Boncuk Loyalty P7-D.1 — a catalog-reward redemption debits the
      // customer's Loyalty account; refresh their displayed balance/reward
      // catalog now rather than waiting for a later screen (mirrors
      // DeliveryCheckoutScreen/TakeawayCheckoutScreen exactly).
      if (order.catalogReward != null) {
        ref.invalidate(loyaltySnapshotProvider);
        ref.invalidate(loyaltyRewardCatalogProvider);
      }

      if (!mounted) return;
      final catalogReward = order.catalogReward;
      final catalogRewardProductName = catalogReward == null
          ? null
          : order.lines
              .firstWhere(
                  (line) => line.productId == catalogReward.redeemedProductId)
              .productName;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => OrderSuccessScreen(
            orderId: order.id.value,
            dineInBranchName: tableContext.branchName,
            dineInTableName: tableContext.tableName,
            catalogRewardTitle: catalogReward?.title,
            catalogRewardBoncukCost: catalogReward?.boncukCost,
            catalogRewardRedeemedProductName: catalogRewardProductName,
            catalogRewardCoveredValueMinorUnits:
                catalogReward?.coveredValueMinorUnits,
          ),
        ),
        (route) => route.isFirst,
      );
    } on SubmitDineInOrderException catch (error) {
      if (!mounted) return;
      final isBoncukError = error.boncukErrorReason != null;
      setState(() {
        _isSubmitting = false;
        _submitError = _errorMessageFor(error);
        if (isBoncukError) {
          // CRITICAL — never auto-resubmit without the reward (mirrors
          // DeliveryCheckoutScreen/TakeawayCheckoutScreen exactly).
          _selectedRewardId = null;
        }
      });
      if (isBoncukError) {
        ref.invalidate(loyaltySnapshotProvider);
        ref.invalidate(loyaltyRewardCatalogProvider);
      }
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
    final isRealCustomerSession = isRealCustomer(ref.watch(authProvider));

    ref.listen<List<CartItem>>(cartProvider, (previous, next) {
      _handleCartMightHaveInvalidatedReward();
    });
    if (isRealCustomerSession) {
      ref.listen<AsyncValue<List<LoyaltyReward>>>(loyaltyRewardCatalogProvider,
          (previous, next) {
        _handleCartMightHaveInvalidatedReward();
      });
    }

    final cartProductIds = cartItems
        .where((item) => !_isBowlCartItem(item))
        .map((item) => item.id)
        .toSet();
    final rewardsAsync =
        isRealCustomerSession ? ref.watch(loyaltyRewardCatalogProvider) : null;

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
                  // Boncuk Loyalty Program P7-D.1 (2026-08-24) — real
                  // customer only; an anonymous table guest never sees this
                  // card at all, not even a disabled/zero state.
                  if (isRealCustomerSession && rewardsAsync != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    CatalogRewardCard(
                      rewardsAsync: rewardsAsync,
                      cartProductIds: cartProductIds,
                      selectedRewardId: _selectedRewardId,
                      boncukCashRedemptionActive: false,
                      controlsFrozen: _isSubmitting,
                      onSelect: _onRewardSelect,
                      onRetry: () =>
                          ref.invalidate(loyaltyRewardCatalogProvider),
                    ),
                  ],
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
