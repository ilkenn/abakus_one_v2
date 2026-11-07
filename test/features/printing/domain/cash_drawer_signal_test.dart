import 'package:abakus_one_v2/features/printing/domain/cash_drawer_signal.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adım 4 (2026-11-07) — proves the exact byte sequence the operator's own
/// hardware notes specified (`ESC p 0 25 250`) is kept literally, not
/// re-derived.
void main() {
  test('kCashDrawerKickBytes matches ESC p 0 25 250 exactly', () {
    expect(kCashDrawerKickBytes, [0x1B, 0x70, 0x00, 0x19, 0xFA]);
  });
}
