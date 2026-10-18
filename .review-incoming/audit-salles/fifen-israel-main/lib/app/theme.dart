import 'package:flutter/material.dart';

class FiseSchoolTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF166534),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF6FAF7),
      fontFamily: 'Roboto',
    );
  }
}
