import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/widgets/sd_button.dart';
import '../../../core/widgets/sd_states.dart';
import '../../../domain/car_card.dart';

/// The words that go with a shared card. No location, serial or owner data:
/// the image already shows what the spotter chose to share.
String shareTextFor(CarCard card) =>
    'I just caught a ${card.make} ${card.model} (${card.tier.label} tier) on SpeedDex! 🏁';

/// Renders the card under [boundary] to a PNG and opens the system share
/// sheet, which lists WhatsApp, Instagram, Facebook and any other app that
/// accepts images. Returns false if the card couldn't be captured.
Future<bool> shareCard(BuildContext context, GlobalKey boundary, CarCard card) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  final render = boundary.currentContext?.findRenderObject();
  if (render is! RenderRepaintBoundary) return false;

  final image = await render.toImage(pixelRatio: 3);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (png == null) return false;

  final file = File('${Directory.systemTemp.path}/speeddex-card-${card.id}.png');
  await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: shareTextFor(card),
      subject: '${card.make} ${card.model} · SpeedDex',
      sharePositionOrigin: origin, // anchors the sheet on iPad
    ),
  );
  return true;
}

/// "Share" button that captures [boundary] when tapped.
class ShareCardButton extends StatefulWidget {
  const ShareCardButton({super.key, required this.boundary, required this.card});
  final GlobalKey boundary;
  final CarCard card;

  @override
  State<ShareCardButton> createState() => _ShareCardButtonState();
}

class _ShareCardButtonState extends State<ShareCardButton> {
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final ok = await shareCard(context, widget.boundary, widget.card);
      if (!ok && mounted) _snack();
    } catch (_) {
      if (mounted) _snack();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack() => showSdSnack(context, 'Couldn’t share this card. Try again.');

  @override
  Widget build(BuildContext context) {
    return SdButton(
      label: 'Share card',
      icon: Icons.share_rounded,
      variant: SdButtonVariant.gold,
      loading: _busy,
      onPressed: _share,
    );
  }
}
