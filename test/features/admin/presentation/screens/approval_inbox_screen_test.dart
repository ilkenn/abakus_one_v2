import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/approval_gateway.dart';
import 'package:abakus_one_v2/features/admin/data/approval_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/approval/approval_request.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/approval_inbox_screen.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/actor_session_provider.dart';

class _FakeApprovalRepository implements ApprovalRepository {
  _FakeApprovalRepository({this.eligible = const [], this.mine = const []});
  final List<ApprovalRequest> eligible;
  final List<ApprovalRequest> mine;

  @override
  Stream<List<ApprovalRequest>> watchEligibleApprovals({
    required String organizationId,
    required String branchId,
  }) =>
      Stream.value(eligible);

  @override
  Stream<List<ApprovalRequest>> watchMyRequests({required String actorUid}) =>
      Stream.value(
          mine.where((r) => r.requestedByActorUid == actorUid).toList());
}

class _FakeApprovalGateway implements ApprovalGateway {
  String? lastRequestId;
  bool? lastApprove;
  String? lastReason;
  int callCount = 0;

  @override
  Future<void> respond({
    required String requestId,
    required bool approve,
    required String reasonMessage,
  }) async {
    callCount += 1;
    lastRequestId = requestId;
    lastApprove = approve;
    lastReason = reasonMessage;
  }
}

ApprovalRequest _request({
  String requestId = 'approval-1',
  String requestedByActorUid = 'staff-2',
  ApprovalStatus status = ApprovalStatus.pending,
}) {
  return ApprovalRequest(
    requestId: requestId,
    organizationId: 'org-1',
    branchId: 'branch-1',
    actionType: ApprovalActionType.deviceActivation,
    requestedByActorUid: requestedByActorUid,
    targetAggregateRef: 'trustedDeviceRegistrations/org-1_branch-1_devxyz123',
    status: status,
    createdAt: DateTime(2026, 1, 1),
    expiresAt: DateTime(2026, 1, 2),
    version: 1,
  );
}

void main() {
  Future<void> pumpInbox(
    WidgetTester tester, {
    required ApprovalRepository repository,
    ApprovalGateway? gateway,
    ActorSession? session,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          approvalRepositoryProvider.overrideWithValue(repository),
          if (gateway != null)
            approvalGatewayProvider.overrideWithValue(gateway),
          if (session != null)
            actorSessionProvider.overrideWith((ref) => session),
        ],
        child: const MaterialApp(home: ApprovalInboxScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  const managerSession = ActorSession(
    actorId: 'staff-1',
    roles: {StaffRole.manager},
    activeRole: StaffRole.manager,
    branchAccess: {'branch-1'},
  );
  const staffOnlySession = ActorSession(
    actorId: 'staff-3',
    roles: {StaffRole.staff},
    activeRole: StaffRole.staff,
    branchAccess: {'branch-1'},
  );

  testWidgets(
      'an eligible responder (manager) sees the pending inbox and can approve with a reason',
      (tester) async {
    final gateway = _FakeApprovalGateway();
    await pumpInbox(
      tester,
      repository: _FakeApprovalRepository(eligible: [_request()]),
      gateway: gateway,
      session: managerSession,
    );

    expect(find.text('Bekliyor'), findsOneWidget);
    expect(find.textContaining('Cihaz Aktivasyonu'), findsOneWidget);

    await tester.tap(find.text('Onayla').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'verified in person');
    await tester.tap(find.text('Onayla').last);
    await tester.pumpAndSettle();

    expect(gateway.callCount, 1);
    expect(gateway.lastRequestId, 'approval-1');
    expect(gateway.lastApprove, true);
    expect(gateway.lastReason, 'verified in person');
  });

  testWidgets(
      'a non-eligible role (plain staff) never sees the approver tab content, only a permission notice',
      (tester) async {
    await pumpInbox(
      tester,
      repository: _FakeApprovalRepository(eligible: [_request()]),
      session: staffOnlySession,
    );

    expect(find.textContaining('Onay verme yetkiniz yok'), findsOneWidget);
    expect(find.text('Onayla'), findsNothing);
    expect(find.text('Reddet'), findsNothing);
  });

  testWidgets(
      'the requester\'s own pending request shows no approve/reject buttons — self-approval is blocked at the UI too',
      (tester) async {
    await pumpInbox(
      tester,
      repository: _FakeApprovalRepository(
          eligible: [_request(requestedByActorUid: 'staff-1')]),
      session: managerSession,
    );

    expect(find.textContaining('kendi talebinizi'), findsOneWidget);
    expect(find.text('Onayla'), findsNothing);
    expect(find.text('Reddet'), findsNothing);
  });

  testWidgets(
      'an already-resolved (approved) request shows its status but no action buttons — never re-actionable',
      (tester) async {
    await pumpInbox(
      tester,
      repository: _FakeApprovalRepository(
          eligible: [_request(status: ApprovalStatus.approved)]),
      session: managerSession,
    );

    expect(find.text('Onaylandı'), findsOneWidget);
    expect(find.text('Onayla'), findsNothing);
    expect(find.text('Reddet'), findsNothing);
  });

  testWidgets('an expired request renders its terminal status clearly',
      (tester) async {
    await pumpInbox(
      tester,
      repository: _FakeApprovalRepository(
          eligible: [_request(status: ApprovalStatus.expired)]),
      session: managerSession,
    );

    expect(find.text('Süresi Doldu'), findsOneWidget);
  });

  testWidgets(
      'no full canonical payload is rendered — no payload hash, no raw target path exposed as-is',
      (tester) async {
    await pumpInbox(
      tester,
      repository: _FakeApprovalRepository(eligible: [_request()]),
      session: managerSession,
    );

    expect(find.textContaining('trustedDeviceRegistrations/'), findsNothing);
    expect(find.textContaining('payloadHash'), findsNothing);
  });

  testWidgets(
      'the requester tab shows only the current actor\'s own requests, live status included',
      (tester) async {
    await pumpInbox(
      tester,
      repository: _FakeApprovalRepository(mine: [
        _request(
            requestId: 'approval-mine',
            requestedByActorUid: 'staff-1',
            status: ApprovalStatus.approved),
      ]),
      session: managerSession,
    );

    await tester.tap(find.text('Taleplerim'));
    await tester.pumpAndSettle();

    expect(find.textContaining('cihaz artık aktif'), findsOneWidget);
  });

  testWidgets(
      'no active session shows a clear "no session" state, never a crash',
      (tester) async {
    await pumpInbox(
      tester,
      repository: _FakeApprovalRepository(),
    );

    expect(find.textContaining('Onay verme yetkiniz yok'), findsOneWidget);
    await tester.tap(find.text('Taleplerim'));
    await tester.pumpAndSettle();
    expect(find.text('Oturum bulunamadı.'), findsOneWidget);
  });

  testWidgets('backend unavailable shows an explicit error state with retry',
      (tester) async {
    await pumpInbox(
      tester,
      repository: const UnavailableApprovalRepository(),
      session: managerSession,
    );

    expect(find.textContaining('ulaşılamadı'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
  });
}
