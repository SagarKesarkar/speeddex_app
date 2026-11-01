import 'package:flutter/widgets.dart';

/// Spacing scale (4pt base).
abstract final class SdSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 48.0;

  /// Horizontal page gutter.
  static const gutter = 20.0;
}

/// Corner radii. Kept tight: cards read as machined objects, not bubbles.
abstract final class SdRadius {
  static const xs = Radius.circular(3);
  static const sm = Radius.circular(6);
  static const md = Radius.circular(10);
  static const lg = Radius.circular(14);
  static const xl = Radius.circular(20);
}

/// Component dimensions.
abstract final class SdSize {
  static const minTouch = 48.0;
  static const buttonHeight = 52.0;
  static const buttonHeightCompact = 40.0;
  static const navBarHeight = 64.0;
  static const topBarHeight = 56.0;

  /// Content never stretches past this on tablets.
  static const maxContentWidth = 560.0;

  /// Collector cards keep a 5:7 trading-card ratio.
  static const cardAspect = 5 / 7.4;
}

abstract final class SdMotion {
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 520);
  static const curve = Curves.easeOutCubic;
}
