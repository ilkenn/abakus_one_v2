import 'package:flutter/material.dart';

abstract final class AppShadows {
  AppShadows._();

  static const List<BoxShadow> subtle = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 4.0, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 12.0, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x14000000), blurRadius: 20.0, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> modal = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 28.0,
      offset: Offset(0, -4),
    ),
  ];
}
