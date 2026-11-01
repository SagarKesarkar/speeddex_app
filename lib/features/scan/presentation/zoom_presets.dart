import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';

/// 1× / 2× / 5× zoom buttons (those the lens supports). Between presets, the
/// nearest one below shows the current level, e.g. "2.6×".
class ZoomPresets extends StatelessWidget {
  const ZoomPresets({
    super.key,
    required this.min,
    required this.max,
    required this.zoom,
    required this.onSelect,
  });
  final double min;
  final double max;
  final double zoom;
  final ValueChanged<double> onSelect;

  static String _label(double z) =>
      z == z.roundToDouble() ? '${z.round()}×' : '${z.toStringAsFixed(1)}×';

  @override
  Widget build(BuildContext context) {
    final presets = [
      for (final p in const [1.0, 2.0, 5.0])
        if (p >= min - 0.01 && p <= max + 0.01) p,
    ];
    if (presets.isEmpty) return const SizedBox.shrink();
    final active = presets.lastWhere((p) => p <= zoom + 0.05, orElse: () => presets.first);
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: SdColors.ink.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in presets)
              Semantics(
                button: true,
                selected: p == active,
                label: 'Zoom ${_label(p)}',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelect(p);
                  },
                  child: AnimatedContainer(
                    duration: SdMotion.fast,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 44,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p == active ? SdColors.surfaceHigh : Colors.transparent,
                    ),
                    child: Text(
                      p == active ? _label(zoom) : _label(p),
                      style: SdType.label.copyWith(
                        fontSize: 11,
                        color: p == active ? SdColors.gold : SdColors.text,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
