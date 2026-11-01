import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:speeddex/features/scan/application/photo_orientation.dart';

/// A portrait test photo whose top row is red and bottom row is blue, as the
/// camera saves it when the phone is held sideways.
img.Image _portrait() {
  final p = img.Image(width: 40, height: 80);
  img.fill(p, color: img.ColorRgb8(128, 128, 128));
  img.fillRect(p, x1: 0, y1: 0, x2: 39, y2: 9, color: img.ColorRgb8(255, 0, 0));
  img.fillRect(p, x1: 0, y1: 70, x2: 39, y2: 79, color: img.ColorRgb8(0, 0, 255));
  return p;
}

bool _red(img.Pixel p) => p.r > 180 && p.b < 90;

void main() {
  test('reads how the phone was held from gravity', () {
    expect(heldAs(0, 9.8), HeldAs.portrait);
    expect(heldAs(9.6, 1), HeldAs.landscapeLeft);
    expect(heldAs(-9.6, 1), HeldAs.landscapeRight);
    expect(heldAs(1, 0.5), HeldAs.portrait); // flat on a table
  });

  test('turns a sideways shot upright', () {
    final jpeg = img.encodeJpg(_portrait());
    // Top edge left: the photo's top (red) is the scene's left side.
    final left = img.decodeJpg(uprightJpeg(jpeg, HeldAs.landscapeLeft))!;
    expect(left.width > left.height, isTrue);
    expect(_red(left.getPixel(2, left.height ~/ 2)), isTrue, reason: 'red now on the left');

    final right = img.decodeJpg(uprightJpeg(jpeg, HeldAs.landscapeRight))!;
    expect(right.width > right.height, isTrue);
    expect(_red(right.getPixel(right.width - 3, right.height ~/ 2)), isTrue);
  });

  test('leaves portrait and already-landscape photos alone, and strips metadata', () {
    final portrait = _portrait()..exif.imageIfd['Make'] = img.IfdValueAscii('PhoneCo');
    final same = img.decodeJpg(uprightJpeg(img.encodeJpg(portrait), HeldAs.portrait))!;
    expect((same.width, same.height), (40, 80));
    expect(same.exif.imageIfd['Make'], isNull);

    final wide = img.Image(width: 80, height: 40);
    final kept = img.decodeJpg(uprightJpeg(img.encodeJpg(wide), HeldAs.landscapeLeft))!;
    expect((kept.width, kept.height), (80, 40));
  });

  test('caps the longest edge', () {
    final big = img.Image(width: 3000, height: 1500);
    final out = img.decodeJpg(uprightJpeg(img.encodeJpg(big), HeldAs.portrait))!;
    expect((out.width, out.height), (1600, 800));
  });
}
