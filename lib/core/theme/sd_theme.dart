import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sd_colors.dart';
import 'sd_tokens.dart';
import 'sd_typography.dart';

abstract final class SdTheme {
  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      primary: SdColors.signal,
      onPrimary: SdColors.text,
      secondary: SdColors.gold,
      onSecondary: SdColors.ink,
      surface: SdColors.surface,
      onSurface: SdColors.text,
      error: SdColors.danger,
      outline: SdColors.line,
    );

    final border = OutlineInputBorder(
      borderRadius: const BorderRadius.all(SdRadius.sm),
      borderSide: const BorderSide(color: SdColors.line),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: SdColors.ink,
      textTheme: SdType.textTheme(),
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: const DividerThemeData(color: SdColors.line, space: 1),
      // Secondary text actions stay quiet; signal red is reserved for the primary CTA.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SdColors.gold,
          minimumSize: const Size(SdSize.minTouch, SdSize.minTouch),
          textStyle: SdType.bodyStrong.copyWith(fontSize: 13),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: SdColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: SdType.subheading,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SdColors.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SdSpace.lg,
          vertical: SdSpace.md + 2,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: SdColors.gold, width: 1.4),
        ),
        errorBorder: border.copyWith(borderSide: const BorderSide(color: SdColors.danger)),
        focusedErrorBorder: border.copyWith(
          borderSide: const BorderSide(color: SdColors.danger, width: 1.4),
        ),
        labelStyle: SdType.body.copyWith(color: SdColors.textMuted),
        floatingLabelStyle: SdType.label.copyWith(color: SdColors.gold),
        hintStyle: SdType.body.copyWith(color: SdColors.textFaint),
        errorStyle: SdType.caption.copyWith(color: SdColors.danger),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: SdColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: SdColors.lineStrong,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: SdRadius.xl)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: SdColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(SdRadius.lg),
          side: BorderSide(color: SdColors.line),
        ),
        titleTextStyle: SdType.heading,
        contentTextStyle: SdType.body.copyWith(color: SdColors.textMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: SdColors.surfaceHigh,
        contentTextStyle: SdType.body,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(SdRadius.md),
          side: BorderSide(color: SdColors.lineStrong),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: const BorderSide(color: SdColors.lineStrong, width: 1.4),
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? SdColors.gold : null,
        ),
        checkColor: const WidgetStatePropertyAll(SdColors.ink),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SdColors.gold,
        linearTrackColor: SdColors.line,
      ),
    );
  }
}
