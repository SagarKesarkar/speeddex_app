import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/sd_colors.dart';
import '../theme/sd_tokens.dart';
import '../theme/sd_typography.dart';

/// Compact segmented control with a sliding indicator.
class SdSegmented<T> extends StatelessWidget {
  const SdSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.iconOf,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final IconData Function(T)? iconOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: const BorderRadius.all(SdRadius.sm),
        border: Border.all(color: SdColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in values)
            Semantics(
              button: true,
              selected: v == selected,
              label: labelOf(v),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (v == selected) return;
                  HapticFeedback.selectionClick();
                  onChanged(v);
                },
                child: AnimatedContainer(
                  duration: SdMotion.fast,
                  padding: const EdgeInsets.symmetric(horizontal: SdSpace.md),
                  alignment: Alignment.center,
                  constraints: const BoxConstraints(minWidth: 44),
                  decoration: BoxDecoration(
                    color: v == selected ? SdColors.surfaceHigh : Colors.transparent,
                    borderRadius: const BorderRadius.all(Radius.circular(4)),
                  ),
                  child: iconOf != null
                      ? Icon(
                          iconOf!(v),
                          size: 18,
                          color: v == selected ? SdColors.text : SdColors.textFaint,
                        )
                      : Text(
                          labelOf(v).toUpperCase(),
                          style: SdType.label.copyWith(
                            fontSize: 11,
                            color: v == selected ? SdColors.text : SdColors.textFaint,
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal filter chip row item.
class SdFilterChip extends StatelessWidget {
  const SdFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? SdColors.gold;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(SdRadius.xl),
        child: AnimatedContainer(
          duration: SdMotion.fast,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: SdSpace.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.16) : SdColors.surface,
            borderRadius: const BorderRadius.all(SdRadius.xl),
            border: Border.all(color: selected ? c : SdColors.line),
          ),
          child: Text(
            label.toUpperCase(),
            style: SdType.label.copyWith(fontSize: 11, color: selected ? c : SdColors.textMuted),
          ),
        ),
      ),
    );
  }
}
