import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/courier_type.dart';
import '../../../../shared/models/money.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../courier/domain/identity/courier.dart';
import '../../../courier/domain/identity/courier_registry_status.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/domain/pricing/channel_price_resolver.dart';
import '../../../menu/domain/pricing/channel_pricing_policy.dart';
import '../../../menu/presentation/providers/channel_price_display_provider.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../data/pos_action_gateway.dart' show PosDeviceContext;
import '../../data/pos_phone_order_gateway.dart';
import '../providers/courier_dispatch_dependencies_provider.dart';
import '../providers/pos_workspace_providers.dart';
import '../widgets/pos_catalog_browser.dart';
import '../widgets/print_courier_slip_action.dart';

/// The two modes of the phone / counter order screen (2026-11-11).
enum PosPhoneOrderMode {
  takeaway('Gel-Al', Icons.shopping_bag_outlined, OrderChannel.takeaway),
  delivery(
      'Paket Servis', Icons.delivery_dining_rounded, OrderChannel.delivery);

  const PosPhoneOrderMode(this.label, this.icon, this.channel);
  final String label;
  final IconData icon;

  /// The sales channel whose prices the catalog and cart show.
  final OrderChannel channel;
}

/// Pay-on-delivery choices for a delivery order.
enum PosPayOnDeliveryMethod {
  cash('Kapıda Nakit', Icons.payments_outlined),
  card('Kapıda POS', Icons.credit_card_rounded),
  mealCard('Kapıda Yemek Kartı', Icons.restaurant_rounded);

