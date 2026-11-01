import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/sd_colors.dart';
import '../theme/sd_tokens.dart';
import '../theme/sd_typography.dart';

enum SdButtonVariant { primary, secondary, gold, ghost }

/// The single button primitive. One `primary` per screen.
class SdButton extends StatefulWidget {
  const SdButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = SdButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.compact = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final SdButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool compact;
  final bool expand;

  @override
  State<SdButton> createState() => _SdButtonState();
}

class _SdButtonState extends State<SdButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (widget.variant) {
      SdButtonVariant.primary => (SdColors.signal, SdColors.text, SdColors.signal),
      SdButtonVariant.gold => (SdColors.gold, SdColors.ink, SdColors.gold),
      SdButtonVariant.secondary => (SdColors.surfaceHigh, SdColors.text, SdColors.lineStrong),
      SdButtonVariant.ghost => (Colors.transparent, SdColors.textMuted, Colors.transparent),
    };
    final height = widget.compact ? SdSize.buttonHeightCompact : SdSize.buttonHeight;
    final opacity = widget.onPressed == null ? 0.4 : 1.0;

    final content = widget.loading
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: fg),
                const SizedBox(width: SdSpace.sm),
              ],
              Flexible(
                child: Text(
                  widget.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SdType.label.copyWith(
                    color: fg,
                    fontSize: widget.compact ? 12 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: _enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: SdMotion.fast,
          child: AnimatedOpacity(
            opacity: opacity,
            duration: SdMotion.fast,
            child: Container(
              height: height,
              width: widget.expand ? double.infinity : null,
              padding: EdgeInsets.symmetric(horizontal: widget.compact ? SdSpace.lg : SdSpace.xl),
              // An aligned Container grows to fill its constraints, so only
              // align when expanding; otherwise the button hugs its label.
              alignment: widget.expand ? Alignment.center : null,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.all(SdRadius.sm),
                border: Border.all(color: border),
                gradient:
                    widget.variant == SdButtonVariant.primary ||
                        widget.variant == SdButtonVariant.gold
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color.lerp(bg, Colors.white, 0.08)!, bg],
                      )
                    : null,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
