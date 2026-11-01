import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../core/widgets/sd_states.dart';
import '../../../core/widgets/tilt_card.dart';
import '../../../domain/car_card.dart';
import '../../feed/application/feed_controller.dart';
import '../application/share_card.dart';
import '../application/unlock_flow.dart';
import 'collector_card.dart';
import 'model_photos.dart';

final cardDetailProvider = FutureProvider.autoDispose.family<CarCard, String>(
  (ref, id) => ref.watch(cardsRepositoryProvider).detail(id),
);

class CardDetailScreen extends ConsumerStatefulWidget {
  const CardDetailScreen({super.key, required this.cardId});
  final String cardId;

  @override
  ConsumerState<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends ConsumerState<CardDetailScreen> {
  bool _unlocking = false;
  final _shareKey = GlobalKey(debugLabel: 'share-detail');

  Future<void> _unlock(CarCard card) async {
    setState(() => _unlocking = true);
    final unlocked = await runUnlockFlow(context, ref, card);
    if (!mounted) return;
    setState(() => _unlocking = false);
    if (unlocked != null) {
      ref.invalidate(cardDetailProvider(widget.cardId));
      ref.invalidate(modelPhotosProvider(widget.cardId));
      ref.read(feedControllerProvider.notifier).applyCard(unlocked);
      showSdSnack(context, 'Card unlocked.', success: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(cardDetailProvider(widget.cardId));
    return Scaffold(
      appBar: AppBar(title: Text(async.value?.displayName.toUpperCase() ?? 'CAR CARD')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SdErrorState(
          error: e,
          onRetry: () => ref.invalidate(cardDetailProvider(widget.cardId)),
        ),
        data: (card) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                SdSpace.gutter,
                SdSpace.sm,
                SdSpace.gutter,
                SdSpace.huge,
              ),
              children: [
                // Drag a finger over the card to tilt it towards the light. The
                // tilt sits outside the share capture, so shared images are flat.
                TiltCard(
                  borderRadius: const BorderRadius.all(SdRadius.lg),
                  child: RepaintBoundary(
                    key: _shareKey,
                    child: CollectorCard(
                      card: card,
                      heroTag: 'card-${card.id}',
                      unlocking: _unlocking,
                      onUnlock: () => _unlock(card),
                    ),
                  ),
                ),
                // Where, when and in what condition the car was caught is part
                // of what an unlock buys, so it stays hidden until then.
                if (card.ownedByViewer || card.hiddenUnlocked) ...[
                  const SizedBox(height: SdSpace.xxl),
                  const SdSectionLabel('Capture record'),
                  const SizedBox(height: SdSpace.md),
                  _Rows(captureRows(card)),
                  // Reference photos of this generation.
                  ModelPhotosStrip(cardId: card.id, modelName: card.displayName),
                  const SizedBox(height: SdSpace.xxl),
                  const SdSectionLabel('Vehicle details'),
                  const SizedBox(height: SdSpace.md),
                  _Rows(vehicleRows(card)),
                ],
                // Locked cards: the photos are locked too, and follow the card.
                if (!card.ownedByViewer && !card.hiddenUnlocked)
                  ModelPhotosStrip(
                    cardId: card.id,
                    modelName: card.displayName,
                    onUnlock: _unlocking ? null : () => _unlock(card),
                  ),
                if (card.about case final about?) ...[
                  const SizedBox(height: SdSpace.xxl),
                  const SdSectionLabel('About'),
                  const SizedBox(height: SdSpace.md),
                  _About(about: about),
                ],
                // Spotters share their own catches, not other people's.
                if (card.ownedByViewer) ...[
                  const SizedBox(height: SdSpace.xxl),
                  ShareCardButton(boundary: _shareKey, card: card),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A detail line: label, value and an optional value colour.
typedef DetailRow = (String, String, Color?);

/// Everything recorded about this catch. Rows without a value are left out.
List<DetailRow> captureRows(CarCard card) {
  final c = card.capture;
  return [
    ('Captured', SdFormat.dateTime(card.capturedAt), null),
    if (c?.addedAt case final at?) ('Added to Garage', SdFormat.dateTime(at), null),
    if (card.locationLabel case final v?) ('Location', v, null),
    if (c?.color case final v?) ('Colour', v, null),
    if (card.conditionRating case final v?) ('Condition', '${v.toStringAsFixed(1)} / 10', null),
    if (c?.aiConfidence case final v?) ('AI match', '${(v * 100).round()}%', null),
    ('XP value', '${SdFormat.number(card.xp)} XP', SdColors.gold),
    ('Serial', card.serial, null),
  ];
}

/// Every catalogue figure there is for this vehicle, in metric units as in
/// the source. Figures the catalogue lacks are left out, never shown as 0.
List<DetailRow> vehicleRows(CarCard card) {
  final s = card.specs;
  final h = card.hidden;
  final n = SdFormat.number;
  String mm(int v) => '${n(v)} mm';
  return [
    ('Vehicle', _vehicleName(card), null),
    if (h?.manufacturer case final v?) ('Manufacturer', v, null),
    if (h?.parentCompany case final v?) ('Parent company', v, null),
    if (card.origin.isNotEmpty) ('Origin', card.origin, null),
    if (card.category.isNotEmpty) ('Category', card.category, null),
    ('Rarity', card.tier.label, card.tier.color),
    if (card.yearLabel.isNotEmpty) ('Production', card.yearLabel, null),
    if (h?.productionStatus case final v?) ('Status', v, null),
    if (s.fuelType case final v?) ('Fuel', v, null),
    if (s.engine case final v?) ('Engine', v, null),
    if (s.displacementCc case final v?) ('Displacement', '${n(v)} cc', null),
    if (h?.cylinders case final v?) ('Cylinders', '$v', null),
    if (h?.induction case final v?) ('Induction', v, null),
    if (s.horsepower case final v?) ('Power', '${n(v)} hp', null),
    if (h?.torqueNm case final v?) ('Torque', '${n(v)} Nm', null),
    if (s.zeroToSixtySeconds case final v?) ('0–60 mph', '${v}s', null),
    if (s.topSpeedMph case final v?) ('Top speed', '$v mph', null),
    if (h?.transmission case final v?) ('Gearbox', v, null),
    if (h?.drivetrain case final v?) ('Drive', v, null),
    if (h?.lengthMm case final v?) ('Length', mm(v), null),
    if (h?.widthMm case final v?) ('Width', mm(v), null),
    if (h?.heightMm case final v?) ('Height', mm(v), null),
    if (h?.wheelbaseMm case final v?) ('Wheelbase', mm(v), null),
    if (h?.curbWeightKg case final v?) ('Kerb weight', '${n(v)} kg', null),
    if (h?.doors case final v?) ('Doors', '$v', null),
    if (h?.seating case final v?) ('Seats', '$v', null),
    if (h?.batteryKwh case final v?) ('Battery', '${v.toStringAsFixed(1)} kWh', null),
    if (h?.evRangeMiles case final v?) ('Range', '${n(v)} mi', null),
  ];
}

class _Rows extends StatelessWidget {
  const _Rows(this.rows);
  final List<DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    return SdPanel(
      child: Column(
        children: [
          for (final (i, (label, value, color)) in rows.indexed)
            _Row(label, value, valueColor: color, last: i == rows.length - 1),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.valueColor, this.last = false});
  final String label;
  final String value;
  final Color? valueColor;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: SdSpace.md),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: SdColors.line)),
      ),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: SdType.label.copyWith(fontSize: 11)),
          const SizedBox(width: SdSpace.lg),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: SdType.data.copyWith(fontSize: 13, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Model summary from the catalogue source, with the attribution its licence
/// requires (Wikipedia text is CC BY-SA 4.0). Rendered as plain text.
class _About extends StatelessWidget {
  const _About({required this.about});
  final CarAbout about;

  @override
  Widget build(BuildContext context) {
    final source = about.sourceUrl == null ? null : Uri.tryParse(about.sourceUrl!);
    final fromWikipedia = source?.host.endsWith('wikipedia.org') ?? false;
    return SdPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(about.summary, style: SdType.body.copyWith(color: SdColors.textMuted, height: 1.55)),
          if (source != null) ...[
            const SizedBox(height: SdSpace.md),
            Text(
              [
                fromWikipedia ? 'Text: Wikipedia contributors' : 'Source: ${source.host}',
                ?about.license,
              ].join(' · '),
              style: SdType.caption.copyWith(fontSize: 11),
            ),
            SelectableText(
              source.toString(),
              style: SdType.caption.copyWith(fontSize: 11, color: SdColors.textFaint),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Make Model Variant", without repeating a variant that only restates the
/// make and model (some catalogue rows name the variant that way).
String _vehicleName(CarCard card) {
  final base = '${card.make} ${card.model}';
  final v = card.variant?.trim();
  if (v == null ||
      v.isEmpty ||
      v.toLowerCase() == base.toLowerCase() ||
      v.toLowerCase() == card.model.toLowerCase()) {
    return base;
  }
  return '$base $v';
}
