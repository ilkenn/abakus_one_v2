import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../crm/domain/segmentation/customer.dart';
import '../../../crm/domain/segmentation/customer_account_status.dart';
import '../../../crm/presentation/providers/crm_dependencies_provider.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import 'customer_detail_screen.dart';

/// Customer administration — Phase 6F (`docs/decisions.md` ADR-023).
/// Search is client-side over `CustomerRepository.findAll()` (no
/// dedicated search query exists on the repository — this codebase's
/// `Customer` registry is small enough in-memory that this is an honest,
/// not-fabricated, approach; a real backend would need a proper indexed
/// search). Filters by name, phone, or category name.
///
/// **Access is enforced by `RoleGate` at the shell's push site, not
/// here** — this screen itself doesn't re-check role because
/// `PosAuthorizedAction.viewCustomerAdmin` is staff-tier, so any staff
/// member reaching this screen at all is already permitted the base
/// view. "Courier: no customer-management access" holds because this
/// screen is never wired into any courier-visible section of the shell.
class CustomerManagementScreen extends ConsumerStatefulWidget {
  const CustomerManagementScreen({
    super.key,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<CustomerManagementScreen> createState() =>
      _CustomerManagementScreenState();
}

class _CustomerManagementScreenState
    extends ConsumerState<CustomerManagementScreen> {
  List<Customer>? _customers;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final customers = await ref.read(customerRepositoryProvider).findAll();
    if (!mounted) return;
    setState(() => _customers = customers);
  }

  List<Customer> _filtered(List<Customer> customers) {
    if (_query.trim().isEmpty) return customers;
    final query = _query.toLowerCase();
    return customers
        .where((c) =>
            c.displayName.toLowerCase().contains(query) ||
            c.phoneNumber.contains(query) ||
            (c.category?.name.toLowerCase().contains(query) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final customers = _customers;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Müşteri Yönetimi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: customers == null
            ? const LoadingView(message: 'Müşteriler yükleniyor...')
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'İsim, telefon veya kategoriye göre ara',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      children: [
                        for (final customer in _filtered(customers))
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: AppCard(
                              padding: EdgeInsets.zero,
                              child: ListTile(
                                leading: Icon(
                                  Icons.person_outline,
                                  color: customer.accountStatus ==
                                          CustomerAccountStatus.active
                                      ? AppColors.primary
                                      : AppColors.error,
                                ),
                                title: Text(customer.displayName,
                                    style: AppTypography.bodyLarge),
                                subtitle: Text(
                                  '${customer.phoneNumber} · '
                                  '${customer.category?.name ?? 'kategori yok'} · '
                                  '${customer.accountStatus.name}',
                                  style: AppTypography.bodySmall
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CustomerDetailScreen(
                                      customerId: customer.id,
                                      authorizationPolicy:
                                          widget.authorizationPolicy,
                                      performedByStaffId:
                                          widget.performedByStaffId,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
