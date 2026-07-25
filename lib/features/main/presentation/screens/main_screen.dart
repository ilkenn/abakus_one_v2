import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../cart/presentation/screens/cart_screen.dart';
import '../../../home/presentation/screens/home_screen.dart';
import '../../../menu/presentation/screens/menu_screen.dart';
import '../../../navigation/presentation/providers/navigation_provider.dart';
import '../../../profile/presentation/screens/profile_screen.dart';

class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  final List<Widget> _screens = const [
    HomeScreen(),
    MenuScreen(),
    CartScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTab = ref.watch(navigationProvider);
    // This screen only knows 4 of navigationProvider's 5 AppTab values (no
    // Build Bowl) — clamp defensively rather than assume selectedTab.index
    // always fits _screens.length.
    final selectedIndex = selectedTab.index.clamp(0, _screens.length - 1);

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          ref.read(navigationProvider.notifier).selectTab(AppTab.values[index]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Ana Sayfa',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu_rounded),
            label: 'Menü',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart_rounded),
            label: 'Sepetim',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.1),
      ),
    );
  }
}
