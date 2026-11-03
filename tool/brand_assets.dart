// Generates every logo and icon file from the master logo.
//
//   dart run tool/brand_assets.dart [path/to/logo.png] [--inspect]
//
// The master (default ../reference/logo.png) is the full lockup: gauge, car
// silhouette, SPEEDDEX wordmark and tagline, on a transparent square, drawn
// for dark backgrounds. Run again whenever the logo changes.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// The app's background (SdColors.ink): icons sit on it, as the logo is
/// drawn for dark backgrounds.
final ink = img.ColorRgba8(0x0B, 0x0C, 0x0F, 0xFF);

/// The bounding box of everything visible (alpha above [threshold]).
({int x, int y, int w, int h}) visibleBox(img.Image im, {int threshold = 24}) {
  var minX = im.width, minY = im.height, maxX = -1, maxY = -1;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      if (im.getPixel(x, y).a > threshold) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  return (x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1);
}

/// How much is visible in each row of [im] (for finding the tagline band).
List<int> rowCoverage(img.Image im, {int threshold = 24}) => [
  for (var y = 0; y < im.height; y++)
    [for (var x = 0; x < im.width; x++) im.getPixel(x, y).a > threshold ? 1 : 0]
        .fold(0, (a, b) => a + b),
];

img.Image resizeTo(img.Image src, int width) =>
    img.copyResize(src, width: width, interpolation: img.Interpolation.cubic);

/// [art] scaled to fit [box] of a [size] square, centred, on [bg] (null: transparent).
img.Image placed(img.Image art, int size, double box, {img.Color? bg}) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  if (bg != null) img.fill(canvas, color: bg);
  final scale = math.min(size * box / art.width, size * box / art.height);
  final w = math.max(1, (art.width * scale).round());
  final h = math.max(1, (art.height * scale).round());
  final small = img.copyResize(art, width: w, height: h, interpolation: img.Interpolation.cubic);
  img.compositeImage(canvas, small, dstX: (size - w) ~/ 2, dstY: (size - h) ~/ 2);
  return canvas;
}

void writePng(String path, img.Image im) {
  File(path).parent.createSync(recursive: true);
  File(path).writeAsBytesSync(img.encodePng(im, level: 9));
  stdout.writeln('  $path  ${im.width}x${im.height}');
}

Future<void> main(List<String> args) async {
  final source = args.firstWhere((a) => !a.startsWith('--'), orElse: () => '../reference/logo.png');
  final master = img.decodePng(File(source).readAsBytesSync())!;
  final box = visibleBox(master);
  stdout.writeln('master ${master.width}x${master.height}, visible box $box');
  final full = img.copyCrop(master, x: box.x, y: box.y, width: box.w, height: box.h);
  if (args.contains('--inspect')) {
    final preview = resizeTo(full, 900);
    final dark = img.Image(width: preview.width, height: preview.height, numChannels: 4);
    img.fill(dark, color: ink);
    img.compositeImage(dark, preview);
    writePng('build/brand_preview.png', dark);
    final cov = rowCoverage(resizeTo(full, 400));
    stdout.writeln('row coverage (400 wide): ${cov.join(',')}');
    return;
  }

  // ---- the lockup, cropped to its edges with a little air, for headers
  final pad = (full.width * 0.015).round();
  final lockup = img.Image(
    width: full.width + pad * 2,
    height: full.height + pad * 2,
    numChannels: 4,
  );
  img.compositeImage(lockup, full, dstX: pad, dstY: pad);

  stdout.writeln('App (Flutter):');
  writePng('assets/brand/logo.png', resizeTo(lockup, 1000));

  // ---- square icon: the lockup on the app's dark background
  img.Image icon(int size, double box) => placed(lockup, size, box, bg: ink);

  // Android legacy launcher icons (pre-8.0 and launchers without masks).
  stdout.writeln('Android:');
  const densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
  const res = 'android/app/src/main/res';
  for (final MapEntry(key: d, value: f) in densities.entries) {
    writePng('$res/mipmap-$d/ic_launcher.png', icon((48 * f).round(), 0.86));
    // Adaptive icon foreground: 108 dp, of which only the centre 66 dp circle
    // is sure to show. A 2.6:1 logo fits that circle at about 57% width.
    writePng('$res/mipmap-$d/ic_launcher_foreground.png', placed(lockup, (108 * f).round(), 0.57));
    // Themed icon (Android 13+): one colour, tinted by the system.
    final mono = placed(lockup, (108 * f).round(), 0.57);
    for (final p in mono) {
      p
        ..r = 255
        ..g = 255
        ..b = 255;
    }
    writePng('$res/mipmap-$d/ic_launcher_monochrome.png', mono);
  }
  // Start-up screen before Flutter draws (Android before 12): the logo,
  // 280 dp wide, on the app's dark background (launch_background.xml).
  for (final MapEntry(key: d, value: f) in densities.entries) {
    writePng('$res/drawable-$d/launch_logo.png', resizeTo(lockup, (280 * f).round()));
  }

  // iOS: square, no transparency (the system rounds the corners).
  stdout.writeln('iOS:');
  const iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final contents = File('$iosDir/Contents.json').readAsStringSync();
  final names = RegExp(r'"filename"\s*:\s*"([^"]+)"')
      .allMatches(contents)
      .map((m) => m.group(1)!)
      .toSet();
  for (final name in names) {
    final m = RegExp(r'(\d+(?:\.\d+)?)x\d+(?:\.\d+)?@(\d)x').firstMatch(name);
    if (m == null) continue;
    final px = (double.parse(m.group(1)!) * int.parse(m.group(2)!)).round();
    final out = icon(px, 0.84);
    writePng('$iosDir/$name', out.convert(numChannels: 3));
  }

  // Google Play listing icon, 512 x 512.
  stdout.writeln('Store:');
  writePng('../StoreAssets/play-icon-512.png', icon(512, 0.86));

  // Website and admin panel: favicons and the header logo.
  stdout.writeln('Website and admin panel:');
  // The legal pages are deployed on their own (also under the API), so they
  // carry their own copies in assets/.
  for (final dir in ['../Website/landing/img', '../Website/assets', '../Web/public']) {
    writePng('$dir/favicon-32.png', icon(32, 0.94));
    writePng('$dir/favicon-192.png', icon(192, 0.9));
    writePng('$dir/apple-touch-icon.png', icon(180, 0.86).convert(numChannels: 3));
    // Shown at most about 140 px wide: 400 px is sharp on high-density screens.
    writePng('$dir/logo.png', resizeTo(lockup, 400));
  }
}
