import 'package:abakus_one_v2/core/utils/clock.dart';

/// A controllable [Clock] for tests — starts at [initial] and advances only
/// when [advance] is called, so a test can assert exact timestamps instead
/// of "some time after the test started."
class FakeClock implements Clock {
  FakeClock(DateTime initial) : _current = initial;

  DateTime _current;

  @override
  DateTime now() => _current;

  void advance(Duration duration) {
    _current = _current.add(duration);
  }

  void setTo(DateTime value) {
    _current = value;
  }
}
