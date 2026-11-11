import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/courier_type.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../admin/data/tenant_customer_directory_gateway.dart';
import '../../../admin/presentation/providers/admin_dependencies_provider.dart';
import '../../../courier/domain/identity/courier.dart';
import '../../../courier/domain/identity/courier_registry_status.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/domain/models/selected_modifier.dart';
import '../../../takeaway/data/submit_takeaway_order_gateway.dart';
import '../../../takeaway/presentation/providers/takeaway_dependencies_provider.dart';
import '../../data/pos_action_gateway.dart' show PosDeviceContext;
import '../providers/courier_dispatch_dependencies_provider.dart';
import '../widgets/pos_catalog_browser.dart';

/// The two modes of the phone / counter order screen (2026-11-11).
enum PosPhoneOrderMode {
  takeaway('Gel-Al', Icons.shopping_bag_outlined),
  delivery('Paket Servis', Icons.delivery_dining_rounded);

  const PosPhoneOrderMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Pay-on-delivery choices for a delivery order (Faz 2 sends them).
enum PosPayOnDeliveryMethod {
  cash('Kapıda Nakit', Icons.payments_outlined),
  card('Kapıda POS', Icons.credit_card_rounded),
  mealCard('Kapıda Yemek Kartı', Icons.restaurant_rounded);

