import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';

/// Standard bordered, surface-colored card container used across the app
/// for grouped content (settings sections, list groups, summaries).
///
/// Wraps [child] in a [Material] surface rather than painting the surface
/// color directly on the outer [Container]. A plain `Container(decoration:
/// BoxDecoration(color: ...))` around interactive content (`ListTile`,
/// `SwitchListTile`, `InkWell`, etc.) silently hides that content's ink
/// splashes and trips a Flutter framework assertion in debug mode — using
/// this widget instead of hand-rolling the container avoids that bug by
/// construction instead of relying on every call site to remember the fix.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final BorderRadius borderRadius;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.borderRadius = AppRadius.kMedium,
  });

  @override
  Widget build(BuildContext context) {
    final content =
        padding != null ? Padding(padding: padding!, child: child) : child;

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}
