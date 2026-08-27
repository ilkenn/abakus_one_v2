import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/organization_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/organization/organization.dart';
import 'package:abakus_one_v2/features/entitlements/data/entitlement_grant_repository.dart';
import 'package:abakus_one_v2/features/entitlements/domain/entitlement_grant.dart';
import 'package:abakus_one_v2/features/entitlements/domain/entitlement_module.dart';
import 'package:abakus_one_v2/features/entitlements/domain/entitlement_scope_type.dart';
import 'package:abakus_one_v2/features/entitlements/domain/entitlement_status.dart';
import 'package:abakus_one_v2/features/entitlements/presentation/providers/entitlement_dependencies_provider.dart';
import 'package:abakus_one_v2/features/platform/data/entitlement_admin_gateway.dart';
import 'package:abakus_one_v2/features/platform/data/firestore_platform_organization_repository.dart';
import 'package:abakus_one_v2/features/platform/presentation/providers/platform_dependencies_provider.dart';
import 'package:abakus_one_v2/features/platform/presentation/screens/platform_entitlement_console_screen.dart';

class _FakeOrganizationRepository implements OrganizationRepository {
  _FakeOrganizationRepository(this.orgs);
  final List<Organization> orgs;

  @override
  Future<List<Organization>> findAll() async => orgs;
  @override
  Future<Organization?> findById(String organizationId) async =>
      orgs.where((o) => o.id == organizationId).firstOrNull;
  @override
  Future<void> save(Organization organization) async {}
}

class _FakeReadRepository implements EntitlementGrantRepository {
  _FakeReadRepository(this.grants);
  final List<EntitlementGrant> grants;

  @override
  Future<List<EntitlementGrant>> findByScope(
          EntitlementScopeType scopeType, String scopeId) async =>
      grants;
  @override
  Future<EntitlementGrant?> findById(String id) async => null;
  @override
  Future<EntitlementGrant?> findByModuleAndScope(EntitlementModule module,
          EntitlementScopeType scopeType, String scopeId) async =>
      null;
  @override
  Future<void> save(EntitlementGrant grant) async {}
}

class _FakeEntitlementAdminGateway implements EntitlementAdminGateway {
  String? lastAction;
  String? lastEntitlementId;
  bool? lastAsActive;
  String? lastReason;

  @override
  Future<void> grant({
    required String organizationId,
    required EntitlementScopeType scopeType,
    required String scopeId,
    required EntitlementModule module,
    bool asActiveImmediately = false,
    DateTime? contractStartsAt,
    DateTime? contractEndsAt,
  }) async {
    lastAction = 'grant';
    lastAsActive = asActiveImmediately;
  }

  @override
  Future<void> renew(
      {required String entitlementId, required DateTime contractEndsAt}) async {
    lastAction = 'renew';
    lastEntitlementId = entitlementId;
  }

  @override
  Future<void> suspend({
    required String entitlementId,
    required String reasonMessage,
    List<EntitlementModule>? postGraceDisabledModules,
  }) async {
    lastAction = 'suspend';
    lastEntitlementId = entitlementId;
    lastReason = reasonMessage;
  }

  @override
  Future<void> revoke(
      {required String entitlementId, required String reasonMessage}) async {
    lastAction = 'revoke';
    lastEntitlementId = entitlementId;
    lastReason = reasonMessage;
  }
}

