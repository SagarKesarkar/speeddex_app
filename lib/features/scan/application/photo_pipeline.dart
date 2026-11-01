import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'photo_orientation.dart';
import 'privacy_blur.dart';

/// Turns the camera's photo into the one that may be sent: upright,
/// metadata stripped, compressed, with faces and number plates blurred.
///
/// This is slow (on-device detection plus re-encoding), so it runs when the
/// player taps Identify rather than when they take the shot.
abstract interface class PhotoPreparer {
  /// Returns the path of the prepared photo and deletes the original. Throws
  /// if the privacy check can't run; the photo must then not be sent.
  Future<String> prepare(String rawPath, HeldAs held);
}

class DevicePhotoPreparer implements PhotoPreparer {
  PrivacyScanner? _privacy;

  @override
  Future<String> prepare(String rawPath, HeldAs held) async {
    final raw = await File(rawPath).readAsBytes();
    // Upright, metadata stripped and sized, by the platform's image code.
    final upright = await uprightJpegFast(raw, held);
    final out = File('$rawPath-ready.jpg');
    await out.writeAsBytes(upright, flush: true);
    final image = await decodeImage(upright);
    try {
      final boxes = await (_privacy ??= PrivacyScanner()).find(out.path, image);
      if (boxes.isNotEmpty) {
        final blurred = await blurredImage(image, boxes);
        try {
          await out.writeAsBytes(await encodeJpeg(blurred), flush: true);
        } finally {
          blurred.dispose();
        }
      }
    } catch (_) {
      unawaited(out.delete().catchError((_) => out));
      rethrow;
    } finally {
      image.dispose();
    }
    unawaited(File(rawPath).delete().catchError((_) => File(rawPath)));
    return out.path;
  }

  Future<void> close() async => _privacy?.close();
}

/// Without a server (built-in demo data) there's nothing to protect the photo
/// from, and tests can't run the on-device detectors: the photo is used as is.
class PassThroughPhotoPreparer implements PhotoPreparer {
  const PassThroughPhotoPreparer();

  @override
  Future<String> prepare(String rawPath, HeldAs held) async => rawPath;
}

final photoPreparerProvider = Provider<PhotoPreparer>((ref) {
  if (ref.watch(appConfigProvider).usesDevData) return const PassThroughPhotoPreparer();
  final p = DevicePhotoPreparer();
  ref.onDispose(p.close);
  return p;
});
