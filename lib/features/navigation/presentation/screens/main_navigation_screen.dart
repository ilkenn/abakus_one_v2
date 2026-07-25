import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../bowl_builder/presentation/screens/bowl_builder_screen.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../cart/presentation/screens/cart_screen.dart';
import '../../../home/presentation/screens/home_screen.dart';
import '../../../menu/presentation/screens/menu_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../qr/presentation/screens/qr_scanner_screen.dart';
import '../providers/navigation_provider.dart';

/// The app's shell: a Material 3 [NavigationBar] across 5 persistent
/// destinations (Home/Menu/Build Bowl/Cart/Profile), each with its own
/// nested [Navigator] so a push inside one tab (e.g. Product Detail from
/// Menu) never touches the others' history. Tab widgets are built once in
/// [initState] and kept alive under an [IndexedStack] — switching tabs
/// never rebuilds/disposes a tab's screen, which is what keeps scroll
/// position and in-progress form state (e.g. Menu's search field) intact
/// across a switch.
///
/// QR order is intentionally not one of the 5 destinations — it's a
/// one-shot scan action, pushed on the shell's own (root) Navigator so it
/// overlays the whole shell including the bottom bar, exactly like before.
class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  late final Map<AppTab, GlobalKey<NavigatorState>> _navigatorKeys;
  late final Map<AppTab, NavigatorObserver> _tabObservers;
  late final Map<AppTab, Widget> _tabRoots;

  /// Built once, in [initState], and never reconstructed. A [Navigator]
  /// carries its route history in its own [State] (found via [GlobalKey]);
  /// rebuilding a *new* `Navigator(key: sameKey, ...)` widget instance on
  /// every parent rebuild forces Flutter to reconcile that history via a
  /// GlobalKey lookup each time, which — combined with `IndexedStack`
  /// keeping every tab mounted — triggers a framework-level element-tree
  /// assertion. Keeping the exact same widget instances lets Flutter's
  /// `identical()` fast path skip that reconciliation entirely.
  late final Map<AppTab, Widget> _tabNavigators;

  @override
  void initState() {
    super.initState();
    _navigatorKeys = {
      for (final tab in AppTab.values) tab: GlobalKey<NavigatorState>(),
    };
    // Each tab's Navigator reports its own push/pop back to this State so
    // the shell can re-evaluate the Android back-button decision (see
    // `build`) right when a tab's own stack actually changes — not on
    // some other, unrelated rebuild. `didPush` also fires once for a
    // Navigator's *initial* route, i.e. while all 5 tab Navigators are
    // still being mounted for the first time — calling `setState`
    // synchronously there re-enters the framework's build/mount pass
    // mid-flight and trips an element-tree assertion. Deferring to a
    // post-frame callback lets the current frame finish mounting first.
    _tabObservers = {
      for (final tab in AppTab.values)
        tab: _TabStackObserver(onStackChanged: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }),
    };
    _tabRoots = {
      AppTab.home: const HomeScreen(),
      AppTab.menu: const MenuScreen(),
      AppTab.buildBowl: const BowlBuilderScreen(),
      AppTab.cart: const CartScreen(),
      AppTab.profile: const ProfileScreen(),
    };
    _tabNavigators = {
      for (final tab in AppTab.values)
        tab: Navigator(
          key: _navigatorKeys[tab],
          observers: [_tabObservers[tab]!],
          onGenerateRoute: (settings) => MaterialPageRoute(
            settings: settings,
            builder: (context) => _tabRoots[tab]!,
          ),
        ),
    };
  }

  void _openQrOrder() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );
  }

  void _handleBackPress(AppTab currentTab) {
    final tabNavigator = _navigatorKeys[currentTab]?.currentState;
    if (tabNavigator != null && tabNavigator.canPop()) {
      tabNavigator.pop();
      return;
    }
    if (currentTab != AppTab.home) {
      ref.read(navigationProvider.notifier).selectTab(AppTab.home);
    }
    // currentTab == Home and its stack is already empty: `canPop` below is
    // `true` in that case, so this branch is never reached — the system
    // handles the exit itself.
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = ref.watch(navigationProvider);
    final cartItemCount = ref.watch(cartTotalItemsProvider);
    final currentTabCanPop =
        _navigatorKeys[currentTab]?.currentState?.canPop() ?? false;

    return PopScope(
      canPop: currentTab == AppTab.home && !currentTabCanPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPress(currentTab);
      },
      child: Scaffold(
        body: IndexedStack(
          index: currentTab.index,
          children: [
            for (final tab in AppTab.values) _tabNavigators[tab]!,
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openQrOrder,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('QR ile Sipariş'),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: currentTab.index,
          onDestinationSelected: (index) {
            ref
                .read(navigationProvider.notifier)
                .selectTab(AppTab.values[index]);
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_rounded),
              label: 'Ana Sayfa',
            ),
            const NavigationDestination(
              icon: Icon(Icons.restaurant_menu_rounded),
              label: 'Menü',
            ),
            const NavigationDestination(
              icon: Icon(Icons.blender_rounded),
              label: 'Build Bowl',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: cartItemCount > 0,
                label: Text('$cartItemCount'),
                child: const Icon(Icons.shopping_bag_rounded),
              ),
              label: 'Sepetim',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_rounded),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}

class _TabStackObserver extends NavigatorObserver {
  final VoidCallback onStackChanged;

  _TabStackObserver({required this.onStackChanged});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onStackChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onStackChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onStackChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onStackChanged();
  }
}
