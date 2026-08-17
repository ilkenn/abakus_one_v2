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

  bool get _canSubmit {
    return _selectedAddress != null &&
        _selectedAddress!.isDeliveryAuthorized &&
        _selectedPaymentMethodId != null &&
        !_isSubmitting &&
        !_isCapturingLocation;
  }

  String _errorMessageFor(String code, String message) {
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

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => OrderSuccessScreen(orderId: order.id.value),
        ),
        (route) => route.isFirst,
      );
    } on SubmitDeliveryOrderException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = _errorMessageFor(error.code, error.message);
      });
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
    const currency = Currency.tryLira;

    Money subtotal = Money.zero(currency);
    final lineEstimates = <CartItem, Money>{};
    for (final item in cartItems) {
      final unitPrice = _estimatedUnitPrice(item, catalog);
      final lineTotal = unitPrice * item.quantity;
      lineEstimates[item] = lineTotal;
      subtotal = subtotal + lineTotal;
    }

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
                onPressed: _canSubmit ? _submitOrder : null,
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
