import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/real_customer_check.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/fraud/domain/fraud_evidence.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../address_search/presentation/providers/address_search_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../cart/domain/models/cart_item.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../cart/presentation/screens/order_success_screen.dart';
import '../../../cart/presentation/screens/takeaway_checkout_screen.dart'
    show computeClientEstimatedMaxBoncuk;
import '../../../cart/presentation/widgets/boncuk_redemption_card.dart';
import '../../../cart/presentation/widgets/campaign_selection_card.dart';
import '../../../cart/presentation/widgets/catalog_reward_card.dart';
import '../../../campaigns/domain/models/campaign.dart';
import '../../../campaigns/presentation/providers/campaigns_provider.dart';
import '../../../loyalty/domain/models/loyalty_account_snapshot.dart';
import '../../../loyalty/domain/models/loyalty_reward.dart';
import '../../../loyalty/presentation/providers/loyalty_providers.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/domain/pricing/channel_price_resolver.dart';
import '../../../menu/domain/pricing/delivery_channel_pricing_policy.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../orders/domain/models/order_model.dart';
import '../../../orders/domain/models/saved_address.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../orders/presentation/providers/saved_address_providers.dart';
import '../../../payment/domain/models/delivery_payment_policy.dart';
import '../../../payment/domain/models/payment_method.dart';
import '../../../payment/domain/models/payment_method_seed_data.dart';
import '../../data/check_delivery_eligibility_gateway.dart';
import '../../data/submit_delivery_order_gateway.dart';
import '../providers/delivery_dependencies_provider.dart';
import 'delivery_address_selection_screen.dart';

/// Checkout for a real, authenticated Paket Servis (delivery) order —
/// Paket Servis P.3. **The canonical delivery checkout screen** — reached
/// from `CartScreen` whenever the shopping channel is
/// [OrderChannel.delivery] (the app's default channel; see
/// `ShoppingChannelContext.delivery()`), replacing the legacy `CheckoutScreen`
/// on that path (`docs/decisions.md` Paket Servis P.3).
///
/// Same "send intent, not price" discipline as `TakeawayCheckoutScreen`:
/// this screen sends only `savedAddressId`/`paymentMethodId`/item
/// selections/an idempotency key to `submitDeliveryOrder` and reads the
/// resulting canonical order back — `unitPrice`/`subtotal`/`grandTotal`/
/// `customerId`/organization/branch scope are never client-selected.
///
/// Every price shown here is a **display-only estimate**: computed locally
/// via `ChannelPriceResolver` + `DeliveryChannelPricingPolicy.value` (never
/// the live, shared `channelPricingPolicyRepositoryProvider` — see that
/// policy's own doc comment for why wiring it live would silently change
/// today's dine-in/takeaway/bowl-builder prices). The server recomputes the
/// authoritative total independently; a stale/forged client price is never
/// trusted.
class DeliveryCheckoutScreen extends ConsumerStatefulWidget {
  const DeliveryCheckoutScreen({super.key});

  @override
  ConsumerState<DeliveryCheckoutScreen> createState() =>
      _DeliveryCheckoutScreenState();
}

