import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/tenant_customer_directory_gateway.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/customer_detail_screen.dart';

class _FakeTenantCustomerDirectoryGateway
    implements TenantCustomerDirectoryGateway {
  TenantCustomerDetail? detailToReturn;
  TenantCustomerDirectoryException? detailErrorToThrow;
  int getDetailCallCount = 0;

  bool? lastSetRestrictionValue;
  String? lastSetRestrictionReasonCode;
  String? lastSetRestrictionReasonMessage;

  @override
  Future<TenantCustomerListPage> list({
    required String organizationId,
    String? namePrefix,
    String? cursor,
  }) async =>
      const TenantCustomerListPage(customers: [], nextCursor: null);

  @override
  Future<List<TenantCustomerSearchResult>> search({
    required String organizationId,
    String? phoneNumber,
    String? namePrefix,
  }) async =>
      const [];

  @override
  Future<TenantCustomerDetail> getDetail({
    required String organizationId,
    required String customerId,
  }) async {
    getDetailCallCount += 1;
    final error = detailErrorToThrow;
    if (error != null) throw error;
    final detail = detailToReturn;
    if (detail == null) {
      throw const TenantCustomerDirectoryException('not-found', 'Not found.');
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
    // The next getDetail() call reflects the mutation, exactly like the
    // real backend would after a successful write + re-read.
    final current = detailToReturn;
    if (current != null) {
      detailToReturn = TenantCustomerDetail(
        id: current.id,
        displayName: current.displayName,
        phoneMasked: current.phoneMasked,
        registrationDate: current.registrationDate,
        lastActivityAt: current.lastActivityAt,
        accountState: current.accountState,
        relatedBranchIds: current.relatedBranchIds,
        lastOrderAt: current.lastOrderAt,
        totalOrderCount: current.totalOrderCount,
        orderAddressSnapshots: current.orderAddressSnapshots,
        restrictionStatus: restrict ? 'active' : 'none',
        restrictionReasonMessage: restrict ? reasonMessage : null,
        marketingConsent: current.marketingConsent,
      );
    }
  }
}

TenantCustomerDetail _detail({
  String id = 'cust-1',
  String displayName = 'Ayşe Yılmaz',
  String restrictionStatus = 'none',
  List<Map<String, dynamic>> addresses = const [],
}) {
  return TenantCustomerDetail(
    id: id,
    displayName: displayName,
    phoneMasked: '***45',
    registrationDate: DateTime(2026, 1, 1),
    lastActivityAt: DateTime(2026, 8, 1),
    accountState: 'active',
    relatedBranchIds: const ['branch-1'],
    lastOrderAt: DateTime(2026, 8, 1),
    totalOrderCount: 7,
    orderAddressSnapshots: addresses,
    restrictionStatus: restrictionStatus,
    restrictionReasonMessage:
        restrictionStatus == 'active' ? 'Şüpheli işlem tespit edildi.' : null,
    marketingConsent: 'notCaptured',
  );
}

Future<_FakeTenantCustomerDirectoryGateway> _pump(
  WidgetTester tester, {
  required TenantCustomerDetail? detail,
  TenantCustomerDirectoryException? error,
}) async {
  final gateway = _FakeTenantCustomerDirectoryGateway()
    ..detailToReturn = detail
    ..detailErrorToThrow = error;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tenantCustomerDirectoryGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        home: CustomerDetailScreen(
          customerId: 'cust-1',
          organizationId: 'org-1',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return gateway;
}

void main() {
  testWidgets('renders real detail fields (no visits/feedback/notes panels)',
      (tester) async {
    await _pump(tester, detail: _detail());

    expect(find.text('***45'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.textContaining('Hesap aktif'), findsOneWidget);
    expect(find.textContaining('Ziyaretler'), findsNothing);
    expect(find.textContaining('Geri Bildirimler'), findsNothing);
    expect(find.textContaining('Personel Notları'), findsNothing);
  });

  testWidgets('a restricted customer shows the restriction reason and an '
      'unrestrict button', (tester) async {
    await _pump(tester, detail: _detail(restrictionStatus: 'active'));

    expect(find.textContaining('Hesap kısıtlı'), findsOneWidget);
    expect(find.textContaining('Şüpheli işlem tespit edildi.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Kısıtlamayı Kaldır'),
        findsOneWidget);
  });

  testWidgets(
      'restricting a customer opens the reason dialog and calls the '
      'gateway with the chosen reason', (tester) async {
    final gateway = await _pump(tester, detail: _detail());

    await tester.tap(find.widgetWithText(OutlinedButton, 'Hesabı Kısıtla'));
    await tester.pumpAndSettle();

    expect(find.text('Hesabı Kısıtla'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('restrictionReasonMessageField')),
      'Şüpheli sipariş deseni.',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
    await tester.pumpAndSettle();

    expect(gateway.lastSetRestrictionValue, true);
    expect(gateway.lastSetRestrictionReasonMessage, 'Şüpheli sipariş deseni.');
    expect(find.textContaining('Hesap kısıtlı'), findsOneWidget);
  });

  testWidgets('an empty reason message does not submit the dialog',
      (tester) async {
    final gateway = await _pump(tester, detail: _detail());

    await tester.tap(find.widgetWithText(OutlinedButton, 'Hesabı Kısıtla'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
    await tester.pumpAndSettle();

    expect(gateway.lastSetRestrictionValue, isNull);
    expect(find.text('Açıklama'), findsOneWidget);
  });

  testWidgets('not-found shows an explicit empty state, not a crash',
      (tester) async {
    await _pump(
      tester,
      detail: null,
      error: const TenantCustomerDirectoryException(
        'not-found',
        'Customer not found for this organization.',
      ),
    );

    expect(find.textContaining('bulunamadı'), findsOneWidget);
  });

  testWidgets('permission-denied shows an unauthorized message with retry',
      (tester) async {
    await _pump(
      tester,
      detail: null,
      error: const TenantCustomerDirectoryException(
        'permission-denied',
        'The "viewTenantCustomerDirectory" permission is required.',
      ),
    );

    expect(find.textContaining('görüntüleme yetkiniz yok'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Tekrar Dene'), findsOneWidget);
  });
}
