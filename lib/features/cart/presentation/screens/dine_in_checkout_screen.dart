import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/auth/real_customer_check.dart';
import '../../../../core/services/connectivity/network_connectivity_monitor.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/cards/option_selection_card.dart';
import '../../../../shared/widgets/layout/app_section_header.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/models/cart_item.dart';
import '../../../campaigns/domain/models/campaign.dart';
import '../../../campaigns/presentation/providers/campaigns_provider.dart';
import '../../../loyalty/domain/models/loyalty_reward.dart';
import '../../../loyalty/presentation/providers/loyalty_providers.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../orders/domain/models/order_model.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../domain/models/pending_dine_in_submission.dart';
import '../../../qr/domain/identity/dine_in_sub_account_id.dart';
import '../../../qr/presentation/providers/active_table_context_provider.dart';
import '../../../qr/presentation/providers/table_guest_session_dependencies_provider.dart';
import '../../../qr/presentation/widgets/table_context_badge.dart';
import '../../data/submit_dine_in_order_gateway.dart';
import '../../data/table_session_cart_firestore_client.dart';
import '../providers/cart_provider.dart';
import '../providers/dine_in_order_dependencies_provider.dart';
import '../widgets/campaign_selection_card.dart';
import '../widgets/catalog_reward_card.dart';
import 'order_success_screen.dart';

