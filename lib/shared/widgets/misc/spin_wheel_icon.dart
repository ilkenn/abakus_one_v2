import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Native, honestly-illustrated spin wheel — a segmented ring drawn with
/// [CustomPaint], not a photo-realistic prop (no wheel illustration asset
/// exists). Shown on both the Loyalty screen and Home, so it lives here per
/// the architecture bible's shared-widget-promotion rule.
class SpinWheelIcon extends StatelessWidget {
  final double size;

  const SpinWheelIcon({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SpinWheelPainter()),
    );
  }
}

class _SpinWheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const segmentCount = 8;
    const sweep = 2 * 3.14159265 / segmentCount;

    for (var i = 0; i < segmentCount; i++) {
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = i.isEven
            ? AppColors.primary
            : AppColors.primaryLight.withValues(alpha: 0.7);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep,
        true,
        paint,
      );
    }

    canvas.drawCircle(
      center,
      radius * 0.32,
      Paint()..color = AppColors.surface,
    );
    canvas.drawCircle(
      center,
      radius * 0.32,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
