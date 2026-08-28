import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/platform/data/platform_customer_directory_gateway.dart';
import 'package:abakus_one_v2/features/platform/presentation/providers/platform_dependencies_provider.dart';
import 'package:abakus_one_v2/features/platform/presentation/screens/platform_customer_detail_screen.dart';
import 'package:abakus_one_v2/features/platform/presentation/screens/platform_customer_directory_screen.dart';

class _FakePlatformCustomerDirectoryGateway
    implements PlatformCustomerDirectoryGateway {
  _FakePlatformCustomerDirectoryGateway({this.summaries = const []});

  List<PlatformCustomerSummary> summaries;
  PlatformCustomerDirectoryException? listErrorToThrow;
  PlatformCustomerDetail? detailToReturn;
  PlatformCustomerDirectoryException? detailErrorToThrow;
  List<Map<String, dynamic>>? addressesToReturn;
  bool? lastSetRestrictionValue;
  String? lastRevealReason;

  @override
  Future<PlatformCustomerListPage> list({
    String? namePrefix,
    String? cursor,
  }) async {
    final error = listErrorToThrow;
    if (error != null) throw error;
    final filtered = namePrefix == null || namePrefix.isEmpty
        ? summaries
        : summaries
            .where((c) =>
                c.displayName.toLowerCase().contains(namePrefix.toLowerCase()))
            .toList();
    return PlatformCustomerListPage(customers: filtered, nextCursor: null);
  }

  @override
  Future<List<PlatformCustomerSummary>> searchByPhone(
    String phoneNumber,
  ) async =>
      const [];

  @override
  Future<PlatformCustomerDetail> getDetail(String uid) async {
    final error = detailErrorToThrow;
    if (error != null) throw error;
    final detail = detailToReturn;
    if (detail == null) {
      throw const PlatformCustomerDirectoryException('not-found', 'Not found.');
    }
    return detail;
  }

  @override
  Future<List<Map<String, dynamic>>> revealFullAddressBook({
    required String uid,
    required String reason,
  }) async {
    lastRevealReason = reason;
    return addressesToReturn ?? const [];
  }

  @override
  Future<void> setRestriction({
    required String uid,
    required bool restrict,
    required String reasonCode,
    required String reasonMessage,
  }) async {
    lastSetRestrictionValue = restrict;
    final current = detailToReturn;
    if (current != null) {
      detailToReturn = PlatformCustomerDetail(
        uid: current.uid,
        displayName: current.displayName,
        phoneMasked: current.phoneMasked,
        registrationDate: current.registrationDate,
        accountState: current.accountState,
        relatedOrganizationIds: current.relatedOrganizationIds,
        restrictionStatus: restrict ? 'active' : 'none',
        restrictionReasonMessage: restrict ? reasonMessage : null,
        marketingConsent: current.marketingConsent,
      );
    }
  }
}

PlatformCustomerSummary _summary(String id, String displayName) {
  return PlatformCustomerSummary(
    id: id,
    displayName: displayName,
    registrationDate: DateTime(2026, 1, 1),
    accountState: 'active',
  );
}

void main() {
  testWidgets('renders the platform-wide customer list', (tester) async {
    final gateway = _FakePlatformCustomerDirectoryGateway(summaries: [
      _summary('u1', 'Ayşe Yılmaz'),
      _summary('u2', 'Mehmet Kaya'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformCustomerDirectoryGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PlatformCustomerDirectoryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('Mehmet Kaya'), findsOneWidget);
  });

  testWidgets('permission-denied shows the platform-specific message',
      (tester) async {
    final gateway = _FakePlatformCustomerDirectoryGateway()
      ..listErrorToThrow = const PlatformCustomerDirectoryException(
        'permission-denied',
        'The "customerDirectory.listAllRegistered" capability is required.',
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformCustomerDirectoryGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PlatformCustomerDirectoryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Küresel müşteri dizinini'), findsOneWidget);
  });

  Future<void> pumpDetail(
    WidgetTester tester, {
    required _FakePlatformCustomerDirectoryGateway gateway,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformCustomerDirectoryGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(
          home: PlatformCustomerDetailScreen(uid: 'u1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('detail shows tenant relationships and no-tenant customers '
      'explicitly', (tester) async {
    final gateway = _FakePlatformCustomerDirectoryGateway()
      ..detailToReturn = PlatformCustomerDetail(
        uid: 'u1',
        displayName: 'Ayşe Yılmaz',
        phoneMasked: '***45',
        registrationDate: DateTime(2026, 1, 1),
        accountState: 'active',
        relatedOrganizationIds: const [],
        restrictionStatus: 'none',
        restrictionReasonMessage: null,
        marketingConsent: 'notCaptured',
      );
    await pumpDetail(tester, gateway: gateway);

    expect(find.text('***45'), findsOneWidget);
    expect(find.textContaining('kiracısız kayıt'), findsOneWidget);
  });

  testWidgets('restricting platform-wide calls the gateway with the chosen '
      'reason', (tester) async {
    final gateway = _FakePlatformCustomerDirectoryGateway()
      ..detailToReturn = PlatformCustomerDetail(
        uid: 'u1',
        displayName: 'Ayşe Yılmaz',
        phoneMasked: '***45',
        registrationDate: DateTime(2026, 1, 1),
        accountState: 'active',
        relatedOrganizationIds: const ['org-1'],
        restrictionStatus: 'none',
        restrictionReasonMessage: null,
        marketingConsent: 'notCaptured',
      );
    await pumpDetail(tester, gateway: gateway);

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Platform Genelinde Kısıtla'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('platformRestrictionReasonMessageField')),
      'Şüpheli çoklu hesap.',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
    await tester.pumpAndSettle();

    expect(gateway.lastSetRestrictionValue, true);
    expect(find.textContaining('Platform genelinde kısıtlı'), findsOneWidget);
  });

  testWidgets(
      'revealing the address book requires a reason and calls the '
      'audited callable', (tester) async {
    final gateway = _FakePlatformCustomerDirectoryGateway()
      ..detailToReturn = PlatformCustomerDetail(
        uid: 'u1',
        displayName: 'Ayşe Yılmaz',
        phoneMasked: '***45',
        registrationDate: DateTime(2026, 1, 1),
        accountState: 'active',
        relatedOrganizationIds: const ['org-1'],
        restrictionStatus: 'none',
        restrictionReasonMessage: null,
        marketingConsent: 'notCaptured',
      )
      ..addressesToReturn = [
        {'label': 'Ev', 'line1': 'Test Sokak No:1', 'city': 'İstanbul'},
      ];
    await pumpDetail(tester, gateway: gateway);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Adres Defterini Göster'));
    await tester.pumpAndSettle();

    // The dialog appears; submitting without a reason must not proceed.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Görüntüle'));
    await tester.pumpAndSettle();
    expect(gateway.lastRevealReason, isNull);

    await tester.enterText(
      find.byKey(const Key('revealAddressBookReasonField')),
      'Dolandırıcılık şikayeti soruşturması.',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Görüntüle'));
    await tester.pumpAndSettle();

    expect(gateway.lastRevealReason, 'Dolandırıcılık şikayeti soruşturması.');
    expect(find.textContaining('Ev · Test Sokak No:1 · İstanbul'),
        findsOneWidget);
  });
}
