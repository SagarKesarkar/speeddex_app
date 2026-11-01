import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:speeddex/features/scan/application/privacy_blur.dart';

/// Sharp black-and-white stripes, so any blur shows up as lost contrast.
img.Image _stripes() {
  final p = img.Image(width: 200, height: 100);
  for (var x = 0; x < 200; x++) {
    final c = (x ~/ 2).isEven ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0);
    img.drawLine(p, x1: x, y1: 0, x2: x, y2: 99, color: c);
  }
  return p;
}

/// A line of OCR words laid out left to right from [x], [y], 20 px tall.
OcrLine _line(List<String> words, {double x = 0, double y = 0}) {
  final line = <OcrWord>[];
  var left = x;
  for (final w in words) {
    line.add((text: w, box: Rect.fromLTWH(left, y, w.length * 12.0, 20)));
    left += w.length * 12.0 + 8;
  }
  return line;
}

/// Brightness range across a row segment.
num _contrast(img.Image p, int y, int from, int to) {
  final values = [for (var x = from; x < to; x++) p.getPixel(x, y).r];
  return values.reduce((a, b) => a > b ? a : b) - values.reduce((a, b) => a < b ? a : b);
}

void main() {
  test('recognises number plates but not ordinary words', () {
    for (final plate in [
      'MH 12 AB 1234',
      'KA01MJ2024',
      'AB-123-CD',
      'DL 3C AY 5678',
      'B 1234 XYZ',
    ]) {
      expect(looksLikePlate(plate), isTrue, reason: plate);
    }
    for (final other in ['SpeedDex', 'AMG', 'GT3', 'Volkswagen', '2024', '12345678', 'HYBRID']) {
      expect(looksLikePlate(other), isFalse, reason: other);
    }
  });

  test('finds a plate inside a line with other text, like the "IND" strip', () {
    // The failing photo: OCR read the plate together with the small "IND" mark.
    final rects = plateRects([
      _line(['IND', 'KL', '20', 'U', '0080'], y: 100),
    ]);
    expect(rects, isNotEmpty);
    // The blur covers the number itself, not just the "IND" mark.
    expect(
      rects.any((r) => r.right >= _line(['IND', 'KL', '20', 'U', '0080']).last.box.right),
      isTrue,
    );
  });

  test('finds two-row plates and a number block read alone', () {
    final twoRow = plateRects([
      _line(['PB02'], x: 100, y: 100),
      _line(['4785'], x: 100, y: 124),
    ]);
    expect(twoRow.any((r) => r.top <= 100 && r.bottom >= 144), isTrue, reason: 'both rows covered');

    expect(
      plateRects([
        _line(['8525']),
      ]),
      isNotEmpty,
    );
    expect(
      plateRects([
        _line(['L', '8525']),
      ]),
      isNotEmpty,
    );
  });

  test('leaves ordinary text alone', () {
    expect(
      plateRects([
        _line(['POPULAR', 'HOTEL']),
      ]),
      isEmpty,
    );
    expect(
      plateRects([
        _line(['Computerised', 'No.', 'Plates']),
      ]),
      isEmpty,
    );
    // Lines far apart are not one plate.
    expect(
      plateRects([
        _line(['AB'], y: 0),
        _line(['CD'], y: 400),
      ]),
      isEmpty,
    );
  });

  test('cuts four overlapping tiles, enlarging those of a small photo', () {
    final big = tileRects(1920, 1080);
    expect(big, hasLength(4));
    expect(big.first, (x: 0, y: 0, w: 1152, h: 648, scale: 1.0));
    expect(big.last, (x: 768, y: 432, w: 1152, h: 648, scale: 1.0));
    // A 600 px photo: tiles are doubled so small faces stay findable.
    expect(tileRects(600, 360).first.scale, 2.0);
  });

  // Rendering needs the engine's image pipeline, so these run with runAsync.
  testWidgets('blurs only the given regions, beyond recognition', (tester) async {
    await tester.runAsync(() async {
      final image = await decodeImage(img.encodeJpg(_stripes(), quality: 100));
      final blurred = await blurredImage(image, [(x: 20, y: 20, w: 80, h: 60)]);
      final out = img.decodeJpg(await encodeJpeg(blurred))!;
      expect((out.width, out.height), (200, 100));
      expect(_contrast(out, 50, 45, 75), lessThan(80), reason: 'stripes inside are smeared');
      expect(_contrast(out, 50, 140, 180), greaterThan(200), reason: 'outside is untouched');
    });
  });

  testWidgets('clips regions that run off the photo and skips empty ones', (tester) async {
    await tester.runAsync(() async {
      final image = await decodeImage(img.encodeJpg(_stripes()));
      final blurred = await blurredImage(image, [
        (x: 180, y: -10, w: 60, h: 40),
        (x: 500, y: 500, w: 10, h: 10),
      ]);
      expect((blurred.width, blurred.height), (200, 100));
    });
  });
}
