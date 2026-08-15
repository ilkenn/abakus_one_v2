import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/data/dev_table_qr_seed.dart';
import 'package:abakus_one_v2/features/qr/domain/models/active_table_context.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/active_table_context_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/table_session_dependencies_provider.dart';

/// Provider-level coverage for the "scan -> table context" pipeline —
/// exercises the exact sequence `qr_scanner_screen.dart` runs
/// (`resolveTableQrTokenProvider` -> `openTableSessionProvider` ->
/// `createGuestSessionProvider` -> `activeTableContextProvider.notifier
/// .set`) without needing the real camera widget, and proves the
/// singleton-provider shape genuinely "survives navigation" (any number of
/// independent reads within the same container return the identical,
/// still-set context — the same guarantee `authProvider`/`navigationProvider`
/// already rely on).
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  test('baslangicta aktif masa baglami yoktur', () {
    expect(container.read(activeTableContextProvider), isNull);
  });

  test('gecerli bir tarama sonrasi tam baglam kurulur', () async {
    final resolution = await container.read(resolveTableQrTokenProvider).call(
          DevTableQrSeed.validTokenTable12,
        );
    expect(resolution.isUsable, isTrue);

    final session = await container.read(openTableSessionProvider).call(
          restaurantId: resolution.restaurantId!,
          branchId: resolution.branchId!,
          tableId: resolution.tableId!,
        );
    final guestSession = container.read(createGuestSessionProvider).call(
          tableSessionId: session.id,
          branchId: resolution.branchId!,
          tableId: resolution.tableId!,
        );

    container.read(activeTableContextProvider.notifier).set(
          ActiveTableContext(
            restaurantId: resolution.restaurantId!,
            branchId: resolution.branchId!,
            branchName: resolution.branchDisplayName!,
            tableId: resolution.tableId!,
            tableName: resolution.tableDisplayName!,
            session: session,
            guestSession: guestSession,
          ),
        );

    final context = container.read(activeTableContextProvider);
    expect(context, isNotNull);
    expect(context!.tableId, DevTableQrSeed.table12Id);
    expect(context.tableName, 'Masa 12');
    expect(context.session.tableId, DevTableQrSeed.table12Id);
    expect(context.guestSession.tableSessionId, session.id);
    expect(context.guestSession.isAnonymous, isTrue);
  });

  test(
    'baglam bir kez kurulunca herhangi bir bagimsiz okuma (farkli ekranlari '
    'simule eder) ayni degeri gorur',
    () async {
      final resolution = await container.read(resolveTableQrTokenProvider).call(
            DevTableQrSeed.validTokenTable7,
          );
      final session = await container.read(openTableSessionProvider).call(
            restaurantId: resolution.restaurantId!,
            branchId: resolution.branchId!,
            tableId: resolution.tableId!,
          );
      final guestSession = container.read(createGuestSessionProvider).call(
            tableSessionId: session.id,
            branchId: resolution.branchId!,
            tableId: resolution.tableId!,
          );
      container.read(activeTableContextProvider.notifier).set(
            ActiveTableContext(
              restaurantId: resolution.restaurantId!,
              branchId: resolution.branchId!,
              branchName: resolution.branchDisplayName!,
              tableId: resolution.tableId!,
              tableName: resolution.tableDisplayName!,
              session: session,
              guestSession: guestSession,
            ),
          );

      // Three independent reads, standing in for Menu/Cart/Bowl Builder
      // each watching the same provider from their own widget tree.
      final readFromMenu = container.read(activeTableContextProvider);
      final readFromCart = container.read(activeTableContextProvider);
      final readFromBowlBuilder = container.read(activeTableContextProvider);

      expect(readFromMenu, same(readFromCart));
      expect(readFromCart, same(readFromBowlBuilder));
      expect(readFromMenu!.tableName, 'Masa 7');
    },
  );

  test(
    'ayni masaya iki ayri tarama (QR = tek bir siparis degildir) iki farkli '
    'oturum acar, eskisini asla yeniden kullanmaz',
    () async {
      final resolution = await container.read(resolveTableQrTokenProvider).call(
            DevTableQrSeed.validTokenTable12,
          );

      final firstSession = await container.read(openTableSessionProvider).call(
            restaurantId: resolution.restaurantId!,
            branchId: resolution.branchId!,
            tableId: resolution.tableId!,
          );
      final secondSession = await container.read(openTableSessionProvider).call(
            restaurantId: resolution.restaurantId!,
            branchId: resolution.branchId!,
            tableId: resolution.tableId!,
          );

      expect(firstSession.id, isNot(secondSession.id));
      expect(firstSession.tableId, secondSession.tableId);
    },
  );

  test('clear() baglami sifirlar', () async {
    final resolution = await container.read(resolveTableQrTokenProvider).call(
          DevTableQrSeed.validTokenTable12,
        );
    final session = await container.read(openTableSessionProvider).call(
          restaurantId: resolution.restaurantId!,
          branchId: resolution.branchId!,
          tableId: resolution.tableId!,
        );
    final guestSession = container.read(createGuestSessionProvider).call(
          tableSessionId: session.id,
          branchId: resolution.branchId!,
          tableId: resolution.tableId!,
        );
    container.read(activeTableContextProvider.notifier).set(
          ActiveTableContext(
            restaurantId: resolution.restaurantId!,
            branchId: resolution.branchId!,
            branchName: resolution.branchDisplayName!,
            tableId: resolution.tableId!,
            tableName: resolution.tableDisplayName!,
            session: session,
            guestSession: guestSession,
          ),
        );
    expect(container.read(activeTableContextProvider), isNotNull);

    container.read(activeTableContextProvider.notifier).clear();

    expect(container.read(activeTableContextProvider), isNull);
  });
}
