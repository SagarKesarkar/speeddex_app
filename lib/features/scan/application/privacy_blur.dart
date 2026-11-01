import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Rect;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// A region of a photo to hide, in image pixels.
typedef Box = ({int x, int y, int w, int h});

/// A word the text recogniser read, with where it sits.
typedef OcrWord = ({String text, Rect box});

/// One line of recognised text, as its words in reading order.
typedef OcrLine = List<OcrWord>;

/// True for text that reads like a number plate: 5–11 letters and digits
/// with at least two digits and one letter once spaces and dashes are
/// dropped ("MH 12 AB 1234", "AB-123-CD", "KA01MJ2024"). Errs towards
/// blurring: an occasional badge such as "TURBO 20" is hidden too.
bool looksLikePlate(String text) {
  final t = _alnum(text);
  if (t.length < 5 || t.length > 11) return false;
  final digits = t.replaceAll(RegExp('[^0-9]'), '').length;
  return digits >= 2 && digits < t.length;
}

/// The number block of a plate read on its own ("8525", "0080"): 3–4
/// digits, optionally after one or two letters. OCR often reads only this
/// part of a small or partly hidden plate; it is what identifies the car, so
/// it is blurred even alone. A stray year or price gets blurred too.
bool looksLikePlateNumber(String text) => RegExp(r'^[A-Z]{0,2}[0-9]{3,4}$').hasMatch(_alnum(text));

String _alnum(String s) => s.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

/// Where number plates are among recognised [lines]. Pure, for testing.
///
/// A plate rarely arrives as a tidy line of its own, so this looks for:
/// - any run of up to six consecutive words on a line that reads like a
///   plate, so neighbouring text ("IND", a dealer's name, a misread
///   border) doesn't hide it;
/// - two short lines stacked closely, for two-row plates ("PB02" over "4785");
/// - a plate's number block read on its own ([looksLikePlateNumber]).
List<Rect> plateRects(List<OcrLine> lines) {
  final found = <Rect>[];
  for (final words in lines) {
    for (var i = 0; i < words.length; i++) {
      for (var j = i; j < words.length && j < i + 6; j++) {
        final run = words.sublist(i, j + 1);
        final joined = run.map((w) => w.text).join(' ');
        if (looksLikePlate(joined) || (i == j && looksLikePlateNumber(joined))) {
          found.add(_union(run.map((w) => w.box)));
          break; // the shortest match from here is enough; longer ones overlap it
        }
      }
    }
  }
  for (final top in lines) {
    for (final bottom in lines) {
      if (identical(top, bottom) || top.isEmpty || bottom.isEmpty) continue;
      final a = _union(top.map((w) => w.box));
      final b = _union(bottom.map((w) => w.box));
      final gap = b.top - a.bottom;
      final overlap = math.min(a.right, b.right) - math.max(a.left, b.left);
      final short =
          _alnum(top.map((w) => w.text).join()).length <= 6 &&
          _alnum(bottom.map((w) => w.text).join()).length <= 6;
      if (short &&
          gap > -a.height * 0.3 &&
          gap < math.max(a.height, b.height) * 0.8 &&
          overlap > math.min(a.width, b.width) * 0.5 &&
          looksLikePlate('${top.map((w) => w.text).join()} ${bottom.map((w) => w.text).join()}')) {
        found.add(a.expandToInclude(b));
      }
    }
  }
  return found;
}

Rect _union(Iterable<Rect> rects) => rects.reduce((a, b) => a.expandToInclude(b));

/// Finds faces and number plates on the device, so neither leaves the phone
/// unblurred. Uses Google ML Kit's bundled on-device models: the photo is
/// not sent anywhere to be checked.
///
/// Faces and text are looked for in the whole photo. Faces are also looked
/// for in four overlapping tiles: the detector scales each image to a fixed
/// working size, so in a tile a small face (someone in the background) is
/// effectively larger. Tiles are cut from the decoded image by the GPU and
/// handed over as raw pixels, so nothing is re-encoded.
class PrivacyScanner {
  final _faces = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate, minFaceSize: 0.02),
  );
  final _text = TextRecognizer(script: TextRecognitionScript.latin);

  /// Regions to blur in the upright JPEG at [path], decoded as [image].
  /// Throws if a detector fails; the caller must then not send the photo.
  Future<List<Box>> find(String path, ui.Image image) async {
    // ML Kit works on its own threads, so all checks run side by side; the
    // whole-photo check starts while the tiles are still being cut.
    final checks = [_check(InputImage.fromFilePath(path), dx: 0, dy: 0, text: true)];
    for (final t in tileRects(image.width, image.height)) {
      checks.add(_tileCheck(image, t));
    }
    return [for (final found in await Future.wait(checks)) ...found];
  }

  Future<List<Box>> _tileCheck(ui.Image image, TileRect t) async {
    final w = (t.w * t.scale).round();
    final h = (t.h * t.scale).round();
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH(t.x.toDouble(), t.y.toDouble(), t.w.toDouble(), t.h.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final tile = await recorder.endRecording().toImage(w, h);
    try {
      final pixels = await tile.toByteData(format: ui.ImageByteFormat.rawRgba);
      return await _check(
        InputImage.fromBitmap(bitmap: pixels!.buffer.asUint8List(), width: w, height: h),
        dx: t.x,
        dy: t.y,
        scale: t.scale,
        text: false,
      );
    } finally {
      tile.dispose();
    }
  }

  /// Runs the detectors on one image; maps results back to the photo.
  Future<List<Box>> _check(
    InputImage input, {
    required int dx,
    required int dy,
    double scale = 1,
    required bool text,
  }) async {
    final (faces, recognised) = await (
      _faces.processImage(input),
      text ? _text.processImage(input) : Future.value(null),
    ).wait;
    Rect back(Rect r) =>
        Rect.fromLTWH(dx + r.left / scale, dy + r.top / scale, r.width / scale, r.height / scale);
    final lines = [
      for (final b in recognised?.blocks ?? const <TextBlock>[])
        for (final l in b.lines)
          [for (final e in l.elements) (text: e.text, box: back(e.boundingBox))],
    ];
    return [
      // Faces: a little wider and taller than the detector's box, to cover
      // hair and chin.
      for (final f in faces) _pad(back(f.boundingBox), 0.25, 0.35),
      // Plates: the text sits inside the plate's border, so pad generously.
      for (final r in plateRects(lines)) _pad(r, 0.3, 0.6),
    ];
  }

  Future<void> close() async {
    await _faces.close();
    await _text.close();
  }

  static Box _pad(Rect r, double padX, double padY) {
    final dx = r.width * padX;
    final dy = r.height * padY;
    return (
      x: (r.left - dx).floor(),
      y: (r.top - dy).floor(),
      w: (r.width + 2 * dx).ceil(),
      h: (r.height + 2 * dy).ceil(),
    );
  }
}

