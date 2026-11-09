import 'package:abakus_one_v2/core/services/functions/rest_callable_client.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_action_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the callable name + payload instead of hitting the network.
class _RecordingRestCallableClient extends RestCallableClient {
  _RecordingRestCallableClient() : super(idTokenProvider: () async => 'token');

  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    calls.add((name, data));
    return {};
  }
}

void main() {
  // The REST path is the one `FirebaseKitchenActionGateway` takes on
  // Windows (the real KDS host) — forcing it here lets the test observe the
  // exact callable + payload without any Firebase SDK.
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<(String, Map<String, dynamic>)> cancelVia(
    String channel,
    DineInCancellationReasonCode reason,
  ) async {
    final rest = _RecordingRestCallableClient();
    await FirebaseKitchenActionGateway(restClient: rest).cancelOrder(
      orderId: 'order-1',
      channel: channel,
      reasonCode: reason,
    );
    expect(rest.calls, hasLength(1));
    return rest.calls.single;
  }

  test('dineInQr cancels through advanceDineInOrderStatus', () async {
    final (name, data) =
        await cancelVia('dineInQr', DineInCancellationReasonCode.guestLeft);
    expect(name, 'advanceDineInOrderStatus');
    expect(data, {
      'orderId': 'order-1',
      'targetStatus': 'cancelled',
      'reasonCode': 'guestLeft',
    });
  });

  for (final entry in {
    'takeaway': 'cancelTakeawayOrderForStaff',
    'delivery': 'cancelDeliveryOrderForStaff',
    'reservationPreorder': 'cancelReservationPreorderOrderForStaff',
  }.entries) {
    test('${entry.key} cancels through ${entry.value}', () async {
      final (name, data) = await cancelVia(
          entry.key, DineInCancellationReasonCode.itemUnavailable);
      expect(name, entry.value);
      expect(data, {'orderId': 'order-1', 'reasonCode': 'itemUnavailable'});
    });

    test('${entry.key} sends guestLeft as customerNoShow', () async {
      final (_, data) =
          await cancelVia(entry.key, DineInCancellationReasonCode.guestLeft);
      expect(data['reasonCode'], 'customerNoShow');
    });
  }

  test('an unknown channel throws without calling anything', () async {
    final rest = _RecordingRestCallableClient();
    await expectLater(
      FirebaseKitchenActionGateway(restClient: rest).cancelOrder(
        orderId: 'order-1',
        channel: 'dineInStaff',
        reasonCode: DineInCancellationReasonCode.other,
      ),
      throwsA(isA<KitchenActionException>()),
    );
    expect(rest.calls, isEmpty);
  });
}
