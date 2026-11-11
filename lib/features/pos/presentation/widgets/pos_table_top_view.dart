import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_typography.dart';

/// 2026-11-11 — how a table looks on the POS bird's-eye Masalar grid
/// (product owner's rules):
/// - bill requested → orange; a live order at the table → red; no live
///   order → green ("Boş", even while a QR guest is only browsing);
/// - cleaning / disabled / reserved keep a neutral grey, so "disabled" can
///   never be confused with the red "has an order" state.
enum PosTableTone {
  free,
  occupied,
  billRequested,
  cleaning,
  reserved,
  disabled;

  /// [status] is the server's display status (`displayTableStatus`);
  /// [activePortionCount] the server's `countActivePortions`.
  static PosTableTone resolve({
    required String status,
    required int activePortionCount,
  }) {
    return switch (status) {
      'billRequested' => PosTableTone.billRequested,
      'cleaning' => PosTableTone.cleaning,
      'reserved' => PosTableTone.reserved,
      'disabled' => PosTableTone.disabled,
      _ => activePortionCount > 0 ? PosTableTone.occupied : PosTableTone.free,
    };
  }

  Color get color => switch (this) {
        PosTableTone.free => AppColors.success,
        PosTableTone.occupied => AppColors.error,
        PosTableTone.billRequested => AppColors.accent,
        PosTableTone.cleaning ||
        PosTableTone.reserved ||
        PosTableTone.disabled =>
          AppColors.textSecondary,
      };

  String get label => switch (this) {
        PosTableTone.free => 'Boş',
        PosTableTone.occupied => 'Dolu',
        PosTableTone.billRequested => 'Hesap İstendi',
        PosTableTone.cleaning => 'Temizleniyor',
        PosTableTone.reserved => 'Rezerve',
        PosTableTone.disabled => 'Kapalı',
      };
}

/// The four chair positions around the table top, in fill order.
enum PosChairSide { top, bottom, left, right }

/// How many chairs to draw (the table's capacity, 1–4; 4 when unset —
/// four sides is the most a top-down card can show) and how many of them
/// are taken (one per live main portion, never more than the chairs).
({int chairs, int seated}) posTableSeating({
  required int? capacity,
  required int activePortionCount,
}) {
  final chairs =
      (capacity == null || capacity <= 0) ? 4 : math.min(capacity, 4);
  final seated = activePortionCount.clamp(0, chairs);
  return (chairs: chairs, seated: seated);
}

/// A top-down drawing of one table: the table top in the middle with the
/// table's name, and up to four chairs around it — a filled chair shows a
/// person, an empty chair is an outline.
class PosTableTopView extends StatelessWidget {
  const PosTableTopView({
    super.key,
    required this.tableName,
    required this.tone,
    required this.chairs,
    required this.seated,
  });

  final String tableName;
  final PosTableTone tone;
  final int chairs;
  final int seated;

  @override
  Widget build(BuildContext context) {
    final sides = PosChairSide.values.take(chairs).toList();
    return Semantics(
      label: '$tableName, ${tone.label}, $seated / $chairs sandalye dolu',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = math.min(constraints.maxWidth, constraints.maxHeight);
          final chair = size * 0.2;
          final gap = size * 0.04;
          final tableSize = size - 2 * (chair + gap);
          return Center(
            child: SizedBox.square(
              dimension: size,
              child: Stack(
                children: [
                  Positioned(
                    left: chair + gap,
                    top: chair + gap,
                    width: tableSize,
                    height: tableSize,
                    child: _TableTop(name: tableName, tone: tone),
                  ),
                  for (var i = 0; i < sides.length; i++)
                    _positionedChair(
                      side: sides[i],
                      size: size,
                      chair: chair,
                      child: _Chair(
                        key: ValueKey('chair-${sides[i].name}'),
                        seated: i < seated,
                        tone: tone,
                        size: chair,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _positionedChair({
    required PosChairSide side,
    required double size,
    required double chair,
    required Widget child,
  }) {
    final centered = (size - chair) / 2;
    return switch (side) {
      PosChairSide.top => Positioned(left: centered, top: 0, child: child),
      PosChairSide.bottom =>
        Positioned(left: centered, bottom: 0, child: child),
      PosChairSide.left => Positioned(left: 0, top: centered, child: child),
      PosChairSide.right => Positioned(right: 0, top: centered, child: child),
    };
  }
}

class _TableTop extends StatelessWidget {
  const _TableTop({required this.name, required this.tone});

  final String name;
  final PosTableTone tone;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.color.withValues(alpha: 0.14),
        border: Border.all(color: tone.color, width: 2),
        borderRadius: AppRadius.kMedium,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Chair extends StatelessWidget {
  const _Chair({
    super.key,
    required this.seated,
    required this.tone,
    required this.size,
  });

  final bool seated;
  final PosTableTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: seated ? tone.color : AppColors.surface,
        border: Border.all(
          color: seated ? tone.color : AppColors.border,
          width: 1.5,
        ),
        borderRadius: AppRadius.kSmall,
      ),
      child: seated
          ? Icon(
              Icons.person,
              key: const ValueKey('seated'),
              size: size * 0.8,
              color: AppColors.onPrimary,
            )
          : null,
    );
  }
}
