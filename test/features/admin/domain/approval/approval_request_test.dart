import 'package:abakus_one_v2/features/admin/domain/approval/approval_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('approvalActionTypeFromWire', () {
    test('AP-5 Sprint 6: resolves stockCountAdjustment', () {
      expect(approvalActionTypeFromWire('stockCountAdjustment'),
          ApprovalActionType.stockCountAdjustment);
    });
  });

  group('ApprovalRequest.stockCountId', () {
    ApprovalRequest buildRequest(String targetAggregateRef) {
      return ApprovalRequest(
        requestId: 'req-1',
        organizationId: 'org-1',
        branchId: 'branch-1',
        actionType: ApprovalActionType.stockCountAdjustment,
        requestedByActorUid: 'staff-1',
        targetAggregateRef: targetAggregateRef,
        status: ApprovalStatus.pending,
        createdAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2026, 1, 2),
        version: 1,
      );
    }

    test('parses the count id from a stockCounts/{id} ref', () {
      expect(buildRequest('stockCounts/count-abc123').stockCountId,
          'count-abc123');
    });

    test('is null for a ref that does not match the stockCounts/{id} shape',
        () {
      expect(
          buildRequest('trustedDeviceRegistrations/org-1_branch-1_dev1')
              .stockCountId,
          isNull);
    });
  });
}
