import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/domain/models/modifier_group.dart';
import 'package:abakus_one_v2/features/menu/domain/models/modifier_option.dart';
import 'package:abakus_one_v2/features/menu/domain/models/product_nutrition.dart';
import 'package:abakus_one_v2/features/pos/presentation/widgets/pos_product_customization_dialog.dart';

const _product = MenuProduct(
  id: 'prod_test_bowl',
  categoryId: 'cat_bowl2',
  name: 'Test Bowl',
  description: 'Mısır, Marul.',
  basePrice: 500,
  imageKey: 'test-bowl',
  nutrition: ProductNutrition(calories: 560),
  allergens: ['gluten', 'süt'],
  modifierGroups: [
    ModifierGroup(
      id: 'carb',
      name: 'Karbonhidrat',
      selectionType: ModifierSelectionType.single,
      isRequired: true,
      minSelections: 1,
      maxSelections: 1,
      options: [
        ModifierOption(id: 'carb_basmati', name: 'Basmati', isDefault: true),
        ModifierOption(
            id: 'carb_meksika', name: 'Meksika Pilavı', extraPrice: 20),
      ],
    ),
    ModifierGroup(
      id: 'extras',
      name: 'Ekstra',
      selectionType: ModifierSelectionType.multiple,
      maxSelections: 2,
      options: [
        ModifierOption(id: 'extra_avokado', name: 'Avokado', extraPrice: 80),
      ],
    ),
  ],
);

/// Holds the still-pending dialog result Future. A plain local variable
/// can't cross out of an `async` helper that opens the dialog — returning
/// a `Future` from inside another `async` function makes Dart await it
/// before the helper itself returns, which would deadlock here (the
/// dialog isn't dismissed yet at that point). This box sidesteps that:
/// the helper only ever returns `Future<void>`.
class _PendingResult {
  Future<PosProductCustomizationResult?>? value;
}

Future<void> _openDialog(WidgetTester tester, _PendingResult pending) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  pending.value =
                      PosProductCustomizationDialog.show(context, _product);
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the calorie and allergen badge', (tester) async {
    await _openDialog(tester, _PendingResult());

    expect(find.textContaining('560 kcal'), findsOneWidget);
    expect(find.text('gluten'), findsOneWidget);
    expect(find.text('süt'), findsOneWidget);
  });

  testWidgets(
      "the required group's default option is pre-selected; Kaydet is "
      'already enabled at the base price', (tester) async {
    await _openDialog(tester, _PendingResult());

    expect(
        find.widgetWithText(ElevatedButton, 'Kaydet (500 TL)'), findsOneWidget);
  });

  testWidgets('selecting a paid extra updates the total', (tester) async {
    await _openDialog(tester, _PendingResult());

    await tester.tap(find.text('Avokado'));
    await tester.pumpAndSettle();

    expect(
        find.widgetWithText(ElevatedButton, 'Kaydet (580 TL)'), findsOneWidget);
  });

  testWidgets('confirms and returns quantity, note and selected modifiers',
      (tester) async {
    final pending = _PendingResult();
    await _openDialog(tester, pending);

    await tester.tap(find.text('Meksika Pilavı'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sosu ayrı olsun');
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Kaydet (1560 TL)'));
    await tester.pumpAndSettle();

    final result = await pending.value!;
    expect(result, isNotNull);
    expect(result!.quantity, 3);
    expect(result.note, 'Sosu ayrı olsun');
    expect(result.selectedModifiers.map((m) => m.optionId), ['carb_meksika']);
  });

  testWidgets(
      'deselecting the only choice in a required single-select group '
      'disables Kaydet', (tester) async {
    await _openDialog(tester, _PendingResult());

    await tester.tap(find.text('Basmati'));
    await tester.pumpAndSettle();

    final saveButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Kaydet (500 TL)'),
    );
    expect(saveButton.onPressed, isNull);
  });
}
