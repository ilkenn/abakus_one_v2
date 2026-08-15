import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/navigation_provider.dart';

/// The customer app's bottom navigation: Ana Sayfa, Menü, an emphasized
/// center QR action, Sepetim, Profil. Four of the five slots map to a real
/// [AppTab] (selection state from [currentTab]); the QR slot has no tab of
/// its own — [onQrTap] is expected to open [QrActionsBottomSheet], not
/// change the selected tab, so whatever's showing underneath stays showing
/// once the sheet closes.
class CustomerBottomNavigation extends StatelessWidget {
  final AppTab currentTab;
  final int cartItemCount;
  final ValueChanged<AppTab> onTabSelected;
  final VoidCallback onQrTap;

  const CustomerBottomNavigation({
    super.key,
    required this.currentTab,
    required this.cartItemCount,
    required this.onTabSelected,
    required this.onQrTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Ana Sayfa',
                isSelected: currentTab == AppTab.home,
                onTap: () => onTabSelected(AppTab.home),
              ),
              _NavItem(
                icon: Icons.restaurant_menu_rounded,
                label: 'Menü',
                isSelected: currentTab == AppTab.menu,
                onTap: () => onTabSelected(AppTab.menu),
              ),
              _QrNavItem(onTap: onQrTap),
              _NavItem(
                icon: Icons.shopping_bag_rounded,
                label: 'Sepetim',
                isSelected: currentTab == AppTab.cart,
                onTap: () => onTabSelected(AppTab.cart),
                badgeCount: cartItemCount,
              ),
              _NavItem(
                icon: Icons.person_rounded,
                label: 'Profil',
                isSelected: currentTab == AppTab.profile,
                onTap: () => onTabSelected(AppTab.profile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.primary : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: badgeCount > 0,
                  label: Text('$badgeCount'),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    color: color,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The visually emphasized center action — raised, filled, circular —
/// distinct from the four flat [_NavItem]s on either side of it, per the
/// "QR button must be visually emphasized" requirement.
class _QrNavItem extends StatelessWidget {
  final VoidCallback onTap;

  const _QrNavItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'QR İşlemleri',
      child: Transform.translate(
        offset: const Offset(0, -10),
        child: Material(
          color: AppColors.primary,
          shape: const CircleBorder(),
          elevation: 0,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: AppShadows.floating,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: AppColors.onPrimary,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
