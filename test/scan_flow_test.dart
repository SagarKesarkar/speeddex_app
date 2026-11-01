import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speeddex/app/providers.dart';
import 'package:speeddex/core/errors/app_failure.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/features/scan/application/photo_orientation.dart';
import 'package:speeddex/features/scan/application/photo_pipeline.dart';
import 'package:speeddex/features/scan/application/scan_controller.dart';

/// Records what it prepared; fails while [failing] is set.
class _Preparer implements PhotoPreparer {
  final calls = <(String, HeldAs)>[];
  bool failing = false;

  @override
  Future<String> prepare(String rawPath, HeldAs held) async {
    calls.add((rawPath, held));
    if (failing) throw StateError('detector unavailable');
    return '$rawPath-ready';
  }

  @override
  Future<Uint8List?> thumbnail(Uint8List prepared) async => Uint8List.fromList([7, 7, 7]);
}

/// Records which local photos were sent.
class _Captures implements CaptureRepository {
  final sent = <String>[];
  final thumbnails = <Uint8List?>[];

  @override
  Future<IdentifyOutcome> identify(
    Uint8List jpegBytes, {
    required String localPath,
    Uint8List? thumbnail,
  }) async {
    sent.add(localPath);
    thumbnails.add(thumbnail);
    return const Rejected('Not a car');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late Directory dir;
  late _Preparer preparer;
  late _Captures captures;
  late ProviderContainer c;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sdx-scan');
    preparer = _Preparer();
    captures = _Captures();
    c = ProviderContainer(
      overrides: [
        photoPreparerProvider.overrideWithValue(preparer),
        captureRepositoryProvider.overrideWithValue(captures),
      ],
    );
  });
  tearDown(() async {
    c.dispose();
    await dir.delete(recursive: true);
  });

  Future<String> shot() async {
    final raw = File('${dir.path}/shot.jpg');
    await raw.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
    // What the preparer would produce.
    await File('${raw.path}-ready').writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
    return raw.path;
  }

  test('the shutter only shows the photo; Identify blurs it, then sends the result', () async {
    final scan = c.read(scanControllerProvider.notifier);
    final raw = await shot();
    scan.captured(raw, held: HeldAs.landscapeLeft);
    expect(c.read(scanControllerProvider), isA<ScanPreview>());
    expect(preparer.calls, isEmpty); // nothing processed before Identify

    final seen = <ScanState>[];
    c.listen(scanControllerProvider, (_, s) => seen.add(s));
    await scan.identify();
    expect(seen.first, isA<ScanPreparing>());
    expect(seen[1], isA<ScanIdentifying>());
    expect(preparer.calls, [(raw, HeldAs.landscapeLeft)]);
    expect(captures.sent, ['$raw-ready']); // never the original
    expect(captures.thumbnails.single, [7, 7, 7]); // the small copy goes with it
  });

  test('if the privacy check fails nothing is sent, and trying again prepares it again', () async {
    final scan = c.read(scanControllerProvider.notifier);
    final raw = await shot();
    scan.captured(raw);
    preparer.failing = true;
    await scan.identify();
    final failed = c.read(scanControllerProvider) as ScanFailed;
    expect(failed.error, isA<PrivacyCheckFailure>());
    expect(failed.prepared, isFalse);
    expect(captures.sent, isEmpty);

    preparer.failing = false;
    await scan.identify();
    expect(preparer.calls, hasLength(2));
    expect(captures.sent, ['$raw-ready']);
  });
}
