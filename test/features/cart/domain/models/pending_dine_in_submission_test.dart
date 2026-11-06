import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/cart/domain/models/pending_dine_in_submission.dart';

void main() {
  group('PendingDineInSubmission', () {
    test('toJson/fromJson round-trips every field exactly', () {
      final submission = PendingDineInSubmission(
        submissionKey: 'key-1',
        tableSessionId: 'table-session-1',
        items: [
          {
            'kind': 'product',
            'productId': 'p1',
            'quantity': 2,
            'selectedModifiers': [
              {'groupId': 'g1', 'optionId': 'o1'},
            ],
            'note': 'az baharatlı',
            'excludedIngredients': ['soğan'],
          },
          {
            'kind': 'bowl',
            'quantity': 1,
            'ingredientIds': ['pirinc', 'tavuk'],
            'note': '',
          },
        ],
        customerNote: 'kapıda değil masada',
        selectedRewardId: 'reward-1',
        selectedCampaignId: 'campaign-1',
        guestDisplayName: 'Ahmet',
        submittedCartLineIds: ['line-1', 'line-2'],
        queuedAt: DateTime.utc(2026, 11, 6, 10, 30),
      );

      final roundTripped =
          PendingDineInSubmission.fromJson(submission.toJson());

      expect(roundTripped.submissionKey, 'key-1');
      expect(roundTripped.tableSessionId, 'table-session-1');
      expect(roundTripped.items, submission.items);
      expect(roundTripped.customerNote, 'kapıda değil masada');
      expect(roundTripped.selectedRewardId, 'reward-1');
      expect(roundTripped.selectedCampaignId, 'campaign-1');
      expect(roundTripped.guestDisplayName, 'Ahmet');
      expect(roundTripped.submittedCartLineIds, ['line-1', 'line-2']);
      expect(roundTripped.queuedAt, DateTime.utc(2026, 11, 6, 10, 30));
    });

    test('fromJson defaults every optional field absent from the stored JSON',
        () {
      final roundTripped = PendingDineInSubmission.fromJson({
        'submissionKey': 'key-2',
        'tableSessionId': 'table-session-2',
        'items': <Map<String, dynamic>>[],
        'queuedAt': DateTime.utc(2026, 11, 6).toIso8601String(),
      });

      expect(roundTripped.customerNote, '');
      expect(roundTripped.selectedRewardId, isNull);
      expect(roundTripped.selectedCampaignId, isNull);
      expect(roundTripped.guestDisplayName, isNull);
      expect(roundTripped.submittedCartLineIds, isEmpty);
    });

    test(
        'toJson encodes a null customerNote-adjacent optional as null, not absent',
        () {
      final submission = PendingDineInSubmission(
        submissionKey: 'key-3',
        tableSessionId: 'table-session-3',
        items: const [],
        customerNote: '',
        queuedAt: DateTime.utc(2026, 11, 6),
      );

      final json = submission.toJson();

      expect(json['selectedRewardId'], isNull);
      expect(json['selectedCampaignId'], isNull);
      expect(json['guestDisplayName'], isNull);
      expect(json['submittedCartLineIds'], isEmpty);
    });
  });
}
