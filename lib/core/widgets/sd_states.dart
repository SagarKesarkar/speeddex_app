import 'package:flutter/material.dart';

import '../errors/app_failure.dart';
import '../theme/sd_colors.dart';
import '../theme/sd_tokens.dart';
import '../theme/sd_typography.dart';
import 'sd_button.dart';

/// Pulsing placeholder block for skeleton layouts.
class SdSkeleton extends StatefulWidget {
  const SdSkeleton({super.key, this.height = 16, this.width, this.radius = SdRadius.sm});

  final double height;
  final double? width;
  final Radius radius;

  @override
  State<SdSkeleton> createState() => _SdSkeletonState();
}

class _SdSkeletonState extends State<SdSkeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(SdColors.surfaceRaised, SdColors.surfaceHigh, _c.value),
          borderRadius: BorderRadius.all(widget.radius),
        ),
      ),
    );
  }
}

class SdEmptyState extends StatelessWidget {
  const SdEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SdSpace.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(SdRadius.lg),
                border: Border.all(color: SdColors.lineStrong),
              ),
              child: Icon(icon, color: SdColors.gold, size: 28),
            ),
            const SizedBox(height: SdSpace.xl),
            Text(title.toUpperCase(), style: SdType.heading, textAlign: TextAlign.center),
            const SizedBox(height: SdSpace.sm),
            Text(
              message,
              style: SdType.body.copyWith(color: SdColors.textMuted),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: SdSpace.xl),
              SdButton(label: actionLabel!, onPressed: onAction, expand: false),
            ],
          ],
        ),
      ),
    );
  }
}

class SdErrorState extends StatelessWidget {
  const SdErrorState({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = error is NetworkFailure;
    return SdEmptyState(
      icon: offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: offline ? 'Offline' : 'Couldn’t load',
      message: error.userMessage,
      actionLabel: 'Try again',
      onAction: onRetry,
    );
  }
}

/// Inline, non-blocking error strip shown above already-loaded content.
class SdInlineError extends StatelessWidget {
  const SdInlineError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.md, vertical: SdSpace.sm),
      decoration: BoxDecoration(
        color: SdColors.danger.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.all(SdRadius.sm),
        border: Border.all(color: SdColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: SdColors.danger),
          const SizedBox(width: SdSpace.sm),
          Expanded(
            child: Text(message, style: SdType.caption.copyWith(color: SdColors.text)),
          ),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

void showSdSnack(BuildContext context, String message, {bool success = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              size: 18,
              color: success ? SdColors.success : SdColors.gold,
            ),
            const SizedBox(width: SdSpace.md),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}
