import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/tenant_customer_directory_gateway.dart';
import '../providers/admin_dependencies_provider.dart';
import 'customer_detail_screen.dart';

/// Customer administration — AP-3 continuation (`docs/decisions.md`
/// ADR-039). Rewires the canonical `customer-360`/"Müşteri 360" Admin
/// destination onto the real, server-authoritative tenant Customer
/// Directory backend (`listTenantCustomers`/`searchCustomersForPos`),
/// replacing the previous in-memory `CustomerRepository.findAll()` +
/// client-side substring filter.
///
/// **Access is enforced by `RoleGate` at the shell's push site** (unchanged
/// from before this rewire) — the REAL, authoritative enforcement is
/// server-side: `listTenantCustomers`/`getTenantCustomerDetail` both
/// require the `viewTenantCustomerDirectory` `StaffPermission`
/// (`functions/src/staffAuthorization.ts`), a structurally separate
/// authorization system from the client-side `RoleGate`/
/// `PosAuthorizedAction` convenience filter — a caller lacking the real
/// permission is rejected by the callable itself (`permission-denied`),
/// surfaced here as an explicit unauthorized error state, never a silent
/// empty list.
class CustomerManagementScreen extends ConsumerStatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  ConsumerState<CustomerManagementScreen> createState() =>
      _CustomerManagementScreenState();
}

class _CustomerManagementScreenState
    extends ConsumerState<CustomerManagementScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<TenantCustomerSummary>? _customers;
  String? _nextCursor;
  bool _loadingMore = false;
  Object? _error;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _organizationId => ref.read(currentOrganizationIdProvider);

  Future<void> _load({bool append = false}) async {
    if (append) {
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _customers = null;
        _error = null;
        _nextCursor = null;
      });
    }
    try {
      final page = await ref.read(tenantCustomerDirectoryGatewayProvider).list(
            organizationId: _organizationId,
            namePrefix: _activeQuery.isEmpty ? null : _activeQuery,
            cursor: append ? _nextCursor : null,
          );
      if (!mounted) return;
      setState(() {
        _customers =
            append ? [...?_customers, ...page.customers] : page.customers;
        _nextCursor = page.nextCursor;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loadingMore = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _activeQuery = value.trim();
      _load();
    });
  }

  String _errorMessage(Object error) {
    if (error is TenantCustomerDirectoryException) {
      if (error.code == 'permission-denied') {
        return 'Müşteri dizinini görüntüleme yetkiniz yok.';
      }
      return error.message;
    }
    return 'Müşteriler yüklenirken bir sorun oluştu.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Müşteri Yönetimi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'İsme göre ara',
                  border: OutlineInputBorder(),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final error = _error;
    final customers = _customers;
    if (error != null && customers == null) {
      return ErrorView(
        message: _errorMessage(error),
        retryLabel: 'Tekrar Dene',
        onRetry: () => _load(),
      );
    }
    if (customers == null) {
      return const LoadingView(message: 'Müşteriler yükleniyor...');
    }
    if (customers.isEmpty) {
      return EmptyView(
        icon: Icons.people_outline,
        message: _activeQuery.isEmpty
            ? 'Bu şubede henüz kayıtlı müşteri yok.'
            : '"$_activeQuery" ile eşleşen müşteri bulunamadı.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: customers.length + (_nextCursor != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == customers.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: () => _load(append: true),
                      child: const Text('Daha Fazla Yükle'),
                    ),
            ),
          );
        }
        final customer = customers[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(
                Icons.person_outline,
                color: customer.accountState == 'active'
                    ? AppColors.primary
                    : AppColors.error,
              ),
              title: Text(customer.displayName, style: AppTypography.bodyLarge),
              subtitle: Text(
                '${customer.totalOrderCount} sipariş · '
                'Son aktivite: ${_formatDate(customer.lastActivityAt)} · '
                '${customer.accountState}',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CustomerDetailScreen(
                    customerId: customer.id,
                    organizationId: _organizationId,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