  const PosPayOnDeliveryMethod(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The meal-card brands offered for "Kapıda Yemek Kartı" — payment-method
/// catalog ids (server: `STAFF_DELIVERY_PAYMENT_METHOD_IDS`).
const _mealCardBrands = [
  (id: 'pluxee', label: 'Pluxee'),
  (id: 'multinet', label: 'Multinet'),
  (id: 'setcard', label: 'Setcard'),
  (id: 'edenred', label: 'Edenred'),
];

/// "Yeni Gel-Al / Paket Servis Siparişi" — 2026-11-11 redesign.
///
/// Faz 1: Gel-Al / Paket Servis mode switch, "Müşteri Ara (İsim veya Tel)",
/// the shared touch catalog ([PosCatalogBrowser]), customer / cart / actions.
///
/// Faz 2 (product owner decisions):
/// - the search covers the organization's local customer book (full phone,
///   remembered addresses) and its app-customer directory (masked phone) —
///   `searchPosCustomers`;
/// - Gel-Al sends its order-level kitchen note; Paket Servis is sent with
///   `submitStaffDeliveryOrder` — typed address, courier note, kitchen note,
///   pay-on-delivery method (meal cards by brand), an optional manual
///   delivery fee (default 0, 20% VAT server-side) and the planned courier
///   (assigned later from the dispatch board, never automatically);
/// - prices are the channel's own (Gel-Al +20 TL; Paket Servis ×1.35,
///   nearest 5 TL) in the catalog, the cart and the courier slip — display
///   only, the server prices every order itself;
/// - the courier slip prints automatically once the delivery order is
///   confirmed, and can be printed again from the confirmation dialog;
/// - products sold by weight stay dine-in only (ADR-067).
///
/// The courier pool is Faz 3.
class PosNewTakeawayOrderScreen extends ConsumerStatefulWidget {
  const PosNewTakeawayOrderScreen({
    super.key,
    required this.ctx,
    this.initialMode = PosPhoneOrderMode.takeaway,
  });

  final PosDeviceContext ctx;
  final PosPhoneOrderMode initialMode;

  @override
  ConsumerState<PosNewTakeawayOrderScreen> createState() =>
      _PosNewTakeawayOrderScreenState();
}

class _PhoneOrderCartLine {
  _PhoneOrderCartLine(this.selection) : quantity = selection.quantity;

  /// As chosen in the catalog (its product carries that moment's channel
  /// prices; the cart re-prices from the catalog for the current mode).
  final PosCatalogSelection selection;
  int quantity;

  String get productId => selection.product.id;
  String get productName => selection.product.name;

  /// Same product + same configuration = one line (quantity merges).
  String get mergeKey => [
        productId,
        for (final m in selection.selectedModifiers)
          '${m.groupId}:${m.optionId}',
        ...selection.excludedIngredients,
        selection.note,
      ].join('|');

  Map<String, dynamic> toWire() => {
        'kind': 'product',
        'productId': productId,
        'quantity': quantity,
        'selectedModifiers': [
          for (final m in selection.selectedModifiers)
            {'groupId': m.groupId, 'optionId': m.optionId},
        ],
        'note': selection.note,
        'excludedIngredients': selection.excludedIngredients,
      };
}

/// A Turkish phone number in E.164, or `null` — mirrors the server's
/// `normalizeTurkishPhone` so obvious typos are caught before sending.
String? normalizeTurkishPhoneForPos(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  String national;
  if (digits.length == 12 && digits.startsWith('90')) {
    national = digits.substring(2);
  } else if (digits.length == 11 && digits.startsWith('0')) {
    national = digits.substring(1);
  } else if (digits.length == 10) {
    national = digits;
  } else {
    return null;
  }
  return RegExp(r'^[2-5]\d{9}$').hasMatch(national) ? '+90$national' : null;
}

class _PosNewTakeawayOrderScreenState
    extends ConsumerState<PosNewTakeawayOrderScreen> {
  late PosPhoneOrderMode _mode = widget.initialMode;

  final _customerSearchController = TextEditingController();
  List<PosCustomerBookEntry>? _customerResults;
  bool _searchingCustomers = false;
  String? _customerSearchError;
  PosCustomerBookEntry? _selectedCustomer;
  List<PosDeliveryAddressInput> _previousAddresses = const [];

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _streetController = TextEditingController();
  final _buildingNoController = TextEditingController();
  final _apartmentNoController = TextEditingController();
  final _floorController = TextEditingController();
  final _addressDescriptionController = TextEditingController();
  final _courierNoteController = TextEditingController();
  final _kitchenNoteController = TextEditingController();
  final _deliveryFeeController = TextEditingController();
  final _firstNameFocus = FocusNode();

  PosPayOnDeliveryMethod _payOnDelivery = PosPayOnDeliveryMethod.cash;
  String _mealCardBrandId = _mealCardBrands.first.id;
  String? _selectedCourierId;

  final List<_PhoneOrderCartLine> _cartLines = [];
  bool _submitting = false;
  String? _error;

  /// Kept across retries of the same order so a resend after a dropped
  /// response can never create a second order (server idempotency).
  String? _pendingSubmissionKey;

  List<TextEditingController> get _customerControllers => [
        _firstNameController,
        _lastNameController,
        _phoneController,
        _neighborhoodController,
        _streetController,
        _buildingNoController,
        _apartmentNoController,
        _floorController,
        _addressDescriptionController,
      ];

  @override
  void dispose() {
    for (final controller in [
      ..._customerControllers,
      _customerSearchController,
      _courierNoteController,
      _kitchenNoteController,
      _deliveryFeeController,
    ]) {
      controller.dispose();
    }
    _firstNameFocus.dispose();
    super.dispose();
  }

  bool get _isDelivery => _mode == PosPhoneOrderMode.delivery;

  void _orderChanged() => _pendingSubmissionKey = null;

  // --- customer search ------------------------------------------------------

  Future<void> _searchCustomers() async {
    final query = _customerSearchController.text.trim();
    if (query.length < 2) return;
    setState(() {
      _searchingCustomers = true;
      _customerSearchError = null;
    });
    try {
      final results = await ref
          .read(posPhoneOrderGatewayProvider)
          .searchCustomers(
              organizationId: widget.ctx.organizationId, query: query);
      if (mounted) setState(() => _customerResults = results);
    } on PosPhoneOrderException {
      if (mounted) {
        setState(() {
          _customerResults = null;
          _customerSearchError = 'Müşteri araması şu anda yapılamıyor.';
        });
      }
    } finally {
      if (mounted) setState(() => _searchingCustomers = false);
    }
  }

  /// A book record fills the name, the FULL phone and its remembered
  /// addresses; an app customer fills the name only (its phone stays
  /// masked and must be typed).
  void _selectCustomer(PosCustomerBookEntry customer) {
    setState(() {
      _selectedCustomer = customer;
      _customerResults = null;
      _firstNameController.text = customer.firstName;
      _lastNameController.text = customer.lastName;
      _phoneController.text = customer.phoneNumber ?? '';
      _previousAddresses = customer.addresses;
      if (customer.addresses.isNotEmpty) {
        _applyAddress(customer.addresses.first);
      }
      _orderChanged();
    });
  }

  /// "Yeni Müşteri" — clears any selection and starts typing a new one.
  void _startNewCustomer() {
    setState(() {
      _selectedCustomer = null;
      _customerResults = null;
      _previousAddresses = const [];
      for (final controller in _customerControllers) {
        controller.clear();
      }
      _orderChanged();
    });
    _firstNameFocus.requestFocus();
  }

  void _applyAddress(PosDeliveryAddressInput address) {
    _neighborhoodController.text = address.neighborhoodName;
    _streetController.text = address.streetName;
    _buildingNoController.text = address.buildingNo;
    _apartmentNoController.text = address.apartmentNo;
    _floorController.text = address.floor;
    _addressDescriptionController.text = address.addressDescription;
  }

  // --- cart & prices --------------------------------------------------------

  void _addSelection(PosCatalogSelection selection) {
    final line = _PhoneOrderCartLine(selection);
    setState(() {
      _orderChanged();
      for (final existing in _cartLines) {
        if (existing.mergeKey == line.mergeKey) {
          existing.quantity += line.quantity;
          return;
        }
      }
      _cartLines.add(line);
    });
  }

  void _changeQuantity(_PhoneOrderCartLine line, int delta) {
    setState(() {
      _orderChanged();
      line.quantity += delta;
      if (line.quantity <= 0) _cartLines.remove(line);
    });
  }

  /// [line]'s unit price on the current mode's channel, re-priced from the
  /// catalog (the line remembers only what was chosen).
  Money _unitPrice(
    _PhoneOrderCartLine line,
    Map<String, MenuProduct> catalog,
    ChannelPricingPolicy policy,
  ) {
    final channel = _mode.channel;
    final product = catalog[line.productId] ?? line.selection.product;
    var total = ChannelPriceResolver.resolveProductUnitPrice(
      product: product,
      categoryId: product.categoryId,
      channel: channel,
      policy: policy,
    );
    for (final selected in line.selection.selectedModifiers) {
      final option = product.modifierGroups
          .where((g) => g.id == selected.groupId)
          .expand((g) => g.options)
          .where((o) => o.id == selected.optionId)
          .firstOrNull;
      total += ChannelPriceResolver.resolveModifierExtraPrice(
        extraPrice: Money.fromLegacyDoubleTry(
            option?.extraPrice ?? selected.extraPrice),
        channel: channel,
        policy: policy,
      );
    }
    return total;
  }

  /// The manual delivery fee in minor units (whole TL, default 0).
  int get _deliveryFeeMinorUnits {
    final whole = int.tryParse(_deliveryFeeController.text.trim());
    return whole == null || whole < 0 ? 0 : whole * 100;
  }

  String get _paymentMethodId => switch (_payOnDelivery) {
        PosPayOnDeliveryMethod.cash => 'cash',
        PosPayOnDeliveryMethod.card => 'credit_card',
        PosPayOnDeliveryMethod.mealCard => _mealCardBrandId,
      };

  // --- submit ---------------------------------------------------------------

  String? _validate() {
    if (_firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      return 'Ad, soyad ve telefon alanları zorunludur.';
    }
    if (normalizeTurkishPhoneForPos(_phoneController.text) == null) {
      return 'Telefon numarası geçerli değil (ör. 0532 111 22 33).';
    }
    if (_isDelivery &&
        (_neighborhoodController.text.trim().isEmpty ||
            _streetController.text.trim().isEmpty)) {
      return 'Paket servis için mahalle ve cadde / sokak zorunludur.';
    }
    if (_isDelivery &&
        _deliveryFeeController.text.trim().isNotEmpty &&
        int.tryParse(_deliveryFeeController.text.trim()) == null) {
      return 'Teslimat ücretini tam TL olarak girin.';
    }
    if (_cartLines.isEmpty) return 'Sepete en az bir ürün eklemelisiniz.';
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final submissionKey = _pendingSubmissionKey ??=
        DateTime.now().microsecondsSinceEpoch.toString();
    final contact = PosPhoneOrderContact(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      phone: normalizeTurkishPhoneForPos(_phoneController.text)!,
      linkedCustomerId: _selectedCustomer?.linkedCustomerId,
    );
    final items = [for (final line in _cartLines) line.toWire()];
    setState(() {
      _submitting = true;
      _error = null;
    });
    final gateway = ref.read(posPhoneOrderGatewayProvider);
    try {
      if (!_isDelivery) {
        await gateway.submitTakeaway(
          ctx: widget.ctx,
          submissionKey: submissionKey,
          contact: contact,
          items: items,
          kitchenNote: _kitchenNoteController.text.trim(),
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }
      final result = await gateway.submitDelivery(
        ctx: widget.ctx,
        submissionKey: submissionKey,
        contact: contact,
        address: PosDeliveryAddressInput(
          neighborhoodName: _neighborhoodController.text.trim(),
          streetName: _streetController.text.trim(),
          buildingNo: _buildingNoController.text.trim(),
          apartmentNo: _apartmentNoController.text.trim(),
          floor: _floorController.text.trim(),
          addressDescription: _addressDescriptionController.text.trim(),
        ),
        items: items,
        courierNote: _courierNoteController.text.trim(),
        kitchenNote: _kitchenNoteController.text.trim(),
        paymentMethodId: _paymentMethodId,
        deliveryFeeMinorUnits: _deliveryFeeMinorUnits,
        plannedCourierId: _selectedCourierId,
      );
      if (!mounted) return;
      // Product-owner decision: the courier slip prints the moment the
      // order is confirmed; a printer problem never undoes the order.
      await printCourierSlip(
          context: context,
          ref: ref,
          branchId: widget.ctx.branchId,
          orderId: result.orderId);
      if (!mounted) return;
      setState(() => _submitting = false);
      await _showDeliveryConfirmed(result);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PosPhoneOrderException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _messageFor(e);
        _submitting = false;
      });
    }
  }

  static String _messageFor(PosPhoneOrderException e) => switch (e.code) {
        'permission-denied' ||
        'permission_denied' =>
          'Bu işlem için yetkiniz yok.',
        'invalid-argument' ||
        'invalid_argument' =>
          'Sipariş bilgileri geçersiz; alanları kontrol edip tekrar deneyin.',
        'failed-precondition' ||
        'failed_precondition' =>
          'Sipariş şu anda kaydedilemedi (seçilen kurye uygun olmayabilir). '
              'Bilgileri kontrol edin.',
        _ => 'Sipariş gönderilemedi. Lütfen tekrar deneyin.',
      };

  Future<void> _showDeliveryConfirmed(PosPhoneOrderResult result) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Paket Siparişi Onaylandı'),
        content: Text('${result.orderNumber} mutfağa iletildi.'),
        actions: [
          OutlinedButton.icon(
            key: const Key('reprintCourierSlipButton'),
            icon: const Icon(Icons.print_rounded),
            label: const Text('Kurye Fişini Tekrar Yazdır'),
            onPressed: () => printCourierSlip(
              context: dialogContext,
              ref: ref,
              branchId: widget.ctx.branchId,
              orderId: result.orderId,
              isCopy: true,
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Yeni Sipariş'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            if (_customerResults != null || _customerSearchError != null)
              _buildCustomerResults(),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                final isWide = constraints.maxWidth >= AppBreakpoints.tablet;
                final catalog = PosCatalogBrowser(
                  key: ValueKey(_mode),
                  ctx: widget.ctx,
                  wide: isWide,
                  onAdd: _addSelection,
                  priceChannel: _mode.channel,
                  allowWeighedProducts: false,
                );
                final panel = _buildOrderPanel();
                if (!isWide) {
                  return Column(
                    children: [
                      Expanded(child: catalog),
                      const Divider(height: 1, color: AppColors.border),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: panel,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: catalog),
                    Container(width: 1, color: AppColors.border),
                    SizedBox(width: 380, child: panel),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<PosPhoneOrderMode>(
            key: const Key('phoneOrderModeSwitch'),
            segments: [
              for (final mode in PosPhoneOrderMode.values)
                ButtonSegment(
                  value: mode,
                  icon: Icon(mode.icon),
                  label: Text(mode.label),
                ),
            ],
            selected: {_mode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => setState(() {
              _mode = selection.first;
              _orderChanged();
            }),
          ),
          SizedBox(
            width: 360,
            child: TextField(
              key: const Key('customerSearchField'),
              controller: _customerSearchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchCustomers(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Müşteri Ara (İsim veya Tel)',
                prefixIcon: const Icon(Icons.person_search_rounded, size: 20),
                suffixIcon: _searchingCustomers
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.sm),
                        child: SizedBox.square(
                          dimension: AppSpacing.md,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Ara',
                        icon: const Icon(Icons.search_rounded),
                        onPressed: _searchCustomers,
                      ),
                border: const OutlineInputBorder(
                  borderRadius: AppRadius.kPill,
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          OutlinedButton.icon(
            key: const Key('newCustomerButton'),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Yeni Müşteri'),
            onPressed: _startNewCustomer,
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerResults() {
    final results = _customerResults ?? const [];
    // A `Material` (not a coloured box) so the result rows' ink shows.
    return Material(
      key: const Key('customerSearchResults'),
      color: AppColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: _customerSearchError != null
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(_customerSearchError!,
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.error)),
              )
            : results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Kayıtlı müşteri bulunamadı.',
                              style: AppTypography.bodyMedium),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('Yeni Müşteri Gir'),
                          onPressed: _startNewCustomer,
                        ),
                      ],
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final customer in results)
                        ListTile(
                          leading: Icon(customer.isFromBook
                              ? Icons.menu_book_rounded
                              : Icons.phone_iphone_rounded),
                          title: Text(customer.displayName),
                          subtitle: Text([
                            customer.phoneNumber ?? customer.phoneMasked,
                            if (customer.addresses.isNotEmpty)
                              customer.addresses.first.summary,
                          ].join(' · ')),
                          trailing: Text(
                            customer.isFromBook ? 'Defter' : 'Uygulama',
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                          onTap: () => _selectCustomer(customer),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleMedium
                        .copyWith(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label,
      {Key? key,
      FocusNode? focusNode,
      TextInputType? keyboardType,
      int maxLines = 1,
      String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        key: key,
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: (_) => setState(_orderChanged),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(borderRadius: AppRadius.kSmall),
        ),
      ),
    );
  }

  Widget _buildOrderPanel() {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _buildCustomerSection(),
                if (_isDelivery) ...[
                  const SizedBox(height: AppSpacing.md),
                  _buildDeliverySection(),
                ],
                const SizedBox(height: AppSpacing.md),
                _buildCartSection(),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildCustomerSection() {
    final selected = _selectedCustomer;
    return _section('Müşteri', Icons.person_rounded, [
      if (selected != null && !selected.isFromBook)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            'Uygulama müşterisi: ${selected.displayName} · '
            '${selected.phoneMasked}\nTelefon gizlilik gereği maskeli — '
            'numarayı girin; ilk siparişten sonra deftere kaydedilir.',
            key: const Key('selectedCustomerNotice'),
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
        ),
      Row(
        children: [
          Expanded(
            child: _field(_firstNameController, 'Ad',
                key: const Key('takeawayFirstNameField'),
                focusNode: _firstNameFocus),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _field(_lastNameController, 'Soyad',
                key: const Key('takeawayLastNameField')),
          ),
        ],
      ),
      _field(_phoneController, 'Telefon',
          key: const Key('takeawayPhoneField'),
          keyboardType: TextInputType.phone,
          hint: '0532 111 22 33'),
    ]);
  }

  Widget _buildDeliverySection() {
    final couriers = ref
            .watch(allCouriersForBranchProvider(widget.ctx.branchId))
            .valueOrNull
            ?.where((c) =>
                c.type == CourierType.internal &&
                c.status == CourierRegistryStatus.active)
            .toList() ??
        const <Courier>[];
    return _section('Teslimat', Icons.delivery_dining_rounded, [
      if (_previousAddresses.isNotEmpty) ...[
        const Text('Önceki Adresler', style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final address in _previousAddresses)
              ActionChip(
                avatar: const Icon(Icons.history_rounded, size: 18),
                label: Text(
                  address.label.isEmpty
                      ? address.summary
                      : '${address.label} — ${address.summary}',
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () => setState(() {
                  _applyAddress(address);
                  _orderChanged();
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      _field(_neighborhoodController, 'Mahalle',
          key: const Key('deliveryNeighborhoodField')),
      _field(_streetController, 'Cadde / Sokak',
          key: const Key('deliveryStreetField')),
      Row(
        children: [
          Expanded(child: _field(_buildingNoController, 'Bina No')),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _field(_apartmentNoController, 'Daire')),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _field(_floorController, 'Kat')),
        ],
      ),
      _field(_addressDescriptionController, 'Adres Tarifi', maxLines: 2),
      _field(_courierNoteController, 'Kurye Notu',
          key: const Key('courierNoteField'),
          maxLines: 2,
          hint: 'Zile basmayın, bahçe kapısından girin…'),
      const Text('Kapıda Ödeme', style: AppTypography.labelLarge),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final method in PosPayOnDeliveryMethod.values)
            ChoiceChip(
              avatar: Icon(method.icon, size: 18),
              label: Text(method.label),
              selected: _payOnDelivery == method,
              onSelected: (_) => setState(() {
                _payOnDelivery = method;
                _orderChanged();
              }),
            ),
        ],
      ),
      if (_payOnDelivery == PosPayOnDeliveryMethod.mealCard) ...[
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          key: const Key('mealCardBrands'),
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final brand in _mealCardBrands)
              ChoiceChip(
                label: Text(brand.label),
                selected: _mealCardBrandId == brand.id,
                onSelected: (_) => setState(() {
                  _mealCardBrandId = brand.id;
                  _orderChanged();
                }),
              ),
          ],
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      _field(_deliveryFeeController, 'Teslimat Ücreti (TL)',
          key: const Key('deliveryFeeField'),
          keyboardType: TextInputType.number,
          hint: '0'),
      const Text('Kurye', style: AppTypography.labelLarge),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        key: const Key('courierBadges'),
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final courier in couriers)
            ChoiceChip(
              avatar: const Icon(Icons.two_wheeler_rounded, size: 18),
              label: Text(courier.displayName),
              selected: _selectedCourierId == courier.id,
              onSelected: (selected) => setState(() {
                _selectedCourierId = selected ? courier.id : null;
                _orderChanged();
              }),
            ),
          const Tooltip(
            message: 'Kurye havuzu bir sonraki aşamada (Faz 3) açılacak.',
            child: ChoiceChip(
              avatar: Icon(Icons.groups_rounded, size: 18),
              label: Text('Kurye Havuzu'),
              selected: false,
              onSelected: null,
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          couriers.isEmpty
              ? 'Bu şubede kayıtlı aktif dükkan kuryesi yok.'
              : 'Seçilen kurye siparişe planlanır; atama sipariş hazır '
                  'olunca dağıtım listesinden tek dokunuşla yapılır.',
          style:
              AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
      ),
    ]);
  }

  Widget _buildCartSection() {
    final catalog = {
      for (final product in ref.watch(menuProductsProvider)) product.id: product
    };
    final policy =
        ref.watch(channelPricingPolicySnapshotProvider).valueOrNull ??
            const ChannelPricingPolicy();
    var total = Money.fromLegacyDoubleTry(0);
    final rows = <Widget>[];
    for (final line in _cartLines) {
      final unit = _unitPrice(line, catalog, policy);
      total += unit * line.quantity;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.productName, style: AppTypography.bodyMedium),
                  if (line.selection.selectedModifiers.isNotEmpty ||
                      line.selection.note.isNotEmpty)
                    Text(
                      [
                        for (final m in line.selection.selectedModifiers)
                          m.optionName,
                        if (line.selection.note.isNotEmpty)
                          'Not: ${line.selection.note}',
                      ].join(', '),
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  Text(_tl(unit * line.quantity),
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.primary)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_rounded, size: 18),
              tooltip: 'Azalt',
              onPressed: () => _changeQuantity(line, -1),
            ),
            Text('${line.quantity}', style: AppTypography.bodyMedium),
            IconButton(
              icon: const Icon(Icons.add_rounded, size: 18),
              tooltip: 'Artır',
              onPressed: () => _changeQuantity(line, 1),
            ),
          ],
        ),
      ));
    }
    final fee = _isDelivery ? _deliveryFeeMinorUnits : 0;
    return _section(
        'Sipariş · ${_mode.label} fiyatları', Icons.receipt_long_rounded, [
      if (_cartLines.isEmpty)
        Text('Soldaki menüden ürün ekleyin.',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary))
      else
        ...rows,
      const Divider(),
      if (fee > 0)
        Row(
          children: [
            const Expanded(
                child:
                    Text('Teslimat Ücreti', style: AppTypography.bodyMedium)),
            Text(_tl(Money(fee, total.currency)),
                style: AppTypography.bodyMedium),
          ],
        ),
      Row(
        children: [
          const Expanded(
              child: Text('Toplam', style: AppTypography.titleMedium)),
          Text(
            _tl(total + Money(fee, total.currency)),
            key: const Key('phoneOrderTotal'),
            style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        key: const Key('kitchenNoteField'),
        controller: _kitchenNoteController,
        maxLines: 2,
        maxLength: 500,
        onChanged: (_) => _orderChanged(),
        decoration: const InputDecoration(
          labelText: 'Mutfak Notu',
          hintText: 'Et orta-iyi pişsin, sosu bol olsun…',
          helperText: 'KDS ekranında ve mutfak fişinde görünür.',
          isDense: true,
          counterText: '',
          border: OutlineInputBorder(borderRadius: AppRadius.kSmall),
        ),
      ),
    ]);
  }

  static String _tl(Money money) =>
      '${(money.minorUnits / 100).toStringAsFixed(0)} TL';

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(_error!,
                  key: const Key('phoneOrderError'),
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error)),
            ),
          if (_isDelivery) ...[
            Tooltip(
              message: 'Kurye fişi sipariş onaylanınca otomatik basılır; '
                  'onay penceresinden tekrar yazdırılabilir.',
              child: OutlinedButton.icon(
                key: const Key('printCourierSlipButton'),
                icon: const Icon(Icons.print_rounded),
                label: const Text('Kurye Fişi Yazdır'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56)),
                // No order exists before confirmation — the slip prints
                // automatically on confirmation.
                onPressed: null,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          ElevatedButton.icon(
            key: const Key('submitNewTakeawayOrderButton'),
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size.fromHeight(56),
              textStyle: AppTypography.titleMedium
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            icon: _submitting
                ? const SizedBox.square(
                    dimension: AppSpacing.md,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restaurant_rounded),
            label: const Text('Siparişi Onayla & Mutfağa İlet'),
          ),
        ],
      ),
    );
  }
}
