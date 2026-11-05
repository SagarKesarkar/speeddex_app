// Renders the scan animation as overlay frames for social videos: the app's
// gold corner brackets with its scan line sweeping the frame, on a
// transparent background, plus a green-screen copy and a small GIF.
//
//   dart run tool/scan_overlay.dart <output dir>
//
// Writes <out>/png/frame_0000.png … (1080x1920, transparent, 30 fps),
// <out>/green/frame_0000.png … (the same on #00FF00) and
// <out>/speeddex-scan.gif (540x960, 15 fps, transparent). The loop is
// seamless, so it can be repeated for as long as a shot needs.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const w = 1080, h = 1920;
const fps = 30;

/// One sweep down and back up, as in the app (1.6 s each way).
const loopFrames = 96;

// SdColors.gold.
const gold = (0xD9, 0xB9, 0x70);

// The frame: landscape, centred, sized for a car filling a portrait shot.
const boxW = 960, boxH = 640;
const boxL = (w - boxW) ~/ 2, boxT = (h - boxH) ~/ 2;
const corner = 96, stroke = 8;

/// Straight-alpha RGBA canvas with "over" blending.
class Canvas {
  final px = Uint8List(w * h * 4);

  void blend(int x, int y, (int, int, int) c, double a) {
    if (x < 0 || y < 0 || x >= w || y >= h || a <= 0) return;
    final i = (y * w + x) * 4;
    final da = px[i + 3] / 255;
    final oa = a + da * (1 - a);
    if (oa <= 0) return;
    for (final (k, v) in [(0, c.$1), (1, c.$2), (2, c.$3)]) {
      px[i + k] = ((v * a + px[i + k] * da * (1 - a)) / oa).round().clamp(0, 255);
    }
    px[i + 3] = (oa * 255).round().clamp(0, 255);
  }

  void rect(int l, int t, int rw, int rh, (int, int, int) c, double a) {
    for (var y = t; y < t + rh; y++) {
      for (var x = l; x < l + rw; x++) {
        blend(x, y, c, a);
      }
    }
  }

  img.Image toImage() => img.Image.fromBytes(width: w, height: h, bytes: px.buffer, numChannels: 4);
}

double easeInOut(double t) => t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

img.Image frame(int f) {
  final c = Canvas();
  final t = f / loopFrames; // 0..1 over the loop

  // The scan line: down in the first half, back up in the second.
  final leg = t < 0.5 ? t * 2 : 2 - t * 2;
  final lineY = boxT + (easeInOut(leg) * boxH).round();
  const band = 150; // glow above and below the line
  for (var y = lineY - band; y <= lineY + band; y++) {
    if (y < boxT || y > boxT + boxH) continue;
    final d = (y - lineY).abs() / band;
    final a = 0.30 * math.pow(1 - d, 2);
    c.rect(boxL, y, boxW, 1, gold, a.toDouble());
  }
  c.rect(boxL, lineY - 2, boxW, 5, gold, 0.95);

  // Corner brackets, breathing gently twice a loop.
  final pulse = 0.80 + 0.20 * (0.5 + 0.5 * math.cos(t * 4 * math.pi));
  void bracket(int x, int y, int dx, int dy) {
    // Horizontal and vertical arms, [stroke] thick, from the corner inwards.
    final hx = dx > 0 ? x : x - corner + 1;
    final hy = dy > 0 ? y : y - stroke + 1;
    final vx = dx > 0 ? x : x - stroke + 1;
    final vy = dy > 0 ? y : y - corner + 1;
    c.rect(hx, hy, corner, stroke, gold, pulse);
    c.rect(vx, vy, stroke, corner, gold, pulse);
  }

  bracket(boxL, boxT, 1, 1);
  bracket(boxL + boxW - 1, boxT, -1, 1);
  bracket(boxL, boxT + boxH - 1, 1, -1);
  bracket(boxL + boxW - 1, boxT + boxH - 1, -1, -1);

  // A small centre crosshair.
  const cx = w ~/ 2, cy = h ~/ 2, arm = 22;
  c.rect(cx - arm, cy - 1, arm * 2, 3, gold, 0.55 * pulse);
  c.rect(cx - 1, cy - arm, 3, arm * 2, gold, 0.55 * pulse);
  return c.toImage();
}

/// [im] flattened onto chroma-key green.
img.Image onGreen(img.Image im) {
  final out = img.Image(width: im.width, height: im.height);
  img.fill(out, color: img.ColorRgb8(0, 255, 0));
  img.compositeImage(out, im);
  return out;
}

/// [im] at half size with a two-colour palette, transparent and gold. GIF
/// transparency is all-or-nothing, so the faint glow is left out; the
/// encoder's own colour reduction would lose the transparency altogether.
img.Image gifFrame(img.Image im) {
  final small = img.copyResize(
    im,
    width: w ~/ 2,
    height: h ~/ 2,
    interpolation: img.Interpolation.average,
  );
  final out =
      img.Image(
          width: small.width,
          height: small.height,
          numChannels: 1,
          palette: img.PaletteUint8(2, 4),
        )
        ..palette!.setRgba(0, 0, 0, 0, 0)
        ..palette!.setRgba(1, gold.$1, gold.$2, gold.$3, 255);
  for (final p in small) {
    out.getPixel(p.x, p.y).index = p.a >= 110 ? 1 : 0;
  }
  return out;
}

Future<void> main(List<String> args) async {
  final out = args.isEmpty ? 'build/scan_overlay' : args.first;
  for (final d in ['png', 'green']) {
    Directory('$out/$d').createSync(recursive: true);
  }
  final gif = img.GifEncoder(repeat: 0, samplingFactor: 1);
  for (var f = 0; f < loopFrames; f++) {
    final im = frame(f);
    final name = 'frame_${f.toString().padLeft(4, '0')}.png';
    File('$out/png/$name').writeAsBytesSync(img.encodePng(im, level: 6));
    File('$out/green/$name').writeAsBytesSync(img.encodePng(onGreen(im), level: 6));
    if (f.isEven) {
      gif.addFrame(gifFrame(im), duration: 7); // hundredths of a second, about 15 fps
    }
    stdout.write('\r$f/$loopFrames');
  }
  File('$out/speeddex-scan.gif').writeAsBytesSync(gif.finish()!);
  stdout.writeln('\nwrote $out');
}