/// A part of the photo for a second, closer look: where it sits, and how much
/// it is enlarged.
typedef TileRect = ({int x, int y, int w, int h, double scale});

/// Tiles smaller than this (longest side) are enlarged to it: detectors miss
/// faces only a few pixels wide however the photo is cropped.
const _minTileEdge = 1100;

/// Four overlapping tiles of a [width]×[height] photo, each 60% of its width
/// and height. The overlap is wide enough that a face on a seam is whole in
/// one tile. Tiles of a small photo are enlarged, up to 2×, to [_minTileEdge].
List<TileRect> tileRects(int width, int height) {
  final w = (width * 0.6).round();
  final h = (height * 0.6).round();
  final scale = (_minTileEdge / math.max(w, h)).clamp(1.0, 2.0);
  return [
    for (final (x, y) in [(0, 0), (width - w, 0), (0, height - h), (width - w, height - h)])
      (x: x, y: y, w: w, h: h, scale: scale),
  ];
}

/// How strongly faces are blurred: the blur radius as a fraction of the
/// region's shorter side. Enough that a face can't be recognised while the
/// photo still looks natural.
const faceBlur = 0.09;

/// The same for number plates. A plate's characters fill its height, so it
/// needs a stronger blur than a face of the same size to be unreadable.
const plateBlur = 0.15;

/// Draws [image] with [boxes] blurred so faces and plate characters can't be
/// made out: a soft Gaussian blur inside rounded shapes (near-oval for faces).
/// Wide regions are plates (padded plate boxes are 2–5× as wide as tall;
/// faces are taller than wide) and get [plateBlur]; others get [faceBlur].
/// Boxes are clipped to the image. Rendered by the GPU, not in Dart.
Future<ui.Image> blurredImage(ui.Image image, List<Box> boxes) {
  final bounds = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..drawImage(image, ui.Offset.zero, ui.Paint());
  for (final b in boxes) {
    final r = Rect.fromLTWH(
      b.x.toDouble(),
      b.y.toDouble(),
      b.w.toDouble(),
      b.h.toDouble(),
    ).intersect(bounds);
    if (r.width < 2 || r.height < 2) continue;
    final shortest = math.min(r.width, r.height);
    final plate = r.width >= 1.6 * r.height;
    // Same strength as the tuned Dart blur, whose radius was its sigma.
    final sigma = math.max(3.0, shortest * (plate ? plateBlur : faceBlur));
    final source = r.inflate(sigma * 3).intersect(bounds);
    canvas
      ..save()
      ..clipRRect(
        ui.RRect.fromRectAndRadius(r, ui.Radius.circular(shortest * (plate ? 0.25 : 0.45))),
      )
      ..saveLayer(
        source,
        ui.Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: ui.TileMode.clamp,
          ),
      )
      ..drawImageRect(image, source, source, ui.Paint())
      ..restore()
      ..restore();
  }
  return recorder.endRecording().toImage(image.width, image.height);
}

/// [image] as a JPEG (quality 90, no metadata). Encoded natively; falls back
/// to Dart if the native encoder fails or isn't available (tests).
Future<Uint8List> encodeJpeg(ui.Image image) async {
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  try {
    return await FlutterImageCompress.compressWithList(
      png!.buffer.asUint8List(),
      minWidth: image.width,
      minHeight: image.height,
      quality: 90,
      autoCorrectionAngle: false,
    );
  } catch (_) {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = image.width;
    final h = image.height;
    final bytes = rgba!.buffer.asUint8List();
    return Isolate.run(
      () => img.encodeJpg(
        img.Image.fromBytes(width: w, height: h, bytes: bytes.buffer, numChannels: 4),
        quality: 90,
      ),
    );
  }
}

/// Decodes [jpeg] with the platform's native decoder.
Future<ui.Image> decodeImage(Uint8List jpeg) async {
  final codec = await ui.instantiateImageCodec(jpeg);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}
