import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/layout/app_breakpoints.dart';

void main() {
  test('600 altinda tek sutun (telefon)', () {
    expect(AppBreakpoints.columnsForWidth(0), 1);
    expect(AppBreakpoints.columnsForWidth(320), 1);
    expect(AppBreakpoints.columnsForWidth(599), 1);
  });

  test('600 (dahil) - 839 arasi iki sutun (tablet)', () {
    expect(AppBreakpoints.columnsForWidth(600), 2);
    expect(AppBreakpoints.columnsForWidth(720), 2);
    expect(AppBreakpoints.columnsForWidth(839), 2);
  });

  test('840 ve uzeri uc sutun (buyuk tablet/web)', () {
    expect(AppBreakpoints.columnsForWidth(840), 3);
    expect(AppBreakpoints.columnsForWidth(1440), 3);
  });
}