  const PosPayOnDeliveryMethod(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// "Yeni Gel-Al / Paket Servis Siparişi" — 2026-11-11 redesign (product
/// owner, Faz 1), replacing the flat searchable product list:
///
/// - top: a Gel-Al / Paket Servis mode switch and a "Müşteri Ara (İsim veya
///   Tel)" search over the organization's customer directory (no Caller ID);
/// - left/centre: the shared touch catalog ([PosCatalogBrowser] — category
///   rail, photo product cards, customization dialog), the same one the
///   table workspace uses;
/// - right: customer details, the cart, the kitchen note and the actions.
///   Paket Servis adds the address, the courier note, pay-on-delivery
///   choices and the shop's courier badges.
///
/// **Faz 1 scope (disclosed)**: Gel-Al orders are sent with the existing
/// `submitTakeawayOrder` staff-entry call. A delivery order cannot be
/// created by staff on the server yet, and there is no order-level kitchen
/// note or pre-assigned courier field — those (and the courier slip and the
/// local customer book with full phone numbers) are Faz 2, so their controls
/// are shown disabled with a plain explanation instead of pretending to
/// send. The courier pool is Faz 3.
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

  final PosCatalogSelection selection;
  int quantity;

  MenuProduct get product => selection.product;
  List<SelectedModifier> get selectedModifiers => selection.selectedModifiers;

  /// Same product + same configuration = one line (quantity merges); a
  /// weighed line never merges.
  String get mergeKey => selection.weightGrams != null
      ? '${identityHashCode(this)}'
      : [
          product.id,
          for (final m in selectedModifiers) '${m.groupId}:${m.optionId}',
          ...selection.excludedIngredients,
          selection.note,
        ].join('|');

  double get unitPrice =>
      product.basePrice +
      selectedModifiers.fold(0.0, (sum, m) => sum + m.extraPrice);

  /// A weighed product is priced by the server from its per-kg price.
  double? get totalRowPrice =>
      selection.weightGrams != null ? null : unitPrice * quantity;
}

/// 2026-11-11 — notices for the parts that need the Faz 2 server work.
const _deliverySubmitNotice =
    'Paket servis siparişinin kaydı bir sonraki güncellemede (Faz 2) '
    'açılacak. Şimdilik Gel-Al siparişi gönderilebilir.';
const _kitchenNoteNotice =
    'Sipariş geneli mutfak notu bir sonraki güncellemede iletilecek; '
    'şimdilik ürün notlarını kullanın.';

class _PosNewTakeawayOrderScreenState
    extends ConsumerState<PosNewTakeawayOrderScreen> {
  late PosPhoneOrderMode _mode = widget.initialMode;

  final _customerSearchController = TextEditingController();
  List<TenantCustomerSearchResult>? _customerResults;
  bool _searchingCustomers = false;
  String? _customerSearchError;
  TenantCustomerSearchResult? _selectedCustomer;
  List<Map<String, dynamic>> _previousAddresses = const [];

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _streetController = TextEditingController();
  final _buildingNoController = TextEditingController();
  final _apartmentNoController = TextEditingController();
  final _addressDescriptionController = TextEditingController();
  final _courierNoteController = TextEditingController();
  final _kitchenNoteController = TextEditingController();
  final _firstNameFocus = FocusNode();

  PosPayOnDeliveryMethod _payOnDelivery = PosPayOnDeliveryMethod.cash;
  String? _selectedCourierId;

  final List<_PhoneOrderCartLine> _cartLines = [];
  bool _submitting = false;
  String? _error;

  static final _phoneLikeQuery = RegExp(r'^[+\d][\d\s]*$');

  @override
  void dispose() {
    for (final controller in [
      _customerSearchController,
      _firstNameController,
      _lastNameController,
      _phoneController,
      _neighborhoodController,
      _streetController,
      _buildingNoController,
      _apartmentNoController,
      _addressDescriptionController,
      _courierNoteController,
      _kitchenNoteController,
    ]) {
      controller.dispose();
    }
    _firstNameFocus.dispose();
    super.dispose();
  }

  bool get _isDelivery => _mode == PosPhoneOrderMode.delivery;

  // --- customer search ------------------------------------------------------

  Future<void> _searchCustomers() async {
    final query = _customerSearchController.text.trim();
    if (query.isEmpty) return;
    final isPhoneLike = _phoneLikeQuery.hasMatch(query);
    setState(() {
      _searchingCustomers = true;
      _customerSearchError = null;
    });
    try {
      final results =
          await ref.read(tenantCustomerDirectoryGatewayProvider).search(
                organizationId: widget.ctx.organizationId,
                phoneNumber: isPhoneLike ? query.replaceAll(' ', '') : null,
                namePrefix: isPhoneLike ? null : query,
              );
      if (mounted) setState(() => _customerResults = results);
    } on TenantCustomerDirectoryException {
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

  /// Fills the name and loads this customer's previous delivery addresses
  /// (the organization's own past orders only — the directory never exposes
  /// the customer's private address book). The phone stays masked: the full
  /// number of an app customer is not shared with the POS.
  Future<void> _selectCustomer(TenantCustomerSearchResult customer) async {
    final parts = customer.displayName.trim().split(RegExp(r'\s+'));
    setState(() {
      _selectedCustomer = customer;
      _customerResults = null;
      _firstNameController.text = parts.isEmpty ? '' : parts.first;
      _lastNameController.text =
          parts.length > 1 ? parts.skip(1).join(' ') : '';
      _previousAddresses = const [];
    });
    try {
      final detail =
          await ref.read(tenantCustomerDirectoryGatewayProvider).getDetail(
                organizationId: widget.ctx.organizationId,
                customerId: customer.id,
              );
      if (!mounted || _selectedCustomer?.id != customer.id) return;
      setState(() => _previousAddresses = detail.orderAddressSnapshots);
      if (detail.orderAddressSnapshots.isNotEmpty) {
        _applyAddress(detail.orderAddressSnapshots.first);
      }
    } on TenantCustomerDirectoryException {
      // The name is already filled; addresses are typed by hand.
    }
  }

  /// "Yeni Müşteri" — clears any selection and starts typing a new one.
  void _startNewCustomer() {
    setState(() {
      _selectedCustomer = null;
      _customerResults = null;
      _previousAddresses = const [];
      for (final controller in [
        _firstNameController,
        _lastNameController,
        _phoneController,
        _neighborhoodController,
        _streetController,
        _buildingNoController,
        _apartmentNoController,
        _addressDescriptionController,
      ]) {
        controller.clear();
      }
    });
    _firstNameFocus.requestFocus();
  }

  void _applyAddress(Map<String, dynamic> snapshot) {
    String text(String key) => (snapshot[key] as String?) ?? '';
    setState(() {
      _neighborhoodController.text = text('neighborhoodName');
      _streetController.text = text('streetName');
      _buildingNoController.text = text('buildingNo');
      _apartmentNoController.text = text('apartmentNo');
      _addressDescriptionController.text = text('addressDescription');
    });
  }

  static String _addressSummary(Map<String, dynamic> snapshot) {
    final parts = [
      snapshot['neighborhoodName'],
      snapshot['streetName'],
      if (snapshot['buildingNo'] != null) 'No ${snapshot['buildingNo']}',
      if ((snapshot['apartmentNo'] as String?)?.isNotEmpty ?? false)
        'D ${snapshot['apartmentNo']}',
    ].whereType<String>().where((p) => p.isNotEmpty);
    final label = snapshot['label'] as String?;
    final summary = parts.join(', ');
    return label == null || label.isEmpty ? summary : '$label — $summary';
  }

  // --- cart -----------------------------------------------------------------

  void _addSelection(PosCatalogSelection selection) {
    final line = _PhoneOrderCartLine(selection);
    setState(() {
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
      line.quantity += delta;
      if (line.quantity <= 0) _cartLines.remove(line);
    });
  }

  double get _total =>
      _cartLines.fold(0.0, (sum, line) => sum + (line.totalRowPrice ?? 0.0));

  bool get _hasWeighedLine =>
      _cartLines.any((line) => line.selection.weightGrams != null);

  // --- submit ---------------------------------------------------------------

  Future<void> _submit() async {
    if (_isDelivery) return; // Faz 2 — see [_deliverySubmitNotice].
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();
    if (firstName.isEmpty || lastName.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Ad, soyad ve telefon alanları zorunludur.');
      return;
    }
    if (_cartLines.isEmpty) {
      setState(() => _error = 'Sepete en az bir ürün eklemelisiniz.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(submitTakeawayOrderGatewayProvider).submitStaffEntryOrder(
        submissionKey: DateTime.now().microsecondsSinceEpoch.toString(),
        organizationId: widget.ctx.organizationId,
        branchId: widget.ctx.branchId,
        deviceId: widget.ctx.deviceId,
        deviceSessionId: widget.ctx.deviceSessionId,
        contactFirstName: firstName,
        contactLastName: lastName,
        contactPhone: phone,
        items: [
          for (final line in _cartLines)
            TakeawayProductItem(
              productId: line.product.id,
              quantity: line.selection.weightGrams != null ? 1 : line.quantity,
              selectedModifiers: [
                for (final modifier in line.selectedModifiers)
                  (groupId: modifier.groupId, optionId: modifier.optionId),
              ],
              note: line.selection.note,
              excludedIngredients: line.selection.excludedIngredients,
              weightGrams: line.selection.weightGrams,
            ),
        ],
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SubmitTakeawayOrderException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    }
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
                  ctx: widget.ctx,
                  wide: isWide,
                  onAdd: _addSelection,
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
            onSelectionChanged: (selection) =>
                setState(() => _mode = selection.first),
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
        constraints: const BoxConstraints(maxHeight: 220),
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
                          leading: const Icon(Icons.person_rounded),
                          title: Text(customer.displayName),
                          subtitle: Text(customer.phoneMasked),
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
              Text(title,
                  style: AppTypography.titleMedium
                      .copyWith(fontWeight: FontWeight.bold)),
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
      if (selected != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            'Kayıtlı müşteri: ${selected.displayName} · ${selected.phoneMasked}\n'
            'Telefon gizlilik gereği maskeli — teyit için numarayı girin.',
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
          keyboardType: TextInputType.phone),
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
                label: Text(_addressSummary(address),
                    overflow: TextOverflow.ellipsis),
                onPressed: () => _applyAddress(address),
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
              onSelected: (_) => setState(() => _payOnDelivery = method),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
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
              onSelected: (selected) => setState(
                  () => _selectedCourierId = selected ? courier.id : null),
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
      if (couriers.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text('Bu şubede kayıtlı aktif dükkan kuryesi yok.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
        ),
    ]);
  }

  Widget _buildCartSection() {
    return _section('Sipariş', Icons.receipt_long_rounded, [
      if (_cartLines.isEmpty)
        Text('Soldaki menüden ürün ekleyin.',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary))
      else
        for (final line in _cartLines)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.product.name, style: AppTypography.bodyMedium),
                      if (line.selectedModifiers.isNotEmpty ||
                          line.selection.note.isNotEmpty)
                        Text(
                          [
                            for (final m in line.selectedModifiers)
                              m.optionName,
                            if (line.selection.note.isNotEmpty)
                              'Not: ${line.selection.note}',
                          ].join(', '),
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                if (line.selection.weightGrams != null)
                  Text('${line.selection.weightGrams} g',
                      style: AppTypography.bodyMedium)
                else ...[
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
                if (line.selection.weightGrams != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    tooltip: 'Satırı Kaldır',
                    onPressed: () => _changeQuantity(line, -line.quantity),
                  ),
              ],
            ),
          ),
      const Divider(),
      Row(
        children: [
          const Expanded(
              child: Text('Toplam', style: AppTypography.titleMedium)),
          Text(
            '${_total.toStringAsFixed(0)} TL${_hasWeighedLine ? ' + tartı' : ''}',
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
        enabled: false,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Mutfak Notu',
          hintText: 'Et orta-iyi pişsin, sosu bol olsun…',
          helperText: _kitchenNoteNotice,
          helperMaxLines: 2,
          isDense: true,
          border: OutlineInputBorder(borderRadius: AppRadius.kSmall),
        ),
      ),
    ]);
  }

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
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error)),
            ),
          if (_isDelivery) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(_deliverySubmitNotice,
                  key: const Key('deliverySubmitNotice'),
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.warning)),
            ),
            OutlinedButton.icon(
              key: const Key('printCourierSlipButton'),
              icon: const Icon(Icons.print_rounded),
              label: const Text('Kurye Fişi Yazdır'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56)),
              onPressed: null,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          ElevatedButton.icon(
            key: const Key('submitNewTakeawayOrderButton'),
            onPressed: _submitting || _isDelivery ? null : _submit,
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
