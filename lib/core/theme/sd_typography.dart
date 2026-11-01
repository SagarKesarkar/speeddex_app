import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'sd_colors.dart';

/// Type system.
///
/// * Display — Chakra Petch: squared, technical, automotive. Uppercase only.
/// * Body — Inter: neutral and highly legible at small sizes.
/// * Data — JetBrains Mono: tabular figures for specs, serials and XP.
abstract final class SdType {
  static TextStyle _display(double size, {double spacing = 0.5}) => GoogleFonts.chakraPetch(
    fontSize: size,
    fontWeight: FontWeight.w700,
    letterSpacing: spacing,
    height: 1.05,
    color: SdColors.text,
  );

  static TextStyle _body(double size, FontWeight weight, {double height = 1.4}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, height: height, color: SdColors.text);

  static TextStyle _mono(double size, FontWeight weight, {double spacing = 0}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        height: 1.25,
        color: SdColors.text,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle get hero => _display(40, spacing: 0.8);
  static TextStyle get title => _display(28);
  static TextStyle get heading => _display(20);
  static TextStyle get subheading => _display(16, spacing: 0.6);

  /// Small uppercase labels: section tags, tabs, tier chips.
  static TextStyle get label => GoogleFonts.chakraPetch(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.6,
    color: SdColors.textMuted,
  );

  static TextStyle get bodyLarge => _body(16, FontWeight.w400, height: 1.5);
  static TextStyle get body => _body(14, FontWeight.w400);
  static TextStyle get bodyStrong => _body(14, FontWeight.w600);
  static TextStyle get caption => _body(12, FontWeight.w400).copyWith(color: SdColors.textMuted);

  static TextStyle get data => _mono(14, FontWeight.w500);
  static TextStyle get dataSmall =>
      _mono(11, FontWeight.w500, spacing: 0.6).copyWith(color: SdColors.textMuted);
  static TextStyle get dataLarge => _mono(22, FontWeight.w700);

  static TextTheme textTheme() => TextTheme(
    displayLarge: hero,
    headlineMedium: title,
    titleLarge: heading,
    titleMedium: subheading,
    bodyLarge: bodyLarge,
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: label.copyWith(color: SdColors.text),
    labelMedium: label,
  );
}