/// Self-Order QR Faz 4 — "Sadece Kendi Ürünlerimi Gönder" vs "Tüm Masayı
/// Gönder" (23-rule plan §4). Only ever meaningful once the shared cart
/// (Faz 3) actually holds more than one contributor — see
/// [_DineInCheckoutScreenState._isMultiGuestCart].
enum DineInSubmissionScope { ownItemsOnly, wholeTable }

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

  /// Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) — mirrors
  /// `DeliveryCheckoutScreen._selectedCampaignId`/
  /// `ReservationFlowScreen._selectedCampaignId` exactly: mutually
  /// exclusive with a catalog reward above. Only ever meaningful for a
  /// real, phone-verified customer — the LOCKED guest policy means this is
  /// never even set for an anonymous table guest (no campaign control is
  /// ever shown to one, see [build]'s own `isRealCustomerSession` gate).
  String? _selectedCampaignId;
  bool _isSubmitting = false;
  String? _submitError;

  /// AP-3 continuation — captured once, the first time the server rejects a
  /// submission with `dineIn/guest-display-name-required`, then sent on
  /// every subsequent submission at this table (including a resubmission
  /// this same visit) so the guest is never asked twice. `null` until that
  /// first rejection, or for a guest whose sub-account already carries a
  /// name (this screen never asks proactively — see [_submitOrder]'s own
  /// doc comment for why an early, speculative read isn't worth adding).
  String? _guestDisplayName;

  /// Self-Order QR Faz 4 — defaults to "only my own items," the safer
  /// choice (never silently submits, and pays for, a tablemate's items
  /// without an explicit switch).
  DineInSubmissionScope _submissionScope = DineInSubmissionScope.ownItemsOnly;

  /// Self-Order QR Faz 6 (23-rule plan §7, "offline order queueing with
  /// auto-flush on reconnect").
  StreamSubscription<NetworkConnectivityStatus>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    _selectedPaymentMethod = _paymentMethods.first;
    _submissionKey = DateTime.now().microsecondsSinceEpoch.toString();
    // Covers both "already online when this screen opens" (something
    // queued earlier this visit) and a live reconnect while it's open.
    unawaited(_flushOfflineQueue());
    try {
      _connectivitySubscription =
          ref.read(networkConnectivityMonitorProvider).onStatusChanged.listen(
        (status) {
          if (status == NetworkConnectivityStatus.online) {
            unawaited(_flushOfflineQueue());
          }
        },
        // The platform channel this wraps isn't available in every
        // environment (e.g. widget tests) — a stream error here must
        // never surface as an unhandled exception; the next manual
        // submit attempt still determines connectivity on its own.
        onError: (_) {},
      );
    } catch (_) {
      // Same reasoning as above — reconnect auto-flush is a convenience,
      // never a requirement for the screen to function.
    }
  }

  Future<void> _flushOfflineQueue() async {
    try {
      final sync = await ref.read(syncOfflineDineInOrdersProvider.future);
      await sync.call();
    } catch (_) {
      // Best-effort — the next reconnect/screen-open tries again.
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
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
            excludedIngredients: item.removedIngredients,
          ),
    ];
  }

  /// Self-Order QR Faz 4 — `true` only once the shared cart (Faz 3)
  /// genuinely holds more than one contributor; a solo guest never sees
  /// the hybrid-submission choice at all, since both modes would submit
  /// the exact same thing.
  bool _isMultiGuestCart(List<CartItem> cartItems) {
    final contributors =
        cartItems.map((item) => item.addedBySubAccountId).toSet();
    return contributors.length > 1;
  }

  /// `null` whenever there's no active table session, or nobody is
  /// signed in to Firebase Auth yet — mirrors `DineInTableCartNotifier
  /// ._currentSubAccountId`'s identical reasoning/guard.
  String? get _myOwnSubAccountId {
    final tableContext = ref.read(activeTableContextProvider);
    if (tableContext == null) return null;
    final uid = ref.read(technicalIdentityProviderProvider).currentUid;
    if (uid == null) return null;
    return deterministicIdentitySubAccountId(
      tableSessionId: tableContext.session.id,
      uid: uid,
    );
  }

  /// The cart narrowed to whatever [_submissionScope] actually means —
  /// "Tüm Masayı Gönder" is every line, unchanged; "Sadece Kendi
  /// Ürünlerimi Gönder" keeps only this device's own lines (plus, purely
  /// defensively, any line with no attribution at all, which should not
  /// occur inside an active table session but is never silently dropped).
  List<CartItem> _scopedCartItems(List<CartItem> cartItems) {
    if (_submissionScope == DineInSubmissionScope.wholeTable) return cartItems;
    final myId = _myOwnSubAccountId;
    return cartItems
        .where((item) =>
            item.addedBySubAccountId == null ||
            item.addedBySubAccountId == myId)
        .toList();
  }

  /// The exact `tableSessionCarts` line ids this submission is about to
  /// consume — sent to `submitDineInOrder` so it can delete them
  /// atomically with order creation (Faz 4; see that gateway method's own
  /// doc comment). A line with no attribution has no Firestore document
  /// to delete in the first place.
  List<String> _computeSubmittedCartLineIds(List<CartItem> scopedItems) {
    return [
      for (final item in scopedItems)
        if (item.addedBySubAccountId != null)
          deterministicCartLineId(
            addedBySubAccountId: item.addedBySubAccountId!,
            customizationsKey: item.customizationsKey,
          ),
    ];
  }

  void _onRewardSelect(String? rewardId) {
    setState(() {
      _selectedRewardId = rewardId;
      // Server-Authoritative Campaign Engine P8-C.3 — mutual exclusivity
      // with an active campaign selection.
      if (rewardId != null) _selectedCampaignId = null;
      _submitError = null;
    });
  }

  /// Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) — mirrors
  /// `DeliveryCheckoutScreen._onCampaignSelect`/
  /// `ReservationFlowScreen._onCampaignSelect` exactly.
  void _onCampaignSelect(String? campaignId) {
    setState(() {
      _selectedCampaignId = campaignId;
      if (campaignId != null) _selectedRewardId = null;
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

  /// Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) — mirrors
  /// `DeliveryCheckoutScreen._handleCampaignListMightHaveInvalidatedSelection`
  /// exactly.
  void _handleCampaignListMightHaveInvalidatedSelection() {
    final campaignId = _selectedCampaignId;
    if (campaignId == null) return;
    final campaigns = ref.read(activeCampaignsProvider).valueOrNull;
    final stillListed = campaigns != null &&
        campaigns.any((c) =>
            c.campaignId == campaignId && c.isEligibleForChannel('dineIn'));
    if (!stillListed) {
      setState(() => _selectedCampaignId = null);
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
        case 'benefit/stacking-not-allowed':
          return 'Aynı anda birden fazla avantaj kullanılamaz.';
        case 'catalogReward/channel-not-eligible':
          return 'Seçtiğin ödül Masa siparişleri için kullanılamıyor. '
              'Lütfen tekrar seçim yap veya ödül kullanmadan devam et.';
        case 'boncuk/redemption-not-allowed':
          return 'Boncuk Masa siparişlerinde şu anda kullanılamıyor.';
        // Server-Authoritative Campaign Engine P8-C.3 (2026-08-25) —
        // campaign-specific reasons, same shared `boncukErrorReason`
        // field/namespace. Mirrors `DeliveryCheckoutScreen`'s own copy,
        // adapted to this screen's tense.
        case 'campaign/not-found':
          return 'Seçtiğin kampanya artık bulunamıyor. Lütfen tekrar seçim '
              'yap veya kampanya kullanmadan devam et.';
        case 'campaign/inactive':
        case 'campaign/archived':
          return 'Seçtiğin kampanya artık geçerli değil. Lütfen tekrar '
              'seçim yap veya kampanya kullanmadan devam et.';
        case 'campaign/channel-not-eligible':
          return 'Seçtiğin kampanya Masa siparişlerinde geçerli değil.';
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
        // Server-Authoritative Campaign Engine P8-C.3 — LOCKED guest
        // policy: this screen never shows a campaign control to an
        // anonymous guest, so this branch should be structurally
        // unreachable from the UI — kept only as a safe, honest fallback
        // message if the server is ever reached with a stale/forged
        // selection some other way.
        case 'campaign/requires-customer-identity':
          return 'Kampanya kullanmak için telefon numaranla giriş yapmalısın.';
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
    // Self-Order QR Faz 4 — "Sadece Kendi Ürünlerimi Gönder" narrows this
    // before the empty check, so choosing that mode with nothing of my
    // own in a tablemate-only cart correctly reads as "my scope is
    // empty," not "the whole table's cart is empty."
    final scopedItems = _scopedCartItems(cartItems);
    if (scopedItems.isEmpty) {
      setState(() {
        _isSubmitting = false;
        _submitError = 'Sepetin boş.';
      });
      return;
    }

    // Self-Order QR Faz 6 — checked BEFORE attempting the real network
    // call, so a known-offline device never wastes a guaranteed-to-fail
    // round-trip: the order is queued immediately and replayed
    // automatically once connectivity returns (this screen's own
    // `_flushOfflineQueue`, triggered on reconnect and on next open).
    // If the connectivity signal itself can't be read (platform channel
    // unavailable, as in widget tests), default to "online" — attempting
    // the real submission is strictly safer than silently queueing every
    // order whenever this signal is merely unreadable.
    NetworkConnectivityStatus connectivity;
    try {
      connectivity =
          await ref.read(networkConnectivityMonitorProvider).currentStatus();
    } catch (_) {
      connectivity = NetworkConnectivityStatus.online;
    }
    if (connectivity == NetworkConnectivityStatus.offline) {
      final submittedCartLineIds = _computeSubmittedCartLineIds(scopedItems);
      final queueRepository =
          await ref.read(dineInOfflineOrderQueueRepositoryProvider.future);
      await queueRepository.enqueue(
        PendingDineInSubmission(
          submissionKey: _submissionKey,
          tableSessionId: tableContext.session.id,
          items: [
            for (final item in _buildOrderItems(scopedItems)) item.toJson(),
          ],
          customerNote: _noteController.text.trim(),
          selectedRewardId: _selectedRewardId,
          selectedCampaignId: _selectedCampaignId,
          guestDisplayName: _guestDisplayName,
          submittedCartLineIds: submittedCartLineIds,
          queuedAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = 'Bağlantı yok. Siparişiniz, bağlantı sağlanır '
            'sağlanmaz otomatik olarak gönderilecek.';
      });
      return;
    }

    try {
      final gateway = ref.read(submitDineInOrderGatewayProvider);
      final result = await gateway.submit(
        submissionKey: _submissionKey,
        tableSessionId: tableContext.session.id,
        items: _buildOrderItems(scopedItems),
        customerNote: _noteController.text.trim(),
        selectedRewardId: _selectedRewardId,
        selectedCampaignId: _selectedCampaignId,
        guestDisplayName: _guestDisplayName,
        submittedCartLineIds: _computeSubmittedCartLineIds(scopedItems),
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
      // Self-Order QR Faz 4 — no client-side `clearCart()` here anymore:
      // `submitDineInOrder` deletes exactly the `submittedCartLineIds`
      // lines server-side (Admin SDK), atomically with order creation.
      // That already covers both hybrid modes correctly — including
      // "Tüm Masayı Gönder," where a client-side `clearCart()` could
      // only ever delete this device's OWN lines (the ownership-locked
      // Security Rule applies regardless of which mode was chosen).

      // Boncuk Loyalty P7-D.1 — a catalog-reward redemption debits the
      // customer's Loyalty account; refresh their displayed balance/reward
      // catalog now rather than waiting for a later screen (mirrors
      // DeliveryCheckoutScreen/TakeawayCheckoutScreen exactly).
      if (order.catalogReward != null) {
        ref.invalidate(loyaltySnapshotProvider);
        ref.invalidate(loyaltyRewardCatalogProvider);
      }
      // Server-Authoritative Campaign Engine P8-C.3 — a campaign redemption
      // consumes usage server-side, so the customer's active-campaign list
      // is refreshed identically (mirrors DeliveryCheckoutScreen/
      // ReservationFlowScreen).
      if (order.campaign != null) {
        ref.invalidate(activeCampaignsProvider);
      }

      if (!mounted) return;
      final catalogReward = order.catalogReward;
      final catalogRewardProductName = catalogReward == null
          ? null
          : order.lines
              .firstWhere(
                  (line) => line.productId == catalogReward.redeemedProductId)
              .productName;
      final campaign = order.campaign;
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
            // Server-Authoritative Campaign Engine P8-C.3 — server-
            // confirmed only, sourced straight from the canonical re-read
            // Order, same discipline as catalogReward above; never the
            // pre-submit local estimate/eligibility hint.
            campaignTitle: campaign?.title,
            campaignDiscountMinorUnits: campaign?.discountMinorUnits,
            campaignNewGrandTotalMinorUnits:
                campaign == null ? null : order.pricing.grandTotal.minorUnits,
          ),
        ),
        (route) => route.isFirst,
      );
    } on SubmitDineInOrderException catch (error) {
      if (!mounted) return;
      if (error.boncukErrorReason == 'dineIn/guest-display-name-required') {
        setState(() => _isSubmitting = false);
        final name = await _promptForGuestDisplayName();
        if (name == null || !mounted) return;
        setState(() => _guestDisplayName = name);
        await _submitOrder();
        return;
      }
      final isBoncukError = error.boncukErrorReason != null;
      setState(() {
        _isSubmitting = false;
        _submitError = _errorMessageFor(error);
        if (isBoncukError) {
          // CRITICAL — never auto-resubmit without the reward/campaign
          // (mirrors DeliveryCheckoutScreen/TakeawayCheckoutScreen
          // exactly). Server-Authoritative Campaign Engine P8-C.3 — the
          // same reset covers a campaign rejection too (shared
          // `boncukErrorReason` namespace/signal).
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
      // Server-Authoritative Campaign Engine P8-C.3 — same reasoning, for a
      // cart change or a refreshed active-campaign list potentially
      // invalidating the current campaign selection. Real customer only —
      // mirrors the LOCKED guest policy: an anonymous guest never has a
      // campaign selection to invalidate in the first place.
      ref.listen<List<CartItem>>(cartProvider, (previous, next) {
        _handleCampaignListMightHaveInvalidatedSelection();
      });
      ref.listen<AsyncValue<List<Campaign>>>(activeCampaignsProvider,
          (previous, next) {
        _handleCampaignListMightHaveInvalidatedSelection();
      });
    }

    final cartProductIds = cartItems
        .where((item) => !_isBowlCartItem(item))
        .map((item) => item.id)
        .toSet();
    final rewardsAsync =
        isRealCustomerSession ? ref.watch(loyaltyRewardCatalogProvider) : null;
    final campaignsAsync =
        isRealCustomerSession ? ref.watch(activeCampaignsProvider) : null;

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
                  // Self-Order QR Faz 4 — "Sadece Kendi Ürünlerimi Gönder"
                  // vs "Tüm Masayı Gönder." Only shown once the shared
                  // cart (Faz 3) genuinely holds more than one
                  // contributor — a solo guest has nothing to choose
                  // between.
                  if (_isMultiGuestCart(cartItems)) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AppCard(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppSectionHeader(
                            title: 'Bu siparişte kimin ürünleri gönderilsin?',
                            subtitle:
                                'Masadaki diğer misafirler de bu sepete ürün '
                                'ekledi.',
                            isRequired: true,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          OptionSelectionCard(
                            name: 'Sadece Kendi Ürünlerimi Gönder',
                            extraPrice: 0,
                            isSelected: _submissionScope ==
                                DineInSubmissionScope.ownItemsOnly,
                            onTap: () => setState(() => _submissionScope =
                                DineInSubmissionScope.ownItemsOnly),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          OptionSelectionCard(
                            name: 'Tüm Masayı Gönder',
                            extraPrice: 0,
                            isSelected: _submissionScope ==
                                DineInSubmissionScope.wholeTable,
                            onTap: () => setState(() => _submissionScope =
                                DineInSubmissionScope.wholeTable),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Seçilen tutar: '
                            '${_scopedCartItems(cartItems).fold<double>(0, (sum, item) => sum + item.totalRowPrice).toStringAsFixed(0)} TL',
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Boncuk Loyalty Program P7-D.1 (2026-08-24) — real
                  // customer only; an anonymous table guest never sees this
                  // card at all, not even a disabled/zero state.
                  if (isRealCustomerSession && rewardsAsync != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    CatalogRewardCard(
                      rewardsAsync: rewardsAsync,
                      cartProductIds: cartProductIds,
                      selectedRewardId: _selectedRewardId,
                      // Server-Authoritative Campaign Engine P8-C.3 — this
                      // flag literally means "another benefit is active,
                      // hide myself"; an active campaign selection reuses
                      // it (no cash Boncuk exists on this channel at all,
                      // so this was always `false` pre-campaign).
                      boncukCashRedemptionActive: _selectedCampaignId != null,
                      controlsFrozen: _isSubmitting,
                      onSelect: _onRewardSelect,
                      onRetry: () =>
                          ref.invalidate(loyaltyRewardCatalogProvider),
                    ),
                  ],
                  // Server-Authoritative Campaign Engine P8-C.3 (2026-08-25)
                  // — mirrors `DeliveryCheckoutScreen`/`ReservationFlowScreen`
                  // exactly: real, server-authoritative active-campaign
                  // list, `commercialChannel: 'dineIn'` (never hardcoded to
                  // another channel — the exact P8-C.1-fixed bug this file
                  // must not repeat). **LOCKED guest policy**: shown ONLY
                  // for a real, phone-verified customer
                  // (`isRealCustomerSession`) — an anonymous table guest
                  // never sees this control at all, not even a disabled
                  // one, mirroring the catalog-reward card's own identical
                  // guest exclusion immediately above.
                  if (isRealCustomerSession && campaignsAsync != null) ...[
                    CampaignSelectionCard(
                      campaignsAsync: campaignsAsync,
                      commercialChannel: 'dineIn',
                      cartProductIds: cartProductIds,
                      cartTotalPriceTl: totalPrice,
                      selectedCampaignId: _selectedCampaignId,
                      otherBenefitActive: _selectedRewardId != null,
                      controlsFrozen: _isSubmitting,
                      onSelect: _onCampaignSelect,
                      onRetry: () => ref.invalidate(activeCampaignsProvider),
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

  /// AP-3 continuation — a mandatory-feeling but cancellable name prompt,
  /// shown reactively (see [_guestDisplayName]'s own doc comment for why
  /// this isn't asked proactively). Returns the trimmed name, or `null` if
  /// the guest dismissed the dialog without submitting one (in which case
  /// [_submitOrder] leaves [_submitError] showing the server's own
  /// rejection message rather than silently retrying).
  Future<String?> _promptForGuestDisplayName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.kLarge),
          title: const Text('Adını Öğrenebilir miyiz?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Masadaki siparişini kasaya iletebilmemiz için önce adını '
                'almamız gerekiyor. Bu isim yalnızca bu masadaki siparişini '
                'diğer misafirlerden ayırt etmek için kullanılır.',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('guestDisplayNameField'),
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Adın',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  final trimmed = value.trim();
                  if (trimmed.isNotEmpty) {
                    Navigator.of(dialogContext).pop(trimmed);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isEmpty) return;
                Navigator.of(dialogContext).pop(trimmed);
              },
              child: const Text('Devam Et'),
            ),
          ],
        );
      },
    );
  }
}