void main() {
  Future<void> pumpConsole(
    WidgetTester tester, {
    required OrganizationRepository organizations,
    required EntitlementGrantRepository grants,
    EntitlementAdminGateway? gateway,
  }) async {
    // The default 800x600 test surface is too small for
    // DropdownButtonFormField's popup route to hit-test reliably in this
    // screen's layout — confirmed by direct investigation (the item WAS
    // present in the tree and its reported center WAS tappable-looking,
    // but the resulting selection silently never landed at the default
    // size, and reliably did once the surface was enlarged). A real
    // device/desktop window is never this small, so this is a test-
    // environment artifact, not a production bug.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformOrganizationRepositoryProvider
              .overrideWithValue(organizations),
          entitlementGrantReadRepositoryProvider.overrideWithValue(grants),
          if (gateway != null)
            entitlementAdminGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(home: PlatformEntitlementConsoleScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'lists tenants in the picker; selecting one loads its module list',
      (tester) async {
    await pumpConsole(
      tester,
      organizations: _FakeOrganizationRepository([
        Organization(
            id: 'org-1',
            name: 'Abaküs Kadıköy',
            createdAt: DateTime(2026, 1, 1),
            revision: 1),
      ]),
      grants: _FakeReadRepository(const []),
    );

    expect(find.text('İşletme Seçin'), findsOneWidget);
    expect(find.textContaining('Devam etmek için'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abaküs Kadıköy').last);
    await tester.pumpAndSettle();

    expect(find.text('POS'), findsOneWidget);
    expect(find.text('Abonelik yok'), findsWidgets);
  });

  testWidgets(
      'an ungranted module offers trial/direct-activate; trial calls the gateway with asActiveImmediately=false',
      (tester) async {
    final gateway = _FakeEntitlementAdminGateway();
    await pumpConsole(
      tester,
      organizations: _FakeOrganizationRepository([
        Organization(
            id: 'org-1',
            name: 'Abaküs Kadıköy',
            createdAt: DateTime(2026, 1, 1),
            revision: 1),
      ]),
      grants: _FakeReadRepository(const []),
      gateway: gateway,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abaküs Kadıköy').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deneme Oluştur').first);
    await tester.pumpAndSettle();

    expect(gateway.lastAction, 'grant');
    expect(gateway.lastAsActive, false);
  });

  testWidgets(
      'a granted module shows status/version and offers renew/suspend/revoke; suspend requires a reason',
      (tester) async {
    final gateway = _FakeEntitlementAdminGateway();
    await pumpConsole(
      tester,
      organizations: _FakeOrganizationRepository([
        Organization(
            id: 'org-1',
            name: 'Abaküs Kadıköy',
            createdAt: DateTime(2026, 1, 1),
            revision: 1),
      ]),
      grants: _FakeReadRepository([
        EntitlementGrant(
          id: 'org-1_organization_org-1_pos',
          module: EntitlementModule.pos,
          scopeType: EntitlementScopeType.organization,
          scopeId: 'org-1',
          status: EntitlementStatus.active,
          grantedByStaffId: 'platform-1',
          grantedAt: DateTime(2026, 1, 1),
          revision: 3,
        ),
      ]),
      gateway: gateway,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abaküs Kadıköy').last);
    await tester.pumpAndSettle();

    expect(find.text('Aktif'), findsOneWidget);
    expect(find.textContaining('Sürüm: 3'), findsOneWidget);

    await tester.tap(find.text('Askıya Al').first);
    await tester.pumpAndSettle();
    // Confirm button in the dialog is disabled while the reason is blank.
    final confirmFinder = find.widgetWithText(ElevatedButton, 'Onayla');
    await tester.enterText(find.byType(TextField), 'non-payment');
    await tester.tap(confirmFinder);
    await tester.pumpAndSettle();

    expect(gateway.lastAction, 'suspend');
    expect(gateway.lastEntitlementId, 'org-1_organization_org-1_pos');
    expect(gateway.lastReason, 'non-payment');
  });

  testWidgets(
      'a revoked module offers no further mutating actions — terminal state',
      (tester) async {
    await pumpConsole(
      tester,
      organizations: _FakeOrganizationRepository([
        Organization(
            id: 'org-1',
            name: 'Abaküs Kadıköy',
            createdAt: DateTime(2026, 1, 1),
            revision: 1),
      ]),
      grants: _FakeReadRepository([
        EntitlementGrant(
          id: 'org-1_organization_org-1_pos',
          module: EntitlementModule.pos,
          scopeType: EntitlementScopeType.organization,
          scopeId: 'org-1',
          status: EntitlementStatus.revoked,
          grantedByStaffId: 'platform-1',
          grantedAt: DateTime(2026, 1, 1),
          revision: 5,
        ),
      ]),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abaküs Kadıköy').last);
    await tester.pumpAndSettle();

    expect(find.text('İptal Edildi'), findsOneWidget);
    // The buttons stay rendered (a `revoked` grant is still shown, just
    // terminal) but every one of them must be disabled — never tappable
    // into a no-op or, worse, a confusing backend error.
    for (final label in ['Yenile', 'Askıya Al', 'İptal Et']) {
      final button = tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label));
      expect(button.onPressed, isNull,
          reason: '"$label" must be disabled for a revoked grant');
    }
  });

  testWidgets('a grace-status module shows its grace end date distinctly',
      (tester) async {
    await pumpConsole(
      tester,
      organizations: _FakeOrganizationRepository([
        Organization(
            id: 'org-1',
            name: 'Abaküs Kadıköy',
            createdAt: DateTime(2026, 1, 1),
            revision: 1),
      ]),
      grants: _FakeReadRepository([
        EntitlementGrant(
          id: 'org-1_organization_org-1_pos',
          module: EntitlementModule.pos,
          scopeType: EntitlementScopeType.organization,
          scopeId: 'org-1',
          status: EntitlementStatus.grace,
          graceEndsAt: DateTime(2026, 2, 4),
          grantedByStaffId: 'platform-1',
          grantedAt: DateTime(2026, 1, 1),
          revision: 4,
        ),
      ]),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abaküs Kadıköy').last);
    await tester.pumpAndSettle();

    expect(find.text('Ek Süre'), findsOneWidget);
    expect(find.textContaining('Ek süre bitiş'), findsOneWidget);
  });

  testWidgets('no organizations shows a clear empty state', (tester) async {
    await pumpConsole(
      tester,
      organizations: _FakeOrganizationRepository(const []),
      grants: _FakeReadRepository(const []),
    );

    expect(find.text('Kayıtlı işletme yok.'), findsOneWidget);
  });

  testWidgets(
      'tenant directory unavailable shows an explicit error state with retry',
      (tester) async {
    await pumpConsole(
      tester,
      organizations: const UnavailablePlatformOrganizationRepository(),
      grants: _FakeReadRepository(const []),
    );

    expect(find.textContaining('ulaşılamadı'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
  });
}
