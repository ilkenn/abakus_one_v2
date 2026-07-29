import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/transition_kitchen_work_item.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';
import '../../test_support/kds_test_fixtures.dart';

void main() {
  group('TransitionKitchenWorkItem', () {
    test('acknowledges a queued item, stamping acknowledgedAt', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final item = buildTestKitchenWorkItem();
      await projectionRepository.save(item);
      final auditRepository = InMemoryKitchenAuditEntryRepository();

      final useCase = TransitionKitchenWorkItem(
        clock: FakeClock(DateTime(2026, 1, 1, 12, 5)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        projectionRepository: projectionRepository,
        auditRepository: auditRepository,
        recordKitchenEvent: buildTestRecordKitchenEvent(),
      );

      final updated = await useCase(
        workItemId: item.id,
        to: KitchenLineStatus.acknowledged,
        expectedRevision: item.revision,
        performedByStaffId: 'staff-1',
      );

      expect(updated.status, KitchenLineStatus.acknowledged);
      expect(updated.acknowledgedAt, DateTime(2026, 1, 1, 12, 5));
      expect(updated.revision, 2);

      final auditEntries = await auditRepository.findByOrderId('order-1');
      expect(auditEntries, hasLength(1));
      expect(auditEntries.single.previousStateName, 'queued');
      expect(auditEntries.single.newStateName, 'acknowledged');
    });

    test('rejects an invalid transition (queued straight to ready)', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final item = buildTestKitchenWorkItem();
      await projectionRepository.save(item);

      final useCase = TransitionKitchenWorkItem(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        projectionRepository: projectionRepository,
        auditRepository: InMemoryKitchenAuditEntryRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
      );

      expect(
        () => useCase(
          workItemId: item.id,
          to: KitchenLineStatus.ready,
          expectedRevision: item.revision,
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<InvalidKitchenLineTransitionViolation>()),
      );
    });

    test(
        'a ready line can never transition directly back to preparing —'
        ' only to recalled', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final item = buildTestKitchenWorkItem(status: KitchenLineStatus.ready);
      await projectionRepository.save(item);

      final useCase = TransitionKitchenWorkItem(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        projectionRepository: projectionRepository,
        auditRepository: InMemoryKitchenAuditEntryRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
      );

      expect(
        () => useCase(
          workItemId: item.id,
          to: KitchenLineStatus.preparing,
          expectedRevision: item.revision,
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<InvalidKitchenLineTransitionViolation>()),
      );

      final recalled = await useCase(
        workItemId: item.id,
        to: KitchenLineStatus.recalled,
        expectedRevision: item.revision,
        performedByStaffId: 'staff-1',
        reason: 'Yanlış pişirilmiş',
      );
      expect(recalled.status, KitchenLineStatus.recalled);
    });

    test(
        'throws when expectedRevision is stale — prevents two devices '
        'both completing the same line', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final item = buildTestKitchenWorkItem();
      await projectionRepository.save(item);

      final useCase = TransitionKitchenWorkItem(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        projectionRepository: projectionRepository,
        auditRepository: InMemoryKitchenAuditEntryRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
      );

      expect(
        () => useCase(
          workItemId: item.id,
          to: KitchenLineStatus.acknowledged,
          expectedRevision: 99,
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<StaleKitchenRevisionViolation>()),
      );
    });

    test('throws when authorization is denied', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final item = buildTestKitchenWorkItem();
      await projectionRepository.save(item);

      final useCase = TransitionKitchenWorkItem(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: false, reason: 'Yetkisiz')),
        projectionRepository: projectionRepository,
        auditRepository: InMemoryKitchenAuditEntryRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
      );

      expect(
        () => useCase(
          workItemId: item.id,
          to: KitchenLineStatus.acknowledged,
          expectedRevision: item.revision,
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test(
        'a second device racing on the same item after the first '
        'succeeded is rejected by the revision check', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final item = buildTestKitchenWorkItem();
      await projectionRepository.save(item);

      final useCase = TransitionKitchenWorkItem(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        projectionRepository: projectionRepository,
        auditRepository: InMemoryKitchenAuditEntryRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
      );

      // Device A acknowledges first.
      await useCase(
        workItemId: item.id,
        to: KitchenLineStatus.acknowledged,
        expectedRevision: item.revision,
        performedByStaffId: 'staff-1',
        deviceId: 'device-A',
      );

      // Device B still has the stale, pre-acknowledge revision cached.
      expect(
        () => useCase(
          workItemId: item.id,
          to: KitchenLineStatus.acknowledged,
          expectedRevision: item.revision,
          performedByStaffId: 'staff-2',
          deviceId: 'device-B',
        ),
        throwsA(isA<StaleKitchenRevisionViolation>()),
      );
    });
  });
}
