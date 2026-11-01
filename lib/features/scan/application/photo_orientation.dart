import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// How the phone was held when the shutter fired, from gravity on the
/// accelerometer (Android axes: +x to the right edge, +y to the top edge).
enum HeldAs {
  portrait,

  /// Top edge to the left (rotated a quarter turn counter-clockwise).
  landscapeLeft,

  /// Top edge to the right (rotated a quarter turn clockwise).
  landscapeRight,
}

/// Reads [HeldAs] from an accelerometer sample. Lying flat or nearly so
/// counts as portrait: there's no "up" to correct for.
HeldAs heldAs(double x, double y) {
  if (x.abs() < 4 || x.abs() < y.abs()) return HeldAs.portrait;
  return x > 0 ? HeldAs.landscapeLeft : HeldAs.landscapeRight;
}

/// Turns a camera JPEG upright and strips its metadata (EXIF can carry GPS
/// and device details we never send).
///
/// The app UI is locked to portrait, so a photo taken with the phone sideways
/// is still saved portrait, with the scene on its side. When [held] says
/// landscape and the image is still portrait, it is rotated to match. An
/// image that is already landscape (a camera that handled it) is left alone.
/// Pure and synchronous so it can run in a background isolate.
Uint8List uprightJpeg(Uint8List jpeg, HeldAs held, {int maxEdge = 1920}) {
  final decoded = img.decodeJpg(jpeg);
  if (decoded == null) return jpeg; // not ours to fix; the server validates
  var image = img.bakeOrientation(decoded);
  if (held != HeldAs.portrait && image.height > image.width) {
    // Top edge left: the scene's "up" is the image's right edge, so turn
    // the image counter-clockwise. Top edge right: clockwise.
    image = img.copyRotate(image, angle: held == HeldAs.landscapeLeft ? 270 : 90);
  }
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > maxEdge) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxEdge)
        : img.copyResize(image, height: maxEdge);
  }
  image.exif = img.ExifData();
  return img.encodeJpg(image, quality: 90);
}

/// [uprightJpeg] on a background isolate. Top-level on purpose: a closure
/// made inside a widget method would capture the widget state (camera and
/// all), which can't be sent to another isolate.
Future<Uint8List> uprightJpegInBackground(Uint8List jpeg, HeldAs held) =>
    Isolate.run(() => uprightJpeg(jpeg, held));

/// [uprightJpeg], done by the platform's native image code: much faster
/// than decoding and re-encoding a full photo in Dart. Applies the camera's
/// EXIF orientation, drops all metadata, keeps the shorter side at most
/// 1080 px, and turns a sideways shot upright. Falls back to [uprightJpeg]
/// if the native encoder fails or isn't available (tests).
Future<Uint8List> uprightJpegFast(Uint8List jpeg, HeldAs held) async {
  try {
    var out = await _native(jpeg, rotate: 0, exif: true);
    if (held != HeldAs.portrait) {
      final (w, h) = await _sizeOf(out);
      // Still portrait though the phone was sideways: turn it, as uprightJpeg does.
      if (h > w) {
        out = await _native(out, rotate: held == HeldAs.landscapeLeft ? 270 : 90, exif: false);
      }
    }
    return out;
  } catch (_) {
    return uprightJpegInBackground(jpeg, held);
  }
}

Future<Uint8List> _native(Uint8List jpeg, {required int rotate, required bool exif}) =>
    FlutterImageCompress.compressWithList(
      jpeg,
      // The shorter side is scaled down to 1080 px if larger; never up.
      minWidth: 1080,
      minHeight: 1080,
      quality: 90,
      rotate: rotate,
      autoCorrectionAngle: exif,
      keepExif: false,
    );

/// Width and height from the image header, without decoding the pixels.
Future<(int, int)> _sizeOf(Uint8List jpeg) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(jpeg);
  final d = await ui.ImageDescriptor.encoded(buffer);
  final size = (d.width, d.height);
  d.dispose();
  buffer.dispose();
  return size;
}
