import 'package:abakus_one_v2/features/restaurant/domain/models/channel_operational_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChannelOperationalStateTransitions', () {
    test('open can move to busy, closed, or emergencyClosed', () {
      expect(
        ChannelOperationalStateTransitions.canTransition(
            ChannelOperationalState.open, ChannelOperationalState.busy),
        isTrue,
      );
      expect(
        ChannelOperationalStateTransitions.canTransition(
            ChannelOperationalState.open, ChannelOperationalState.closed),
        isTrue,
      );
      expect(
        ChannelOperationalStateTransitions.canTransition(
            ChannelOperationalState.open,
            ChannelOperationalState.emergencyClosed),
        isTrue,
      );
    });

    test('emergencyClosed can only move to open', () {
      expect(
        ChannelOperationalStateTransitions.canTransition(
            ChannelOperationalState.emergencyClosed,
            ChannelOperationalState.busy),
        isFalse,
      );
      expect(
        ChannelOperationalStateTransitions.canTransition(
            ChannelOperationalState.emergencyClosed,
            ChannelOperationalState.open),
        isTrue,
      );
    });

    test('a state never transitions to itself', () {
      expect(
        ChannelOperationalStateTransitions.canTransition(
            ChannelOperationalState.open, ChannelOperationalState.open),
        isFalse,
      );
    });
  });
}
