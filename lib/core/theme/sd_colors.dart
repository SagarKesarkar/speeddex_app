import 'package:flutter/material.dart';

/// SpeedDex colour tokens.
///
/// Graphite surfaces with two deliberate accents: champagne gold for status,
/// rewards and progression, and signal red for the single primary action on a
/// screen. Everything else stays neutral so tier colours read clearly.
abstract final class SdColors {
  // Surfaces, darkest to lightest.
  static const ink = Color(0xFF0B0C0F);
  static const surface = Color(0xFF14161B);
  static const surfaceRaised = Color(0xFF1B1E24);
  static const surfaceHigh = Color(0xFF242830);
  static const line = Color(0xFF2B2F38);
  static const lineStrong = Color(0xFF3B404C);

  // Text.
  static const text = Color(0xFFF3EFE7);
  static const textMuted = Color(0xFFA3A6AE);
  static const textFaint = Color(0xFF6B6F79);

  // Accents.
  static const gold = Color(0xFFD9B970);
  static const goldDeep = Color(0xFF9C7F3C);
  static const signal = Color(0xFFE2352E);
  static const signalDeep = Color(0xFF9E1F1A);

  // Feedback.
  static const success = Color(0xFF4DB384);
  static const warning = Color(0xFFE5A53C);
  static const danger = Color(0xFFE5484D);

  static const scrim = Color(0xCC07080A);
}
