import 'package:abakus_one_v2/features/courier/domain/identity/courier.dart';
import 'package:abakus_one_v2/features/courier/presentation/widgets/courier_assignment_dialog.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/courier_dispatch_dependencies_provider.dart';
import 'package:abakus_one_v2/shared/models/courier_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _branchId = 'branch-1';

Courier _courier(String id, {DateTime? returnedAt}) {
  return Courier(
    id: id,
    primaryBranchId: _branchId,
    displayName: 'Kurye $id',
    phoneNumber: '+905551112233',
    registeredAt: DateTime(2026, 1, 1),
    returnedAt: returnedAt,
  );
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required List<Override> overrides,
  CourierType? courierType,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CourierAssignmentDialog(
                  organizationId: 'org-1',
                  branchId: _branchId,
                  orderId: 'order-1',
                  courierType: courierType,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('CourierAssignmentDialog', () {
    testWidgets('marketplace-carried order renders the locked state, no courier list, no assign action', (tester) async {
      await _pumpDialog(tester, overrides: const [], courierType: CourierType.marketplace);

      expect(find.text('Pazaryeri Kuryesi Taşımaktadır'), findsOneWidget);
      expect(find.text('Ata'), findsNothing);
    });

    testWidgets('the first FIFO-sorted (oldest returnedAt) courier is tagged as recommended', (tester) async {
      final couriers = [
        _courier('c-old', returnedAt: DateTime(2026, 1, 1, 10, 0)),
        _courier('c-new', returnedAt: DateTime(2026, 1, 1, 12, 0)),
      ];
      await _pumpDialog(
        tester,
        overrides: [
          availableCouriersForBranchProvider(_branchId)
              .overrideWith((ref) => Stream.value(couriers)),
        ],
      );

      expect(find.text('Önerilen (İlk Dönen)'), findsOneWidget);
      expect(find.text('Kurye c-old'), findsOneWidget);
      expect(find.text('Kurye c-new'), findsOneWidget);
      expect(find.text('Ata'), findsNWidgets(2));
    });

    testWidgets('an empty available-courier list shows the empty-state message', (tester) async {
      await _pumpDialog(
        tester,
        overrides: [
          availableCouriersForBranchProvider(_branchId)
              .overrideWith((ref) => Stream.value(const <Courier>[])),
        ],
      );

      expect(find.text('Şu anda dükkanda uygun kurye yok.'), findsOneWidget);
    });
  });
}
