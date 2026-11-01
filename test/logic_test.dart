import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speeddex/app/providers.dart';
import 'package:speeddex/core/errors/app_failure.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/dev/dev_backend.dart';
import 'package:speeddex/domain/social.dart';
import 'package:speeddex/features/auth/application/auth_controller.dart';
import 'package:speeddex/features/feed/application/feed_controller.dart';
import 'package:speeddex/features/scan/application/scan_controller.dart';

/// Feed repository whose like call always fails, to exercise rollback.
class _FailingLikes implements FeedRepository {
  _FailingLikes(this._inner);
  final FeedRepository _inner;

  @override
  Future<FeedPage> fetch({String? cursor, int limit = 20}) =>
      _inner.fetch(cursor: cursor, limit: limit);
  @override
  Future<FeedPost> post(String postId) => _inner.post(postId);
  @override
  Future<void> setLiked(String postId, {required bool liked}) async => throw const NetworkFailure();
  @override
  Future<List<FeedComment>> comments(String postId) => _inner.comments(postId);
  @override
  Future<FeedComment> addComment(String postId, String text) => _inner.addComment(postId, text);
  @override
  Future<void> report(String postId, String reason) => _inner.report(postId, reason);
}

Future<void> _settle(ProviderContainer c, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  group('AuthValidators', () {
    test('email', () {
      expect(AuthValidators.email(''), isNotNull);
      expect(AuthValidators.email('nope'), isNotNull);
      expect(AuthValidators.email('a@b.co'), isNull);
    });

    test('password policy needs length, a letter and a digit', () {
      expect(AuthValidators.password('short1'), isNotNull);
      expect(AuthValidators.password('longenough'), isNotNull);
      expect(AuthValidators.password('12345678'), isNotNull);
      expect(AuthValidators.password('redline99'), isNull);
    });
  });

  group('Card unlock', () {
    test('debits 5 coins once and is idempotent', () async {
      final store = DevStore();
      final cards = DevCardsRepository(store);
      final profile = DevProfileRepository(store);
      final before = (await profile.wallet()).coins;

      final r1 = await cards.unlock('p0-card', idempotencyKey: 'k1');
      final r2 = await cards.unlock('p0-card', idempotencyKey: 'k1');

      expect(r1.coinsCharged, 5);
      expect(r2.coinsCharged, 0);
      expect(r1.card.hiddenUnlocked, isTrue);
      expect((await profile.wallet()).coins, before - 5);
    });

    test('fails with InsufficientCoinsFailure when balance is short', () async {
      final store = DevStore();
      final cards = DevCardsRepository(store);
      await cards.unlock('p0-card', idempotencyKey: 'a'); // 12 -> 7
      await cards.unlock('p1-card', idempotencyKey: 'b'); // 7 -> 2
      expect(
        () => cards.unlock('p3-card', idempotencyKey: 'c'),
        throwsA(isA<InsufficientCoinsFailure>()),
      );
    });
  });

  group('Card ownership', () {
    test('own Garage cards always include the spec sheet and never charge', () async {
      final store = DevStore();
      final garage = await DevGarageRepository(store).cards(const GarageQuery());
      expect(garage, isNotEmpty);
      for (final c in garage) {
        expect(c.ownedByViewer, isTrue);
        expect(c.hiddenUnlocked, isTrue);
        expect(c.hidden, isNotNull);
      }
      final r = await DevCardsRepository(store).unlock(garage.first.id, idempotencyKey: 'own');
      expect(r.coinsCharged, 0);
    });

    test("other players' cards withhold the spec sheet until unlocked", () async {
      final store = DevStore();
      final cards = DevCardsRepository(store);
      final locked = await cards.detail('p0-card');
      expect(locked.ownedByViewer, isFalse);
      expect(locked.hiddenUnlocked, isFalse);
      expect(locked.hidden, isNull);

      await cards.unlock('p0-card', idempotencyKey: 'x');
      final unlocked = await cards.detail('p0-card');
      expect(unlocked.hiddenUnlocked, isTrue);
      expect(unlocked.hidden, isNotNull);
    });

    test("unlocking one player's card does not unlock the same model elsewhere", () async {
      final store = DevStore();
      final cards = DevCardsRepository(store);
      // p0 and p12 are both Huracáns posted by different players.
      final a = await cards.detail('p0-card');
      final b = await cards.detail('p12-card');
      expect(a.vehicleId, b.vehicleId);
      await cards.unlock('p0-card', idempotencyKey: 'y');
      expect((await cards.detail('p12-card')).hiddenUnlocked, isFalse);
    });
  });

  test('Feed like rolls back when the request fails', () async {
    final store = DevStore();
    final c = ProviderContainer(
      overrides: [
        feedRepositoryProvider.overrideWithValue(_FailingLikes(DevFeedRepository(store))),
      ],
    );
    addTearDown(c.dispose);
    c.read(feedControllerProvider);
    await _settle(c, () => !c.read(feedControllerProvider).loading);

    final post = c.read(feedControllerProvider).posts.first;
    final ok = await c.read(feedControllerProvider.notifier).toggleLike(post.id);
    final after = c.read(feedControllerProvider).posts.first;

    expect(ok, isFalse);
    expect(after.viewerHasLiked, post.viewerHasLiked);
    expect(after.likeCount, post.likeCount);
  });

  test('Scan flow: identify, add, rewards, and duplicate detection', () async {
    final dir = await Directory.systemTemp.createTemp('sdx');
    addTearDown(() => dir.delete(recursive: true));
    Future<String> still() async {
      final f = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg');
      await f.writeAsBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]));
      return f.path;
    }

    final c = ProviderContainer();
    addTearDown(c.dispose);
    final scan = c.read(scanControllerProvider.notifier);

    // 1st in the dev sequence: a new, confidently identified card.
    scan.captured(await still());
    await scan.identify();
    final first = c.read(scanControllerProvider) as ScanResult;
    expect(first.isConfident, isTrue);
    expect(first.outcome.duplicateOf, isNull);
    // The viewer's own capture shows every detail without an unlock.
    expect(first.outcome.candidate.ownedByViewer, isTrue);
    expect(first.outcome.candidate.hidden, isNotNull);

    await scan.addToGarage();
    final added = c.read(scanControllerProvider) as ScanAdded;
    expect(added.result.coinsAwarded, 3);

    // 2nd: a car already in the Garage.
    scan.reset();
    scan.captured(await still());
    await scan.identify();
    final dup = c.read(scanControllerProvider) as ScanResult;
    expect(dup.outcome.duplicateOf, isNotNull);

    // Replacing earns nothing, so cards cannot be farmed.
    await scan.addToGarage(replace: true);
    final replaced = (c.read(scanControllerProvider) as ScanAdded).result;
    expect(replaced.coinsAwarded, 0);
    expect(replaced.replaced, isTrue);

    // 3rd: a low-confidence result must be flagged.
    scan.reset();
    scan.captured(await still());
    await scan.identify();
    expect((c.read(scanControllerProvider) as ScanResult).isConfident, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
