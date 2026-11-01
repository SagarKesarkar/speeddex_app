import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/repositories.dart';
import '../../feed/application/feed_controller.dart';
import 'photo_orientation.dart';
import 'photo_pipeline.dart';

/// Scan flow states, aligned with the capture lifecycle in spec §2.2.
sealed class ScanState {
  const ScanState();
}

/// Live viewfinder.
class ScanFraming extends ScanState {
  const ScanFraming();
}

/// Still taken, shown as the camera saved it; user chooses Retake or
/// Identify. Nothing has been processed or sent yet.
class ScanPreview extends ScanState {
  const ScanPreview(this.path, {this.held = HeldAs.portrait});
  final String path;

  /// How the phone was held, to show and straighten a sideways shot.
  final HeldAs held;
}

/// Identify tapped: straightening, compressing and blurring faces and
/// plates on the device. [path] is still the unprocessed photo.
class ScanPreparing extends ScanState {
  const ScanPreparing(this.path, {this.held = HeldAs.portrait});
  final String path;
  final HeldAs held;
}

/// The prepared photo is being uploaded and identified.
class ScanIdentifying extends ScanState {
  const ScanIdentifying(this.path);
  final String path;
}

class ScanResult extends ScanState {
  const ScanResult(this.path, this.outcome, {this.adding = false, this.error});
  final String path;
  final Identified outcome;
  final bool adding;
  final Object? error;

  bool get isConfident =>
      outcome.reviewerConfirmed || outcome.confidence >= ScanController.confidenceThreshold;
}

class ScanNeedsReview extends ScanState {
  const ScanNeedsReview(this.path);
  final String path;
}

class ScanRejected extends ScanState {
  const ScanRejected(this.path, this.reason);
  final String path;
  final String reason;
}

class ScanAdded extends ScanState {
  const ScanAdded(this.result);
  final AddResult result;
}

class ScanFailed extends ScanState {
  const ScanFailed(this.path, this.error, {this.prepared = true, this.held = HeldAs.portrait});
  final String path;
  final Object error;

  /// False if it failed before the privacy step finished: [path] is then the
  /// unprocessed photo, and trying again must prepare it first.
  final bool prepared;
  final HeldAs held;
}

class ScanController extends Notifier<ScanState> {
  /// Below this the result is shown as a cautious "likely" match (spec §3.5).
  static const confidenceThreshold = 0.85;

  @override
  ScanState build() => const ScanFraming();

  void captured(String path, {HeldAs held = HeldAs.portrait}) =>
      state = ScanPreview(path, held: held);

  /// Discards the pending still and returns to the viewfinder.
  Future<void> retake() async {
    final s = state;
    state = const ScanFraming();
    if (s is ScanResult) {
      await ref.read(captureRepositoryProvider).discard(s.outcome.captureId);
    }
    await _deleteTemp(_pathOf(s));
  }

  Future<void> identify() async {
    final s = state;
    if (s is! ScanPreview && s is! ScanFailed) return;
    var path = _pathOf(s)!;
    // Blur and compress first. A photo that hasn't been through this is
    // never sent; a retry after an upload failure reuses the prepared one.
    final needsPreparing = s is ScanPreview || (s is ScanFailed && !s.prepared);
    if (needsPreparing) {
      final held = switch (s) {
        ScanPreview(:final held) || ScanFailed(:final held) => held,
        _ => HeldAs.portrait,
      };
      state = ScanPreparing(path, held: held);
      try {
        path = await ref.read(photoPreparerProvider).prepare(path, held);
      } catch (_) {
        state = ScanFailed(path, const PrivacyCheckFailure(), prepared: false, held: held);
        return;
      }
    }
    state = ScanIdentifying(path);
    try {
      final bytes = await File(path).readAsBytes();
      final outcome = await ref.read(captureRepositoryProvider).identify(bytes, localPath: path);
      state = switch (outcome) {
        Identified() => ScanResult(path, outcome),
        ReviewRequired() => ScanNeedsReview(path),
        Rejected(:final reason) => ScanRejected(path, reason),
      };
    } catch (e) {
      state = ScanFailed(path, e);
    }
  }

  Future<void> addToGarage({
    bool replace = false,
    String? replaceCardId,
    bool keepBoth = false,
  }) async {
    final s = state;
    if (s is! ScanResult || s.adding) return;
    state = ScanResult(s.path, s.outcome, adding: true);
    try {
      final result = await ref
          .read(captureRepositoryProvider)
          .addToGarage(
            s.outcome.captureId,
            replace: replace,
            replaceCardId: replaceCardId,
            keepBoth: keepBoth,
          );
      ref
        ..invalidate(walletProvider)
        ..invalidate(garageSummaryProvider)
        ..invalidate(profileProvider);
      // The new catch is posted to the feed; reload it without losing the view mode.
      unawaited(ref.read(feedControllerProvider.notifier).refresh());
      state = ScanAdded(result);
    } catch (e) {
      state = ScanResult(s.path, s.outcome, error: e);
    }
  }

  void reset() => state = const ScanFraming();

  /// Reopens a capture identified earlier (e.g. approved by a reviewer) in the
  /// normal result flow. There is no local photo; the card uses the server image.
  void resume(Identified outcome) => state = ScanResult('', outcome);

  String? _pathOf(ScanState s) => switch (s) {
    ScanPreview(:final path) ||
    ScanPreparing(:final path) ||
    ScanIdentifying(:final path) ||
    ScanResult(:final path) ||
    ScanNeedsReview(:final path) ||
    ScanRejected(:final path) ||
    ScanFailed(:final path) => path,
    _ => null,
  };

  /// Captures are private: remove discarded stills from the device cache.
  Future<void> _deleteTemp(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Best effort; the OS clears the cache directory eventually.
    }
  }
}

final scanControllerProvider = NotifierProvider<ScanController, ScanState>(ScanController.new);
