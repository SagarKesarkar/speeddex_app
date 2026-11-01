import 'package:flutter/material.dart';

import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/car_visual.dart';
import '../../../core/widgets/sd_button.dart';
import '../../../domain/car_card.dart';

/// What to do with a scan of a car the player already has.
sealed class DuplicateChoice {
  const DuplicateChoice();
}

/// Add it as another card (a different colour, a nicer photo).
class KeepBoth extends DuplicateChoice {
  const KeepBoth();
}

/// Put the new photo on this existing card.
class ReplaceCard extends DuplicateChoice {
  const ReplaceCard(this.cardId);
  final String cardId;
}

class DiscardScan extends DuplicateChoice {
  const DiscardScan();
}

/// "Already in your Garage": keep this one too, replace one of the copies
/// (the player picks which when there are several), or discard. Null if
/// dismissed.
Future<DuplicateChoice?> showDuplicateSheet(
  BuildContext context, {
  required CarCard candidate,
  required List<CarCard> copies,
}) {
  return showModalBottomSheet<DuplicateChoice>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _DuplicateSheet(candidate: candidate, copies: copies),
  );
}

class _DuplicateSheet extends StatelessWidget {
  const _DuplicateSheet({required this.candidate, required this.copies});
  final CarCard candidate;
  final List<CarCard> copies;

  @override
  Widget build(BuildContext context) {
    final name = candidate.displayName;
    final one = copies.length == 1;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(SdSpace.gutter, 0, SdSpace.gutter, SdSpace.xl),
          children: [
            Text('ALREADY IN YOUR GARAGE', style: SdType.heading),
            const SizedBox(height: SdSpace.sm),
            Text(
              one
                  ? 'You already have a $name, caught on ${SdFormat.date(copies.single.capturedAt)}.'
                  : 'You already have ${copies.length} cards of the $name.',
              style: SdType.body.copyWith(color: SdColors.textMuted),
            ),
            const SizedBox(height: SdSpace.xl),
            SdButton(
              label: 'Keep this one too',
              icon: Icons.add_circle_outline_rounded,
              onPressed: () => Navigator.of(context).pop(const KeepBoth()),
            ),
            const SizedBox(height: SdSpace.sm),
            Text(
              'Adds another card, e.g. a different colour. Repeats earn no coins or XP.',
              style: SdType.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SdSpace.xl),
            Text(one ? 'OR REPLACE THE PHOTO' : 'OR REPLACE ONE', style: SdType.label),
            const SizedBox(height: SdSpace.sm),
            for (final c in copies) ...[
              _CopyRow(card: c, onReplace: () => Navigator.of(context).pop(ReplaceCard(c.id))),
              const SizedBox(height: SdSpace.sm),
            ],
            Text(
              'The card keeps its number and history; only the photo changes. No new rewards.',
              style: SdType.caption,
            ),
            const SizedBox(height: SdSpace.lg),
            SdButton(
              label: 'Discard this photo',
              variant: SdButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(const DiscardScan()),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.card, required this.onReplace});
  final CarCard card;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final color = card.capture?.color;
    return Semantics(
      button: true,
      label: 'Replace ${card.serial}, caught ${SdFormat.date(card.capturedAt)}',
      excludeSemantics: true,
      child: Material(
        color: SdColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(SdRadius.md),
          side: const BorderSide(color: SdColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onReplace,
          child: Row(
            children: [
              SizedBox(width: 92, height: 72, child: CarVisual(card: card)),
              const SizedBox(width: SdSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.serial, style: SdType.data),
                    const SizedBox(height: 2),
                    if (color != null && color.isNotEmpty)
                      Text(
                        _cap(color),
                        style: SdType.caption.copyWith(color: SdColors.text),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text('Caught ${SdFormat.date(card.capturedAt)}', style: SdType.caption),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SdSpace.md),
                child: Text('REPLACE', style: SdType.label.copyWith(color: SdColors.gold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _cap(String s) => s[0].toUpperCase() + s.substring(1);
}
