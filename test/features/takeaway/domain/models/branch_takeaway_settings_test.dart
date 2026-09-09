import 'package:abakus_one_v2/features/takeaway/domain/models/branch_takeaway_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BranchTakeawaySettings', () {
    test('paused requires a non-null pausedUntil', () {
      expect(
        () => BranchTakeawaySettings(
          branchId: 'branch-1',
          status: TakeawayOperationStatus.paused,
          updatedByStaffId: 'staff-1',
          updatedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('active/busy never require pausedUntil', () {
      expect(
        () => BranchTakeawaySettings(
          branchId: 'branch-1',
          status: TakeawayOperationStatus.busy,
          busyDelayMinutes: 30,
          updatedByStaffId: 'staff-1',
          updatedAt: DateTime(2026, 1, 1),
        ),
        returnsNormally,
      );
    });

    group('isPausedAt', () {
      test('true while paused and pausedUntil is still in the future', () {
        final settings = BranchTakeawaySettings(
          branchId: 'branch-1',
          status: TakeawayOperationStatus.paused,
          pausedUntil: DateTime(2026, 1, 1, 13, 0),
          updatedByStaffId: 'staff-1',
          updatedAt: DateTime(2026, 1, 1, 12, 0),
        );
        expect(settings.isPausedAt(DateTime(2026, 1, 1, 12, 30)), isTrue);
      });

      test('false once pausedUntil has passed', () {
        final settings = BranchTakeawaySettings(
          branchId: 'branch-1',
          status: TakeawayOperationStatus.paused,
          pausedUntil: DateTime(2026, 1, 1, 13, 0),
          updatedByStaffId: 'staff-1',
          updatedAt: DateTime(2026, 1, 1, 12, 0),
        );
        expect(settings.isPausedAt(DateTime(2026, 1, 1, 13, 0, 1)), isFalse);
      });

      test('false for active/busy regardless of the clock', () {
        final settings = BranchTakeawaySettings(
          branchId: 'branch-1',
          status: TakeawayOperationStatus.busy,
          busyDelayMinutes: 15,
          updatedByStaffId: 'staff-1',
          updatedAt: DateTime(2026, 1, 1),
        );
        expect(settings.isPausedAt(DateTime(2026, 1, 1)), isFalse);
      });
    });

    test('copyWith preserves fields not overridden', () {
      final original = BranchTakeawaySettings(
        branchId: 'branch-1',
        status: TakeawayOperationStatus.active,
        updatedByStaffId: 'staff-1',
        updatedAt: DateTime(2026, 1, 1),
        revision: 3,
      );
      final updated = original.copyWith(status: TakeawayOperationStatus.busy, busyDelayMinutes: 45);
      expect(updated.status, TakeawayOperationStatus.busy);
      expect(updated.busyDelayMinutes, 45);
      expect(updated.branchId, 'branch-1');
      expect(updated.revision, 3);
    });

    test('kTakeawayBusyDelayMinuteOptions is exactly the five fixed values', () {
      expect(kTakeawayBusyDelayMinuteOptions, [0, 15, 30, 45, 60]);
    });
  });
}