class _DeliveryCheckoutScreenState
    extends ConsumerState<DeliveryCheckoutScreen> {
  /// Generated once, on screen init, then reused on every retry within this
  /// screen's lifetime — mirrors `TakeawayCheckoutScreen._submissionKey`.
  late final String _submissionKey;

  SavedAddress? _selectedAddress;
  String? _selectedPaymentMethodId;

  bool _isSubmitting = false;
  String? _submitError;

  bool _isCheckingEligibility = false;
  DeliveryEligibilityResult? _eligibility;

  /// Boncuk Loyalty Program P5-B (2026-08-24) — local, screen-owned
  /// interaction state ONLY, mirroring `TakeawayCheckoutScreen`'s own
  /// `_boncukUsageEnabled`/`_selectedBoncukAmount` exactly (per the locked
  /// reuse rule: no new checkout controller/provider for delivery either).
  /// Server data continues to come exclusively from [loyaltySnapshotProvider],
  /// watched fresh in [build]; nothing here duplicates it.
  bool _boncukUsageEnabled = false;
  int _selectedBoncukAmount = 0;

  /// Boncuk Loyalty Program P7-D (2026-08-24) — mirrors
  /// `TakeawayCheckoutScreen._selectedRewardId` exactly: mutually exclusive
  /// with cash Boncuk redemption above (selecting one clears the other).
  String? _selectedRewardId;

  /// Server-Authoritative Campaign Engine P8-C.1 (2026-08-25) — mirrors
  /// `TakeawayCheckoutScreen._selectedCampaignId` exactly: mutually
  /// exclusive with both cash Boncuk redemption and a catalog reward above.
  String? _selectedCampaignId;

  /// FRAUD-F.2 — captured at most ONCE per submission attempt and reused
  /// across retries of the same [_submissionKey] (Architect Correction
  /// §3): a retry must never mint a fresh device-location read.
  ({
    ClientLocationEvidence? evidence,
    String? unavailableReason
  })? _cachedLocationCapture;
  bool _isCapturingLocation = false;

  @override
  void initState() {
    super.initState();
    _submissionKey =
        '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    _initializeSelectedAddress();
  }

  Future<void> _initializeSelectedAddress() async {
    final addresses = await ref.read(savedAddressListProvider.future);
    if (!mounted) return;
    final verified = addresses.where((a) => a.isDeliveryAuthorized).toList();
    if (verified.isEmpty) return;
    final defaultAddress = verified.firstWhere(
      (a) => a.isDefault,
      orElse: () => verified.first,
    );
    setState(() => _selectedAddress = defaultAddress);
    unawaited(_refreshEligibility());
  }

  Future<void> _refreshEligibility() async {
    final address = _selectedAddress;
    if (address == null) return;
    setState(() => _isCheckingEligibility = true);
    try {
      final result = await ref
          .read(checkDeliveryEligibilityGatewayProvider)
          .check(savedAddressId: address.id);
      if (!mounted) return;
      setState(() {
        _eligibility = result;
        _isCheckingEligibility = false;
      });
    } on CheckDeliveryEligibilityException {
      if (!mounted) return;
      // Advisory-only precheck — a failure here never blocks checkout;
      // `submitDeliveryOrder` re-validates independently regardless.
      setState(() {
        _eligibility = null;
        _isCheckingEligibility = false;
      });
    }
  }

  Future<void> _changeAddress() async {
    final selected = await Navigator.push<SavedAddress>(
      context,
      MaterialPageRoute(
        builder: (context) => const DeliveryAddressSelectionScreen(),
      ),
    );
    if (selected == null) return;
    setState(() {
      _selectedAddress = selected;
      _eligibility = null;
    });
    await _refreshEligibility();
  }

  bool _isBowlCartItem(CartItem item) => item.id.startsWith('custom_bowl_');

  /// The display-only, delivery-channel-adjusted unit price for [item] —
  /// never sent to the server, never treated as authoritative.
  Money _estimatedUnitPrice(CartItem item, List<MenuProduct> catalog) {
    if (_isBowlCartItem(item)) {
      final ingredientTotal = Money.fromLegacyDoubleTry(
        item.selectedModifiers.fold(0.0, (sum, m) => sum + m.extraPrice),
      );
      return ChannelPriceResolver.resolveBowlUnitPrice(
        ingredientTotal: ingredientTotal,
        channel: OrderChannel.delivery,
        policy: DeliveryChannelPricingPolicy.value,
      );
    }
    final product = catalog.where((p) => p.id == item.id).firstOrNull;
    if (product == null) {
      // No canonical product to resolve a category against — fall back to
      // the cart's own already-resolved price rather than guessing a
      // category. Display-only; the server independently resolves the
      // real product/price regardless.
      return Money.fromLegacyDoubleTry(item.price);
    }
    return ChannelPriceResolver.resolveProductUnitPrice(
      product: product,
      categoryId: product.categoryId,
      channel: OrderChannel.delivery,
      policy: DeliveryChannelPricingPolicy.value,
    );
  }

  List<DeliveryOrderItem> _buildOrderItems(List<CartItem> cartItems) {
    return [
      for (final item in cartItems)
        if (_isBowlCartItem(item))
          DeliveryBowlItem(
            quantity: item.quantity,
            ingredientIds: [
              for (final modifier in item.selectedModifiers) modifier.optionId,
            ],
            note: item.note,
          )
        else
          DeliveryProductItem(
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

  /// The current, non-authoritative estimated subtotal (TL) — the same
  /// delivery-channel-adjusted per-item pricing [build] already displays as
  /// "Ara Toplam", recomputed here from a fresh `ref.read` for use by the
  /// imperative Boncuk handlers below (which run outside `build` and so
  /// cannot close over `build`'s own local `subtotal` variable). Mirrors
  /// `TakeawayCheckoutScreen`'s reliance on `cartTotalPriceProvider` for the
  /// same purpose — delivery has no equivalent provider (its estimate is
  /// channel/catalog-resolved, not a plain cart sum), so this recomputes the
  /// identical loop instead of introducing one.
  double _currentEstimatedSubtotalTl() {
    final cartItems = ref.read(cartProvider);
    final catalog = ref.read(menuProductsProvider);
    const currency = Currency.tryLira;
    Money subtotal = Money.zero(currency);
    for (final item in cartItems) {
      subtotal =
          subtotal + (_estimatedUnitPrice(item, catalog) * item.quantity);
    }
    return subtotal.minorUnits / currency.minorUnitsPerWhole;
  }

  /// Boncuk Loyalty P5-B — mirrors `TakeawayCheckoutScreen._onBoncukToggle`
  /// exactly.
  void _onBoncukToggle(bool value) {
    setState(() {
      _boncukUsageEnabled = value;
      _selectedBoncukAmount =
          value ? (_selectedBoncukAmount > 0 ? _selectedBoncukAmount : 1) : 0;
      // Boncuk Loyalty P7-D — mutual exclusivity: turning cash redemption
      // on clears any catalog-reward selection.
      // Server-Authoritative Campaign Engine P8-C.1 — same exclusivity
      // with any active campaign selection.
      if (value) {
        _selectedRewardId = null;
        _selectedCampaignId = null;
      }
      _submitError = null;
    });
  }

  /// Boncuk Loyalty Program P7-D (2026-08-24) — mirrors
  /// `TakeawayCheckoutScreen._onRewardSelect` exactly.
  void _onRewardSelect(String? rewardId) {
    setState(() {
      _selectedRewardId = rewardId;
      if (rewardId != null) {
        _boncukUsageEnabled = false;
        _selectedBoncukAmount = 0;
        // Server-Authoritative Campaign Engine P8-C.1 — mutual exclusivity
        // with any active campaign selection.
        _selectedCampaignId = null;
      }
      _submitError = null;
    });
  }

  /// Server-Authoritative Campaign Engine P8-C.1 (2026-08-25) — mirrors
  /// `TakeawayCheckoutScreen._onCampaignSelect` exactly.
  void _onCampaignSelect(String? campaignId) {
    setState(() {
      _selectedCampaignId = campaignId;
      if (campaignId != null) {
        _boncukUsageEnabled = false;
        _selectedBoncukAmount = 0;
        _selectedRewardId = null;
      }
      _submitError = null;
    });
  }

  void _onBoncukAmountChanged(int newAmount) {
    setState(() {
      _selectedBoncukAmount = newAmount;
      _submitError = null;
    });
  }

  void _onBoncukUseMax() {
    final snapshot = ref.read(loyaltySnapshotProvider).valueOrNull;
    if (snapshot == null) return;
    final max = computeClientEstimatedMaxBoncuk(
      snapshot,
      _currentEstimatedSubtotalTl(),
    );
    setState(() {
      _boncukUsageEnabled = max > 0;
      _selectedBoncukAmount = max > 0 ? max : 0;
      _submitError = null;
    });
  }

  /// Boncuk Loyalty P5-B — mirrors
  /// `TakeawayCheckoutScreen._handleBoncukEstimateMightHaveChanged` exactly:
  /// never silently clamps [_selectedBoncukAmount] down to a smaller
  /// nonzero value; the ONE state mutation is turning Boncuk usage off and
  /// resetting the selection to 0 when the estimated max reaches exactly
  /// zero.
  void _handleBoncukEstimateMightHaveChanged() {
    if (!_boncukUsageEnabled) return;
    final snapshot = ref.read(loyaltySnapshotProvider).valueOrNull;
    if (snapshot == null) return;
    final max = computeClientEstimatedMaxBoncuk(
      snapshot,
      _currentEstimatedSubtotalTl(),
    );
    if (max <= 0) {
      setState(() {
        _boncukUsageEnabled = false;
        _selectedBoncukAmount = 0;
      });
    }
  }

  /// Boncuk Loyalty Program P7-D (2026-08-24) — mirrors
  /// `TakeawayCheckoutScreen._handleCartMightHaveInvalidatedReward` exactly.
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

  /// Server-Authoritative Campaign Engine P8-C.1 (2026-08-25) — mirrors
  /// `TakeawayCheckoutScreen._handleCampaignListMightHaveInvalidatedSelection`
  /// exactly.
  void _handleCampaignListMightHaveInvalidatedSelection() {
    final campaignId = _selectedCampaignId;
    if (campaignId == null) return;
    final campaigns = ref.read(activeCampaignsProvider).valueOrNull;
    final stillListed = campaigns != null &&
        campaigns.any((c) =>
            c.campaignId == campaignId && c.isEligibleForChannel('delivery'));
    if (!stillListed) {
      setState(() => _selectedCampaignId = null);
    }
  }

  bool get _canSubmit {
    return _selectedAddress != null &&
        _selectedAddress!.isDeliveryAuthorized &&
        _selectedPaymentMethodId != null &&
        !_isSubmitting &&
        !_isCapturingLocation;
  }

  /// Boncuk Loyalty P5-B §13 — a Boncuk-specific rejection is mapped from
  /// [SubmitDeliveryOrderException.boncukErrorReason] (the SAME stable,
  /// machine-readable server reason vocabulary
  /// `TakeawayCheckoutScreen._errorMessageFor` branches on), NEVER inferred
  /// from [error]'s `code` alone.
  String _errorMessageFor(SubmitDeliveryOrderException error) {
    final boncukReason = error.boncukErrorReason;
    if (boncukReason != null) {
      switch (boncukReason) {
        case 'boncuk/exceeds-max-usable':
          return 'Boncuk bakiyen veya kullanabileceğin miktar değişti. '
              'Bilgileri güncelledik; tekrar seçim yap.';
        case 'boncuk/account-unavailable':
          return 'Boncuk hesabına şu anda ulaşılamıyor. Tekrar deneyebilir '
              'veya Boncuk kullanmadan devam edebilirsin.';
        case 'boncuk/policy-unavailable':
          return 'Boncuk kullanımı şu anda geçici olarak kullanılamıyor. '
              'Biraz sonra tekrar deneyebilirsin.';
        // Boncuk Loyalty P7-D (2026-08-24) — catalog-reward-specific
        // reasons, same shared `boncukErrorReason` field/namespace.
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
        case 'benefit/stacking-not-allowed':
          return 'Aynı anda birden fazla avantaj kullanılamaz. Lütfen '
              'birini seç.';
        case 'catalogReward/channel-not-eligible':
          return 'Seçtiğin ödül Paket Servis için kullanılamıyor. Lütfen '
              'tekrar seçim yap veya ödül kullanmadan devam et.';
        // Server-Authoritative Campaign Engine P8-C.1 (2026-08-25) —
        // campaign-specific reasons, same shared `boncukErrorReason`
        // field/namespace.
        case 'campaign/not-found':
          return 'Seçtiğin kampanya artık bulunamıyor. Lütfen tekrar seçim '
              'yap veya kampanya kullanmadan devam et.';
        case 'campaign/inactive':
        case 'campaign/archived':
          return 'Seçtiğin kampanya artık geçerli değil. Lütfen tekrar '
              'seçim yap veya kampanya kullanmadan devam et.';
        case 'campaign/channel-not-eligible':
          return 'Seçtiğin kampanya Paket Servis siparişlerinde geçerli '
              'değil.';
        case 'campaign/schedule-not-open':
          return 'Seçtiğin kampanya şu anda geçerli saatlerde değil.';
        case 'campaign/minimum-basket-not-met':
          return 'Bu kampanya için sepet tutarın yeterli değil.';
        case 'campaign/no-eligible-line':
        case 'campaign/trigger-quantity-not-met':
          return 'Sepetinde bu kampanyaya uygun bir ürün yok.';
        case 'campaign/usage-limit-reached':
        case 'campaign/customer-usage-limit-reached':
          return 'Bu kampanyanın kullanım hakkı doldu.';
        case 'campaign/reservation-conflict':
          return 'Kampanya şu anda kullanılamıyor. Lütfen tekrar dene.';
        default:
          return 'Boncuk kullanılırken bir sorun oluştu. Boncuk kullanmadan '
              'devam edebilirsin.';
      }
    }
    final code = error.code;
    final message = error.message;
    switch (code) {
      case 'not-found':
        return 'Seçilen adres bulunamadı. Lütfen adresini kontrol et.';
      case 'permission-denied':
      case 'unauthenticated':
        return 'Sipariş gönderilirken bir sorun oluştu. Lütfen tekrar giriş yap.';
      case 'failed-precondition':
        if (message.contains('paket servis hizmeti')) {
          return 'Bu adrese şu anda paket servis hizmeti veremiyoruz.';
        }
        if (message.contains('Minimum sipariş')) {
          return 'Bu adres için minimum sipariş tutarına ulaşmadın.';
        }
        if (message.contains('doğrulaması')) {
          return 'Bu adres teslimat için henüz doğrulanmadı.';
        }
        return 'Sipariş şu anda tamamlanamıyor. Lütfen tekrar dene.';
      case 'invalid-argument':
        return 'Sipariş bilgileri geçersiz görünüyor. Lütfen sepeti kontrol et.';
      default:
        return 'Sipariş gönderilirken bir sorun oluştu. Lütfen tekrar dene.';
    }
  }

  Future<void> _submitOrder() async {
    if (_isSubmitting) return;
    if (!_canSubmit) return;

    // Defense-in-depth (mirrors TakeawayCheckoutScreen §9) — the submit
    // button is already disabled whenever the UI's own derived
    // `boncukSelectionInvalid` is true; this re-checks the same condition
    // against a freshly-read snapshot right before sending, rather than
    // trusting only the last-built widget state.
    if (_boncukUsageEnabled) {
      final snapshot = ref.read(loyaltySnapshotProvider).valueOrNull;
      final max = snapshot == null
          ? 0
          : computeClientEstimatedMaxBoncuk(
              snapshot, _currentEstimatedSubtotalTl());
      if (_selectedBoncukAmount <= 0 || _selectedBoncukAmount > max) {
        return;
      }
    }

    // Boncuk Loyalty P7-D — the same defense-in-depth discipline for a
    // catalog-reward selection, mirroring TakeawayCheckoutScreen exactly.
    if (_selectedRewardId != null) {
      final rewards = ref.read(loyaltyRewardCatalogProvider).valueOrNull;
      final cartProductIds = ref
          .read(cartProvider)
          .where((item) => !_isBowlCartItem(item))
          .map((item) => item.id)
          .toSet();
      final stillEligible = rewards != null &&
          rewards.any((r) =>
              r.rewardId == _selectedRewardId &&
              r.isEligibleForCart(cartProductIds));
      if (!stillEligible) {
        setState(() => _selectedRewardId = null);
        return;
      }
    }

    // Server-Authoritative Campaign Engine P8-C.1 — the same defense-in-
    // depth discipline for a campaign selection, mirroring
    // TakeawayCheckoutScreen exactly.
    if (_selectedCampaignId != null) {
      final campaigns = ref.read(activeCampaignsProvider).valueOrNull;
      final stillListed = campaigns != null &&
          campaigns.any((c) =>
              c.campaignId == _selectedCampaignId &&
              c.isEligibleForChannel('delivery'));
      if (!stillListed) {
        setState(() => _selectedCampaignId = null);
        return;
      }
    }

    final address = _selectedAddress;
    final paymentMethodId = _selectedPaymentMethodId;
    if (address == null || paymentMethodId == null) return;

    final authSession = ref.read(authProvider).session;
    final isReal = isRealCustomer(ref.read(authProvider));
    if (authSession == null || !isReal) {
      setState(() {
        _submitError =
            'Sipariş gönderilirken bir sorun oluştu. Lütfen tekrar giriş yap.';
      });
      return;
    }

    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) {
      setState(() => _submitError = 'Sepetin boş.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    // FRAUD-F.2 — one single foreground capture per submission attempt,
    // cached and reused across retries of the same _submissionKey
    // (Architect Correction §3). Never fabricated, never re-captured.
    if (_cachedLocationCapture == null) {
      setState(() => _isCapturingLocation = true);
      final capture = await ref
          .read(addressLocationGatewayProvider)
          .captureLocationEvidence();
      _cachedLocationCapture = (
        evidence: capture.evidence,
        unavailableReason: capture.unavailableReason?.name,
      );
      if (!mounted) return;
      setState(() => _isCapturingLocation = false);
    }
    final locationCapture = _cachedLocationCapture!;

    try {
      final result = await ref.read(submitDeliveryOrderGatewayProvider).submit(
            submissionKey: _submissionKey,
            savedAddressId: address.id,
            paymentMethodId: paymentMethodId,
            items: _buildOrderItems(cartItems),
            deviceLocation: locationCapture.evidence,
            deviceLocationUnavailableReason: locationCapture.unavailableReason,
            requestedBoncukAmount:
                _boncukUsageEnabled ? _selectedBoncukAmount : 0,
            selectedRewardId: _selectedRewardId,
            selectedCampaignId: _selectedCampaignId,
          );

      final order = await ref
          .read(canonicalOrderRepositoryProvider)
          .findById(OrderId(result.orderId));
      if (order == null) {
        throw StateError(
          'submitDeliveryOrder succeeded but the resulting order could not '
          'be read back (orderId: ${result.orderId}).',
        );
      }

      await ref
          .read(ordersProvider.notifier)
          .addOrder(OrderModel.fromCanonicalOrder(order));
      ref.read(cartProvider.notifier).clearCart();

      // Boncuk Loyalty P5-B — redemption occurs at submission time, not at
      // completed-order earning; refresh the customer's displayed balance
      // now rather than waiting for a later screen to happen to re-fetch it
      // (mirrors TakeawayCheckoutScreen §14).
      ref.invalidate(loyaltySnapshotProvider);
      // Boncuk Loyalty P7-D — a catalog-reward redemption debits the same
      // account, so the reward catalog's own balance-eligibility state is
      // refreshed identically (mirrors TakeawayCheckoutScreen exactly).
      if (order.catalogReward != null) {
        ref.invalidate(loyaltyRewardCatalogProvider);
      }
      // Server-Authoritative Campaign Engine P8-C.1 — a campaign redemption
      // consumes a usage slot, so refresh the customer's displayed active
      // campaigns now rather than waiting for a later screen to re-fetch.
      if (order.campaign != null) {
        ref.invalidate(activeCampaignsProvider);
      }

      if (!mounted) return;
      final boncukRedemption = order.boncukRedemption;
      final catalogReward = order.catalogReward;
      final campaign = order.campaign;
      // Server-confirmed only (P7-D) — cross-referenced from the SAME
      // canonical order's own `lines`, never a separate catalog lookup.
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
            isDeliveryOrder: true,
            orderTotalMinorUnits: order.pricing.grandTotal.minorUnits,
            boncukUsed: boncukRedemption?.boncukUsed,
            boncukValueMinorUnits: boncukRedemption?.valueMinorUnits,
            remainingPayableMinorUnits:
                boncukRedemption?.remainingPayableMinorUnits,
            catalogRewardTitle: catalogReward?.title,
            catalogRewardBoncukCost: catalogReward?.boncukCost,
            catalogRewardRedeemedProductName: catalogRewardProductName,
            catalogRewardCoveredValueMinorUnits:
                catalogReward?.coveredValueMinorUnits,
            // Server-Authoritative Campaign Engine P8-C.1 — server-
            // confirmed only, sourced straight from the canonical re-read
            // Order, same discipline as boncukRedemption/catalogReward
            // above; never the pre-submit local estimate/eligibility hint.
            campaignTitle: campaign?.title,
            campaignDiscountMinorUnits: campaign?.discountMinorUnits,
            campaignNewGrandTotalMinorUnits:
                campaign == null ? null : order.pricing.grandTotal.minorUnits,
          ),
        ),
        (route) => route.isFirst,
      );
    } on SubmitDeliveryOrderException catch (error) {
      if (!mounted) return;
      final isBoncukError = error.boncukErrorReason != null;
      setState(() {
        _isSubmitting = false;
        _submitError = _errorMessageFor(error);
        if (isBoncukError) {
          // CRITICAL — never auto-resubmit without Boncuk (mirrors
          // TakeawayCheckoutScreen §13). Turning the selection off makes the
          // screen immediately submittable again WITHOUT Boncuk, but the
          // customer must tap "Siparişi Ver" themselves. Boncuk Loyalty
          // P7-D — the same reset covers a catalog-reward rejection too.
          // Server-Authoritative Campaign Engine P8-C.1 — and a campaign
          // rejection, same shared namespace/signal.
          _boncukUsageEnabled = false;
          _selectedBoncukAmount = 0;
          _selectedRewardId = null;
          _selectedCampaignId = null;
        }
      });
      if (isBoncukError) {
        ref.invalidate(loyaltySnapshotProvider);
        ref.invalidate(loyaltyRewardCatalogProvider);
        ref.invalidate(activeCampaignsProvider);
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

  String _formattedAddressOf(SavedAddress address) {
    if (address.formattedAddress != null) return address.formattedAddress!;
    final parts = [
      if (address.neighborhoodName != null) address.neighborhoodName,
      if (address.streetName != null) address.streetName,
      if (address.buildingNo != null) 'No:${address.buildingNo}',
      'Daire:${address.apartmentNo}',
      if (address.districtName != null) address.districtName,
    ];
    return parts.join(', ');
  }

  List<PaymentMethod> _availableDeliveryMethods() {
    const policy = DeliveryPaymentPolicy(
      enabledMethodIds: {
        'cash',
        'credit_card',
        'pluxee',
        'multinet',
        'setcard',
        'edenred',
        'metropol_card',
      },
    );
    return PaymentMethodSeedData.all
        .where(policy.isAvailableForDeliveryCheckout)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final catalog = ref.watch(menuProductsProvider);
    final loyaltySnapshotAsync = ref.watch(loyaltySnapshotProvider);
    final rewardsAsync = ref.watch(loyaltyRewardCatalogProvider);
    final campaignsAsync = ref.watch(activeCampaignsProvider);
    const currency = Currency.tryLira;

    // Boncuk Loyalty P5-B — react to a cart change or loyalty snapshot
    // change while Boncuk usage is on (mirrors TakeawayCheckoutScreen §9/
    // §10's `ref.listen` side-effect pattern exactly; see
    // `_currentEstimatedSubtotalTl`'s own doc comment for why this listens
    // to `cartProvider` directly rather than a derived total provider).
    ref.listen<List<CartItem>>(cartProvider, (previous, next) {
      _handleBoncukEstimateMightHaveChanged();
      _handleCartMightHaveInvalidatedReward();
    });
    ref.listen<AsyncValue<LoyaltyAccountSnapshot>>(loyaltySnapshotProvider,
        (previous, next) {
      _handleBoncukEstimateMightHaveChanged();
    });
    // Boncuk Loyalty P7-D — mirrors TakeawayCheckoutScreen's own reward-
    // invalidation listener exactly.
    ref.listen<AsyncValue<List<LoyaltyReward>>>(loyaltyRewardCatalogProvider,
        (previous, next) {
      _handleCartMightHaveInvalidatedReward();
    });
    // Server-Authoritative Campaign Engine P8-C.1 — same reasoning, for a
    // campaign selection the active-campaign list itself can invalidate.
    ref.listen<AsyncValue<List<Campaign>>>(activeCampaignsProvider,
        (previous, next) {
      _handleCampaignListMightHaveInvalidatedSelection();
    });

    final cartProductIds = cartItems
        .where((item) => !_isBowlCartItem(item))
        .map((item) => item.id)
        .toSet();

    Money subtotal = Money.zero(currency);
    final lineEstimates = <CartItem, Money>{};
    for (final item in cartItems) {
      final unitPrice = _estimatedUnitPrice(item, catalog);
      final lineTotal = unitPrice * item.quantity;
      lineEstimates[item] = lineTotal;
      subtotal = subtotal + lineTotal;
    }
    final subtotalTl = subtotal.minorUnits / currency.minorUnitsPerWhole;

    final clientEstimatedMaxBoncuk = loyaltySnapshotAsync.maybeWhen(
      data: (snapshot) => computeClientEstimatedMaxBoncuk(snapshot, subtotalTl),
      orElse: () => 0,
    );
    // Derived, never stored (mirrors TakeawayCheckoutScreen §9).
    final boncukSelectionInvalid =
        _boncukUsageEnabled && _selectedBoncukAmount > clientEstimatedMaxBoncuk;
    final canSubmit = _canSubmit && !boncukSelectionInvalid;

    final eligibility = _eligibility;
    final minimumOrderMinorUnits = eligibility?.minimumOrderMinorUnits;
    final belowMinimum = minimumOrderMinorUnits != null &&
        subtotal.minorUnits < minimumOrderMinorUnits;

    return Scaffold(
      appBar: AppBar(title: const Text('Paket Servis Siparişi')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            _SectionCard(
              title: 'Teslimat Adresi',
              trailing: TextButton(
                onPressed: _changeAddress,
                child: const Text('Değiştir'),
              ),
              child: _selectedAddress == null
                  ? const Text(
                      'Teslimat için bir adres seçmelisin.',
                      style: AppTypography.bodyMedium,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedAddress!.label,
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _formattedAddressOf(_selectedAddress!),
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_isCheckingEligibility)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: LinearProgressIndicator(),
              )
            else if (eligibility != null && !eligibility.eligible) ...[
              _EligibilityWarning(reason: eligibility.reason),
              const SizedBox(height: AppSpacing.lg),
            ] else if (belowMinimum) ...[
              _EligibilityWarning(
                reason: null,
                customMessage:
                    'Bu adres için minimum sipariş tutarı ${(minimumOrderMinorUnits / currency.minorUnitsPerWhole).toStringAsFixed(0)} TL.',
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            _SectionCard(
              title: 'Ödeme Yöntemi',
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final method in _availableDeliveryMethods())
                    _PaymentChip(
                      label: method.name,
                      isSelected: _selectedPaymentMethodId == method.id,
                      onTap: () => setState(
                        () => _selectedPaymentMethodId = method.id,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionCard(
              title: 'Ürünler',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in cartItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${item.quantity}x ${item.name}',
                              style: AppTypography.bodyMedium,
                            ),
                          ),
                          Text(
                            '${((lineEstimates[item]?.minorUnits ?? 0) / currency.minorUnitsPerWhole).toStringAsFixed(0)} TL',
                            style: AppTypography.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Ara Toplam',
                          style: AppTypography.titleMedium),
                      Text(
                        '${(subtotal.minorUnits / currency.minorUnitsPerWhole).toStringAsFixed(0)} TL',
                        style: AppTypography.titleLarge.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Yukarıdaki tutar tahminidir; kesin tutar siparişin '
                    'onaylanmasıyla belirlenir.',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Boncuk Loyalty P7-D (2026-08-24) — mutual exclusivity with the
            // catalog-reward card below: selecting a reward REMOVES this
            // card entirely (never just visually disables it), mirroring
            // TakeawayCheckoutScreen exactly.
            // Server-Authoritative Campaign Engine P8-C.1 (2026-08-25) —
            // same exclusivity extended to an active campaign selection.
            if (_selectedRewardId == null && _selectedCampaignId == null)
              BoncukRedemptionCard(
                snapshotAsync: loyaltySnapshotAsync,
                enabled: _boncukUsageEnabled,
                selectedAmount: _selectedBoncukAmount,
                maxUsableBoncuk: clientEstimatedMaxBoncuk,
                selectionInvalid: boncukSelectionInvalid,
                controlsFrozen: _isSubmitting,
                cartTotalPriceTl: subtotalTl,
                onToggle: _onBoncukToggle,
                onAmountChanged: _onBoncukAmountChanged,
                onUseMax: _onBoncukUseMax,
                onRetry: () => ref.invalidate(loyaltySnapshotProvider),
              ),
            const SizedBox(height: AppSpacing.lg),
            CatalogRewardCard(
              rewardsAsync: rewardsAsync,
              cartProductIds: cartProductIds,
              selectedRewardId: _selectedRewardId,
              // Server-Authoritative Campaign Engine P8-C.1 — this flag
              // literally means "another benefit is active, hide myself";
              // an active campaign selection reuses it rather than adding
              // a second, near-duplicate param to an otherwise-unrelated
              // P7-D widget.
              boncukCashRedemptionActive:
                  _boncukUsageEnabled || _selectedCampaignId != null,
              controlsFrozen: _isSubmitting,
              onSelect: _onRewardSelect,
              onRetry: () => ref.invalidate(loyaltyRewardCatalogProvider),
            ),
            CampaignSelectionCard(
              campaignsAsync: campaignsAsync,
              commercialChannel: 'delivery',
              cartProductIds: cartProductIds,
              cartTotalPriceTl: subtotalTl,
              selectedCampaignId: _selectedCampaignId,
              otherBenefitActive:
                  _boncukUsageEnabled || _selectedRewardId != null,
              controlsFrozen: _isSubmitting,
              onSelect: _onCampaignSelect,
              onRetry: () => ref.invalidate(activeCampaignsProvider),
            ),
            if (_submitError != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                _submitError!,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canSubmit ? _submitOrder : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                  ),
                ),
                child: (_isSubmitting || _isCapturingLocation)
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : const Text('Siparişi Ver'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: AppRadius.kPill,
        ),
        child: Text(
          label,
          style: AppTypography.labelLarge.copyWith(
            color: isSelected ? AppColors.onPrimary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _EligibilityWarning extends StatelessWidget {
  final String? reason;
  final String? customMessage;

  const _EligibilityWarning({this.reason, this.customMessage});

  String get _message {
    if (customMessage != null) return customMessage!;
    switch (reason) {
      case 'address_not_verified':
        return 'Seçili adres teslimat için henüz doğrulanmadı.';
      case 'not_covered':
        return 'Bu adrese şu anda paket servis hizmeti veremiyoruz.';
      case 'ambiguous_configuration':
        return 'Bu adres için teslimat bölgesi yapılandırması belirsiz.';
      default:
        return 'Bu adrese teslimat şu anda uygun olmayabilir.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: AppRadius.kMedium,
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _message,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
