import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/tenant_customer_directory_gateway.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/customer_detail_screen.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/customer_management_screen.dart';

/// AP-3 continuation (ADR-039) — the Admin Customers screen's real test
/// matrix, rewired onto [TenantCustomerDirectoryGateway]. Mirrors
/// `device_registry_screen_test.dart`'s established "override the gateway
/// provider with a plain fake" convention.
class _FakeTenantCustomerDirectoryGateway
    implements TenantCustomerDirectoryGateway {
  _FakeTenantCustomerDirectoryGateway({
    this.summaries = const [],
    this.pageSize = 30,
  });

  List<TenantCustomerSummary> summaries;
  int pageSize;
  TenantCustomerDirectoryException? errorToThrow;
  TenantCustomerDetail? detailToReturn;
  TenantCustomerDirectoryException? detailErrorToThrow;

  String? lastSetRestrictionReasonCode;
  String? lastSetRestrictionReasonMessage;
  bool? lastSetRestrictionValue;

  @override
  Future<TenantCustomerListPage> list({
    required String organizationId,
    String? namePrefix,
    String? cursor,
  }) async {
    final error = errorToThrow;
    if (error != null) throw error;
    var filtered = namePrefix == null || namePrefix.isEmpty
        ? summaries
        : summaries
            .where((c) =>
                c.displayName.toLowerCase().contains(namePrefix.toLowerCase()))
            .toList();
    final startIndex = cursor == null
        ? 0
        : filtered.indexWhere((c) => c.id == cursor) + 1;
    final page = filtered.skip(startIndex).take(pageSize).toList();
    final isLastPage = startIndex + page.length >= filtered.length;
    return TenantCustomerListPage(
      customers: page,
      nextCursor: isLastPage || page.isEmpty ? null : page.last.id,
    );
  }

  @override
  Future<List<TenantCustomerSearchResult>> search({
    required String organizationId,
    String? phoneNumber,
    String? namePrefix,
  }) async {
    return const [];
  }

  @override
  Future<TenantCustomerDetail> getDetail({
    required String organizationId,
    required String customerId,
  }) async {
    final error = detailErrorToThrow;
    if (error != null) throw error;
    final detail = detailToReturn;
    if (detail == null) {
      throw const TenantCustomerDirectoryException(
        'not-found',
        'Customer not found for this organization.',
      );
    }
    return detail;
  }

  @override
  Future<void> setRestriction({
    required String organizationId,
    required String customerId,
    required bool restrict,
    required String reasonCode,
    required String reasonMessage,
  }) async {
    lastSetRestrictionValue = restrict;
    lastSetRestrictionReasonCode = reasonCode;
    lastSetRestrictionReasonMessage = reasonMessage;
  }
}

TenantCustomerSummary _summary({
  required String id,
  required String displayName,
  String accountState = 'active',
  int totalOrderCount = 3,
}) {
  return TenantCustomerSummary(
    id: id,
    displayName: displayName,
    registrationDate: DateTime(2026, 1, 1),
    lastActivityAt: DateTime(2026, 8, 1),
    accountState: accountState,
    relatedBranchIds: const ['branch-1'],
    lastOrderAt: DateTime(2026, 8, 1),
    totalOrderCount: totalOrderCount,
  );
}

Future<_Pumped> _pumpManagementScreen(
  WidgetTester tester, {
  required _FakeTenantCustomerDirectoryGateway gateway,
}) async {
  final container = ProviderContainer(
    overrides: [
      currentOrganizationIdProvider.overrideWith((ref) => 'org-1'),
      tenantCustomerDirectoryGatewayProvider.overrideWithValue(gateway),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CustomerManagementScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return _Pumped(container);
}

class _Pumped {
  _Pumped(this.container);
  final ProviderContainer container;
}

void main() {
  testWidgets('loading then data: renders the customer list', (tester) async {
    final gateway = _FakeTenantCustomerDirectoryGateway(summaries: [
      _summary(id: 'cust-1', displayName: 'Ayşe Yılmaz'),
      _summary(id: 'cust-2', displayName: 'Mehmet Kaya'),
    ]);
    await _pumpManagementScreen(tester, gateway: gateway);

    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('Mehmet Kaya'), findsOneWidget);
  });

  testWidgets('empty state: no customers at all', (tester) async {
    final gateway = _FakeTenantCustomerDirectoryGateway(summaries: const []);
    await _pumpManagementScreen(tester, gateway: gateway);

    expect(find.textContaining('henüz kayıtlı müşteri yok'), findsOneWidget);
  });

  testWidgets('error state: permission-denied shows a Turkish unauthorized '
      'message with a retry button', (tester) async {
    final gateway = _FakeTenantCustomerDirectoryGateway()
      ..errorToThrow = const TenantCustomerDirectoryException(
        'permission-denied',
        'The "viewTenantCustomerDirectory" permission is required.',
      );
    await _pumpManagementScreen(tester, gateway: gateway);

    expect(find.textContaining('görüntüleme yetkiniz yok'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Tekrar Dene'), findsOneWidget);
  });

  testWidgets('search: typing filters via namePrefix through the gateway',
      (tester) async {
    final gateway = _FakeTenantCustomerDirectoryGateway(summaries: [
      _summary(id: 'cust-1', displayName: 'Ayşe Yılmaz'),
      _summary(id: 'cust-2', displayName: 'Mehmet Kaya'),
    ]);
    await _pumpManagementScreen(tester, gateway: gateway);

    await tester.enterText(find.byType(TextField), 'Ayşe');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('Mehmet Kaya'), findsNothing);
  });

  testWidgets('pagination: Daha Fazla Yükle loads the next page and appends',
      (tester) async {
    final gateway = _FakeTenantCustomerDirectoryGateway(
      pageSize: 1,
      summaries: [
        _summary(id: 'cust-1', displayName: 'Ayşe Yılmaz'),
        _summary(id: 'cust-2', displayName: 'Mehmet Kaya'),
      ],
    );
    await _pumpManagementScreen(tester, gateway: gateway);

    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('Mehmet Kaya'), findsNothing);
    expect(find.text('Daha Fazla Yükle'), findsOneWidget);

    await tester.tap(find.text('Daha Fazla Yükle'));
    await tester.pumpAndSettle();

    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('Mehmet Kaya'), findsOneWidget);
  });

  testWidgets('tapping a customer pushes the detail screen', (tester) async {
    final gateway = _FakeTenantCustomerDirectoryGateway(summaries: [
      _summary(id: 'cust-1', displayName: 'Ayşe Yılmaz'),
    ])
      ..detailToReturn = TenantCustomerDetail(
        id: 'cust-1',
        displayName: 'Ayşe Yılmaz',
        phoneMasked: '***45',
        registrationDate: DateTime(2026, 1, 1),
        lastActivityAt: DateTime(2026, 8, 1),
        accountState: 'active',
        relatedBranchIds: const ['branch-1'],
        lastOrderAt: DateTime(2026, 8, 1),
        totalOrderCount: 5,
        orderAddressSnapshots: const [],
        restrictionStatus: 'none',
        restrictionReasonMessage: null,
        marketingConsent: 'notCaptured',
      );
    await _pumpManagementScreen(tester, gateway: gateway);

    await tester.tap(find.text('Ayşe Yılmaz'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerDetailScreen), findsOneWidget);
    expect(find.text('***45'), findsOneWidget);
  });
}
